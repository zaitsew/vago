import Foundation

/// How a second of foreground use is counted.
public enum Bucket: String, Codable, Sendable, CaseIterable {
    case productive, neutral, procrastination, ambiguous
}

/// The device that wrote a number.
public enum Device: String, Codable, Sendable, CaseIterable {
    case iphone, mac
}

/// What the Mac (or a shield) observed for one second of use.
public struct ActivitySample: Sendable, Equatable {
    public var bundleID: String          // "com.google.Chrome"
    public var appName: String
    public var windowTitle: String?      // front window title, when known
    public var url: URL?                 // front browser tab, when known

    public init(bundleID: String, appName: String, windowTitle: String? = nil, url: URL? = nil) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
    }

    /// The URL host, lowercased, without a leading "www.". `nil` when there is no URL host.
    public var host: String? {
        guard var host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// The URL path, lowercased. "/" when the URL has none.
    public var path: String {
        let path = url?.path.lowercased() ?? ""
        return path.isEmpty ? "/" : path
    }
}

/// Codable twin of `ActivitySample` (a `URL` is stored as its string).
public struct ActivitySampleRecord: Codable, Sendable, Equatable {
    public var bundleID: String
    public var appName: String
    public var windowTitle: String?
    public var url: String?

    public init(bundleID: String, appName: String, windowTitle: String? = nil, url: String? = nil) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
    }

    public init(_ o: ActivitySample) {
        self.init(bundleID: o.bundleID, appName: o.appName, windowTitle: o.windowTitle, url: o.url?.absoluteString)
    }

    public var sample: ActivitySample {
        ActivitySample(bundleID: bundleID, appName: appName, windowTitle: windowTitle, url: url.flatMap { URL(string: $0) })
    }
}
