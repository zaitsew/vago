import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.onboarded && model.authorized {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        // Foreground: merge iCloud, roll the limit, refresh the widget and Live Activity.
        // While visible, re-read what the monitor wrote every few seconds.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await model.refresh(syncCloud: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
            Task { await model.refresh() }
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") { TodayView() }
            Tab("Focus", systemImage: "leaf") { FocusView() }
            Tab("Report", systemImage: "chart.bar") { ReportView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
    }
}
