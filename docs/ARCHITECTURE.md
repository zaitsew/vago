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

App Group (iPhone app and its extensions): `group.com.zaitsew.vago`.
iCloud key-value store, shared by both apps: `$(TeamIdentifierPrefix)com.zaitsew.vago`.

## VagoKit contract

The two apps depend on these public types. Change them only in a VagoKit PR.

```swift
public enum Bucket: String, Codable, Sendable, CaseIterable { case productive, neutral, procrastination, ambiguous }

public enum Device: String, Codable, Sendable { case iphone, mac }

/// What the Mac (or a shield) observed for one second of use.
public struct Observation: Sendable, Equatable {
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
    public var source: Source            // .builtIn, .user, .review
    public func matches(_ o: Observation) -> Bool
}

public struct RuleBook: Codable, Sendable {
    public var rules: [Rule]             // user and review rules first, then built-ins
    public static let builtIn: RuleBook  // the defaults listed in docs/PRODUCT.md
    public func bucket(for o: Observation) -> Bucket   // .ambiguous when only an ambiguous rule matches
    public mutating func learn(from o: Observation, bucket: Bucket)  // nightly review answer → a .review rule (host+path for web, bundle+title word for apps)
}

/// The AI judge for ambiguous observations. The Mac app supplies the FoundationModels
/// implementation; tests supply a stub.
public protocol Judge: Sendable {
    func judge(_ o: Observation, goals: String) async -> Verdict?
}
public struct Verdict: Codable, Sendable, Equatable { public var bucket: Bucket; public var confidence: Double; public var reason: String }

/// Classifier = rules, then the day cache, then the judge. A verdict under 0.6 confidence,
/// or no judge, counts as procrastination and is queued for review (`unclear == true`).
public actor Classifier {
    public init(rules: RuleBook, judge: Judge?, goals: String)
    public func classify(_ o: Observation) async -> Classification
}
public struct Classification: Sendable, Equatable { public var bucket: Bucket; public var unclear: Bool; public var reason: String }

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
    public var updatedAt: Date
}

/// Sessions the nightly review asks about. The Mac appends; both apps show the top three.
public struct Session: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var start: Date
    public var seconds: Int
    public var observation: ObservationRecord   // Codable twin of Observation
    public var guess: Bucket
    public var reason: String
}

/// All devices' days, merged. The key-value store keeps one JSON value per
/// `day/<day id>/<device>` key; last `updatedAt` wins per key.
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

/// Formatting shared by the menu bar, widget and Live Activity: "😄 12m", "😟 28/30m".
public enum Readout { public static func short(seconds: Int, limitMinutes: Int) -> String }
```

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
- **Menu bar**: an `NSStatusItem` whose attributed title is `Readout.short` tinted by `Mood`.
  During focus it shows the stage emoji and the minutes left.
- **Popover**: today's procrastination, work and focus across devices; the limit and
  baseline; top distractions; Start focus 25 / 50; the review queue; settings (goals text,
  rules, launch at login).
- **Storage**: `~/Library/Application Support/Vago/state.json` (rules, limit, sessions,
  focus). Today's `DeviceDay` is written to the key-value store every 30 seconds.
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
- **Widget and Live Activity**: the widget shows `Readout.short` and the mood tint. The monitor
  extension reloads the widget's timeline at each threshold. The Live Activity is started
  from the app; the extension updates it where ActivityKit allows. Background widget reloads
  have a daily budget, so the widget can lag a few minutes. That is a platform limit, measured
  on device and written in `docs/RELEASE.md`.
- **Report**: a `DeviceActivityReport` extension renders Screen Time's own per-app totals for
  today across devices, as the source of truth for the user.
- **Sync**: the app reads and writes `DeviceDay` values in the key-value store and shows the
  merged ledger, so Mac minutes appear on the iPhone and the other way round.

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
