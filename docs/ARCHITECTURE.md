# Vago — architecture

Three parts. Each part has its own directory and its own owner:

| Part | Directory | What it is |
|---|---|---|
| VagoKit | `Sources/VagoKit`, `Tests/VagoKitTests` | Pure Swift package: buckets, rules, classifier, mood, adaptive limit, day ledger, focus. No UI, no Apple frameworks beyond Foundation. `swift test` runs it. |
| Mac app | `Mac/`, `mac.yml` | Menu-bar agent (`LSUIElement`), not sandboxed. Tracks the front app, window title and browser URL every second. |
| iPhone app | `iOS/`, `ios.yml` | SwiftUI app plus Screen Time extensions and a widget. |

`project.yml` only includes `mac.yml` and `ios.yml` (XcodeGen `include:`), so the two apps
never edit the same spec file. `xcodegen generate` writes `Vago.xcodeproj` (gitignored).

Signing: team `VWH2FKV78Q`, automatic in Debug. Bundle ids:

| Target | Bundle id |
|---|---|
| iPhone app | `com.zaitsew.vago` |
| DeviceActivityMonitor extension | `com.zaitsew.vago.monitor` |
| ShieldConfiguration extension | `com.zaitsew.vago.shield` |
| ShieldAction extension | `com.zaitsew.vago.shieldaction` |
| DeviceActivityReport extension | `com.zaitsew.vago.report` |
| Widget + Live Activity extension | `com.zaitsew.vago.widgets` |
| Mac app | `com.zaitsew.vago.mac` |
| Mac widget extension | `com.zaitsew.vago.mac.widgets` |

App Group (iPhone app and its extensions): `group.com.zaitsew.vago`.
App Group (Mac app and its widget): `VWH2FKV78Q.com.zaitsew.vago`.
iCloud key-value store, shared by both apps: `$(TeamIdentifierPrefix)com.zaitsew.vago`.

## VagoKit contract

The two apps depend on these public types. Change them only in a VagoKit PR.

