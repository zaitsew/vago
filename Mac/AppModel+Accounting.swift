import AppKit
import Foundation
import VagoKit

extension AppModel {
    // MARK: Counting

    /// Counts `seconds` of use of `obs`: classify with the judge's context, let the audit and the
    /// verdict memory see the call, add to today's totals, grow the focus tree, extend or open a
    /// session, let the nudger guard a focus session, and offer the evening review once.
    func process(_ obs: ActivitySample, seconds: Int, now: Date) async {
        rollIfNeeded(now)
        pause = nil
        let key = SiteKey.of(obs)
        let label = SiteKey.label(obs)
        let context = judgeContext(key: key, label: label, seconds: seconds, now: now)
        let answer = overrides[key]
        let c: Classification
        if let answer {
            c = Classification(bucket: answer, unclear: false, reason: CallReason.answer, source: .answer)
        } else {
            c = await classifier.classify(obs, context: context)
        }
        rollIfNeeded(now)

        if answer == nil { learn(from: obs, classification: c, seconds: seconds) }
        today.add(c.bucket == .ambiguous ? .procrastination : c.bucket, seconds: seconds, at: now)
        tickFocus(bucket: c.bucket, seconds: seconds, now: now)
        record(obs, key: key, classification: c, seconds: seconds, now: now)
        commit(now: now)

        place?.bucket = c.bucket
        place?.lastAt = now
        let current = NowPlace(key: key, label: label, sample: obs, bucket: c.bucket, reason: c.reason,
                               source: c.source, unclear: c.unclear)
        if self.now != current { self.now = current }
        nudger?.consider(key: key, label: label, classification: c, focus: focus, now: now)
        noteBreakActivity(key: key, lastInput: Self.lastInput(for: obs, now: now), now: now)
        considerEveningReview(now: now)
        onChange?()
    }

    /// A second in which nothing is counted: locked, asleep or idle. Time still passes for the
    /// day change, the focus timer and the files.
    func tickInactive(_ reason: PauseReason, now: Date) {
        rollIfNeeded(now)
        pause = reason
        currentSession = nil
        leavePlace()
        if self.now != nil { self.now = nil }
        tickFocus(bucket: .neutral, seconds: 0, now: now)
        nudger?.reset()
        commit(now: now)
        onChange?()
    }

    // MARK: Autonomy

    /// What the judge sees besides the page: the local hour, how long this place has been in
    /// front, and the place before it if it was counted in the last 10 minutes.
    private func judgeContext(key: String, label: String, seconds: Int, now: Date) -> JudgeContext {
        if place?.key != key {
            leavePlace()
            place = (key, label, .neutral, now.addingTimeInterval(-Double(seconds)), now)
        }
        let inFront = place.map { Int(now.timeIntervalSince($0.since)) } ?? seconds
        var previous: String?
        if let p = previousPlace, now.timeIntervalSince(p.at) <= 10 * 60 {
            previous = "\(p.label) (\(Words.bucket(p.bucket)))"
        }
        return JudgeContext(hour: Calendar.current.component(.hour, from: now), secondsInFront: inFront, previous: previous)
    }

    private func leavePlace() {
        if let p = place { previousPlace = (p.label, p.bucket, p.lastAt) }
        place = nil
    }

