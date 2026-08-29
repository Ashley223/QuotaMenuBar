#!/bin/bash
# Store claude.ai web credentials in the macOS Keychain so fetch_claude_usage.py
# can read the 5-hour / 7-day quota. Safe to re-run; it overwrites.
#
# Where to get the values (Safari or Chrome, while signed in to claude.ai):
#   1. Open https://claude.ai
#   2. Web Inspector / DevTools -> Application/Storage -> Cookies -> https://claude.ai
#   3. sessionKey  = the value of the "sessionKey" cookie (a long "sk-ant-..." string)
#      org_id      = the value of the "lastActiveOrg" cookie (a UUID)
#
# Only the Claude quota needs this. Gemini and daily-usage work without it.
set -euo pipefail

ACC="$(id -un)"

echo "Paste your claude.ai cookie values (input is hidden)."
echo
read -r -s -p "  sessionKey: " SESSION_KEY; echo
if [ -z "${SESSION_KEY:-}" ]; then
    echo "No sessionKey entered — skipping. The Claude section will show 'Not configured'."
    exit 0
fi
read -r -p "  org_id (lastActiveOrg cookie): " ORG_ID
if [ -z "${ORG_ID:-}" ]; then
    echo "org_id is required when sessionKey is given. Aborting." >&2
    exit 1
fi

security add-generic-password -U -a "$ACC" -s claude-web-session-key -w "$SESSION_KEY"
security add-generic-password -U -a "$ACC" -s claude-web-org-id     -w "$ORG_ID"

# Read back to confirm real values landed (not a placeholder)
GOT="$(security find-generic-password -a "$ACC" -s claude-web-session-key -w)"
if [ "$GOT" = "$SESSION_KEY" ]; then
    echo "Stored. Running one fetch to verify..."
    if python3 "$HOME/.claude/fetch_claude_usage.py"; then
        echo "OK — Claude quota is live."
    else
        echo "Fetch failed. Double-check the cookie values (they expire; grab fresh ones)." >&2
        exit 1
    fi
else
    echo "Keychain read-back mismatch. Try again." >&2
    exit 1
fi
