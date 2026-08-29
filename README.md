# QuotaMenuBar

A native macOS menu bar app (SwiftUI `MenuBarExtra`, `LSUIElement` — no Dock icon)
that shows, at a glance:

- **Claude** — rolling 5‑hour and 7‑day quota remaining, with reset countdowns
- **Gemini** (Antigravity) — quota remaining, model label, reset countdown
- **Claude Code usage** — tokens spent today and a 7‑day bar strip, with an
  estimated dollar cost

Menu bar title: `☁ 5h 64% · 7d 80% · ✦ 99%`

<!-- icon: dark squircle, glowing cyan→violet usage bars, one bright "today" bar -->

## Quick start

```sh
git clone https://github.com/Ashley223/QuotaMenuBar.git
cd QuotaMenuBar
./install.sh
```

`install.sh` builds the app (needs Xcode), installs it to `/Applications`, drops
three `launchd` pollers into `~/Library/LaunchAgents`, and starts everything —
now and at every login. Then, for the Claude numbers:

```sh
./scripts/setup-claude-auth.sh      # paste your claude.ai session cookie
```

Gemini and the daily token panel work without that step.

**No Xcode?** Download `QuotaMenuBar.app.zip` from the
[Releases](https://github.com/Ashley223/QuotaMenuBar/releases) page, unzip into
`/Applications`, run `xattr -dr com.apple.quarantine /Applications/QuotaMenuBar.app`,
then `./install.sh` (it will use the app you dropped in and skip the build).

> The prebuilt app is **ad‑hoc signed** — there's no paid Apple Developer ID, so
> Gatekeeper needs the `xattr` line above the first time. Building from source
> with `./install.sh` avoids that.

## How it works

The app does **no** networking. It reads three JSON caches, refreshing every 30 s.
`launchd` agents keep them fresh:

| Cache | Written by | Every | Needs |
|---|---|---|---|
| `~/.claude/rate_limits_cache.json` | `fetch_claude_usage.py` | 5 min | claude.ai session cookie in Keychain |
| `~/.antigravity/quota_cache.json` | `fetch_antigravity_usage.py` | 1 min | the Antigravity app running |
| `~/.quota-menubar/daily_usage_cache.json` | `fetch_daily_usage.py` | 5 min | `ccusage` (`npm i -g ccusage`) |

`fetch_daily_usage.py` wraps [`ccusage`](https://github.com/ryoppippi/ccusage),
which parses `~/.claude/projects/**/*.jsonl` and prices tokens against public API
rates — **Claude Code CLI usage on this machine only** (not claude.ai web, not the
Desktop app, not other computers). The cost is an estimate, not a bill.

A missing cache shows that source as *Not configured*; one older than 3 hours
shows a staleness warning. `LenientDate` in `QuotaData.swift` decodes each
timestamp as a Unix epoch **or** an ISO‑8601 string, because the upstream caches
have changed representation over time.

## Layout

```
QuotaMenuBar/            SwiftUI app
  QuotaMenuBarApp.swift    MenuBarExtra scene
  QuotaViewModel.swift     @Observable model, 30 s refresh loop
  QuotaData.swift          cache schemas, LenientDate, parsing, formatters
  QuotaMenuBarView.swift   the dropdown panel
  Assets.xcassets/AppIcon.appiconset   16–1024 px icon
scripts/
  fetch_claude_usage.py       -> ~/.claude/
  fetch_antigravity_usage.py  -> ~/.antigravity/
  fetch_daily_usage.py        -> ~/.quota-menubar/
  setup-claude-auth.sh        Keychain helper for the claude.ai cookie
  build-app.sh                Release build -> dist/
  launchd/*.plist.template    the four agents (3 pollers + app autostart)
design/icon/            icon source (SVG/HTML, rendered with headless Chrome + sips)
install.sh  uninstall.sh
```

## Uninstall

```sh
./uninstall.sh                 # add --purge-keychain to also drop the cookie
```

Leaves `~/.claude` and `~/.antigravity` in place (other tools use them); only the
poller scripts this project added are removed.

## Credits

The Claude/Gemini poller scripts began in
[`claude-quota-menubar`](https://github.com/Ashley223/claude-quota-menubar) (an
xbar plugin); this repo is the native successor and bundles them so it stands
alone.

## License

MIT — see [LICENSE](LICENSE).
