import DeviceActivity
import SwiftUI
import VagoKit

/// Screen Time's own per-app totals for today. The extension renders the rows; the app only
/// supplies the filter, because Apple never hands raw usage to the app itself.
struct ReportView: View {
    private var filter: DeviceActivityFilter {
        let start = DayKey.of(.now).start
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: start.addingTimeInterval(24 * 3600))),
            users: .all,
            devices: .all
        )
    }

    var body: some View {
        NavigationStack {
            DeviceActivityReport(.perApp, filter: filter)
                .navigationTitle("Report")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
