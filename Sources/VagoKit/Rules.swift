import Foundation

/// One user, review or built-in rule. All fields that are set must match.
public struct Rule: Codable, Sendable, Equatable, Identifiable {
    public enum Source: String, Codable, Sendable { case builtIn, user, review }

    public var id: UUID
    public var bundleID: String?         // exact match, case-insensitive
    public var host: String?             // "instagram.com" matches "www.instagram.com" too
    public var pathPrefix: String?       // "/direct" matches "/direct" and "/direct/inbox", not "/directory"
    public var titleContains: String?    // case-insensitive
    public var bucket: Bucket
    public var source: Source            // .builtIn, .user, .review

    public init(
        id: UUID = UUID(),
        bundleID: String? = nil,
        host: String? = nil,
        pathPrefix: String? = nil,
        titleContains: String? = nil,
        bucket: Bucket,
        source: Source = .user
    ) {
        self.id = id
        self.bundleID = bundleID
        self.host = host
        self.pathPrefix = pathPrefix
        self.titleContains = titleContains
        self.bucket = bucket
        self.source = source
    }

    /// True when every field that is set matches. A rule with no field set matches nothing.
    public func matches(_ o: ActivitySample) -> Bool {
        let bundle = Self.clean(bundleID), host = Self.clean(host)
        let path = Self.clean(pathPrefix), title = Self.clean(titleContains)
        guard bundle != nil || host != nil || path != nil || title != nil else { return false }

        if let bundle, o.bundleID.caseInsensitiveCompare(bundle) != .orderedSame { return false }
        if host != nil || path != nil {
            guard let oHost = o.host else { return false }
            if let host {
                let wanted = Self.normalizedHost(host)
                guard oHost == wanted || oHost.hasSuffix("." + wanted) else { return false }
            }
            if let path, !Self.path(o.path, startsWith: path) { return false }
        }
        if let title {
            guard let t = o.windowTitle, t.range(of: title, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            else { return false }
        }
        return true
    }

    /// How narrow the rule is: path rules beat host rules, host rules beat bundle rules;
    /// a longer host and a title condition break ties.
    public var specificity: Int {
        var score = 0
        if Self.clean(bundleID) != nil { score += 10 }
        if let host = Self.clean(host) { score += 100 + min(host.count, 99) }
        if let path = Self.clean(pathPrefix) { score += 1000 + min(path.count, 99) }
        if Self.clean(titleContains) != nil { score += 5 }
        return score
    }

    /// Same conditions (the bucket and source may differ).
    func sameMatch(as other: Rule) -> Bool {
        func norm(_ s: String?) -> String? { Self.clean(s)?.lowercased() }
        return norm(bundleID) == norm(other.bundleID)
            && norm(host).map(Self.normalizedHost) == norm(other.host).map(Self.normalizedHost)
            && norm(pathPrefix) == norm(other.pathPrefix)
            && norm(titleContains) == norm(other.titleContains)
    }

    private static func clean(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }

    private static func normalizedHost(_ h: String) -> String {
        var host = h.lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Prefix match on whole path components.
    private static func path(_ path: String, startsWith prefix: String) -> Bool {
        var wanted = prefix.lowercased()
        if !wanted.hasPrefix("/") { wanted = "/" + wanted }
        while wanted.count > 1 && wanted.hasSuffix("/") { wanted.removeLast() }
        if wanted == "/" { return true }
        return path == wanted || path.hasPrefix(wanted + "/")
    }
}

/// The ordered rules: user and review rules first, then built-ins.
public struct RuleBook: Codable, Sendable {
    public var rules: [Rule]             // user and review rules first, then built-ins

    public init(rules: [Rule]) { self.rules = rules }

    /// Your rules in front of the current built-ins. Persist `customRules` and rebuild with
    /// this, so a new VagoKit release brings its new built-ins.
    public init(custom: [Rule]) { self.rules = custom + Self.builtIn.rules }

    /// Rules that are not built-in, in order.
    public var customRules: [Rule] { rules.filter { $0.source != .builtIn } }

    /// The rule that decides `o`: the first matching user or review rule; otherwise the most
    /// specific matching built-in (path, then host, then bundle), the earlier one on a tie.
    public func matchingRule(for o: ActivitySample) -> Rule? {
        if let custom = rules.first(where: { $0.source != .builtIn && $0.matches(o) }) { return custom }
        var best: Rule?
        for rule in rules where rule.source == .builtIn && rule.matches(o) {
            if best == nil || rule.specificity > best!.specificity { best = rule }
        }
        return best
    }

    /// `.ambiguous` when only an ambiguous rule matches (a browser with no URL, Instagram's
    /// home page); `.neutral` when no rule matches.
    public func bucket(for o: ActivitySample) -> Bucket {
        matchingRule(for: o)?.bucket ?? .neutral
    }

    /// Turns a nightly review answer into a `.review` rule at the front of the book.
    /// Web: the host plus the first path component. App: the bundle id, plus the first
    /// meaningful word of the window title when the app is ambiguous (Telegram, WhatsApp).
    /// An earlier `.review` rule with the same conditions is replaced, not duplicated.
    public mutating func learn(from o: ActivitySample, bucket: Bucket) {
        var rule = Rule(bucket: bucket, source: .review)
        if let host = o.host {
            rule.host = host
            if let first = o.url?.pathComponents.first(where: { $0 != "/" && !$0.isEmpty }) {
                rule.pathPrefix = "/" + first.lowercased()
            }
        } else {
            rule.bundleID = o.bundleID
            let bare = ActivitySample(bundleID: o.bundleID, appName: o.appName)
            if Self.builtIn.bucket(for: bare) == .ambiguous {
                rule.titleContains = Self.firstMeaningfulWord(of: o.windowTitle, excluding: o.appName)
            }
        }
        rules.removeAll { $0.source == .review && $0.sameMatch(as: rule) }
        rules.insert(rule, at: 0)
    }

    private static let stopWords: Set<String> = ["the", "and", "for", "with", "from", "you", "your", "new", "untitled", "window"]

    static func firstMeaningfulWord(of title: String?, excluding appName: String) -> String? {
        guard let title else { return nil }
        let appWords = Set(appName.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return title
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .first { $0.count >= 3 && !stopWords.contains($0.lowercased()) && !appWords.contains($0.lowercased()) }
    }
}

// MARK: - Built-in rules

extension RuleBook {
    /// The defaults listed in docs/PRODUCT.md.
    public static let builtIn: RuleBook = {
        var list: [Rule] = []
        func add(_ bucket: Bucket, bundle: String? = nil, host: String? = nil, path: String? = nil) {
            // A stable id per built-in, so a list that shows rules keeps its identity between launches.
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", list.count + 1)) ?? UUID()
            list.append(Rule(id: id, bundleID: bundle, host: host, pathPrefix: path, bucket: bucket, source: .builtIn))
        }
        func apps(_ bucket: Bucket, _ bundles: [String]) { bundles.forEach { add(bucket, bundle: $0) } }
        func sites(_ bucket: Bucket, _ hosts: [String]) { hosts.forEach { add(bucket, host: $0) } }

        // Productive: work tools.
        apps(.productive, [
            "com.apple.dt.Xcode", "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
            "com.todesktop.230313mzl4w4u92",                       // Cursor
            "com.microsoft.VSCode", "dev.zed.Zed",
            "com.anthropic.claudefordesktop", "com.openai.chat", "com.openai.codex",
            "notion.id", "com.linear", "com.figma.Desktop",
            "com.apple.mail", "com.tinyspeck.slackmacgap", "com.tinyspeck.chatlyio",
            "com.apple.iWork.Keynote", "com.apple.iWork.Pages", "com.apple.iWork.Numbers",
        ])
        sites(.productive, [
            "github.com", "linear.app", "notion.so", "figma.com", "docs.google.com", "drive.google.com",
            "mail.google.com", "claude.ai", "chatgpt.com", "developer.apple.com", "stackoverflow.com",
        ])
        // Work inside apps that are otherwise ambiguous.
        add(.productive, host: "instagram.com", path: "/direct")
        add(.productive, host: "linkedin.com", path: "/messaging")

        // Neutral: necessary, neither counted.
        apps(.neutral, [
            "com.apple.finder", "com.apple.systempreferences", "com.apple.Preferences", "com.apple.Maps",
            "com.apple.iCal", "com.apple.mobilecal", "com.apple.Passbook", "com.apple.mobilephone",
            "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-ios",
            "com.apple.Music", "com.spotify.client",
        ])
        sites(.neutral, ["calendar.google.com", "maps.google.com", "music.youtube.com"])

        // Procrastination: feeds, video, games, news.
        apps(.procrastination, ["com.zhiliaoapp.musically", "com.reddit.Reddit", "com.netflix.Netflix", "tv.twitch"])
        sites(.procrastination, [
            "tiktok.com", "reddit.com", "netflix.com", "twitch.tv", "primevideo.com", "9gag.com",
            "news.ycombinator.com", "meduza.io", "lenta.ru", "cnn.com", "nytimes.com", "theguardian.com", "elpais.com",
        ])
        add(.procrastination, host: "bbc.com", path: "/news")
        add(.procrastination, host: "bbc.co.uk", path: "/news")
        add(.procrastination, host: "youtube.com", path: "/shorts")
        add(.procrastination, host: "instagram.com", path: "/reels")
        add(.procrastination, host: "instagram.com", path: "/explore")
        add(.procrastination, host: "x.com", path: "/explore")

        // Ambiguous: serve both work and waste; the four signals decide each session.
        apps(.ambiguous, [
            "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser",
            "com.microsoft.edgemac", "company.thebrowser.dia", "org.mozilla.firefox",
            "ru.keepcoder.Telegram", "org.telegram.desktop", "ph.telegra.Telegraph", "net.whatsapp.WhatsApp",
            "com.burbn.instagram", "com.google.ios.youtube", "com.atebits.Tweetie2", "com.linkedin.LinkedIn",
            "com.burbn.barcelona",
        ])
        sites(.ambiguous, [
            "instagram.com", "youtube.com", "x.com", "twitter.com", "linkedin.com", "t.me", "web.telegram.org",
            "threads.net", "substack.com", "facebook.com",
        ])
        return RuleBook(rules: list)
    }()
}
