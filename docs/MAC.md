# Vago for Mac

A menu-bar app. It counts procrastination and work from what is on screen, shows today's
procrastination against the adaptive limit in the menu bar, and shares daily totals with the
iPhone through iCloud. Spec: `docs/PRODUCT.md`, `docs/ARCHITECTURE.md` (Mac app).

## Install

```
scripts/install-mac.sh          # build, sign for this Mac, put Vago.app in /Applications, open it
scripts/make-mac-profile.sh     # once: the development profile that turns iCloud sync on
```

Without the profile `install-mac.sh` still works and prints "iCloud sync is OFF". The script signs
with your Apple Development identity either way: Accessibility is granted per code signature, and an
ad-hoc signature would ask again after every build.

`make-mac-profile.sh` uses the App Store Connect API key in `~/.appstoreconnect/` (through
`~/ops/bin/testflight`'s helpers). It registers `com.zaitsew.vago.mac`, switches on its iCloud
capability, finds this Mac's device and the Apple Development certificate in the keychain, and
installs the profile "com.zaitsew.vago.mac MacDev". All of it is free.

## Permissions

| Permission | What it gives | Without it |
|---|---|---|
| Accessibility | The focused window title of every app | App names only. A browser still works through Automation. |
| Automation (per browser) | The URL and title of the front tab: Safari, Chrome, Arc, Brave, Edge, Dia | The browser's window title through Accessibility, with no URL. Rules by site then cannot match. |

On first run Vago asks for Accessibility and the popover explains Automation. macOS asks for
Automation the first time each browser is in front. Settings in the popover shows both states
and opens the right System Settings pane. A denied browser shows as "denied"; allow it under
Privacy & Security > Automation.

## What is tracked

Once a second, while someone is at the Mac:

- the front app (bundle id, name);
- for a browser, the front tab's URL and title; for other apps, the focused window's title;
- the result goes through `VagoKit.Classifier`: rules first, then the on-device model for
  ambiguous use. One second is added to today's procrastination or work. Neutral use is not counted.

Counting stops on a locked screen, sleep, a switched-away user session, and after 120 seconds
without input (20 minutes while a YouTube, Netflix, Twitch or Prime Video page or app is in front).

Nothing leaves the Mac except two numbers per day in iCloud's key-value store. Window titles
and URLs stay in `state.json`, in the sessions of the current day only.

## The AI judge and the nudge

- `FoundationModelsJudge` uses Apple's on-device model (`LanguageModelSession`, a `@Generable`
  verdict). The instructions carry your goals text from Settings. If the model is not
  available (Apple Intelligence off, model still downloading), the classifier runs without a
  judge and ambiguous use counts as procrastination and goes to the review queue.
- A floating panel at the top centre asks "Work or scroll?" when the front place is ambiguous,
  the classifier could only guess, and you have not answered for it today. It waits 5 seconds on
  the same place first. During a focus session a clear distraction shows "at risk — back to work?"
  at once. At most one nudge per site in 10 minutes. Answers last until 04:00; they are not rules.
- The review queue in the popover lists the three largest unclear stretches with the AI's guess.
  "Work" or "Waste" there becomes a permanent rule (`RuleBook.learn`). "Work" also moves those
  seconds from procrastination to work.

## Files

`~/Library/Application Support/Vago/`

- `state.json`: your rules (custom only), the adaptive limit, the ledger of recent days,
  today's totals and sessions, the review queue, today's answers, the focus session, goals.
  Written at most every 5 seconds when something changed, and on quit.
- `usage.json`: flat counters for `./check.sh usage`: `days_tracked`,
  `procrastination_min_today` (all devices), `limit_min`, `avg_procrastination_min_7d`,
  `focus_sessions_7d`, `judge_available`.

A state file that cannot be read is copied to `state.corrupt-<time>.json` before a new one starts.

## How sync works

The iCloud key-value store holds one JSON value per device and day under `Ledger.key(day, device)`
(`day/2026-10-29/mac`). The Mac writes its own key every 30 seconds when its totals changed, and on
quit. It reads every `day/` key at launch and on `didChangeExternallyNotification`, and merges them
into its ledger; the later `updatedAt` wins. The popover and the menu bar read the merged ledger,
so iPhone minutes count toward the limit. Values use VagoKit's shared codec (`DeviceDay.encoded()` and `DeviceDay(encoded:)`: JSON `Data`, ISO 8601 dates).

The store needs the entitlement `com.apple.developer.ubiquity-kvstore-identifier`, which needs the
profile above. Without it the store is skipped and Settings says "iCloud sync off".

## Not verified

- Anything that needs your permission: Accessibility and Automation were not granted during the build
  check, so window titles, browser URLs and the AI judge on real pages were not exercised.
- The Foundation Models judge on this Mac depends on Apple Intelligence being enabled; the build
  check records whether it was available, not how accurate its verdicts are.
- iCloud sync between a Mac and an iPhone. Unit tests do not cover the app target.
- Behaviour across the 04:00 day change and wake from sleep over many hours.
- Several Macs on one Apple Account: they share one `mac` key per day, so the last writer wins.