```swift
public enum Bucket: String, Codable, Sendable, CaseIterable { case productive, neutral, procrastination, ambiguous }

public enum Device: String, Codable, Sendable { case iphone, mac }

/// What the Mac (or a shield) observed for one second of use.
public struct ActivitySample: Sendable, Equatable {
    public var bundleID: String          // "com.google.Chrome"
    public var appName: String
    public var windowTitle: String?      // front window title, when known
    public var url: URL?                 // front browser tab, when known
}

/// One user or built-in rule. The first matching rule in `RuleBook.rules` wins.
public struct Rule: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var bundleID: String?         // exact match
    public var host: String?             // "instagram.com" matches "www.instagram.com" too
    public var pathPrefix: String?       // "/direct"
    public var titleContains: String?    // case-insensitive
    public var bucket: Bucket
    public var source: Source            // .builtIn, .user, .review, .auto
    public func matches(_ o: ActivitySample) -> Bool
}

public struct RuleBook: Codable, Sendable {
    public var rules: [Rule]             // user and review rules first, then built-ins
    public static let builtIn: RuleBook  // the defaults listed in docs/PRODUCT.md
    public func bucket(for o: ActivitySample) -> Bucket   // .ambiguous when only an ambiguous rule matches
    public mutating func learn(from o: ActivitySample, bucket: Bucket)  // nightly review answer → a .review rule (host+path for web, bundle+title word for apps)
}

/// What the judge sees besides the page: the hour, time in front, the place before, ambiguous or unknown.
public struct JudgeContext: Sendable, Equatable { public var hour: Int?; public var secondsInFront: Int; public var previous: String?; public var ambiguous: Bool }

/// The AI judge for places no rule settles. The Mac app supplies the FoundationModels
/// implementation; tests supply a stub.
public protocol Judge: Sendable {
    func judge(_ o: ActivitySample, goals: String, context: JudgeContext) async -> Verdict?
}
public struct Verdict: Codable, Sendable, Equatable { public var bucket: Bucket; public var confidence: Double; public var reason: String }

/// Classifier = rules, then the day cache, then the judge (docs/PRODUCT.md, "Vago decides").
/// A rule always wins. Ambiguous and unknown places go to the judge. A verdict at 0.7 or more
/// decides; a weaker one, or none, is neutral and `unclear`. No judge: ambiguous is
/// procrastination (unclear), unknown is neutral. `setJudgeTrusted(false)` turns "work" verdicts
/// on ambiguous places into neutral.
public actor Classifier {
    public init(rules: RuleBook, judge: Judge?, goals: String)
    public func classify(_ o: ActivitySample, context: JudgeContext = .init()) async -> Classification
    public func update(rules: RuleBook), update(goals: String), setJudgeTrusted(_: Bool)
}
public struct Classification: Sendable, Equatable {
    public var bucket: Bucket; public var unclear: Bool; public var reason: String
    public var source: Source            // .rule, .answer, .judge, .fallback
    public var ambiguous: Bool           // a rule called the place ambiguous
    public var confidence: Double?; public var verdict: Bucket?   // the judge's sure answer, even when held
}

/// The guard against "it's all research", and the rules learned from sure verdicts.
public struct JudgeAudit: Codable, Sendable { public mutating func record(_ c: Classification, seconds: Int, day: DayKey); public mutating func corrected(on: DayKey); public func trusted(on: DayKey) -> Bool }
public struct VerdictMemory: Codable, Sendable { public mutating func note(_ o: ActivitySample, _ c: Classification, day: DayKey) -> Rule? }   // an .auto rule after 3 sure days
extension RuleBook { public mutating func adopt(_ rule: Rule) }   // .auto rules go behind the owner's rules

/// A 04:00-to-04:00 day.
public struct DayKey: Codable, Hashable, Comparable, Sendable {
    public let id: String                // "2026-10-29"
    public static func of(_ date: Date, calendar: Calendar = .current) -> DayKey
}

/// One device's totals for one day. Seconds.
public struct DeviceDay: Codable, Sendable, Equatable {
    public var day: DayKey
    public var device: Device
    public var procrastination: Int
    public var productive: Int
    public var focus: Int
    public var neutral: Int                       // 0 on the iPhone and in older values
    public var updatedAt: Date
    public var productiveByHour, procrastinationByHour, neutralByHour: [Int]   // 24 slots from 04:00; empty in older values
    public mutating func add(_ bucket: Bucket, seconds: Int, at: Date)          // total and hour slot
    public mutating func move(_ seconds: Int, from: Bucket, to: Bucket, at: Date) -> Int   // a corrected call
    public var hours: [HourSlot]
}
public struct HourSlot { public var slot, productive, procrastination, neutral: Int; public var clockHour: Int }
extension DayKey { public static func hourSlot(of: Date) -> Int; public static func clockHour(ofSlot: Int) -> Int }

/// The main number (docs/PRODUCT.md): 100 − procrastination / (productive + neutral + procrastination).
public struct ProductiveShare { public var percent: Int? /* nil below 15 active minutes */; public var text: String; public var tint: Tint? }
extension Ledger { public func share(for: DayKey, devices: [Device] = .allCases) -> ProductiveShare; public func hours(for: DayKey, devices: [Device] = .allCases) -> [HourSlot] }

/// Sessions the nightly review asks about. The Mac appends; both apps show the top three.
public struct Session: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var start: Date
    public var seconds: Int
    public var sample: ActivitySampleRecord   // Codable twin of ActivitySample
    public var guess: Bucket
    public var reason: String
}

/// All devices' days, merged. The key-value store keeps one JSON value per
/// `day/<day id>/<device>` key; last `updatedAt` wins per key.
/// The key-value store's wire format, the same on both apps: JSON, ISO 8601 dates.
extension DeviceDay { public func encoded() -> Data; public init?(encoded value: Any) }

public struct Ledger: Codable, Sendable {
    public var days: [String: DeviceDay]         // key = "day/<id>/<device>"
    public func total(for day: DayKey) -> (procrastination: Int, productive: Int, focus: Int)
    public mutating func merge(_ other: DeviceDay)
    public func history(endingBefore day: DayKey, count: Int) -> [Int]  // procrastination minutes, oldest first, tracked days only
}

public enum Mood: Sendable, Equatable {
    case beaming, happy, neutral, worried, upset, wrecked
    public var emoji: String
    public var tint: Tint                        // .green, .yellow, .red
    public init(used seconds: Int, limitMinutes: Int)
}
public enum Tint: String, Sendable { case green, yellow, red }

/// The Garmin-style limit in docs/PRODUCT.md. Pure: same inputs, same answer.
public struct AdaptiveLimit: Codable, Sendable, Equatable {
    public static let targetMinutes = 30
    public static let calibrationMinutes = 60
    public static let calibrationDays = 3
    public var baseline: Int?                    // set after calibration
    public var current: Int                      // minutes, today
    public var lastDay: DayKey?
    public init()
    /// Rolls the limit forward to `today` using finished days' procrastination minutes.
    public mutating func roll(to today: DayKey, ledger: Ledger)
}

/// Forest-style session.
public struct FocusSession: Codable, Sendable, Equatable {
    public var start: Date
    public var minutes: Int                      // 25 or 50
    public var distractedSeconds: Int
    public var state: State                      // .growing, .grown, .wilted, .abandoned
    public func stage(at now: Date) -> String    // "🌱", "🌿", "🪴", "🌳", or "🥀"
    public mutating func tick(bucket: Bucket, seconds: Int, now: Date)
}

/// The move reminder: a streak of use at the Mac, a due reminder, a rotation of desk moves.
public struct Move: Codable, Sendable, Equatable, Identifiable { public var id, title, how: String; public static let all: [Move] }
public struct BreakCoach: Codable, Sendable, Equatable {
    public var enabled: Bool                     // default true
    public var streakMinutes: Int                // default 90
    public var move: Move                        // the next suggestion
    public mutating func active(at now: Date)    // use in the second ending at `now`; a 5-minute gap starts a new streak
    public func streakSeconds(at now: Date) -> Int
    public func wantsPanel(at now: Date) -> Bool // due, not snoozed, fewer than 2 unanswered panels
    public func wantsMark(at now: Date) -> Bool  // due: 🚶 in the menu bar
    public mutating func shown(at now: Date), ignore(at:), later(at:), pauseToday(at:), done(at:), swap()
    public func moves(on day: DayKey) -> Int
}

/// The guard (docs/PRODUCT.md): up to three places the owner names, each paused or blocked.
public struct WorkHours: Codable, Sendable, Equatable {
    public var start: Int, end: Int              // minutes after midnight; end <= start crosses midnight
    public var weekdays: Set<Int>                // Calendar weekdays, 1 = Sunday; default 2...6, 09:00-18:00
    public func contains(_ date: Date, calendar: Calendar) -> Bool
    public func blockEnd(containing date: Date, calendar: Calendar) -> Date?   // nil outside work hours
}
public struct GuardedPlace: Codable, Sendable, Equatable, Identifiable {
    public enum Mode: String, Codable, Sendable, CaseIterable { case pause, block }
    public var id: UUID; public var name: String
    public var host: String?; public var bundleID: String?   // host like Rule.host; bundle exact, case-insensitive
    public var mode: Mode
    public func matches(_ o: ActivitySample) -> Bool
}
public struct GuardList: Codable, Sendable, Equatable {
    public static let maxPlaces = 3, passMinutes = 5, pauseSeconds = 5, defaultBudgetMinutes = 30
    public var places: [GuardedPlace]; public var budgetMinutes: Int; public var workHours: WorkHours
    public var enabled: Bool                     // false until setup is finished
    public func place(for o: ActivitySample) -> GuardedPlace?
    public mutating func add(_ p: GuardedPlace) -> Bool   // false at maxPlaces or for a listed host/bundle
    public mutating func remove(_ id: UUID), setMode(_ id: UUID, _ mode: GuardedPlace.Mode)
    public static func proposals(from sessions: [Session], limit: Int) -> [GuardedPlace]   // waste/ambiguous sessions by host or bundle, by seconds
}
public enum GuardAction: Sendable, Equatable { case none, pause(GuardedPlace, overBudget: Bool), block(GuardedPlace, until: Date?) }
public struct GuardState: Codable, Sendable, Equatable {
    public var passes: [UUID: Date]; public var front: UUID?; public var day: DayKey?
    public var pausesShown, closes, passesTaken, unlocks: [UUID: Int]   // today
    public mutating func tick(_ o: ActivitySample?, list: GuardList, isWork: Bool, usedSeconds: Int, now: Date, calendar: Calendar) -> GuardAction
    public mutating func grantPass(_ id: UUID, now: Date), unlock(_ id: UUID, now: Date), closed(_ id: UUID, now: Date)
    public func hasPass(_ id: UUID, now: Date) -> Bool
}

/// The one-icon mode and the "you drifted" notice.
public enum Mode: String, Codable, Sendable, CaseIterable { case work, procrastination, neutral; public init(_ bucket: Bucket) }
public struct DriftWatch: Codable, Sendable, Equatable {
    public static let dwellSeconds = 60, armSeconds = 60
    public mutating func tick(_ mode: Mode, guarded: Bool, now: Date) -> Bool   // true once per drift
    public mutating func idle()
}

/// Formatting shared by the menu bar, widget and Live Activity: "😄 12m", "😟 28/30m".
public enum Readout { public static func short(seconds: Int, limitMinutes: Int) -> String }
```

