import Foundation
import VagoKit

// vago-mcp: read-only numbers from the Vago Mac app's state file.
//
//   vago-mcp              serve MCP over stdio (what Claude and Codex launch)
//   vago-mcp today|week   print the answer once, for a quick check in a terminal
//
// `--state <path>` or $VAGO_STATE points at another state.json. Nothing is written.

var arguments = Array(CommandLine.arguments.dropFirst())
var stateURL = ProcessInfo.processInfo.environment["VAGO_STATE"].map { URL(fileURLWithPath: $0) } ?? StateFile.defaultURL
if let i = arguments.firstIndex(of: "--state"), i + 1 < arguments.count {
    stateURL = URL(fileURLWithPath: arguments[i + 1])
    arguments.removeSubrange(i...(i + 1))
}

let url = stateURL
let server = VagoMCPServer { try StateFile.load(from: url).report() }

switch arguments.first {
case nil, "serve":
    // One JSON-RPC message per line. Logs go to stderr, never stdout.
    while let line = readLine(strippingNewline: true) {
        if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
        if let reply = server.handle(line: line) { print(reply); fflush(stdout) }
    }
case "today", "week":
    let tool = arguments[0] == "today" ? "get_today" : "get_week"
    let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)"}}"#
    guard let reply = server.handle(line: request),
          let object = try? JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any],
          let result = object["result"] as? [String: Any],
          let content = result["content"] as? [[String: Any]],
          let text = content.first?["text"] as? String
    else { FileHandle.standardError.write(Data("vago-mcp: no answer\n".utf8)); exit(1) }
    print(text)
    if result["isError"] as? Bool == true { exit(1) }
case "--help", "-h", "help":
    print("usage: vago-mcp [serve | today | week] [--state <state.json>]")
default:
    FileHandle.standardError.write(Data("vago-mcp: unknown command \(arguments[0]). Try --help.\n".utf8))
    exit(2)
}
