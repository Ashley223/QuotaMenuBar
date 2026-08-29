# QuotaMenuBar

A native macOS menu bar app (SwiftUI `MenuBarExtra`, `LSUIElement` — no Dock icon)
that shows, at a glance:

- **Claude** — rolling 5‑hour and 7‑day quota remaining, with reset countdowns
- **Gemini** (Antigravity) — quota remaining, model label, reset countdown
- **Claude Code usage** — tokens spent today and a 7‑day bar strip, plus an
  estimated dollar cost

Menu bar title looks like: `☁ 5h 64% · 7d 80% · ✦ 99%`

This is the native successor to the xbar plugin in
[`claude-quota-menubar`](https://github.com/Ashley223/claude-quota-menubar).

## How it works

The app itself does **no** network calls. It only reads three JSON cache files,
refreshing every 30 seconds. Separate `launchd` agents keep those caches fresh:

| Cache file | Written by | Interval | Lives in |
|---|---|---|---|
| `~/.claude/rate_limits_cache.json` | `fetch_claude_usage.py` | 5 min | [`claude-quota-menubar`](https://github.com/Ashley223/claude-quota-menubar) |
| `~/.antigravity/quota_cache.json` | `fetch_antigravity_usage.py` | 1 min | [`claude-quota-menubar`](https://github.com/Ashley223/claude-quota-menubar) |
| `~/.quota-menubar/daily_usage_cache.json` | [`scripts/fetch_daily_usage.py`](scripts/fetch_daily_usage.py) | 5 min | this repo |

`fetch_daily_usage.py` wraps [`ccusage`](https://github.com/ryoppippi/ccusage),
which parses `~/.claude/projects/**/*.jsonl` and prices tokens against public API
rates. **Claude Code CLI usage on this machine only** — not claude.ai web chats,
not the Desktop app, not other computers. The cost figure is an estimate and will
not match a subscription bill.

If a cache file is missing the app shows that source as *Not configured*; if it
is older than 3 hours it shows a staleness warning.

## Setup

### 1. Build the app

Open `QuotaMenuBar.xcodeproj` in Xcode and Run (⌘R), or:

```sh
xcodebuild -project QuotaMenuBar.xcodeproj -scheme QuotaMenuBar \
  -configuration Release -derivedDataPath build build
```

The built `QuotaMenuBar.app` is under
`build/Build/Products/Release/`. Copy it to `/Applications` and add it to
System Settings → General → Login Items to start it automatically.

### 2. Install the daily-usage poller

```sh
npm i -g ccusage                                   # provides /opt/homebrew/bin/ccusage
mkdir -p ~/.quota-menubar
cp scripts/fetch_daily_usage.py ~/.quota-menubar/
chmod +x ~/.quota-menubar/fetch_daily_usage.py

sed "s|__HOME__|$HOME|g" scripts/com.quota-menubar.daily-usage-poller.plist.template \
  > ~/Library/LaunchAgents/com.quota-menubar.daily-usage-poller.plist
launchctl load ~/Library/LaunchAgents/com.quota-menubar.daily-usage-poller.plist
```

The plist sets `PATH=/opt/homebrew/bin:...` so `ccusage`'s `#!/usr/bin/env node`
shebang resolves under `launchd`'s minimal environment.

### 3. Install the Claude & Gemini pollers

From [`claude-quota-menubar`](https://github.com/Ashley223/claude-quota-menubar)
— run its `install.sh`.

## Project layout

```
QuotaMenuBar/
  QuotaMenuBarApp.swift    MenuBarExtra scene
  QuotaViewModel.swift     @Observable model, 30 s refresh loop
  QuotaData.swift          cache schemas, LenientDate, parsing, formatting helpers
  QuotaMenuBarView.swift   the dropdown panel
scripts/
  fetch_daily_usage.py                          ccusage wrapper → daily_usage_cache.json
  com.quota-menubar.daily-usage-poller.plist.template
```

`LenientDate` decodes each timestamp as either a Unix epoch or an ISO‑8601
string, because the upstream cache files have changed representation over time.

## License

MIT — see [LICENSE](LICENSE).
