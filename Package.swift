// swift-tools-version: 5.10

import PackageDescription
import Foundation

let libtorrentPrefix = ProcessInfo.processInfo.environment["TORA_LIBTORRENT_PREFIX"]
let boostPrefix = ProcessInfo.processInfo.environment["TORA_BOOST_PREFIX"]
    ?? (FileManager.default.fileExists(atPath: "/opt/homebrew/opt/boost") ? "/opt/homebrew/opt/boost" : nil)
var libtorrentCxxSettings: [CXXSetting] = [
    .headerSearchPath("include")
]
var libtorrentLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("c++")
]

if let libtorrentPrefix {
    libtorrentCxxSettings.append(.unsafeFlags(["-I", "\(libtorrentPrefix)/include"]))
    libtorrentLinkerSettings.append(.unsafeFlags(["-L", "\(libtorrentPrefix)/lib"]))
    libtorrentLinkerSettings.append(.linkedLibrary("torrent-rasterbar"))
}

if let boostPrefix {
    libtorrentCxxSettings.append(.unsafeFlags(["-I", "\(boostPrefix)/include"]))
    libtorrentLinkerSettings.append(.unsafeFlags(["-L", "\(boostPrefix)/lib"]))
}

let package = Package(
    name: "Tora",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Tora", targets: ["ToraApp"]),
        .executable(name: "ToraDebug", targets: ["ToraDebug"]),
        .library(name: "ToraCore", targets: ["ToraCore"]),
        .library(name: "ToraPersistence", targets: ["ToraPersistence"]),
        .library(name: "ToraLibtorrentBridge", targets: ["ToraLibtorrentBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
    ],
    targets: [
        .executableTarget(
            name: "ToraApp",
            dependencies: [
                "ToraUI",
                "ToraCore",
                "ToraPersistence",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            exclude: ["AppIcon.icns"]
        ),
        .executableTarget(
            name: "ToraDebug",
            dependencies: ["ToraCore"]
        ),
        .target(
            name: "ToraUI",
            dependencies: ["ToraCore"]
        ),
        .target(
            name: "ToraCore",
            dependencies: ["ToraLibtorrentBridge"]
        ),
        .target(
            name: "ToraPersistence",
            dependencies: ["ToraCore"]
        ),
        .target(
            name: "ToraLibtorrentBridge",
            publicHeadersPath: "include",
            cxxSettings: libtorrentCxxSettings,
            linkerSettings: libtorrentLinkerSettings
        ),
        .testTarget(
            name: "ToraCoreTests",
            dependencies: ["ToraCore"]
        ),
        .testTarget(
            name: "ToraPersistenceTests",
            dependencies: ["ToraPersistence"]
        ),
        .testTarget(
            name: "ToraLibtorrentBridgeTests",
            dependencies: ["ToraLibtorrentBridge"],
            resources: [
                .copy("../Fixtures")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
