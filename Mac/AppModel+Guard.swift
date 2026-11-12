import AppKit
import Foundation
import VagoKit
import WidgetKit

/// The core loop (decision 01): the owner's toggle, the guard (pause and block), the drift notice
/// and the mode shown by the menu-bar icon and the Control Center control.
extension AppModel {
    // MARK: Mode and toggle

    /// The mode shown by the icon: the place in front (or the last place before Vago's own
    /// popover took the focus); neutral when nothing is counted.
    var currentMode: Mode {
        guard pause == nil, let target = toggleTarget else { return .neutral }
        return Mode(target.bucket)
    }

    /// True when the place the toggle acts on counts as work.
    var toggleIsWork: Bool { toggleTarget?.bucket == .productive }

    /// What the owner reads: the guarded place's name ("Instagram"), else the site or app.
    func displayName(_ place: NowPlace) -> String {
        guardList.places.first { $0.matches(place.sample) }?.name ?? place.label
    }

    /// Variant B of the toggle: leaving a place clears its toggle. Vago's own windows never count as leaving.
    func leaveToggledPlace(for key: String) {
        defer { lastToggleKey = key }
        guard variants.toggleResets, let last = lastToggleKey, last != key else { return }
        toggles.removeValue(forKey: last)
        dirty = true
    }

    /// One tap: the place in front flips between work and procrastination, both ways, no duration.
    func toggleCurrent() {
        guard let target = toggleTarget else { return }
        setToggle(target.placeKey, to: target.bucket == .productive ? .procrastination : .productive)
    }

    /// Time counts by the toggle from the next second on. A place toggled to work is never paused,
    /// blocked or reported as a drift; flipping it back restores all three.
    func setToggle(_ placeKey: String, to bucket: Bucket) {
        toggles[placeKey] = bucket
        func settled(_ place: NowPlace) -> NowPlace {
            var place = place
            place.bucket = bucket
            place.reason = CallReason.toggle
            place.source = .answer
            place.unclear = false
            return place
        }
        if let current = now, current.placeKey == placeKey { now = settled(current) }
        if let target = toggleTarget, target.placeKey == placeKey { toggleTarget = settled(target) }
        if bucket == .productive {
            guardPanels.dismissAll()
            blockShownFor = nil
        }
        dirty = true
        flush(now: Date())
        publishMode(now: Date(), force: true)
        onChange?()
    }

    // MARK: Guard and drift

    /// One counted second: the guard decides, the drift watch may fire. Called from `process` for
    /// every place except Vago's own windows.
    func runGuard(_ obs: ActivitySample, bucket: Bucket, now: Date) {
        let placeKey = PlaceKey.of(obs)
        let isWork = toggles[placeKey] == .productive
        let listed = guardList.enabled ? guardList.place(for: obs) : nil
        let action = guardState.tick(obs, list: guardList, isWork: isWork, usedSeconds: today.procrastination, now: now)
        dirty = true

        if isWork {
            guardPanels.dismissAll()
        } else {
            guardPanels.dismissPause(unlessPlace: listed?.id)
        }
        if case .block = action {} else { blockShownFor = nil }

        switch action {
        case .none:
            break
        case .pause(let place, let overBudget):
            guardPanels.showPause(
                place: place, overBudget: overBudget, usedMinutes: today.procrastination / 60,
                budgetMinutes: guardList.budgetMinutes, variant: variants.pausePanel,
                close: { [weak self] in
                    PlaceControl.close(obs)
                    self?.guardState.closed(place.id, now: Date())
                    self?.dirty = true
                },
                open: { [weak self] in
                    self?.guardState.grantPass(place.id, now: Date())
                    self?.dirty = true
                }
            )
        case .block(let place, let until):
            if now.timeIntervalSince(lastBlockClose) >= 1 {
                lastBlockClose = now
                PlaceControl.close(obs)
            }
            if blockShownFor != place.id {
                blockShownFor = place.id
                guardPanels.showBlock(
                    place: place, until: until, variant: variants.blockPanel,
                    close: { [weak self] in
                        PlaceControl.close(obs)
                        self?.guardState.closed(place.id, now: Date())
                        self?.dirty = true
                    },
                    unlock: { [weak self] in
                        self?.guardState.unlock(place.id, now: Date())
                        self?.dirty = true
                    }
                )
            }
        }

        if drift.tick(Mode(bucket), guarded: listed != nil, now: now) {
            postDriftNotice(obs, now: now)
        }
    }

