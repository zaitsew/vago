import Foundation
import VagoKit

extension AppModel {
    // MARK: Counting

    /// Counts `seconds` of use of `obs`: classify, add to today's totals, grow the focus tree,
    /// extend or open a session, and let the nudger decide whether to ask.
    func process(_ obs: ActivitySample, seconds: Int, now: Date) async {
        rollIfNeeded(now)
        pause = nil
        let key = SiteKey.of(obs)
        let answer = overrides[key]
        let c: Classification
        if let answer {
            c = Classification(bucket: answer, unclear: false, reason: "your answer today")
        } else {
            c = await classifier.classify(obs)
        }
        rollIfNeeded(now)

        switch c.bucket {
        case .productive: today.productive += seconds
        case .procrastination, .ambiguous: today.procrastination += seconds
        case .neutral: break
        }
        tickFocus(bucket: c.bucket, seconds: seconds, now: now)
        record(obs, key: key, classification: c, seconds: seconds, now: now)
        commit(now: now)

        currentLabel = c.bucket == .neutral ? nil : SiteKey.label(obs)
        nudger?.consider(key: key, label: SiteKey.label(obs), classification: c, answered: answer != nil, focus: focus, now: now)
        onChange?()
    }

    /// A second in which nothing is counted: locked, asleep or idle. Time still passes for the
    /// day change, the focus timer and the files.
    func tickInactive(_ reason: PauseReason, now: Date) {
        rollIfNeeded(now)
        pause = reason
        currentSession = nil
        currentLabel = nil
        tickFocus(bucket: .neutral, seconds: 0, now: now)
        nudger?.reset()
        commit(now: now)
        onChange?()
    }

    private func commit(now: Date) {
        clock = now
        today.focus = focusSecondsToday
        today.updatedAt = now
        ledger.merge(today)
        dirty = true
        flush(now: now)
    }

    /// Extends the open session while the owner stays on the same place with the same verdict
    /// and the same certainty, so an unclear stretch always reaches the review queue.
    private func record(_ obs: ActivitySample, key: String, classification c: Classification, seconds: Int, now: Date) {
        guard c.bucket != .neutral else { currentSession = nil; return }
        if let open = currentSession, open.key == key, sessions.indices.contains(open.index),
           sessions[open.index].guess == c.bucket,
           reviewPending.contains(sessions[open.index].id) == c.unclear,
           now.timeIntervalSince(open.lastAt) <= 4 {
            sessions[open.index].seconds += seconds
            currentSession = (open.index, key, now)
            return
        }
        let session = Session(
            start: now.addingTimeInterval(-Double(seconds)), seconds: seconds,
            sample: ActivitySampleRecord(obs), guess: c.bucket, reason: c.reason
        )
        sessions.append(session)
        if c.unclear { reviewPending.append(session.id) }
        currentSession = (sessions.count - 1, key, now)
        if sessions.count > 3000 { trimSessions() }
    }

    private func trimSessions() {
        let pending = Set(reviewPending)
        sessions = Array(sessions.suffix(3000 / 2)) + sessions.dropLast(3000 / 2).filter { pending.contains($0.id) }
        sessions.sort { $0.start < $1.start }
        reviewPending = reviewPending.filter { id in sessions.contains { $0.id == id } }
        currentSession = nil
    }

    // MARK: Day change

    /// Starts a new 04:00 day when the clock has crossed it: saves yesterday, rolls the limit.
    func rollIfNeeded(_ now: Date) {
        let day = DayKey.of(now)
        guard day != today.day else { return }
        ledger.merge(today)
        sync?.write(today, force: true)
        startNewDay(day, now: now)
        flush(force: true, now: now)
    }

    func startNewDay(_ day: DayKey, now: Date) {
        ledger.merge(today)
        today = DeviceDay(day: day, device: .mac, updatedAt: now)
        sessions = []
        reviewPending = []
        overrides = [:]
        currentSession = nil
        limit.roll(to: day, ledger: ledger)
        let cutoff = day.adding(days: -60)
        ledger.days = ledger.days.filter { $0.value.day >= cutoff }
        let weeks = now.addingTimeInterval(-14 * 86_400)
        focusLog = focusLog.filter { $0.start >= weeks }
        ledger.merge(today)
        dirty = true
    }

    // MARK: Focus

    func startFocus(minutes: Int) {
        guard focus?.state != .growing else { return }
        let now = Date()
        focus = FocusSession(start: now, minutes: minutes)
        nudger?.reset()
        commit(now: now)
        onChange?()
    }

    func giveUpFocus() {
        guard var session = focus, session.state == .growing else { return }
        session.abandon(now: Date())
        focus = session
        finishFocusIfNeeded()
        commit(now: Date())
        onChange?()
    }

    private func tickFocus(bucket: Bucket, seconds: Int, now: Date) {
        guard focus?.state == .growing else { return }
        focus?.tick(bucket: bucket, seconds: seconds, now: now)
        finishFocusIfNeeded()
    }

    private func finishFocusIfNeeded() {
        guard let session = focus, session.state != .growing else { return }
        focusLog.append(session)
        focus = nil
        let minutes = session.focusSeconds(at: clock) / 60
        switch session.state {
        case .grown: lastToast = "🌳 Focus done: \(session.minutes) minutes"
        case .wilted: lastToast = "🥀 The tree wilted after \(minutes) minutes"
        case .abandoned: lastToast = nil
        case .growing: break
        }
        if let toast = lastToast { nudger?.toast(toast) }
    }

    // MARK: Answers

    /// A "Work" or "Scroll" tap on the floating nudge: counts for the rest of today only.
    func answerNudge(key: String, as bucket: Bucket) {
        overrides[key] = bucket
        let ids = reviewPending.filter { id in
            sessions.first { $0.id == id }.map { SiteKey.of($0.sample.sample) == key } ?? false
        }
        settle(ids, as: bucket)
        commit(now: Date())
        onChange?()
    }

    /// A "Work" or "Waste" tap in the review queue: also becomes a permanent rule.
    func answerReview(_ item: ReviewItem, as bucket: Bucket) {
        rules.learn(from: item.sample, bucket: bucket)
        let book = rules, classifier = self.classifier
        Task { await classifier.update(rules: book) }
        settle(item.sessionIDs, as: bucket)
        commit(now: Date())
        onChange?()
    }

    /// Takes sessions out of the queue. Unclear sessions were counted as procrastination, so
    /// "work" moves their seconds to productive.
    private func settle(_ ids: [UUID], as bucket: Bucket) {
        let set = Set(ids)
        reviewPending.removeAll { set.contains($0) }
        guard bucket == .productive else { return }
        var moved = 0
        for i in sessions.indices where set.contains(sessions[i].id) {
            moved += sessions[i].seconds
            sessions[i].guess = .productive
        }
        let shift = min(moved, today.procrastination)
        today.procrastination -= shift
        today.productive += shift
    }
}
