import Foundation
import Testing
@testable import VagoKit

@Suite("Rules and buckets")
struct RulesTests {
    @Test func instagramDirectIsProductive() {
        #expect(builtIn.bucket(for: web("https://www.instagram.com/direct/inbox/")) == .productive)
    }

    @Test func instagramReelsIsProcrastination() {
        #expect(builtIn.bucket(for: web("https://www.instagram.com/reels/abc123/")) == .procrastination)
        #expect(builtIn.bucket(for: web("https://instagram.com/explore/")) == .procrastination)
    }

    @Test func instagramHomeIsAmbiguous() {
        #expect(builtIn.bucket(for: web("https://www.instagram.com/")) == .ambiguous)
        #expect(builtIn.bucket(for: web("https://instagram.com/someprofile")) == .ambiguous)
    }

    @Test func youtubeShortsVsWatch() {
        #expect(builtIn.bucket(for: web("https://www.youtube.com/shorts/xyz")) == .procrastination)
        #expect(builtIn.bucket(for: web("https://www.youtube.com/watch?v=xyz")) == .ambiguous)
        #expect(builtIn.bucket(for: web("https://music.youtube.com/")) == .neutral)
    }

    @Test func xExploreVsHome() {
        #expect(builtIn.bucket(for: web("https://x.com/explore")) == .procrastination)
        #expect(builtIn.bucket(for: web("https://x.com/home")) == .ambiguous)
        #expect(builtIn.bucket(for: web("https://x.com/messages")) == .ambiguous)
    }

    @Test func linkedInMessagingIsProductive() {
        #expect(builtIn.bucket(for: web("https://www.linkedin.com/messaging/thread/1")) == .productive)
        #expect(builtIn.bucket(for: web("https://www.linkedin.com/feed/")) == .ambiguous)
    }

    @Test func newsPathRule() {
        #expect(builtIn.bucket(for: web("https://www.bbc.com/news/world")) == .procrastination)
        #expect(builtIn.bucket(for: web("https://news.ycombinator.com/item?id=1")) == .procrastination)
    }

    @Test func hostRulesCoverSubdomains() {
        #expect(builtIn.bucket(for: web("https://old.reddit.com/r/swift")) == .procrastination)
        #expect(builtIn.bucket(for: web("https://gist.github.com/a")) == .productive)
    }

    @Test func lookalikeHostDoesNotMatch() {
        // "notinstagram.com" is not a subdomain of instagram.com; Chrome's own rule decides.
        #expect(builtIn.bucket(for: web("https://notinstagram.com/reels")) == .ambiguous)
        #expect(builtIn.bucket(for: web("https://notreddit.com/", bundle: "com.example.app")) == .neutral)
    }

    @Test func pathMatchesWholeComponents() {
        let r = Rule(host: "instagram.com", pathPrefix: "/direct", bucket: .productive)
        #expect(r.matches(web("https://instagram.com/direct")))
        #expect(r.matches(web("https://instagram.com/direct/t/1")))
        #expect(!r.matches(web("https://instagram.com/directory")))
    }

    @Test func specificityBeatsOrder() {
        // Every order of three built-in-style rules gives the same answer.
        func rule(_ host: String?, _ path: String?, _ bucket: Bucket, bundle: String? = nil) -> Rule {
            Rule(bundleID: bundle, host: host, pathPrefix: path, bucket: bucket, source: .builtIn)
        }
        let bundleRule = rule(nil, nil, .ambiguous, bundle: "com.google.Chrome")
        let hostRule = rule("instagram.com", nil, .ambiguous)
        let pathRule = rule("instagram.com", "/reels", .procrastination)
        let o = web("https://instagram.com/reels/1")
        let all = [bundleRule, hostRule, pathRule]
        let orders: [[Rule]] = [all, Array(all.reversed()), [hostRule, pathRule, bundleRule], [pathRule, bundleRule, hostRule]]
        for order in orders {
            #expect(RuleBook(rules: order).bucket(for: o) == .procrastination)
        }
    }

    @Test func hostRuleBeatsBrowserBundleRule() {
        #expect(builtIn.bucket(for: web("https://github.com/zaitsew/vago")) == .productive)
        #expect(builtIn.bucket(for: web("https://example.org/page")) == .ambiguous)   // only Chrome's rule matches
    }

    @Test func browserWithoutURLIsAmbiguous() {
        let browsers = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
                        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.dia"]
        for id in browsers {
            #expect(builtIn.bucket(for: app(id, title: "Some tab")) == .ambiguous, "\(id)")
        }
    }

    @Test func unknownAppIsNeutral() {
        #expect(builtIn.bucket(for: app("com.example.unknown")) == .neutral)
    }

    @Test func builtInApps() {
        #expect(builtIn.bucket(for: app("com.apple.dt.Xcode")) == .productive)
        #expect(builtIn.bucket(for: app("com.apple.finder")) == .neutral)
        #expect(builtIn.bucket(for: app("com.spotify.client")) == .neutral)
        #expect(builtIn.bucket(for: app("ru.keepcoder.Telegram")) == .ambiguous)
        #expect(builtIn.bucket(for: app("org.telegram.desktop")) == .ambiguous)
        #expect(builtIn.bucket(for: app("net.whatsapp.WhatsApp")) == .ambiguous)
    }

    @Test func userRuleBeatsBuiltIn() {
        var book = builtIn
        book.rules.insert(Rule(host: "instagram.com", pathPrefix: "/reels", bucket: .productive, source: .user), at: 0)
        #expect(book.bucket(for: web("https://instagram.com/reels/1")) == .productive)
    }

    @Test func userRuleWinsEvenAfterBuiltIns() {
        // A custom rule placed after the built-ins in the array still comes first.
        var book = builtIn
        book.rules.append(Rule(host: "reddit.com", bucket: .productive, source: .user))
        #expect(book.bucket(for: web("https://reddit.com/r/swift")) == .productive)
    }

