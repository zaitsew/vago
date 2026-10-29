import Foundation
import Testing
@testable import VagoKit

@Suite("MCP server")
struct MCPServerTests {
    static let now = at("2026-10-29 15:00")

    static func report(focus: FocusSession? = nil) -> VagoReport {
        var l = Ledger()
        l.merge(deviceDay(DayKey(id: "2026-10-28"), .mac, procrastination: 50, productive: 120))
        l.merge(deviceDay(DayKey(id: "2026-10-29"), .mac, procrastination: 12, productive: 90, focus: 25, updated: at("2026-10-29 14:55")))
        var limit = AdaptiveLimit()
        limit.current = 30
        return StateFile(ledger: l, limit: limit, focus: focus).report(now: now, calendar: utc)
    }

    static func server(_ r: VagoReport? = nil) -> VagoMCPServer {
        let r = r ?? report()
        return VagoMCPServer { r }
    }

    static func reply(_ line: String, _ s: VagoMCPServer = server()) -> [String: Any] {
        let text = s.handle(line: line)!
        #expect(!text.contains("\n"))
        return try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }

    @Test func initializeEchoesASupportedProtocol() {
        let r = Self.reply(#"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        let result = r["result"] as! [String: Any]
        #expect(result["protocolVersion"] as? String == "2025-03-26")
        #expect((result["serverInfo"] as! [String: Any])["name"] as? String == "vago")
        #expect((result["capabilities"] as! [String: Any])["tools"] != nil)
    }

    @Test func initializeOffersTheLatestForAnUnknownProtocol() {
        let r = Self.reply(#"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        #expect(r["id"] as? String == "a")
        #expect((r["result"] as! [String: Any])["protocolVersion"] as? String == "2025-06-18")
    }

    @Test func notificationsGetNoReply() {
        #expect(Self.server().handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test func everyToolIsAReadWithATitleAndHints() {
        let r = Self.reply(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        let tools = (r["result"] as! [String: Any])["tools"] as! [[String: Any]]
        #expect(tools.map { $0["name"] as! String } == ["get_today", "get_week"])
        for tool in tools {
            #expect(!(tool["title"] as! String).isEmpty)
            let hints = tool["annotations"] as! [String: Any]
            #expect(hints["readOnlyHint"] as? Bool == true)
            #expect(hints["destructiveHint"] as? Bool == false)
            #expect(hints["openWorldHint"] as? Bool == false)
            #expect((tool["inputSchema"] as! [String: Any])["type"] as? String == "object")
        }
    }

    @Test func getTodayAnswersInSentenceAndStructure() {
        let r = Self.reply(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_today","arguments":{}}}"#)
        let result = r["result"] as! [String: Any]
        #expect(result["isError"] as? Bool == false)
        let text = ((result["content"] as! [[String: Any]])[0]["text"] as! String)
        #expect(text.contains("12 of 30 min on procrastination, 18 min left."))
        #expect(text.contains("90 min of work, 25 min of focus."))
        #expect(text.contains("Last update 5 min ago."))
        let today = (result["structuredContent"] as! [String: Any])["today"] as! [String: Any]
        #expect(today["procrastinationMinutes"] as? Int == 12)
        #expect(today["limitMinutes"] as? Int == 30)
        #expect(today["day"] as? String == "2026-10-29")
    }

    @Test func getWeekAnswersWithSevenDays() {
        let r = Self.reply(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_week"}}"#)
        let result = r["result"] as! [String: Any]
        let week = (result["structuredContent"] as! [String: Any])["week"] as! [String: Any]
        #expect((week["days"] as! [Any]).count == 7)
        #expect(week["trackedDays"] as? Int == 2)
        #expect(week["averageProcrastinationMinutes"] as? Int == 31)   // (50 + 12) / 2
    }

    @Test func aFocusBlockOnTheMacIsReportedOnlyWhileItRuns() {
        let running = FocusSession(start: at("2026-10-29 14:40"), minutes: 25)       // ends 15:05
        let text = Self.server(Self.report(focus: running)).handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_today"}}"#)!
        #expect(text.contains("25-minute focus block is running on the Mac, 5 min left."))
        let over = FocusSession(start: at("2026-10-29 14:00"), minutes: 25)          // ended 14:25
        #expect(Self.report(focus: over).macFocus == nil)
    }

    @Test func aMissingStateFileIsAToolErrorNotACrash() {
        let s = VagoMCPServer { throw StateFile.LoadError.missing("/nowhere/state.json") }
        let r = Self.reply(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_today"}}"#, s)
        let result = r["result"] as! [String: Any]
        #expect(result["isError"] as? Bool == true)
        #expect(((result["content"] as! [[String: Any]])[0]["text"] as! String).contains("/nowhere/state.json"))
    }

    @Test func protocolErrors() {
        let unknownTool = Self.reply(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"reset_day"}}"#)
        #expect((unknownTool["error"] as! [String: Any])["code"] as? Int == -32602)
        let unknownMethod = Self.reply(#"{"jsonrpc":"2.0","id":7,"method":"resources/list"}"#)
        #expect((unknownMethod["error"] as! [String: Any])["code"] as? Int == -32601)
        let garbage = Self.reply("not json")
        #expect((garbage["error"] as! [String: Any])["code"] as? Int == -32700)
        #expect(garbage["id"] is NSNull)
    }

    @Test func readsTheMacAppsStateFile() throws {
        // The shape the Mac app writes: numeric dates, extra keys a reader must ignore.
        let json = """
        {"goals":"x","customRules":[],"sessions":[{"anything":1}],
         "limit":{"current":25,"baseline":30,"lastDay":{"id":"2026-10-29"}},
         "ledger":{"days":{"day/2026-10-29/mac":{"day":{"id":"2026-10-29"},"device":"mac",
           "focus":120,"procrastination":306,"productive":3600,"updatedAt":814935599.3937}}}}
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vago-state-\(UUID()).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let state = try StateFile.load(from: url)
        #expect(state.limit.current == 25)
        let s = state.ledger.summary(for: DayKey(id: "2026-10-29"), limitMinutes: 25)
        #expect(s.procrastinationMinutes == 5 && s.productiveMinutes == 60 && s.focusMinutes == 2)
    }

    @Test func loadReportsMissingAndUnreadableFiles() throws {
        #expect(throws: StateFile.LoadError.self) { try StateFile.load(from: URL(fileURLWithPath: "/nowhere/state.json")) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vago-bad-\(UUID()).json")
        try "[1,2]".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: StateFile.LoadError.unreadable(url.path)) { try StateFile.load(from: url) }
    }
}