## Guard and drift

`GuardState.tick` runs once per counted second with the place in front. A place on the `GuardList`
is never guarded when the owner switched it to work, or when the list is not `enabled`. In **pause**
mode the tick returns `.pause` once when the place comes to the front without a valid pass, and once
more when a pass ends while the place stays in front; `overBudget` is true when today's waste has
reached the budget. In **block** mode inside work hours it returns `.block(until: end of the work
block)` on every tick until a deliberate `unlock` gives a 5-minute pass; outside work hours a block
place behaves as pause. `grantPass` ("Open for 5 minutes") also gives 5 minutes. `closed` clears
`front`, so reopening the place pauses again. A new `DayKey` clears passes and the daily counters.
`DriftWatch.tick` returns true once when 60 continuous seconds of procrastination follow at least 60
seconds of work since the last notice: neutral seconds are ignored, a guarded place never counts
(its pause is the signal), and `idle()` resets the streak but keeps the arming. `Mode(Bucket)` maps
productive to work, procrastination and ambiguous to procrastination, and neutral to neutral.

## Mac app

- **Tracker**: a 1-second timer. It reads the frontmost app (`NSWorkspace`). For Safari,
  Chrome, Arc, Brave, Edge and Dia it reads the front tab URL and title through Apple Events
  (`NSAppleScript`); for other apps it reads the focused window title through Accessibility
  (`AXUIElement`).
