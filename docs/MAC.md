# Vago for Mac

A menu-bar app. It counts work, neutral and wasted time from what is on screen, decides
unclear places with the on-device AI, shows the day's productive share in the menu bar, and
shares daily totals with the iPhone through iCloud. Spec: `docs/PRODUCT.md`, `docs/ARCHITECTURE.md` (Mac app).

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

On first run Vago asks for Accessibility; until it is on, the popover's Now line says so and
offers **Allow**. macOS asks for Automation the first time each browser is in front. The
Settings window shows both states and opens the right System Settings pane. A denied browser shows as "denied"; allow it under
Privacy & Security > Automation.

## What is tracked

Once a second, while someone is at the Mac:

- the front app (bundle id, name);
- for a browser, the front tab's URL and title; for other apps, the focused window's title;
- the result goes through `VagoKit.Classifier`: rules first, then the on-device model for
  ambiguous and unknown places. One second is added to today's work, neutral or procrastination,
  in the day total and in its hour slot. Neutral time counts on the productive side of the share.

Counting stops on a locked screen, sleep, a switched-away user session, and after 120 seconds
without input (20 minutes while a YouTube, Netflix, Twitch or Prime Video page or app is in front).

Nothing leaves the Mac except the day's totals and hour slots in iCloud's key-value store. Window titles
and URLs stay in `state.json`, in the sessions of the current day only.

## The menu bar and the popover

The menu bar shows the mood for the waste limit and the productive share: `😄 92%`, tinted by
mood. Before 15 active minutes it reads `😄 —`. During focus it shows the tree and the minutes
left; a 🚶 follows while a move is due. Right click: Day, Settings…, Quit Vago.

The popover is 340 points wide and has a fixed layout; nothing in it expands or scrolls.
Top to bottom:

- **Productive share** across devices in large type, tinted green, yellow or red, with
  `3h 12m work · 40m neutral · 41m waste` under it ("12 min so far" before 15 minutes).
- **Mood and limit**: the emoji and a thin bar, "18 of 30 min waste".
- **Day strip**: one lane per device (Mac, iPhone), one cell per hour from 07:00 to 23:00 (wider
  when there is use outside it). A cell is a stacked bar: work green, neutral gray, waste orange.
- **Now**: the place in front and Vago's call ("Now: github.com — work"); the AI's reason on
  hover. **Wrong?** counts the place as work, neutral or waste for today and from now on. Hidden
  for places a rule calls neutral. "Paused" when idle or locked.
- **Focus 25 / Focus 50**, or the tree, the minutes left and **Stop**.
- **Move**: the time since the last break and today's moves, or, when a move is due,
  "90 min at the Mac — <move>" with **Done** and **Later** (its menu has **Not today**).
- **Day** (⌘D), **Settings…** (⌘,), **Quit** (⌘Q).

## The Day window

**Day** opens a resizable window titled with the date. It shows the share and its split, a
device filter (All, Mac, iPhone) that changes both, and the day strip in large cells with the
minutes of each hour on hover. iPhone minutes come from Screen Time reports and can lag a few
minutes. For today it also lists:

- **Top waste** and **Top work**: the five largest sites or apps. Mac only: the iPhone does not
  report per-app minutes to Vago.
- **Vago's calls**: the places the AI judged or was unsure about, grouped by site or app, largest
  first, at most eight, with the AI's reason. Unsure calls carry an "unsure" badge. The Work /
  Neutral / Waste control corrects a call: its minutes move in the day total and in their hours,
  the place gets a rule (`RuleBook.learn`), and the judge's hold lifts for the day.

The arrows step through earlier days in the ledger. Past days show the share and the strip only;
sessions are kept for the current day.

## The Settings window

