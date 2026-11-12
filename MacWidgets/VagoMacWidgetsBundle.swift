import SwiftUI
import WidgetKit

@main
struct VagoMacWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        VagoModeControl()
    }
}
