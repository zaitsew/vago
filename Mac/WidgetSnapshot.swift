import Foundation
import VagoKit

/// What the Mac app hands to its desktop widget: today's merged numbers for all devices.
/// The app writes it to `widget.json` in the App Group container; the widget only reads it.
/// Compiled into both the app and the widget extension.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// The App Group shared by the Mac app and its widget. Team-prefixed: on macOS that needs no
    /// provisioning profile.
    static let groupID = "VWH2FKV78Q.com.zaitsew.vago"
    static let fileName = "widget.json"

    var day: DayKey
    /// Whole percent of productive time; nil before 15 active minutes (`ProductiveShare`).
    var percent: Int?
    var productiveMinutes: Int
    var neutralMinutes: Int
    var wasteMinutes: Int
    var limitMinutes: Int
    var macHours: [HourSlot]
    /// Empty when the iPhone has no value for the day.
    var iphoneHours: [HourSlot]
    var iphoneUpdatedAt: Date?
    var updatedAt: Date
    var mood: String

    /// Active minutes behind the share, for "N min so far".
    var activeMinutes: Int { productiveMinutes + neutralMinutes + wasteMinutes }

    /// The share rebuilt from the minutes, so the widget tints with the app's own thresholds.
    var share: ProductiveShare {
        ProductiveShare(productive: productiveMinutes * 60, neutral: neutralMinutes * 60, procrastination: wasteMinutes * 60)
    }

    /// The tint of the hero number: from the stored percent, by `ProductiveShare`'s thresholds.
    var tint: Tint? {
        guard let p = percent else { return nil }
        return p >= 90 ? .green : p >= 75 ? .yellow : .red
    }

    /// What a widget shows for `snapshot` at `now`. Never yesterday's number.
    enum Display: Equatable {
        case missing                        // no file: the app has not run yet
        case otherDay                       // the file is from an earlier day
        case early(minutes: Int)            // under 15 active minutes
        case ready
    }

    static func display(_ snapshot: WidgetSnapshot?, now: Date) -> Display {
        guard let snapshot else { return .missing }
        guard snapshot.day == DayKey.of(now) else { return .otherDay }
        return snapshot.percent == nil ? .early(minutes: snapshot.activeMinutes) : .ready
    }

    // MARK: File

    static func fileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }

    /// The stored snapshot, or nil when there is none or it cannot be read.
    static func read() -> WidgetSnapshot? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Writes atomically. Returns false (and never throws) when the container is missing or the
    /// write fails.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL() else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(snapshot).write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("Vago: widget snapshot not written: %@", error.localizedDescription)
            return false
        }
    }
}
