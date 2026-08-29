#!/usr/bin/env python3
"""
Polls Antigravity's local API for Gemini quota data and writes it to
~/.antigravity/quota_cache.json — read by the xbar plugin the same way
the Claude cache is.

Unlike the Claude fetcher, this needs no stored credentials at all.
The CSRF token required to call the local API is read fresh, every
run, straight out of the running Antigravity language_server
process's own command-line arguments (visible via `ps`). It only
works against 127.0.0.1 on this same machine, so there's nothing
worth persisting in Keychain here.

Antigravity (the desktop app, or an `agy` session) must be running for
this to produce fresh data — it's polling a local server that only
exists while the app is alive. If it's not running, this exits
quietly without touching the cache, so the xbar plugin just keeps
showing the last known numbers (and its own staleness warning).

How the endpoint was found: by running the real macOS app, grepping
`ps aux` for the language_server process to get its PID and
--csrf_token argument, using `lsof -p <pid>` to find which local ports
it's listening on, then testing each port against
POST /exa.language_server_pb.LanguageServerService/GetUserStatus with
the CSRF token as an X-Codeium-Csrf-Token header. This is not a
documented public API and could change without notice.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from urllib.request import Request, urlopen

CACHE_PATH = os.path.expanduser("~/.antigravity/quota_cache.json")
ENDPOINT_PATH = "/exa.language_server_pb.LanguageServerService/GetUserStatus"


def find_language_server():
    """Return (pid, csrf_token) for the running Antigravity
    language_server process, or (None, None) if it's not running."""
    try:
        out = subprocess.run(
            ["ps", "aux"], capture_output=True, text=True, check=True
        ).stdout
    except subprocess.CalledProcessError:
        return None, None

    for line in out.splitlines():
        if "language_server" in line and "override_ide_name antigravity" in line:
            pid_match = re.search(r"^\S+\s+(\d+)", line)
            csrf_match = re.search(r"--csrf_token\s+(\S+)", line)
            if pid_match and csrf_match:
                return pid_match.group(1), csrf_match.group(1)
    return None, None


def find_listen_ports(pid: str) -> list:
    """Return all localhost TCP ports this pid is listening on.

    IMPORTANT: lsof combines multiple selection filters (-i, -p) with
    OR semantics by default, not AND — without -a, this would return
    every listening port on the whole system (matching -iTCP) unioned
    with this pid's ports, not just this pid's. -a forces AND."""
    try:
        out = subprocess.run(
            ["lsof", "-nP", "-a", "-iTCP", "-sTCP:LISTEN", "-p", pid],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    except subprocess.CalledProcessError:
        return []

    ports = []
    for line in out.splitlines()[1:]:
        m = re.search(r"127\.0\.0\.1:(\d+)", line)
        if m:
            ports.append(m.group(1))
    return ports


def write_cache_atomic(data: dict) -> None:
    cache_dir = os.path.dirname(CACHE_PATH)
    os.makedirs(cache_dir, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=cache_dir, prefix=".quota_", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    os.replace(tmp_path, CACHE_PATH)


def call_get_user_status(port: str, csrf_token: str) -> dict:
    req = Request(
        f"http://127.0.0.1:{port}{ENDPOINT_PATH}",
        data=b"{}",
        headers={
            "Content-Type": "application/json",
            "X-Codeium-Csrf-Token": csrf_token,
        },
        method="POST",
    )
    with urlopen(req, timeout=5) as resp:
        return json.loads(resp.read())


def extract_gemini_quota(body: dict):
    """Pull remainingFraction + resetTime for a representative Gemini
    model out of GetUserStatus's response. Several Gemini model
    entries typically share one quota pool (identical fraction/reset
    time) — take the first one that has quotaInfo.remainingFraction.

    NOTE: as of Antigravity 2.7.x the GetUserStatus response moved
    cascadeModelConfigData out from under userStatus.planStatus up to
    userStatus directly. Older builds nested it one level deeper."""
    configs = (
        body.get("userStatus", {})
        .get("cascadeModelConfigData", {})
        .get("clientModelConfigs", [])
    )
    for cfg in configs:
        label = cfg.get("label", "")
        quota = cfg.get("quotaInfo", {})
        if "Gemini" in label and "remainingFraction" in quota:
            return {
                "label": label,
                "remaining_percentage": round(quota["remainingFraction"] * 100, 1),
                "resets_at": quota.get("resetTime"),
            }
    return None


def main() -> int:
    pid, csrf_token = find_language_server()
    if not pid:
        print("Antigravity 没有在运行，跳过这次刷新。", file=sys.stderr)
        return 0

    ports = find_listen_ports(pid)
    if not ports:
        print("找到 Antigravity 进程，但没找到它监听的端口。", file=sys.stderr)
        return 1

    last_error = None
    last_seen_configs = None
    for port in ports:
        try:
            body = call_get_user_status(port, csrf_token)
        except Exception as e:
            last_error = e
            continue

        gemini = extract_gemini_quota(body)
        if gemini is None:
            configs = (
                body.get("userStatus", {})
                .get("cascadeModelConfigData", {})
                .get("clientModelConfigs", [])
            )
            last_seen_configs = [
                f"{cfg.get('label', '?')} (has remainingFraction: {'remainingFraction' in cfg.get('quotaInfo', {})})"
                for cfg in configs
            ]
            continue

        write_cache_atomic({
            "label": gemini["label"],
            "remaining_percentage": gemini["remaining_percentage"],
            "resets_at": gemini["resets_at"],
            "updated_at": int(time.time()),
        })
        print(f"刷新成功: {gemini['label']} 剩余 {gemini['remaining_percentage']}%")
        return 0

    if last_seen_configs is not None:
        print("所有端口都试过了，没有一个返回带 Gemini 额度的数据。最后一次看到的模型列表：", file=sys.stderr)
        for line in last_seen_configs:
            print(f"  - {line}", file=sys.stderr)
    else:
        print(f"所有端口都请求失败: {last_error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
