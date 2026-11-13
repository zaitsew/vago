# Vago

An AI-native focus app for iPhone and Mac, for one person who wants to stop losing time to
scrolling. Vago counts work and procrastination across both devices and shows one number a day:
the productive share (100% minus the share of waste). A daily limit on waste walks down to 30 minutes.

- **Productive share**: `😄 92%` in the Mac menu bar, and on the iPhone a Today screen with an
  hour-by-hour strip, widgets and a Live Activity. A Mac desktop widget shows a strip per device.
  The share reads "—" before 15 active minutes.
- **Smart buckets**: productive, neutral, procrastination and ambiguous. Instagram can be work.
- **On-device AI**: the Mac judges window titles and URLs against your goals; nothing leaves it.
  Vago never asks during the day. An unsure place counts as neutral.
- **Corrections**: the Mac's Day window lists Vago's calls with the AI's reason. One tap
  corrects a call and becomes a rule. The popover's **Wrong?** and a work switch do the same.
- **Guard** (Mac): up to three places you name get a pause card or a block in work hours.
  A notice says when 60 seconds of procrastination follow work.
- **Intent check** (iPhone): ambiguous apps ask "Work or scroll?" before they open.
- **Focus sessions**: grow a tree 🌱 → 🌳 in 25 or 50 minutes; a distraction wilts it 🥀.
- **Move breaks** (Mac): after 90 minutes at the laptop without a break, a panel suggests one
  2-minute desk exercise with exact reps. It waits out focus and calls, and asks at most twice.
- **Ask it**: Siri and Shortcuts on the iPhone ("How focused am I in Vago"), and a read-only
  MCP server on the Mac so Claude Code or Codex can answer "how focused was I today"
  ([docs/AI.md](docs/AI.md)).

## Quick start

```bash
git clone https://github.com/zaitsew/vago && cd vago
git config core.hooksPath .githooks   # ./check.sh before every push
./check.sh                            # VagoKit tests + both app builds
scripts/install-mac.sh                # Mac menu-bar app in /Applications
scripts/install-mcp.sh                # optional: vago-mcp for Claude Code or Codex
```

iPhone: run `xcodegen generate`, open `Vago.xcodeproj` and run the Vago scheme on your phone
([docs/RELEASE.md](docs/RELEASE.md)). A build also goes to internal TestFlight; the app is not on sale.

The Mac app asks for Accessibility and Automation on first run. The iPhone app asks for
Screen Time. See [docs/PRODUCT.md](docs/PRODUCT.md) for the rules, [docs/MAC.md](docs/MAC.md)
for the Mac app and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it works.

## License

Apache 2.0.

<!-- teyla:reviewed 2026-11-13 -->
