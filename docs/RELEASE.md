# Vago iPhone — run and release

Status: internal TestFlight (see below). No App Store or beta-review submission: the seller
account is on a submission hold (POLICY section 14).

## Run on the iPhone now

Family Controls has a development entitlement that works in Debug builds on a real device,
signed with the team's automatic profiles. It does nothing in the Simulator: there the
Screen Time authorization sheet, the pickers, the shields and the monitor do not run. The
Simulator is good for layout only.

1. Install XcodeGen (`brew install xcodegen`) and run `xcodegen generate` in the repository root.
   `project.yml` includes `mac.yml` and `ios.yml`; until the Mac spec is merged, create an
   untracked `mac.yml` containing `targets: {}`.
2. Open `Vago.xcodeproj`, pick the `Vago` scheme and your iPhone, press Run. Xcode creates the
   App ID, the App Group `group.com.zaitsew.vago` and the iCloud key-value container for the
   app and for each extension on first run (team `VWH2FKV78Q`, automatic signing).
3. On the phone: sign in to iCloud, and in Settings > Screen Time turn on **Share Across
   Devices** (the Report tab shows all devices only with it).
4. Open Vago, allow Screen Time, pick the three lists, tap "Start counting".

Check that it works: open an app from the "Work or scroll" list, choose Work, use the app for a
minute and come back. Today shows the count after the next threshold report (see limits below).
Settings > Counting > "Last report" shows when the monitor last heard from Screen Time.

## TestFlight

App Store Connect record: **Vago: Focus Timer**, app id `6828551197`, SKU `vago`, bundle
`com.zaitsew.vago`, primary language English (U.S.), created 2026-10-29. The plain name "Vago"
was taken on the store.

First build: 0.1.0 (1), uploaded 2026-10-29. Testers: the internal group "Team" (created through
the API, access to all builds, no beta review) with ceozaitsev@gmail.com. `testflight beta
group` only makes external groups, which need beta review.

Upload (internal testing only; no beta or App Store review while the hold stands):

```
xcodegen generate
~/ops/bin/testflight release --project Vago.xcodeproj --scheme Vago --bundle-id com.zaitsew.vago \
    --also-bundle-id com.zaitsew.vago.monitor --also-bundle-id com.zaitsew.vago.shield \
    --also-bundle-id com.zaitsew.vago.shieldaction --also-bundle-id com.zaitsew.vago.report \
    --also-bundle-id com.zaitsew.vago.widgets
```

Release archives sign manually with Apple Distribution and the `<bundle id> AppStore` profiles
(`ios.yml`). After any App ID capability change, recreate them with
`~/ops/bin/testflight bootstrap --refresh-profiles` and the six `--bundle-id` values above.

### Family Controls (Distribution)

The development entitlement is for Xcode builds only. TestFlight and the App Store need Apple's
**Family Controls (Distribution)** entitlement, which Apple grants by hand. It was requested on
2026-10-29 (request ID `UV8Q3ZRHY8`, one request per team: Fabrique Futur LLC, `VWH2FKV78Q`;
replies go to dev@fafutur.com) and approved the same day. Submitting it accepted Apple's Family
Controls terms for the team: the app's primary purpose is parental controls or personal focus
and productivity, and usage data serves only those controls (no sharing, advertising or data
brokers).

App ID capabilities, set in the developer website on 2026-10-29 (the App Store Connect API
cannot set Family Controls or App Group membership):

| Bundle id | Target | Family Controls | App Group `group.com.zaitsew.vago` | iCloud |
|---|---|---|---|---|
| `com.zaitsew.vago` | Vago (app) | Development + Distribution | yes | yes (key-value store) |
| `com.zaitsew.vago.monitor` | VagoMonitor | Development + Distribution | yes | no |
| `com.zaitsew.vago.shield` | VagoShield | Development + Distribution | yes | no |
| `com.zaitsew.vago.shieldaction` | VagoShieldAction | Development + Distribution | yes | no |
| `com.zaitsew.vago.report` | VagoReport | Development + Distribution | yes | no |
| `com.zaitsew.vago.widgets` | VagoWidgets | no | yes | no |

