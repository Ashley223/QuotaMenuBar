#!/usr/bin/env python3
"""
Aggregates per-day Claude Code token usage on this Mac and writes
~/.quota-menubar/daily_usage_cache.json for the QuotaMenuBar app.

Wraps `ccusage daily --json`. ccusage parses ~/.claude/projects/**/*.jsonl,
dedupes messages, and prices tokens against public API rates. This is
Claude Code CLI usage on THIS machine only — not claude.ai web chats,
not the Desktop app, not other computers.

Scheduled by ~/Library/LaunchAgents/com.quota-menubar.daily-usage-poller.plist.
On any failure it exits non-zero WITHOUT touching the cache, so the app
keeps showing the last known numbers (and its own staleness warning).
"""
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import date, timedelta

CACHE_PATH = os.path.expanduser("~/.quota-menubar/daily_usage_cache.json")
DAYS = 7
# Homebrew node puts global bins here; override with CCUSAGE_BIN if needed.
CCUSAGE = os.environ.get("CCUSAGE_BIN", "/opt/homebrew/bin/ccusage")


# USD per million tokens: (input, cache write [1h], cache read, output).
# Claude Code writes 1-hour cache entries (checked against the session logs:
# ephemeral_1h only), so the 1h write rate is used, not the 5m one.
# ccusage's bundled price list lags behind new models and reports $0 for
# them, so any model it prices at 0 is re-priced from this table.
# Source: https://platform.claude.com/docs/en/about-claude/pricing
PRICES = {
    "claude-opus-5-5":   (4.00, 8.00, 0.20, 20.00),
    "claude-opus-5":     (5.00, 10.00, 0.50, 25.00),
    "claude-sonnet-5-5": (2.00, 4.00, 0.20, 10.00),
    "claude-sonnet-5":   (2.00, 4.00, 0.20, 10.00),
}


def model_cost(m: dict) -> float:
    """Cost of one modelBreakdowns entry: ccusage's own figure if it has one,
    otherwise our price table (unknown models stay at 0)."""
    if float(m.get("cost", 0) or 0) > 0:
        return float(m["cost"])
    name = m.get("modelName", "")
    price = next((v for k, v in PRICES.items() if name.startswith(k)), None)
    if not price:
        return 0.0
    i, w, r, o = price
    return (
        m.get("inputTokens", 0) * i
        + m.get("cacheCreationTokens", 0) * w
        + m.get("cacheReadTokens", 0) * r
        + m.get("outputTokens", 0) * o
    ) / 1_000_000


def day_cost(r: dict) -> float:
    breakdowns = r.get("modelBreakdowns")
    if breakdowns:
        return sum(model_cost(m) for m in breakdowns)
    return float(r.get("totalCost", 0.0))


def run_ccusage(since: str) -> dict:
    """Try offline first (cached pricing, no network); fall back to online."""
    last_err = None
    for extra in (["--offline"], []):
        args = [CCUSAGE, "daily", "--json", "--since", since] + extra
        try:
            out = subprocess.run(
                args, capture_output=True, text=True, check=True, timeout=60
            ).stdout
            return json.loads(out)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired,
                json.JSONDecodeError, FileNotFoundError) as e:
            last_err = e
    raise last_err


def write_atomic(data: dict) -> None:
    cache_dir = os.path.dirname(CACHE_PATH)
    os.makedirs(cache_dir, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=cache_dir, prefix=".daily_", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    os.replace(tmp_path, CACHE_PATH)


def main() -> int:
    today = date.today()
    start = today - timedelta(days=DAYS - 1)
    month_start = today.replace(day=1)
    fetch_from = min(start, month_start)  # also cover the whole month for the total

    try:
        body = run_ccusage(fetch_from.strftime("%Y%m%d"))
    except Exception as e:
        print(f"ccusage 调用失败: {e}", file=sys.stderr)
        return 1

    by_date = {row.get("period"): row for row in body.get("daily", [])}

    days = []
    for i in range(DAYS):
        d = start + timedelta(days=i)
        key = d.strftime("%Y-%m-%d")
        r = by_date.get(key, {})
        days.append({
            "date": key,
            "total_tokens": int(r.get("totalTokens", 0)),
            "input_tokens": int(r.get("inputTokens", 0)),
            "output_tokens": int(r.get("outputTokens", 0)),
            "cache_creation_tokens": int(r.get("cacheCreationTokens", 0)),
            "cache_read_tokens": int(r.get("cacheReadTokens", 0)),
            "cost": round(day_cost(r), 4),
        })

    month_key = today.strftime("%Y-%m")
    month_cost = round(sum(
        day_cost(r) for k, r in by_date.items() if k and k.startswith(month_key)
    ), 4)

    write_atomic({
        "updated_at": int(time.time()),
        "days": days,
        "month_cost": month_cost,
    })
    t = days[-1]
    print(f"刷新成功: 今日 {t['total_tokens']} tokens / ${t['cost']:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
