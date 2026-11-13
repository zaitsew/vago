import AppKit
import Foundation
import SwiftUI
import VagoKit

/// Waste seconds per place for the last 7 tracked days, so the setup can show what each place
/// took. The Ledger keeps only day totals. Seconds only: no titles, no URLs; the key is the host
/// or the bundle id, the same two values `PlaceKey` already uses. Stored in `state.json`.
struct PlaceWeek: Codable, Equatable, Sendable {
    static let keptDays = 7

    /// Day id ("2026-11-13") to place key ("h:instagram.com", "b:com.apple.news") to seconds.
    var days: [String: [String: Int]] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        days = try c.decodeIfPresent([String: [String: Int]].self, forKey: .days) ?? [:]
    }

    private enum Keys: String, CodingKey { case days }

    /// "h:host" for a web page, "b:bundleid" for an app, lower case.
    static func key(for sample: ActivitySample) -> String {
        if let host = sample.host { return "h:" + host.lowercased() }
        return "b:" + sample.bundleID.lowercased()
    }

    /// Marks `day` as tracked, even when nothing wasted was seen on it.
    mutating func touch(_ day: DayKey) {
        if days[day.id] == nil { days[day.id] = [:] }
    }

    /// Stores a finished day's waste seconds per place, replacing what the day held.
    mutating func record(_ seconds: [String: Int], day: DayKey) {
        days[day.id] = seconds.filter { $0.value > 0 }
    }

    /// Waste seconds per place key in `sessions`, as they read now (corrections included).
    static func waste(in sessions: [Session]) -> [String: Int] {
        var sums: [String: Int] = [:]
        for s in sessions where s.guess == .procrastination || s.guess == .ambiguous {
            sums[key(for: s.sample.sample), default: 0] += s.seconds
        }
        return sums
    }

    /// Keeps the last `keptDays` tracked days. Called on every day change.
    mutating func prune() {
        let keep = Set(days.keys.sorted().suffix(Self.keptDays))
        days = days.filter { keep.contains($0.key) }
    }

    /// Seconds per place key over every kept day except `excluded` (today, read from sessions).
    func totals(excluding excluded: DayKey) -> [String: Int] {
        var sums: [String: Int] = [:]
        for (id, day) in days where id != excluded.id { for (key, seconds) in day { sums[key, default: 0] += seconds } }
        return sums
    }

    /// Kept days other than `excluded`.
    func dayCount(excluding excluded: DayKey) -> Int { days.keys.filter { $0 != excluded.id }.count }
}

/// One place the setup proposes and the seconds it took in the kept days.
struct SetupProposal: Equatable {
    var place: GuardedPlace
    var seconds: Int
}

extension AppModel {
    /// The setup's proposals: places ranked by the seconds they took over the kept days plus
    /// today, and how many days that covers. `GuardList.proposals` names today's places.
    func setupProposals(limit: Int = 6) -> (items: [SetupProposal], days: Int) {
        // Past days come from the archive; today always comes from the sessions, so a correction
        // made today moves the minutes at once and nothing is counted twice.
        var totals = placeWeek.totals(excluding: today.day)
        for (key, seconds) in PlaceWeek.waste(in: sessions) { totals[key, default: 0] += seconds }
        var places: [String: GuardedPlace] = [:]
        for place in GuardList.proposals(from: sessions, limit: 20) {
            let key = place.host.map { "h:" + $0.lowercased() } ?? "b:" + (place.bundleID ?? "").lowercased()
            places[key] = place
        }
        let ranked = totals.filter { $0.value >= 60 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(max(0, limit))
        let items: [SetupProposal] = ranked.compactMap { key, seconds in
            guard let place = places[key].map(GuardNames.pretty) ?? PlaceArt.place(forKey: key) else { return nil }
            return SetupProposal(place: place, seconds: seconds)
        }
        return (items, placeWeek.dayCount(excluding: today.day) + (sessions.isEmpty ? 0 : 1))
    }
}

/// What the owner sees for a place: its app icon, or a letter monogram in a stable colour.
@MainActor
enum PlaceArt {
    private static let palette: [Color] = [.blue, .pink, .orange, .purple, .teal, .indigo, .brown, .cyan]
    private static var cache: [String: NSImage?] = [:]

    /// A stable colour per name: a sum of scalars, never `hashValue`, which changes per launch.
    static func color(for name: String) -> Color {
        let sum = name.lowercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    static func monogram(_ name: String) -> String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }

    /// The app's icon for an app place; for a site, the icon of an installed app with the same name.
    static func icon(for place: GuardedPlace) -> NSImage? {
        let key = place.bundleID ?? ("n:" + place.name)
        if let hit = cache[key] { return hit }
        var url: URL?
        if let bundle = place.bundleID {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            for folder in ["/Applications", "/System/Applications", home + "/Applications"] {
                let path = "\(folder)/\(place.name).app"
                if FileManager.default.fileExists(atPath: path) { url = URL(fileURLWithPath: path); break }
            }
        }
        let image = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[key] = image
        return image
    }

    /// A place from a stored key. An app is named by its installed display name, else the last part
    /// of its bundle id.
    static func place(forKey key: String) -> GuardedPlace? {
        if key.hasPrefix("h:") { return GuardNames.place(fromSite: String(key.dropFirst(2))) }
        guard key.hasPrefix("b:") else { return nil }
        let bundle = String(key.dropFirst(2))
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return GuardedPlace(name: name, bundleID: bundle)
        }
        let last = bundle.split(separator: ".").last.map(String.init) ?? bundle
        return GuardedPlace(name: last.prefix(1).uppercased() + last.dropFirst(), bundleID: bundle)
    }
}
