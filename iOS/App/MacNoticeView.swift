import SwiftUI

/// The iPhone build also runs on Apple silicon Macs: TestFlight and the App Store offer it there.
/// Screen Time refuses iPhone apps on a Mac, so this build cannot count on one. It also must not
/// write anything: an empty "iPhone" day pushed from here would replace the real iPhone's day in
/// iCloud. On a Mac it shows only this screen; Vago for Mac does the counting.
struct MacNoticeView: View {
    @Environment(\.openURL) private var openURL
    @State private var notInstalled = false

    /// Opens the Mac app's Day window (`vago://day`, registered in mac.yml).
    private static let macDay = URL(string: "vago://day")!

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("💻").font(.system(size: 80))
            Text("This is the iPhone app")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Screen Time counts only on the iPhone itself. On this Mac, Vago for Mac counts from the menu bar. Your day across devices and the desktop widget are there.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if notInstalled {
                Text("Vago for Mac is not installed on this Mac.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button {
                openURL(Self.macDay) { accepted in notInstalled = !accepted }
            } label: {
                Text("Open Vago for Mac").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }
}

extension ProcessInfo {
    /// True when this iPhone build runs on a Mac (an "iPhone app on Mac").
    static var onMac: Bool { processInfo.isiOSAppOnMac }
}
