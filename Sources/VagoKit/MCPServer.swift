import Foundation

/// A read-only Model Context Protocol server over stdio (newline-delimited JSON-RPC 2.0).
///
/// Two tools, both reads: today's numbers and the last seven days. The server holds no state,
/// opens nothing but the state file, and never writes. It returns minutes only: no app names,
/// window titles or URLs. `handle(line:)` is pure apart from the `load` call, so tests drive it
/// with a stub.
public struct VagoMCPServer: Sendable {
    public static let serverVersion = "1.0.0"
    static let latestProtocol = "2025-06-18"
    static let supportedProtocols = ["2025-06-18", "2025-03-26", "2024-11-05"]

    public typealias Loader = @Sendable () throws -> VagoReport

    private let load: Loader

    public init(load: @escaping Loader) { self.load = load }

    /// The reply line for one request line, or nil for a notification (nothing is sent back).
    public func handle(line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return Self.encode(Self.error(id: NSNull(), code: -32700, message: "Parse error")) }
        guard let request = object as? [String: Any], request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String,
              request["id"] == nil || request["id"] is String || Self.isNumber(request["id"])
        else {
            return Self.encode(Self.error(id: NSNull(), code: -32600, message: "Invalid request"))
        }
        guard let id = request["id"] else { return nil }              // a notification
        let params = request["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            let version = Self.supportedProtocols.contains(asked) ? asked : Self.latestProtocol
            return Self.encode(Self.result(id: id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "vago", "title": "Vago", "version": Self.serverVersion],
                "instructions": "Read-only focus numbers from the Vago app: minutes of procrastination, "
                    + "work and focus, today and over the last seven days. Use get_today for \"how focused "
                    + "was I today\" and get_week for trends. Nothing here can change Vago.",
            ]))
        case "ping":
            return Self.encode(Self.result(id: id, [:]))
        case "tools/list":
            return Self.encode(Self.result(id: id, ["tools": Self.tools]))
        case "tools/call":
            return Self.encode(call(id: id, params: params))
        default:
            return Self.encode(Self.error(id: id, code: -32601, message: "Method not found: \(method)"))
        }
    }

    /// A JSON number, not a JSON boolean (both bridge to `NSNumber`).
    private static func isNumber(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
    }

    // MARK: Tools

    private static var readOnly: [String: Any] { [
        "readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false,
    ] }
    private static var noArguments: [String: Any] { [
        "type": "object", "properties": [String: Any](), "additionalProperties": false,
    ] }

    static var tools: [[String: Any]] { [
        [
            "name": "get_today",
            "title": "Get today's focus numbers",
            "description": "Today's minutes of procrastination, work and focus across the owner's Mac and "
                + "iPhone, the daily limit, the minutes left and the mood. Also says which devices "
                + "reported and when the numbers were last updated. Use it to answer \"how focused was "
                + "I today\". The day runs from 04:00 to 04:00. Read-only.",
            "inputSchema": noArguments,
            "annotations": readOnly.merging(["title": "Get today's focus numbers"]) { a, _ in a },
        ],
        [
            "name": "get_week",
            "title": "Get the last seven days",
            "description": "Minutes of procrastination, work and focus for each of the last seven days "
                + "(today included), with averages, the best and worst day, and how many days stayed "
                + "at or under the 30-minute target. Days without data are marked untracked. Read-only.",
            "inputSchema": noArguments,
            "annotations": readOnly.merging(["title": "Get the last seven days"]) { a, _ in a },
        ],
    ] }

    private func call(id: Any, params: [String: Any]) -> [String: Any] {
        guard let name = params["name"] as? String, ["get_today", "get_week"].contains(name) else {
            return Self.error(id: id, code: -32602, message: "Unknown tool: \(params["name"] as? String ?? "")")
        }
        let report: VagoReport
        do { report = try load() } catch {
            return Self.result(id: id, [
                "content": [["type": "text", "text": "\(error)"]],
                "isError": true,
            ])
        }
        let structured = name == "get_today" ? Self.todayJSON(report) : Self.weekJSON(report)
        let text = (name == "get_today" ? Self.todayText(report) : Self.weekText(report))
            + "\n\n" + (Self.encode(structured, pretty: true) ?? "{}")
        return Self.result(id: id, [
            "content": [["type": "text", "text": text]],
            "structuredContent": structured,
            "isError": false,
        ])
    }

    // MARK: Output

    static func todayText(_ r: VagoReport) -> String {
        var lines = [r.today.tracked ? r.today.sentence : "Nothing is tracked yet today."]
        if let focus = r.macFocus { lines.append("A \(focus.minutes)-minute focus block is running on the Mac, \(focus.minutesLeft) min left.") }
        lines.append(freshness(r))
        return lines.joined(separator: "\n")
    }

    static func weekText(_ r: VagoReport) -> String { r.week.sentence + "\n" + freshness(r) }

    private static func freshness(_ r: VagoReport) -> String {
        guard let updated = r.updatedAt else { return "No device has reported today." }
        let minutes = max(0, Int(r.now.timeIntervalSince(updated) / 60))
        return "Devices today: \(r.devicesToday.joined(separator: ", ")). Last update \(minutes) min ago."
    }

    static func todayJSON(_ r: VagoReport) -> [String: Any] {
        var json = base(r)
        json["today"] = dictionary(r.today)
        if let focus = r.macFocus {
            json["macFocusRunning"] = ["minutes": focus.minutes, "minutesLeft": focus.minutesLeft]
        }
        return json
    }

    static func weekJSON(_ r: VagoReport) -> [String: Any] {
        var json = base(r)
        json["week"] = dictionary(r.week)
        return json
    }

    private static func base(_ r: VagoReport) -> [String: Any] {
        var json: [String: Any] = ["devicesToday": r.devicesToday, "asOf": r.now.formatted(.iso8601)]
        if let updated = r.updatedAt { json["lastUpdate"] = updated.formatted(.iso8601) }
        if let baseline = r.baselineMinutes { json["baselineMinutes"] = baseline }
        return json
    }

    /// A Codable value as a JSON dictionary, nil fields dropped.
    private static func dictionary<T: Encodable>(_ value: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    // MARK: JSON-RPC

    private static func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    /// One line of JSON. Newlines inside strings are escaped, so a reply never spans lines.
    static func encode(_ object: [String: Any], pretty: Bool = false) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
