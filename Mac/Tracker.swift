import AppKit
import VagoKit

/// The 1-second sampler. Reads the front app and its window, checks that someone is there, and
/// hands the observation to the model, which does the counting.
@MainActor
final class Tracker {
    private let model: AppModel
    private let presence = Presence()
    private let probe = ContextProbe()
    private var task: Task<Void, Never>?
    private var lastTick: Date?
    private var carry = 0.0
    private var ticks = 0

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func tick() async {
        let now = Date()
        ticks += 1
        model.clock = now
        model.accessibilityGranted = Permissions.accessibilityGranted
        if ticks % 10 == 0 { presence.refresh() }
        if ticks % 60 == 0 { model.refreshJudgeIfNeeded() }

        guard presence.isPresent else { return pause(.locked, now) }
        guard let app = FrontApp.current() else { return pause(.idle, now) }

        let context = await read(app)
        let obs = ActivitySample(bundleID: app.bundleID, appName: app.name, windowTitle: context.title, url: context.url)
        guard Presence.secondsSinceInput() < Presence.idleThreshold(for: obs) else { return pause(.idle, now) }

        // Wall-clock seconds since the last tick, so a slow judge call or a busy Mac loses nothing.
        // Lock, sleep and idle reset `lastTick`; the 60-second cap only guards a stalled loop.
        let elapsed = lastTick.map { now.timeIntervalSince($0) } ?? 1
        lastTick = now
        carry += min(elapsed, 60)
        let whole = Int(carry)
        carry -= Double(whole)
        guard whole > 0 else { return }
        await model.process(obs, seconds: whole, now: now)
    }

    private func pause(_ reason: PauseReason, _ now: Date) {
        lastTick = nil
        carry = 0
        model.tickInactive(reason, now: now)
    }

    /// The window context of `app`: the cached answer when it is fresh, a new read otherwise.
    /// A fresh read always runs in the background so the next second has one.
    private func read(_ app: FrontApp) async -> ProbedContext {
        let cached = await probe.latest(for: app)
        let context: ProbedContext
        if let cached, Date().timeIntervalSince(cached.at) < 5 {
            context = cached
            await probe.refreshInBackground(app)
        } else {
            context = await probe.refresh(app)
        }
        if Browser.family(of: app.bundleID) != nil {
            switch context.status {
            case .ok: model.noteAutomation(app.bundleID, .allowed)
            case .automationDenied: model.noteAutomation(app.bundleID, .denied)
            case .accessibilityDenied, .unavailable: break
            }
        }
        return context
    }
}
