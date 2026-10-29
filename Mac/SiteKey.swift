import VagoKit

/// How the app names "the same place" for day-scoped answers and the review queue:
/// the host plus the first path component for the web, the bundle id for an app.
enum SiteKey {
    static func of(_ o: ActivitySample) -> String {
        guard let host = o.host else { return o.bundleID }
        let first = o.url?.pathComponents.first { $0 != "/" && !$0.isEmpty }
        return first.map { "\(host)/\($0.lowercased())" } ?? host
    }

    /// What the owner reads: the site for a page, the app name otherwise.
    static func label(_ o: ActivitySample) -> String { o.host ?? o.appName }
}