    /// A statement, never a question: "Procrastination · Instagram — 12 of 30 min today".
    private func postDriftNotice(_ obs: ActivitySample, now: Date) {
        let name = guardList.place(for: obs)?.name ?? SiteKey.label(obs)
        notices.postDrift(
            placeName: name, placeKey: PlaceKey.of(obs), usedMinutes: today.procrastination / 60,
            budgetMinutes: guardList.budgetMinutes, withAction: variants.notice == .b
        )
    }

    // MARK: Setup and settings

    /// Setup's starting point: the current list, and proposals from today's sessions.
    func makeSetupDraft() -> SetupDraft {
        SetupDraft(list: guardList, proposals: GuardList.proposals(from: sessions, limit: 3), front: toggleTarget?.sample)
    }

    /// Setup's Done: the list goes live, notifications are asked for.
    func finishSetup(_ list: GuardList) {
        var list = list
        list.enabled = true
        guardList = list
        setupOffered = true
        notices.requestAuthorization()
        dirty = true
        flush(now: Date())
        onChange?()
    }

    func setGuardEnabled(_ on: Bool) {
        guard guardList.enabled != on else { return }
        guardList.enabled = on
        if !on { guardPanels.dismissAll() }
        dirty = true
    }

    func setVariant(_ screen: DesignScreen, _ variant: Variant) {
        variants[screen] = variant
        UserDefaults.standard.set(variant.rawValue, forKey: screen.defaultsKey)
        dirty = true
        onChange?()
    }

    // MARK: Control Center

    /// Writes the place in front and its mode for the control, and asks Control Center to reload
    /// it. At most every 3 seconds unless `force`; nothing happens when nothing changed.
    func publishMode(now: Date, force: Bool = false) {
        let target = toggleTarget
        let snapshot = ModeSnapshot(
            placeKey: target?.placeKey ?? "", label: target.map(displayName) ?? "Vago",
            mode: currentMode, updatedAt: now
        )
        let key = "\(snapshot.placeKey)|\(snapshot.label)|\(snapshot.mode.rawValue)"
        guard force || key != modeLast.key else { return }
        guard force || now.timeIntervalSince(modeLast.written) >= 3 else { return }
        modeLast.key = key
        modeLast.written = now
        guard ModeBridge.writeSnapshot(snapshot) else { return }   // no App Group container: an unsigned build
        modeLast.reloaded = now
        ControlCenter.shared.reloadControls(ofKind: ModeBridge.controlKind)
    }

    /// Listens for the control's switch requests.
    func startControlBridge() {
        modeObserver = DarwinObserver(name: ModeBridge.darwinName) { [weak self] in
            Task { @MainActor in self?.applyModeRequest() }
        }
    }

    func applyModeRequest() {
        guard let request = ModeBridge.takeRequest(), abs(request.at.timeIntervalSinceNow) < 60 else { return }
        guard let key = request.placeKey.isEmpty ? toggleTarget?.placeKey : request.placeKey else { return }
        setToggle(key, to: request.work ? .productive : .procrastination)
    }
}

/// A Darwin notification observer, for the control's request. Darwin notifications carry no payload.
final class DarwinObserver: @unchecked Sendable {
    // @unchecked Sendable: `handler` is set once in `init` and never changes.
    private let handler: @Sendable () -> Void

    init(name: String, handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            name as CFString, nil, .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }
}