- **Idle**: no input for 120 seconds stops counting. For video sites (YouTube, Netflix, Twitch,
  Prime Video) the threshold is 20 minutes, because watching needs no input. A locked screen
  or sleep always stops counting.
- **Judge**: `FoundationModelsJudge` uses `LanguageModelSession` with a `@Generable` verdict.
  When `SystemLanguageModel.default.availability` is not `.available`, the classifier runs
  without a judge. Model-routing note (POLICY §1): on-device, because window titles are
  private, the call runs every few seconds, and the on-device model is free.
- **Autonomy**: `AppModel.process` builds a `JudgeContext` (local hour, seconds the place has
  been in front, the previous place within 10 minutes as "Xcode (work)") for every
  classification. Each classifier result goes to `JudgeAudit.record` and `VerdictMemory.note`; a
  rule the memory returns is adopted (`RuleBook.adopt`) and handed to the classifier. At launch,
  at day start and after a correction the classifier gets `setJudgeTrusted(JudgeAudit.trusted)`;
  `AppModel.judgeHeld` shows the hold. Both structs persist in `state.json`.
- **Corrections**: `correctCurrent(as:)` (the popover's Wrong?) and `correctCall(_:as:)` (the Day
  window) learn a `.review` rule, move the sessions' seconds hour by hour with `DeviceDay.move`,
  and call `JudgeAudit.corrected(on:)`. Unsure calls stay in `reviewPending` until corrected.
- **Nudge**: no daytime question about a place. The evening review no longer opens by itself
  (`AppModel.offersEveningReview` is false, decision 01); the Day window keeps its calls list and
  the Lab switch can still open the review. The focus-session distraction nudge is unchanged.
