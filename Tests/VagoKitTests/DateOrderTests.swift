import Foundation
import Testing
@testable import VagoKit

/// `Date.isAtOrAfter` / `isAtOrBefore` replace Foundation's back-deployed `>=` / `<=`
/// (see DateOrder.swift). They must agree with them on every order, equal dates included.
struct DateOrderTests {
    let a = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func equalDatesAreBothAtOrAfterAndAtOrBefore() {
        #expect(a.isAtOrAfter(a))
        #expect(a.isAtOrBefore(a))
    }

    @Test func laterDateIsAtOrAfterOnly() {
        let later = a.addingTimeInterval(0.001)
        #expect(later.isAtOrAfter(a))
        #expect(!later.isAtOrBefore(a))
        #expect(!a.isAtOrAfter(later))
        #expect(a.isAtOrBefore(later))
    }

    @Test func focusSessionGrowsExactlyAtItsEnd() {
        var session = FocusSession(start: a, minutes: 25)
        session.tick(bucket: .productive, seconds: 1, now: a.addingTimeInterval(25 * 60))
        #expect(session.state == .grown)
    }
}
