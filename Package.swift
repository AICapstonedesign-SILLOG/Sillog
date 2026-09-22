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
    ],
    targets: [
        .target(
            name: "WorkGraphCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(
            name: "WorkGraphCollectors",
            dependencies: ["WorkGraphCore"]
        ),
        .executableTarget(
            name: "WorkGraphApp",
            dependencies: ["WorkGraphCore", "WorkGraphCollectors"],
            exclude: ["Resources/AppIcon.icns"],            // .app 번들에는 scripts/make-app.sh 가 직접 넣는다
            resources: [.copy("Resources/graph")]
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