- **Core loop** (decision 01, `AppModel+Guard.swift`): every counted second `process` classifies,
  applies the owner's toggle, then calls `runGuard`.
  - *Toggle*: `toggles[PlaceKey]` (host for a web page, bundle id for an app) is a `Bucket`. It wins
    over answers, rules and the judge (reason "your toggle", not a call in the Day window), and a
    place toggled to work is never paused, blocked or reported. Time counts by the toggle from the
    second it is flipped. It clears when the owner leaves the place and at the day change (decided 13
    November 2026). The popover's switch is an explicit capsule (`WorkSwitch`): green when on. Vago's own windows never count as leaving a place:
    `toggleTarget` keeps the last real place while the popover has the focus.
  - *Guard*: `GuardState.tick` with `isWork` = toggled to work and `usedSeconds` = today's waste.
    `.pause` shows the pause card (`GuardPanels`): 5 seconds, then **Close** (closes the tab through
    Apple Events, Safari `close current tab of front window`, Chromium browsers `close active tab of
    front window`, or hides the app) and **Open for 5 min** (`grantPass`). `.block` closes the tab
    or hides the app at most once a second and shows the block panel once per entry; the deliberate
    unlock (`GuardState.unlock`) is a 3-second hold. Over budget, the ready pause card keeps the orange
    ring and shows an exclamation mark, never a green check.
  - *Drift notice*: `DriftWatch.tick(Mode(bucket), guarded:)` per second, `idle()` when locked or
    idle. A true result posts a local notification (`NoticeCenter`): "Procrastination · Instagram"
    and "12 of 30 min today", a statement, never a question. Variant B adds a "Switch to work"
    action. Authorization is asked for when setup finishes.
  - *Setup* (`SetupWindow`): first run of the loop and later "Guarded places..." in Settings. The
    owner taps up to 3 places that took the most time; a picked place shows its control (Pause: a
    timer ring, "5 s wait"; Block: a lock, "until 18:00"). Variant A is a wall of tiles, B the same
    places ranked as bars. The budget (30) and the work hours (Mon-Fri 9-18) are already set and sit
    behind one "Change" popover; with 3 drains picked on a first run, Done works at once. Done sets
    `guardList.enabled`. A place no tile shows is added with "Add a site".
  - *Place week* (`PlaceWeek`, `Mac/PlaceWeek.swift`): the Ledger keeps only day totals, so the Mac
    app keeps its own archive in `state.json`: day id, then place key (`h:host` or `b:bundleid`), then
    waste seconds. Seconds only; no titles, no URLs beyond the host. Pruned to the last 7 tracked days
    on every day change. The setup ranks places by it. The period line says "this week" only when 7
    days exist, "in the last N days" before, and "today" for one day; today's sessions fill in a
    place the archive has not seen yet. Not VagoKit: nothing in the contract changed.
  - *State*: `state.json` gains `guardList`, `guardState`, `drift`, `toggles`, `variants` and
    `setupOffered` and `placeWeek`, all with decode defaults.
- **Design variants**: the screens still undecided have two designs (`DesignVariants`,
  `Mac/Design.swift`): setup and notice. Decided on 13 November 2026: mode icon B (the pill), toggle B,
  pause A (the card), block A (hold); their old keys in `state.json` are ignored. `defaults write com.zaitsew.vago.mac
  variant.<screen> b` is read at launch; Settings has a hidden "Design variants" section (hold
  Option when Settings first opens, or set the `showVariants` default). Debug builds take
  `--render-variants <dir>`: it writes PNGs of the screens from sample data and
  exits before any state is loaded. The drift banner PNGs are mocks (`-MOCK`).
- **Menu bar**: an `NSStatusItem` whose attributed title is the mood emoji and the productive
  share (`😄 92%`), tinted by `Mood`, after the mode pill: a capsule tinted 18% with its word in the
  full colour, WORK green, WASTE red, and a grey moon when neutral. During focus it shows the stage
  emoji and the minutes left. Left click opens the popover. Right click opens a menu whose first
  item is "Switch <place> to work" (or to procrastination), then Day, Settings…, Quit.
- **Move breaks**: every counted second feeds `BreakCoach.active`. When `wantsPanel` is true
  and no focus session runs and the microphone is idle (`Microphone.inUse`, a CoreAudio device
  property; Vago never opens the microphone), the panel shows at the next app switch or after
  3 minutes. It shares `NudgePanel` with the nudge and never replaces an open nudge.
- **Popover** (`PopoverView`): a fixed 340-point layout with no scroll view and nothing that
  expands: the mode row (badge, place in front, one Work switch), the productive share across devices, mood and the waste limit, the `DayStrip`, the Now
  line with Wrong?, focus, the move row, and Day / Settings… / Quit.
- **Day window** (`DayWindow`, an `NSWindow` hosting SwiftUI, made once and reused): the share
  with a device filter, the large `DayStrip` with hour tooltips, top waste and top work (Mac
  sessions), and Vago's calls with a Work / Neutral / Waste correction. Earlier days from the
  ledger show the share and the strip.
