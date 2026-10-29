// swift-tools-version: 6.0
import PackageDescription

// VagoKit: the pure-Swift core of Vago. Foundation only; no UI framework, no AI framework.
let package = Package(
    name: "VagoKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "VagoKit", targets: ["VagoKit"]),
    ],
    targets: [
        .target(name: "VagoKit"),
        .testTarget(name: "VagoKitTests", dependencies: ["VagoKit"]),
    ],
    swiftLanguageModes: [.v6]
)
