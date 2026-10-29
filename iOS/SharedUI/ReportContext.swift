import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
    /// Per-app Screen Time totals for today. The app embeds it; the report extension renders it.
    static let perApp = DeviceActivityReport.Context("perApp")
}
