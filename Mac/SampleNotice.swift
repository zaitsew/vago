#if DEBUG
import AppKit
import Foundation
import UserNotifications
import VagoKit

/// `Vago --post-sample-notice <a|b> [--capture <file>]` (Debug builds only): posts the sample drift
/// notice and exits. It creates no `AppModel` (no state is read or written). It never asks for
/// permission: it posts only when notifications are already authorized, waits 2 seconds, and with
/// `--capture` saves the top-right of the main screen with `screencapture`. Otherwise it prints why
/// it posted nothing and exits 3.
@MainActor
enum SampleNotice {
    struct Request { var variant: Variant; var capture: String? }

    static func request(in arguments: [String]) -> Request? {
        guard let i = arguments.firstIndex(of: "--post-sample-notice"), arguments.indices.contains(i + 1) else { return nil }
        let variant: Variant = arguments[i + 1].lowercased() == "b" ? .b : .a
        let capture = arguments.firstIndex(of: "--capture").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        return Request(variant: variant, capture: capture)
    }

    static func run(_ request: Request) {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized else {
                print("post-sample-notice: authorization status is \(status.rawValue), not authorized; nothing posted")
                exit(3)
            }
            let notices = NoticeCenter()
            notices.start()
            notices.post(RenderVariants.sampleNotice(request.variant))
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if let path = request.capture, let screen = NSScreen.main {
                let frame = screen.frame
                let rect = "\(Int(frame.minX + frame.width - 460)),\(Int(frame.minY)),460,170"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-R", rect, path]
                try? process.run()
                process.waitUntilExit()
            }
            print("post-sample-notice: posted variant \(request.variant.rawValue)")
            exit(0)
        }
    }
}
#endif