Goals text (the AI judges against it), launch at login, move reminders and their interval,
the Accessibility and Automation states, the AI judge (on, held or unavailable), iCloud sync,
and the number of learned rules with **Forget learned rules…** (after a confirmation it removes
the rules from corrections and the `.auto` rules; built-ins and the owner's own rules stay).

## The AI judge and the nudge

- `FoundationModelsJudge` uses Apple's on-device model (`LanguageModelSession`, a `@Generable`
  verdict). It sees the goals text, the app, site and title, the local hour, how long the place
  has been in front, and the place before it within 10 minutes ("Xcode (work)"). If the model is
  not available (Apple Intelligence off, model still downloading), mixed apps count as waste and
  are marked unsure, and unknown places are neutral.
- A verdict at 0.7 confidence or more decides. A weaker one is neutral and marked unsure in
  Vago's calls.
- `JudgeAudit` records every sure verdict on a mixed place. After three days of mostly "work" on
  feeds the judge is held: its work calls on mixed places count as neutral until a normal day or
  a correction. Settings and Vago's calls show "held".
- `VerdictMemory` turns the same sure verdict on an unknown place on three days into an `.auto`
  rule, so the judge is asked less and the answer stays put.
- A floating panel asks "Work or scroll?" only when the place is mixed, the call is unsure, and
  you have stayed on it for a minute; at most once per place per day. During a focus session a
  clear distraction shows "at risk — back to work?" at once. Answers last until 04:00.

## Move breaks

After 90 minutes at the Mac without a 5-minute break, a panel at the top centre names one desk
exercise with exact reps. "I did it" counts it, "Another" swaps it, "Later" asks again in 15
minutes. Unanswered, it closes after 90 seconds and asks once more after 25 minutes; after two
misses only 🚶 stays in the menu bar until the next break. It waits during focus and calls (any
app using the microphone), plus one minute. Settings: on or off, and 45 to 120 minutes. Rules:
`docs/PRODUCT.md`, Move breaks. The popover's Move row shows the same reminder.

## Files

`~/Library/Application Support/Vago/`

- `state.json`: your rules (custom only), the adaptive limit, the ledger of recent days,
  today's totals and sessions, the unsure calls, today's answers, the focus session, goals,
  the judge audit and the verdict memory.
  Written at most every 5 seconds when something changed, and on quit.
- `usage.json`: flat counters for `./check.sh usage`: `days_tracked`,
  `procrastination_min_today` (all devices), `limit_min`, `avg_procrastination_min_7d`,
  `focus_sessions_7d`, `judge_available`, `moves_today`, `moves_7d`,
  `productive_percent_today` (all devices; -1 before 15 active minutes), `auto_rules`.

A state file that cannot be read is copied to `state.corrupt-<time>.json` before a new one starts.

## How sync works

The iCloud key-value store holds one JSON value per device and day under `Ledger.key(day, device)`
(`day/2026-10-29/mac`). The Mac writes its own key every 30 seconds when its totals changed, and on
quit. It reads every `day/` key at launch and on `didChangeExternallyNotification`, and merges them
into its ledger; the later `updatedAt` wins. The popover, the Day window and the menu bar read the
merged ledger, so iPhone minutes count toward the share and the limit. Values use VagoKit's shared codec (`DeviceDay.encoded()` and `DeviceDay(encoded:)`: JSON `Data`, ISO 8601 dates).

The store needs the entitlement `com.apple.developer.ubiquity-kvstore-identifier`, which needs the
profile above. Without it the store is skipped and Settings says "iCloud sync off".

## Not verified

- Anything that needs your permission: Accessibility and Automation were not granted during the build
  check, so window titles, browser URLs and the AI judge on real pages were not exercised.
- The Foundation Models judge on this Mac depends on Apple Intelligence being enabled; the build
  check records whether it was available, not how accurate its verdicts are.
- iCloud sync between a Mac and an iPhone. Unit tests do not cover the app target.
- Behaviour across the 04:00 day change and wake from sleep over many hours.
- The move reminder on a real day: the panel's timing, the call hold with each meeting app, and
  whether two misses per streak is the right cap. Unit tests cover `BreakCoach` only.
- Several Macs on one Apple Account: they share one `mac` key per day, so the last writer wins.
- The popover, Day and Settings windows were built and checked for layout, not used for a full
  day; the judge's context and the learned rules have no app-level tests.
