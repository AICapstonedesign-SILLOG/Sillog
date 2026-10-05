// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WorkGraph",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WorkGraphCore", targets: ["WorkGraphCore"]),
        .executable(name: "WorkGraphApp", targets: ["WorkGraphApp"]),
        .executable(name: "wgctl", targets: ["wgctl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // LangGraph for Swift: 문서 플러그인을 브랜치로 물고 있어 버전이 아니라 커밋으로 고정 (마지막 커밋 2025-08-01)
        .package(url: "https://github.com/bsorrentino/LangGraph-Swift.git", revision: "d91c62aaa25e818f2667482c6edbe635a375ec45"),
    ],
    targets: [
        .target(
            name: "WorkGraphCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift"), .product(name: "LangGraph", package: "LangGraph-Swift")],
            resources: [.copy("Chat/Skills")]
        ),
        .target(
            name: "WorkGraphCollectors",
            dependencies: ["WorkGraphCore"]
        ),
        .executableTarget(
            name: "WorkGraphApp",
            dependencies: ["WorkGraphCore", "WorkGraphCollectors"],
            exclude: ["Resources/AppIcon.icns"],            // .app 번들에는 scripts/make-app.sh 가 직접 넣는다
            resources: [.copy("Resources/graph"), .copy("Resources/PluginIcons")]
        ),
        .executableTarget(
            name: "wgctl",
            dependencies: ["WorkGraphCore", "WorkGraphCollectors", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "WorkGraphCoreTests",
            dependencies: ["WorkGraphCore"]
        ),
    ]
)
