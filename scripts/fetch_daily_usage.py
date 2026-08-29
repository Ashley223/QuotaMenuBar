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

    try:
        body = run_ccusage(start.strftime("%Y%m%d"))
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
            "cost": round(float(r.get("totalCost", 0.0)), 4),
        })

    write_atomic({"updated_at": int(time.time()), "days": days})
    t = days[-1]
    print(f"刷新成功: 今日 {t['total_tokens']} tokens / ${t['cost']:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
