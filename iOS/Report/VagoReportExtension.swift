import DeviceActivity
import ExtensionKit
import FamilyControls
import ManagedSettings
import SwiftUI

@main
struct VagoReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        PerAppReport { report in
            PerAppReportView(report: report)
        }
    }
}

/// One row of the report: an app, how long, and which of the owner's lists it is on.
struct AppUsage: Identifiable, @unchecked Sendable {
    enum Bucket { case procrastination, ambiguous, productive, other }

    let id: Int
    let token: ApplicationToken?
    let name: String
    let seconds: TimeInterval
    let bucket: Bucket
}

struct PerAppData: @unchecked Sendable {
    var total: TimeInterval = 0
    var apps: [AppUsage] = []
}

/// Screen Time's own per-app totals for the day, all devices. The extension runs in a sandbox
/// that cannot write anywhere, so this report only displays; the app keeps counting by thresholds.
struct PerAppReport: @preconcurrency DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .perApp
    nonisolated(unsafe) let content: (PerAppData) -> PerAppReportView

    nonisolated init(content: @escaping (PerAppData) -> PerAppReportView) {
        self.content = content
    }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> PerAppData {
        let store = VagoStore()
        let procrastination = store.selection(.procrastination)
        let ambiguous = store.selection(.ambiguous)
        let productive = store.selection(.productive)

        func bucket(app: ApplicationToken?, category: ActivityCategoryToken?) -> AppUsage.Bucket {
            if let app {
                if procrastination.applicationTokens.contains(app) { return .procrastination }
                if ambiguous.applicationTokens.contains(app) { return .ambiguous }
                if productive.applicationTokens.contains(app) { return .productive }
            }
            if let category {
                if procrastination.categoryTokens.contains(category) { return .procrastination }
                if ambiguous.categoryTokens.contains(category) { return .ambiguous }
                if productive.categoryTokens.contains(category) { return .productive }
            }
            return .other
        }

        var result = PerAppData()
        var rows: [AppUsage] = []
        var counter = 0
        for await device in data {
            for await segment in device.activitySegments {
                result.total += segment.totalActivityDuration
                for await category in segment.categories {
                    for await application in category.applications {
                        counter += 1
                        rows.append(AppUsage(
                            id: counter,
                            token: application.application.token,
                            name: application.application.localizedDisplayName ?? "App",
                            seconds: application.totalActivityDuration,
                            bucket: bucket(app: application.application.token, category: category.category.token)
                        ))
                    }
                }
            }
        }
        // The same app can appear once per device; fold the rows by name and token.
        var folded: [String: AppUsage] = [:]
        for row in rows {
            let key = row.token.map { "\($0.hashValue)" } ?? row.name
            if let existing = folded[key] {
                folded[key] = AppUsage(id: existing.id, token: existing.token, name: existing.name,
                                       seconds: existing.seconds + row.seconds, bucket: existing.bucket)
            } else {
                folded[key] = row
            }
        }
        result.apps = folded.values.sorted { $0.seconds > $1.seconds }.prefix(20).map { $0 }
        return result
    }
}

struct PerAppReportView: View {
    let report: PerAppData

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Screen time today")
                    Spacer()
                    Text(Self.format(report.total)).monospacedDigit().foregroundStyle(.secondary)
                }
            } footer: {
                Text("Screen Time's own totals, all your devices.")
            }
            Section("Apps") {
                if report.apps.isEmpty {
                    Text("No usage yet today.").foregroundStyle(.secondary)
                }
                ForEach(report.apps) { app in
                    HStack(spacing: 12) {
                        if let token = app.token {
                            Label(token)
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)
                        } else {
                            Text(app.name).lineLimit(1)
                        }
                        Spacer()
                        Circle().fill(Self.color(app.bucket)).frame(width: 8, height: 8)
                        Text(Self.format(app.seconds)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    static func color(_ bucket: AppUsage.Bucket) -> Color {
        switch bucket {
        case .procrastination: .red
        case .ambiguous: .orange
        case .productive: .green
        case .other: .gray.opacity(0.4)
        }
    }
}
