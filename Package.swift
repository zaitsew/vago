// swift-tools-version: 6.0
import PackageDescription

// VagoKit: the pure-Swift core of Vago. Foundation only; no UI framework, no AI framework.
let package = Package(
    name: "VagoKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "VagoKit", targets: ["VagoKit"]),
        // Read-only MCP server and CLI over the Mac app's state file (docs/AI.md).
        .executable(name: "vago-mcp", targets: ["vago-mcp"]),
    ],
    targets: [
        .target(name: "VagoKit"),
        .executableTarget(name: "vago-mcp", dependencies: ["VagoKit"]),
        .testTarget(name: "VagoKitTests", dependencies: ["VagoKit"]),
    ],
    swiftLanguageModes: [.v6]
)