    /// The audit counts sure verdicts on ambiguous places; the memory turns a verdict repeated on
    /// three days into an `.auto` rule.
    private func learn(from obs: ActivitySample, classification c: Classification, seconds: Int) {
        judgeAudit.record(c, seconds: seconds, day: today.day)
        guard let rule = verdictMemory.note(obs, c, day: today.day) else { return }
        rules.adopt(rule)
        let book = rules, classifier = self.classifier
        Task { await classifier.update(rules: book) }
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
    /// and the same certainty, so every call reaches "Vago's calls". Neutral by rule is not kept;
    /// neutral by fallback is, so "Wrong?" can still move it.
    private func record(_ obs: ActivitySample, key: String, classification c: Classification, seconds: Int, now: Date) {
        guard c.bucket != .neutral || c.unclear || c.source != .rule else { currentSession = nil; return }
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
        place = nil
        previousPlace = nil
        nudger?.forgetDay()
        eveningReviewOffered = nil
        limit.roll(to: day, ledger: ledger)
        let cutoff = day.adding(days: -60)
        ledger.days = ledger.days.filter { $0.value.day >= cutoff }
        let weeks = now.addingTimeInterval(-14 * 86_400)
        focusLog = focusLog.filter { $0.start >= weeks }
        ledger.merge(today)
        applyJudgeTrust()
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

    // MARK: Answers and corrections

    // MARK: Evening review

    /// From this local hour on, Vago offers once to review the day's unsure calls.
    static let eveningReviewHour = 20

    /// Unsure calls still waiting for the owner, as the Day window lists them.
    var unsureCallCount: Int { allCalls.filter(\.unsure).count }

    /// How many unsure calls the chosen review variant lets the owner answer: the Day window
    /// lists the eight largest calls, the other two the five largest unsure places.
    var reviewableCallCount: Int {
        switch eveningReviewStyle {
        case .dayWindow: calls.filter(\.unsure).count
        case .cards, .list: min(EveningReviewWindow.limit, unsureCallCount)
        }
    }

    /// The one question Vago asks about places: in the evening, once per day, and only when
    /// some calls are unsure. Held during focus, a call (microphone in use) and another panel.
    func considerEveningReview(now: Date) {
        // A day runs 04:00 to 04:00, so the hours after midnight are still this day's evening.
        let hour = Calendar.current.component(.hour, from: now)
        guard eveningReviewOffered != today.day,
              hour >= Self.eveningReviewHour || hour < 4,
              focus?.state != .growing,
              nudger?.isShowing == false,
              !Microphone.inUse() else { return }
        let total = unsureCallCount
        let count = reviewableCallCount
        guard count > 0 else { return }
        eveningReviewOffered = today.day
        dirty = true
        nudger?.showEveningReview(count: count, of: total) { [weak self] in
            NSApp.activate()                       // the panel does not activate Vago
            guard let self else { return }
            self.openWindow?(self.eveningReviewStyle == .dayWindow ? .day : .eveningReview)
        }
    }

    func setEveningReviewStyle(_ style: EveningReviewStyle) {
        eveningReviewStyle = style
        dirty = true
    }

    /// "Wrong?" on the popover's Now line: today's time on the place in front moves to `bucket`,
    /// and the place gets a rule.
    func correctCurrent(as bucket: Bucket) {
        guard let current = now else { return }
        let ids = sessions.filter { SiteKey.of($0.sample.sample) == current.key }.map(\.id)
        correct(sample: current.sample, key: current.key, sessionIDs: ids, as: bucket)
    }

    /// A tap in "Vago's calls": the call's minutes move to `bucket`, and the place gets a rule.
    func correctCall(_ item: CallItem, as bucket: Bucket) {
        correct(sample: item.sample, key: item.id, sessionIDs: item.sessionIDs, as: bucket)
    }

    /// A correction: a `.review` rule for the place, the seconds moved in the day total and in
    /// the hours they happened, and the judge's hold lifted for today (`JudgeAudit`).
    private func correct(sample: ActivitySample, key: String, sessionIDs: [UUID], as bucket: Bucket) {
        rules.learn(from: sample, bucket: bucket)
        if overrides[key] != nil { overrides[key] = bucket }
        let book = rules, classifier = self.classifier
        Task { await classifier.update(rules: book) }
        settle(sessionIDs, as: bucket)
        judgeAudit.corrected(on: today.day)
        applyJudgeTrust()
        if var current = now, current.key == key {
            current.bucket = bucket
            current.reason = CallReason.corrected
            current.source = .rule
            current.unclear = false
            now = current
        }
        commit(now: Date())
        onChange?()
    }

    /// Takes sessions out of the unsure list and moves their seconds to `bucket`. Unsure
    /// sessions were counted as neutral (or as procrastination when there was no judge).
    private func settle(_ ids: [UUID], as bucket: Bucket) {
        let set = Set(ids)
        reviewPending.removeAll { set.contains($0) }
        for i in sessions.indices where set.contains(sessions[i].id) {
            let s = sessions[i]
            if s.guess != bucket {
                let from: Bucket = s.guess == .ambiguous ? .procrastination : s.guess
                today.move(s.seconds, from: from, to: bucket, startingAt: s.start)
                sessions[i].guess = bucket
            }
            sessions[i].reason = CallReason.corrected
        }
        currentSession = nil
    }
}

/// The words the app uses for a bucket.
enum Words {
    static func bucket(_ b: Bucket) -> String {
        switch b {
        case .productive: "work"
        case .procrastination: "waste"
        case .neutral: "neutral"
        case .ambiguous: "mixed"
        }
    }
}
