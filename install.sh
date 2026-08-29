#!/bin/bash
# QuotaMenuBar — one-shot installer.
#
# Sets up:
#   • three launchd pollers that write the JSON caches the app reads
#       ~/.claude/fetch_claude_usage.py         -> Claude 5h / 7d quota   (every 5 min)
#       ~/.antigravity/fetch_antigravity_usage.py -> Gemini quota         (every 1 min)
#       ~/.quota-menubar/fetch_daily_usage.py   -> daily Claude Code tokens (every 5 min)
#   • the menu bar app in /Applications, launched now and at every login
#
# Safe to re-run. Existing poller scripts are backed up to *.bak first.
set -euo pipefail

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YEL=$'\033[0;33m'; BLD=$'\033[1m'; NC=$'\033[0m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$GRN" "$NC" "$*"; }
warn() { printf '%s!%s %s\n' "$YEL" "$NC" "$*"; }
die()  { printf '%s✖ %s%s\n' "$RED" "$*" "$NC" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LA="$HOME/Library/LaunchAgents"
mkdir -p "$LA"

[ "$(uname)" = "Darwin" ] || die "macOS only."
PYTHON3="$(command -v python3)" || die "python3 not found. Install it (e.g. 'xcode-select --install')."
ok "python3 -> $PYTHON3"

# ── Node + ccusage (for the daily token numbers) ──────────────────────
NODE_BIN=""
if command -v npm >/dev/null 2>&1; then
    if ! command -v ccusage >/dev/null 2>&1; then
        say "Installing ccusage (npm -g)…"
        npm install -g ccusage >/dev/null 2>&1 || warn "npm install -g ccusage failed — daily usage will be blank until it's installed."
    fi
    if command -v ccusage >/dev/null 2>&1; then
        NODE_BIN="$(dirname "$(command -v ccusage)")"
        ok "ccusage -> $(command -v ccusage)"
    fi
else
    warn "Node/npm not found — the daily token panel needs 'npm install -g ccusage'. Claude & Gemini still work."
fi
[ -n "$NODE_BIN" ] || NODE_BIN="/opt/homebrew/bin:/usr/local/bin"

# ── Poller scripts into place ────────────────────────────────────────
place() { # src dst
    mkdir -p "$(dirname "$2")"
    if [ -f "$2" ] && ! cmp -s "$1" "$2"; then cp "$2" "$2.bak"; warn "backed up existing $(basename "$2") -> $2.bak"; fi
    cp "$1" "$2"; chmod +x "$2"
}
place "$ROOT/scripts/fetch_claude_usage.py"       "$HOME/.claude/fetch_claude_usage.py"
place "$ROOT/scripts/fetch_antigravity_usage.py"  "$HOME/.antigravity/fetch_antigravity_usage.py"
place "$ROOT/scripts/fetch_daily_usage.py"        "$HOME/.quota-menubar/fetch_daily_usage.py"
ok "poller scripts installed"

# ── The app ─────────────────────────────────────────────────────────
APP_DST="/Applications/QuotaMenuBar.app"
APP_SRC=""
if [ -d "$ROOT/dist/QuotaMenuBar.app" ]; then
    APP_SRC="$ROOT/dist/QuotaMenuBar.app"
elif xcodebuild -version >/dev/null 2>&1; then
    say "Building the app from source (Release)…"
    "$ROOT/scripts/build-app.sh" >/dev/null
    APP_SRC="$ROOT/dist/QuotaMenuBar.app"
fi
if [ -n "$APP_SRC" ]; then
    # stop a running copy so the bundle can be replaced
    launchctl bootout "gui/$(id -u)/com.quota-menubar.app" 2>/dev/null || true
    launchctl bootout "gui/$(id -u)/com.will.QuotaMenuBar" 2>/dev/null || true
    rm -rf "$APP_DST"; cp -R "$APP_SRC" "$APP_DST"
    xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DST" 2>/dev/null || true
    ok "installed $APP_DST"
else
    warn "No prebuilt app and no Xcode — skipping app install."
    warn "Install Xcode and re-run, or download QuotaMenuBar.app.zip from the GitHub Releases page and drop it in /Applications."
fi

# ── launchd agents ──────────────────────────────────────────────────
render() { # template label  (writes+loads ~/Library/LaunchAgents/<label>.plist)
    local tmpl="$1" label="$2" out="$LA/$2.plist"
    sed -e "s|__PYTHON3__|$PYTHON3|g" \
        -e "s|__HOME__|$HOME|g" \
        -e "s|__NODE_BIN__|$NODE_BIN|g" \
        -e "s|__APP_PATH__|$APP_DST|g" \
        "$tmpl" > "$out"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$out"
}
render "$ROOT/scripts/launchd/com.claude-quota-poller.plist.template"            com.claude-quota-poller
render "$ROOT/scripts/launchd/com.antigravity-quota-poller.plist.template"       com.antigravity-quota-poller
render "$ROOT/scripts/launchd/com.quota-menubar.daily-usage-poller.plist.template" com.quota-menubar.daily-usage-poller
[ -d "$APP_DST" ] && render "$ROOT/scripts/launchd/com.quota-menubar.app.plist.template" com.quota-menubar.app
# retire the personal-machine label if it lingers
rm -f "$LA/com.will.QuotaMenuBar.plist"
ok "launchd agents loaded"

# ── Claude credentials ──────────────────────────────────────────────
if security find-generic-password -a "$(id -un)" -s claude-web-session-key -w >/dev/null 2>&1; then
    ok "Claude credentials already in Keychain"
else
    say ""
    say "${BLD}Claude quota needs your claude.ai session cookie.${NC}"
    say "Run this any time:  ${BLD}./scripts/setup-claude-auth.sh${NC}"
    say "(Gemini + daily usage work without it.)"
fi

say ""
ok "${BLD}Done.${NC} Look for the bars icon in your menu bar."
say "Uninstall with ./uninstall.sh"