## Platform limits

These come from Apple's Screen Time API, not from Vago. They are the reason the numbers can lag.

- **Threshold granularity.** Vago learns usage only from threshold events: every minute up to
  45, every 5 minutes up to 120, every 15 minutes up to 240, per list. The counter is the
  highest threshold reached, so between 45 and 120 minutes it moves in steps of 5, and past 120
  in steps of 15. Usage past 240 minutes on one list is not counted further. The Work list is counted the same way and adds to productive time. The system
  reports usage in whole minutes and does not say which app ran.
- **Callbacks are not on time.** `eventDidReachThreshold` can arrive late, twice, out of order,
  or (rarely) not at all. The counters only move up, so a duplicate or old callback is ignored,
  but a lost callback shows only when a later threshold arrives. Reported flakiness: callbacks
  stop after a reboot until the app is opened once; restarting a schedule resets the system's
  count unless `includesPastActivity` is set (Vago sets it); many events per schedule (Vago
  registers 68 per list, 204 in all) can make `startMonitoring` fail with `excessiveActivities`
  on some devices. The error shows in Settings > Counting, and "Restart counting" re-registers.
- **Work or scroll minutes.** The new minutes between two ambiguous thresholds go to the pass
  that covers them. A callback that arrives after the pass ended (up to 10 minutes) still
  belongs to that pass. Use outside any pass (for example before the first shield is applied)
  counts as procrastination.
- **Passes.** The `pass` schedule is 60 minutes long, because Apple's minimum interval is 15
  minutes. A pass ends at 15 (Work) or 5 (Scroll) minutes of use, or after 60 minutes,
  whichever comes first. If starting the pass monitoring fails, the shield stays on rather than
  leaving an open door.
- **Widget reloads.** The monitor asks WidgetKit to reload the timeline at every threshold, but
  the system budgets background reloads per day and may skip them. The widget also refreshes
  itself every 15 minutes. Expect it to lag a few minutes. This has to be measured on the
  device; no figure is recorded yet.
- **Live Activity update path.** Only the app can start a Live Activity. The monitor extension
  calls `Activity.update` after every threshold and waits at most two seconds; ActivityKit
  compiles in the extension, but whether the system lets the update through from a background
  extension is unverified on a device. If it does not, the Live Activity shows the numbers as
  of the last time the app ran, and the app refreshes it on foreground. A Live Activity also
  ends by itself after 8 hours; opening the app starts a new one. The focus tree in the Live
  Activity is the stage at the last update, while the countdown and progress bar run on their
  own.
- **Report.** The report extension is sandboxed and cannot write out. It shows Screen Time's
  own per-app totals; Vago's counters come from thresholds, so the two can differ by a few
  minutes. iOS 26.4 adds `DeviceActivityData.activityData(filteredBy:using:)`, which may let
  the app read usage directly; Vago does not use it yet.
- **Focus.** A focus session shields the procrastination and "work or scroll" lists. A
  session ends through the `focus` schedule's interval end, and the app also settles it on
  foreground, so a late callback cannot leave the shield on once the app opens.
- **iCloud.** The key-value store syncs within seconds to minutes and needs the same iCloud
  account on both devices. Each device writes only its own key, `day/<id>/<device>`.

## Overlapping lists

When saving, Vago removes single apps and web domains from a broader list if a narrower list
holds them (Work over "Both", "Both" over Procrastination), so a minute counts once. Screen
Time offers no way to subtract an app from a whole category. If Procrastination holds a
category (Social, say) and an app of that category is also on a narrower list, that app's
minutes are counted by both lists. Settings shows a warning when a list with a category sits
beside a non-empty narrower list. Prefer single apps over categories where the lists overlap.

## Known gaps

- A threshold callback that arrives late is attributed to the latest pass, so a delayed ambiguous minute can go to the wrong kind (`DayCounters.swift`, `apply`).
- Pre-focus usage whose callback arrives after a focus session starts is charged to that session as distraction (`VagoMonitorExtension.swift`, `eventDidReachThreshold`).
- A focus session that crosses 04:00 credits its whole length to the day it started in (`VagoStore.swift`, `focusSeconds`).
