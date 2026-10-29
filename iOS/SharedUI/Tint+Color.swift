import SwiftUI
import VagoKit

extension Tint {
    /// Green, yellow, red: the mood colours of the ring, the widget and the Live Activity.
    var color: Color {
        switch self {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }
}
