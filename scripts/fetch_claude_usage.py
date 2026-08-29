#!/usr/bin/env python3
"""
Pulls live quota data directly from claude.ai's own usage endpoint and
writes it to ~/.claude/rate_limits_cache.json — the same cache file
claude-quota.30s.py (the xbar plugin) already reads. That means the
xbar plugin needs zero changes; only the *source* of the cache file
changes, from "statusLine hook" to "direct API poll".

Run setup_claude_web_auth.sh once first to store credentials in Keychain.

This is meant to be run on a schedule (see the accompanying launchd
plist), independent of whether you're using Claude Code via the
terminal, the Desktop app's Code tab, or not running it at all —
because this hits the account-level endpoint directly, it doesn't
care which surface you use.

Caveats:
  - This endpoint is not publicly documented. It was found by
    inspecting Claude Desktop's own network traffic. It could change
    or disappear without notice.
  - Cloudflare may occasionally challenge automated requests that
    don't look enough like a real browser. If requests start failing
    consistently, the User-Agent below or cookie set may need updating
    from a fresh capture.
  - The sessionKey cookie is a live credential. Treat the Keychain
    entries holding it with the same care as a password.
"""
import json
import os
import ssl
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

CACHE_PATH = os.path.expanduser("~/.claude/rate_limits_cache.json")
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
)


def build_ssl_context() -> ssl.SSLContext:
    """macOS Python installs frequently ship without access to a working
    system root CA bundle, causing CERTIFICATE_VERIFY_FAILED on every
    HTTPS request regardless of network/account setup. Prefer certifi's
    bundle when available since it sidesteps that entirely."""
    try:
        import certifi
        print(f"使用 certifi 证书库: {certifi.where()}", file=sys.stderr)
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        print(
            "警告: 没找到 certifi（可能装到了另一个 python 环境），"
            "回退到系统默认证书，这大概率还是会报证书错误。",
            file=sys.stderr,
        )
        return ssl.create_default_context()


def keychain_read(service: str) -> str | None:
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-a", os.environ["USER"], "-s", service, "-w"],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None


def write_cache_atomic(data: dict) -> None:
    cache_dir = os.path.dirname(CACHE_PATH)
    os.makedirs(cache_dir, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=cache_dir, prefix=".rate_limits_", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    os.replace(tmp_path, CACHE_PATH)


def fetch_usage(session_key: str, org_id: str) -> dict:
    url = f"https://claude.ai/api/organizations/{org_id}/usage"
    req = Request(
        url,
        headers={
            "Cookie": f"sessionKey={session_key}",
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
        },
    )
    with urlopen(req, timeout=10, context=build_ssl_context()) as resp:
        return json.loads(resp.read())


def main() -> int:
    session_key = keychain_read("claude-web-session-key")
    org_id = keychain_read("claude-web-org-id")

    if not session_key or not org_id:
        print("Keychain 里没找到凭证，先跑 setup_claude_web_auth.sh。", file=sys.stderr)
        return 1

    try:
        body = fetch_usage(session_key, org_id)
    except HTTPError as e:
        print(f"请求失败: HTTP {e.code}", file=sys.stderr)
        return 1
    except URLError as e:
        print(f"请求失败: {e.reason}", file=sys.stderr)
        return 1

    five_hour = body.get("five_hour") or {}
    seven_day = body.get("seven_day") or {}

    write_cache_atomic({
        "five_hour": {
            "used_percentage": five_hour.get("utilization"),
            "resets_at": five_hour.get("resets_at"),
        },
        "seven_day": {
            "used_percentage": seven_day.get("utilization"),
            "resets_at": seven_day.get("resets_at"),
        },
        "updated_at": int(time.time()),
    })
    print("刷新成功")
    return 0


if __name__ == "__main__":
    sys.exit(main())
