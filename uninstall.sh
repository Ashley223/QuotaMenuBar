#!/bin/bash
# Remove QuotaMenuBar: launchd agents, app, and the ~/.quota-menubar data dir.
# Leaves ~/.claude and ~/.antigravity alone (other tools use them); only removes
# the poller scripts this project put there. Keychain items are left untouched
# unless you pass --purge-keychain.
set -uo pipefail

LA="$HOME/Library/LaunchAgents"
uid="$(id -u)"

for label in com.quota-menubar.app com.will.QuotaMenuBar \
             com.claude-quota-poller com.antigravity-quota-poller \
             com.quota-menubar.daily-usage-poller; do
    launchctl bootout "gui/$uid/$label" 2>/dev/null || true
    rm -f "$LA/$label.plist"
done
echo "✓ launchd agents removed"

rm -rf /Applications/QuotaMenuBar.app
echo "✓ /Applications/QuotaMenuBar.app removed"

rm -f "$HOME/.claude/fetch_claude_usage.py" \
      "$HOME/.antigravity/fetch_antigravity_usage.py"
rm -rf "$HOME/.quota-menubar"
echo "✓ poller scripts removed"

if [ "${1:-}" = "--purge-keychain" ]; then
    security delete-generic-password -a "$(id -un)" -s claude-web-session-key 2>/dev/null || true
    security delete-generic-password -a "$(id -un)" -s claude-web-org-id 2>/dev/null || true
    echo "✓ Keychain credentials removed"
fi

echo "Done."
