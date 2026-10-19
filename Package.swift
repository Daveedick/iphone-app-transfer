// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AppTransfer",
    defaultLocalization: "en",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "AppTransfer", targets: ["AppTransfer"])],
    targets: [
        .target(name: "ArchiveBridge", cSettings: [.unsafeFlags(["-I/opt/homebrew/opt/libarchive/include"])], linkerSettings: [.linkedLibrary("archive")]),
        .target(name: "DeviceBridge", cSettings: [.unsafeFlags(["-I/opt/homebrew/include", "-I/opt/homebrew/opt/libarchive/include"])], linkerSettings: [.unsafeFlags(["-L/opt/homebrew/lib"]), .linkedLibrary("imobiledevice-1.0"), .linkedLibrary("plist-2.0"), .linkedLibrary("archive")]),
        .target(name: "AppTransferCore", dependencies: ["ArchiveBridge"]),
        .executableTarget(name: "AppTransfer", dependencies: ["AppTransferCore", "DeviceBridge"], resources: [.process("Resources")]),
        .testTarget(name: "AppTransferCoreTests", dependencies: ["AppTransferCore"])
    ],
    swiftLanguageVersions: [.v5]
)