    @Test func titleRuleIsCaseInsensitiveAndNeedsATitle() {
        let r = Rule(bundleID: "ru.keepcoder.Telegram", titleContains: "ACME", bucket: .productive)
        #expect(r.matches(app("ru.keepcoder.Telegram", title: "acme team")))
        #expect(!r.matches(app("ru.keepcoder.Telegram", title: "memes")))
        #expect(!r.matches(app("ru.keepcoder.Telegram")))
    }

    @Test func emptyRuleMatchesNothing() {
        #expect(!Rule(bucket: .productive).matches(app("com.apple.dt.Xcode")))
    }

    @Test func builtInIDsAreStable() {
        #expect(RuleBook.builtIn.rules.map(\.id) == RuleBook.builtIn.rules.map(\.id))
        #expect(Set(RuleBook.builtIn.rules.map(\.id)).count == RuleBook.builtIn.rules.count)
    }

    @Test func ruleBookRoundTripsThroughJSON() throws {
        var book = builtIn
        book.learn(from: web("https://instagram.com/reels/1"), bucket: .productive)
        let data = try JSONEncoder().encode(book)
        let back = try JSONDecoder().decode(RuleBook.self, from: data)
        #expect(back.rules == book.rules)
    }

    @Test func customRulesRebuildOnTopOfBuiltIns() {
        var book = builtIn
        book.learn(from: web("https://reddit.com/r/swift"), bucket: .productive)
        let rebuilt = RuleBook(custom: book.customRules)
        #expect(rebuilt.rules.count == book.rules.count)
        #expect(rebuilt.bucket(for: web("https://reddit.com/r/swift")) == .productive)
    }
}

@Suite("Learning from the nightly review")
struct LearnTests {
    @Test func webLearnsHostAndFirstPathComponent() {
        var book = builtIn
        book.learn(from: web("https://www.Instagram.com/someprofile/posts/1", title: "x"), bucket: .productive)
        let rule = book.rules[0]
        #expect(rule.source == .review)
        #expect(rule.host == "instagram.com")
        #expect(rule.pathPrefix == "/someprofile")
        #expect(rule.bundleID == nil)
        #expect(rule.bucket == .productive)
    }

    @Test func webWithoutPathLearnsHostOnly() {
        var book = builtIn
        book.learn(from: web("https://substack.com/"), bucket: .procrastination)
        #expect(book.rules[0].host == "substack.com")
        #expect(book.rules[0].pathPrefix == nil)
    }

    @Test func learnedRuleChangesTheAnswer() {
        var book = builtIn
        let o = web("https://instagram.com/reels/1")
        #expect(book.bucket(for: o) == .procrastination)
        book.learn(from: o, bucket: .productive)
        #expect(book.bucket(for: o) == .productive)
        #expect(book.bucket(for: web("https://instagram.com/reels/2")) == .productive)
        #expect(book.bucket(for: web("https://instagram.com/explore")) == .procrastination)   // other paths unaffected
    }

    @Test func unknownAppLearnsBundleOnly() {
        var book = builtIn
        book.learn(from: app("com.example.game", name: "Game", title: "Level 3 — Boss"), bucket: .procrastination)
        let rule = book.rules[0]
        #expect(rule.bundleID == "com.example.game")
        #expect(rule.titleContains == nil)
        #expect(book.bucket(for: app("com.example.game")) == .procrastination)
    }

    @Test func ambiguousAppLearnsFirstMeaningfulTitleWord() {
        var book = builtIn
        let chat = app("ru.keepcoder.Telegram", name: "Telegram", title: "The Acme Team — 3 unread")
        book.learn(from: chat, bucket: .productive)
        #expect(book.rules[0].titleContains == "Acme")      // "The" is a stop word, "Telegram"-style app words are skipped
        #expect(book.bucket(for: chat) == .productive)
        #expect(book.bucket(for: app("ru.keepcoder.Telegram", name: "Telegram", title: "Memes")) == .ambiguous)
    }

    @Test func ambiguousAppWithoutUsableTitleLearnsBundleOnly() {
        var book = builtIn
        book.learn(from: app("net.whatsapp.WhatsApp", name: "WhatsApp", title: "WhatsApp"), bucket: .procrastination)
        #expect(book.rules[0].titleContains == nil)
        #expect(book.bucket(for: app("net.whatsapp.WhatsApp")) == .procrastination)
    }

    @Test func learnReplacesAnEarlierReviewRule() {
        var book = builtIn
        let o = web("https://instagram.com/someprofile")
        book.learn(from: o, bucket: .productive)
        let count = book.rules.count
        book.learn(from: web("https://www.instagram.com/someprofile/x"), bucket: .procrastination)
        #expect(book.rules.count == count)                     // replaced, not duplicated
        #expect(book.customRules.count == 1)
        #expect(book.bucket(for: o) == .procrastination)
    }

    @Test func learnPutsTheNewestRuleFirst() {
        var book = builtIn
        book.learn(from: web("https://reddit.com/r/swift"), bucket: .productive)
        book.learn(from: web("https://netflix.com/browse"), bucket: .productive)
        #expect(book.rules[0].host == "netflix.com")
        #expect(book.rules[1].host == "reddit.com")
    }

    @Test func learnLeavesUserRulesAlone() {
        var book = builtIn
        book.rules.insert(Rule(host: "reddit.com", pathPrefix: "/r", bucket: .procrastination, source: .user), at: 0)
        book.learn(from: web("https://reddit.com/r/swift"), bucket: .productive)
        #expect(book.customRules.count == 2)
        #expect(book.customRules.filter { $0.source == .user }.count == 1)
    }
}
