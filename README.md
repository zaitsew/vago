# Vago

An AI-native focus app for iPhone and Mac. Vago counts the minutes you lose to procrastination
and the minutes you work, on every device, and shows them live: `😄 4m` in the Mac menu bar, a
widget and a Live Activity on the iPhone. The daily limit adapts like Garmin's step goal and
walks you down to 30 minutes a day.

- **Smart buckets**: productive, neutral, procrastination and ambiguous. Instagram can be work.
- **Intent check**: ambiguous apps ask "Work or scroll?" before they open.
- **On-device AI**: the Mac judges window titles and URLs against your goals; nothing leaves it.
- **Focus sessions**: grow a tree 🌱 → 🌳 in 25 or 50 minutes; a distraction wilts it 🥀.

## Quick start

```bash
git clone https://github.com/zaitsew/vago && cd vago
git config core.hooksPath .githooks   # ./check.sh before every push
./check.sh                            # VagoKit tests + both app builds
scripts/install-mac.sh                # Mac menu-bar app in /Applications
open Vago.xcodeproj                   # iPhone: run the Vago scheme on your phone
```

The Mac app asks for Accessibility and Automation on first run. The iPhone app asks for
Screen Time. See [docs/PRODUCT.md](docs/PRODUCT.md) for the rules and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it works.

## License

Apache 2.0.
