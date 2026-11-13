#if DEBUG
import AppKit
import SwiftUI
import VagoKit

/// `Vago --render-variants <dir>` (Debug builds only): draws every new screen in both variants from
/// fixed sample data, writes the PNGs and exits. It never creates an `AppModel`, so it reads and
/// writes nothing under Application Support.
///
/// Views are drawn through `NSHostingView.cacheDisplay` in an offscreen window rather than
/// `ImageRenderer`, because `ImageRenderer` cannot draw AppKit-backed controls (segmented pickers,
/// switches, steppers, date fields, text fields).
@MainActor
enum RenderVariants {
    static func directory(in arguments: [String]) -> URL? {
        guard let i = arguments.firstIndex(of: "--render-variants"), arguments.indices.contains(i + 1) else { return nil }
        return URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
    }

    /// Returns true when every file was written and is not empty.
    static func run(into directory: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("Vago render: cannot create %@: %@", directory.path, error.localizedDescription)
            return false
        }
        var ok = true
        func save<V: View>(_ name: String, _ size: CGSize, scale: CGFloat = 2, _ view: V) {
            guard let data = png(view, size: size, scale: scale), !data.isEmpty else {
                NSLog("Vago render: %@ failed", name)
                ok = false
                return
            }
            do { try data.write(to: directory.appendingPathComponent(name)) } catch {
                NSLog("Vago render: %@ not written: %@", name, error.localizedDescription)
                ok = false
            }
        }

        // Setup (the rebuild is on the next branch).
        save("setup-a.png", CGSize(width: 480, height: 560), SetupContent(draft: sampleDraft(), variant: .a).windowBacked())
        for step in 1...3 {
            save("setup-b-step\(step).png", CGSize(width: 480, height: 500),
                 SetupContent(draft: sampleDraft(), variant: .b, step: step).windowBacked())
        }

        // Pause card: ready under budget (check) and ready over budget (exclamation, never green).
        let cardSize = CGSize(width: 560, height: 380)
        for (name, over) in [("pause-ready", false), ("pause-over-ready", true)] {
            let pause = PauseContent(placeName: "Instagram", usedMinutes: over ? 34 : 12, budgetMinutes: 30, overBudget: over, elapsed: 5)
            save("\(name).png", cardSize, ZStack(alignment: .top) {
                MockWindow(title: "Instagram · Safari")
                pause
            })
        }

        // Block card, mid-hold.
        let until = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
        save("block.png", cardSize, ZStack {
            MockWindow(title: "Instagram · Safari")
            BlockContent(placeName: "Instagram", until: until, holdFraction: 0.45)
        })

        // Mode pill next to every share tint.
        let shares: [(String, String, Tint)] = [("green", "😄 92%", .green), ("yellow", "😐 71%", .yellow), ("red", "😞 38%", .red)]
        for mode in Mode.allCases {
            for (name, text, tint) in shares {
                save("mode-icon-\(mode.rawValue)-with-share-\(name).png", CGSize(width: 150, height: 30), scale: 4,
                     MenuBarMock(mode: mode, shareText: text, tint: tint))
            }
        }

        // Popover top with the switch off (waste) and on (work).
        save("toggle-off.png", CGSize(width: 340, height: 190), PopoverTopMock(label: "Instagram", mode: .procrastination))
        save("toggle-on.png", CGSize(width: 340, height: 190), PopoverTopMock(label: "Instagram", mode: .work))

        // The banner is system UI: faithful mocks, named so.
        save("notice-a-MOCK.png", CGSize(width: 420, height: 130), scale: 3, NoticeMock(withAction: false))
        save("notice-b-MOCK.png", CGSize(width: 420, height: 170), scale: 3, NoticeMock(withAction: true))
        return ok
    }

    // MARK: Sample data

    static func samplePlaces() -> [GuardedPlace] {
        [
            GuardedPlace(name: "Instagram", host: "instagram.com", mode: .pause),
            GuardedPlace(name: "YouTube", host: "youtube.com", mode: .block),
            GuardedPlace(name: "Telegram", bundleID: "ru.keepcoder.Telegram", mode: .pause),
        ]
    }

    static func sampleDraft() -> SetupDraft {
        SetupDraft(rows: samplePlaces().map { SetupRow(place: $0, selected: true) }, budget: 30, hours: WorkHours(),
                   front: GuardedPlace(name: "Reddit", host: "reddit.com"))
    }

    // MARK: Drawing

    private static func png<V: View>(_ view: V, size: CGSize, scale: CGFloat) -> Data? {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

private extension View {
    /// An opaque window background, so materials and the PNG have something to sit on.
    func windowBacked() -> some View {
        background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A neutral grey "window" behind a panel, so the panel reads.
private struct MockWindow: View {
    var title: String

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(white: 0.80, alpha: 1))
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(.red.opacity(0.7)).frame(width: 10, height: 10)
                    Circle().fill(.yellow.opacity(0.7)).frame(width: 10, height: 10)
                    Circle().fill(.green.opacity(0.7)).frame(width: 10, height: 10)
                    Spacer()
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color(nsColor: NSColor(white: 0.93, alpha: 1)))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: NSColor(white: 0.88, alpha: 1)))
                            .frame(height: i % 3 == 0 ? 60 : 28)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color(nsColor: NSColor(white: 0.97, alpha: 1)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(18)
        }
    }
}

/// The menu bar around the pill and the share, on a light bar.
private struct MenuBarMock: View {
    var mode: Mode
    var shareText: String
    var tint: Tint

    var body: some View {
        HStack(spacing: 6) {
            ModeBadge(mode: mode)
            Text(verbatim: shareText)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Palette.color(tint))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(nsColor: NSColor(white: 0.86, alpha: 1)))
    }
}

/// The popover's top: the toggle row, then the share.
private struct PopoverTopMock: View {
    var label: String
    var mode: Mode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModeRowContent(label: label, mode: mode, isWork: mode == .work, onToggle: {})
            Divider()
            Hero(share: ProductiveShare(productive: 190 * 60, neutral: 45 * 60, procrastination: 50 * 60))
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// What the drift banner looks like in Notification Center. The real one is drawn by macOS; this is
/// a mock for review, not a capture.
private struct NoticeMock: View {
    var withAction: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(nsColor: NSColor(srgbRed: 0.45, green: 0.55, blue: 0.75, alpha: 1)),
                                    Color(nsColor: NSColor(srgbRed: 0.70, green: 0.62, blue: 0.80, alpha: 1))],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [.green, .teal], startPoint: .top, endPoint: .bottom))
                        .frame(width: 38, height: 38)
                        .overlay(Text("V").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Procrastination · Instagram").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("now").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text("12 of 30 min today").font(.system(size: 12))
                        Text("Vago").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(width: 360)
                .background(Color(nsColor: NSColor(white: 0.97, alpha: 0.92)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                if withAction {
                    Text("Switch to work")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: NSColor(white: 0.97, alpha: 0.92)), in: Capsule())
                }
            }
            .padding(.trailing, 30)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
#endif