- **Strings**: every user-facing string of the Mac app and the widget is in a String Catalog
  (`Mac/Localizable.xcstrings`, `MacWidgets/Localizable.xcstrings`), English only for now, a comment
  per key. SwiftUI literals localize by key; plain strings use `String(localized:comment:)`. Both
  targets set `SWIFT_EMIT_LOC_STRINGS`; `xcodebuild` does not write the catalog, so new keys are merged
  with `xcstringstool sync <catalog> --stringsdata <files>` from the build's `.stringsdata`. Not
  catalogued: stored call reasons ("your toggle"), the AI judge's prompt, and VagoKit's move texts.
- **Settings window** (`SettingsWindow`, same host): goals, launch at login, move reminders,
  guarded places and the guard switch, permissions, the AI judge state, iCloud, and Forget learned rules.
- **DayStrip**: one lane per device, one stacked cell per hour (work, neutral, waste), from
  `Ledger.hours(for:devices:)`; at least 07:00–23:00.
- **Desktop widget** (`VagoMacWidgets`, `MacWidgets/`): "Vago — today", small and medium. The
  app writes `widget.json` (`WidgetSnapshot`, `Mac/WidgetSnapshot.swift`) into the App Group
  container `VWH2FKV78Q.com.zaitsew.vago`; the widget only reads it, so it needs no iCloud and no
  VagoKit state. The snapshot holds the merged day for all devices (the app's ledger already has
  the iPhone's day from iCloud): percent (nil before 15 active minutes), work, neutral and waste
  minutes, the limit, Mac and iPhone hour slots, the mood emoji and two timestamps.
  `flush` writes it at most once a minute (at once when the percent or the day changes) and calls
  `WidgetCenter.reloadAllTimelines()` at most every 5 minutes (same exceptions). The timeline has
  one entry and `.after(now + 15 min)`; a snapshot from another day or none shows "—", never
  yesterday's number. A tap opens `vago://day`, which the app delegate turns into the Day window.
  The widget is sandboxed and compiled with `DayStrip.swift` and `Style.swift`. On macOS a
  team-prefixed group needs no provisioning profile.
- **Control Center control** (`VagoModeControl`, `MacWidgets/`, macOS 26 `ControlWidgetToggle`):
  "Vago mode", on = the place in front is work, labelled with the place, tinted by mode. The app
  writes `mode.json` (`ModeSnapshot`, `Mac/ModeBridge.swift`, compiled into both targets) into the
  App Group and calls `ControlCenter.reloadControls` when the place or mode changes, at most every 3
  seconds. The control's `SetValueIntent` writes `mode-request.json` and posts the Darwin
  notification `com.zaitsew.vago.mac.mode-request`; the app (`DarwinObserver`) reads the file,
  deletes it and applies the toggle.
- **Signing**: the app takes its entitlements and profile from `VAGO_MAC_ENTITLEMENTS` and
  `VAGO_MAC_PROFILE`, which `install-mac.sh` sets. A command-line `CODE_SIGN_ENTITLEMENTS`
  would reach the widget target too and give it the app's entitlements.
- **Storage**: `~/Library/Application Support/Vago/state.json` (rules, limit, sessions,
  focus, breaks, judge audit, verdict memory, guard list and state, drift watch, toggles, variants). Today's `DeviceDay` is written to the key-value store every 30 seconds.
  `~/Library/Application Support/Vago/usage.json` holds the counters `./check.sh usage` prints.
- **Install**: `scripts/install-mac.sh`, signed for this Mac like Knut's. No Mac App Store
  build: the tracker needs Accessibility and Apple Events, which the sandbox does not allow.

## iPhone app

Apple's Screen Time API never shows an app what is on screen and never hands it raw usage.
The app learns usage only from thresholds the system reports to the monitor extension.

- **Onboarding**: `AuthorizationCenter.requestAuthorization(for: .individual)`, then three
  `FamilyActivityPicker`s: procrastination (suggest Social, Entertainment, Games), ambiguous
  (Instagram, YouTube, X, LinkedIn, Telegram…), productive. Selections are saved in the App
  Group.
- **Counting**: one daily `DeviceActivitySchedule` (04:00 to 03:59, repeating) with threshold
  events on the procrastination selection and on the ambiguous selection: every minute up to
  45, every 5 up to 120, every 15 up to 240. The monitor extension writes the latest minute
  per selection to the App Group and to today's `DeviceDay`.
- **Intent check**: the ambiguous selection is shielded. `ShieldConfigurationExtension`
  shows the mood emoji, "12 of 30 min today" and two buttons: "Work · 15 min" and
  "Scroll · 5 min". `ShieldActionExtension` removes the shield and records a pass with its
  kind. It then starts a `pass` activity whose usage-threshold event (15 or 5 minutes)
  re-applies the shield in the monitor extension. Ambiguous minutes count as productive
  during a work pass and as procrastination otherwise.
- **Focus**: during a focus session the app shields procrastination and ambiguous apps. A
  `focus` activity's interval end lifts the shield. The minimum schedule length is 15 minutes,
  which fits 25 and 50.
- **Hours**: when the monitor applies a threshold (`DayCounters.apply`), the minutes it added
  go into the hour slot of the moment the event arrived, as productive or procrastination
  (ambiguous minutes follow the pass: work → productive, otherwise procrastination). The hour
  lists live in `DayCounters` in the App Group, with defaults so older counters load, and
  `VagoStore.publishToday` copies them into the iPhone `DeviceDay` next to the totals, which
  also come from the counters, so totals and hours agree. A threshold that adds several minutes
  (steps of 5 and 15 past 45 minutes) lands in the hour it was reported, not spread back over the
  hours it covered. The iPhone has no neutral time.
- **Today tab**: the hero is `Snapshot.share` (`ProductiveShare`, merged ledger) in large rounded
  type tinted by its tint, with "work · neutral · waste" under it ("—" and "Building today's
  picture" below 15 active minutes). Then the mood emoji with a bar of waste against the limit,
  the day strip, the device lines (each with its own share) and the Focus card. `DayStrip`
  (`iOS/SharedUI`) draws hour columns from the first to the last hour with data (at least
  07:00 to 23:00), two lanes (Mac, iPhone), each cell a stacked bar work / neutral / waste;
  a tap shows "14:00 · Mac 42m work · iPhone 11m waste". The caption says iPhone minutes lag
  and when the Mac last wrote (`Snapshot.macUpdatedAt`).
- **Widget and Live Activity**: the widget "Vago — today" shows the share, the mood and waste
  against the limit (small), the share with the day strip and "updated hh:mm" (medium), and a
  gauge, a bar or one line on the Lock Screen. Its timeline provider merges the Mac's day from
  `NSUbiquitousKeyValueStore` itself (the widget has the app's key-value identifier,
  `CloudRead`) and does not write the ledger back. The monitor extension reloads the widget's
  timeline at each threshold. The Live Activity is started
  from the app; the extension updates it where ActivityKit allows. Background widget reloads
  have a daily budget, so the widget can lag a few minutes. That is a platform limit, measured
  on device and written in `docs/RELEASE.md`.
- **Report**: a `DeviceActivityReport` extension renders Screen Time's own per-app totals for
  today across devices, as the source of truth for the user.
- **Sync**: the app reads and writes `DeviceDay` values in the key-value store and shows the
  merged ledger, so Mac minutes appear on the iPhone and the other way round.

## AI tools

App Intents on the iPhone (`iOS/App/Intents/`) and a read-only stdio MCP server, `vago-mcp`
(`Sources/vago-mcp`, over VagoKit's `StateFile` and `VagoMCPServer`), on the Mac. See
[AI.md](AI.md). `Ledger.summary(for:)` and `weekSummary(endingOn:)` are the shared numbers.

## Privacy

No server, no analytics, no account. The data stays on the devices and in the owner's iCloud
key-value store. The AI judge runs on the Mac. `PrivacyInfo.xcprivacy` declares
`UserDefaults` access (CA92.1, 1C8F.1 for the App Group).

## Distribution

- Mac: `scripts/install-mac.sh` on the owner's Mac.
- iPhone: Debug from Xcode on the owner's iPhone now. TestFlight (internal) needs Apple's
  Family Controls (Distribution) entitlement for the app and each extension. Apple grants
  it by hand, through the form at
  developer.apple.com/contact/request/family-controls-distribution.
- No App Store submission: the seller account is on a submission hold (POLICY §14).
