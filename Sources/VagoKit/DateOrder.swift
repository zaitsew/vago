import Foundation

/// Date order without Foundation's `Date.>=` and `Date.<=`.
///
/// Both operators are `@backDeployed(before: iOS 27.2, macOS 27.2)` in the 27.2 SDK. The
/// client-side thunk calls the system's copy whenever the OS reports 27.2 or later, but the
/// iOS 27.2 betas do not have it: the call jumps to address 0 and the app dies. That was the
/// launch crash of Vago 0.1.0 (3) on an iPhone with iOS 27.2 beta 24B5084k
/// (`CloudSync.push`, TestFlight crash feedback of 2026-11-09). `./check.sh` fails when a built
/// iPhone binary weak-imports a symbol nobody reviewed (scripts/check-backdeploy.sh).
extension Date {
    /// `self >= other`, compared as seconds since the reference date.
    @inlinable public func isAtOrAfter(_ other: Date) -> Bool {
        timeIntervalSinceReferenceDate >= other.timeIntervalSinceReferenceDate
    }

    /// `self <= other`, compared as seconds since the reference date.
    @inlinable public func isAtOrBefore(_ other: Date) -> Bool {
        timeIntervalSinceReferenceDate <= other.timeIntervalSinceReferenceDate
    }
}
