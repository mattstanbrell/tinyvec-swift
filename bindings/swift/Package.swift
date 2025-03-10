// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "tinyvecdb",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "TinyVec",
            targets: ["TinyVec"]),
        .executable(
            name: "TinyVecDemo",
            targets: ["TinyVecDemo"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Ccore",
            dependencies: [],
            path: "Sources/Ccore",
            exclude: [],
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .target(
            name: "TinyVec",
            dependencies: ["Ccore"],
            path: "Sources/TinyVec"
        ),
        .target(
            name: "TinyVecDemo",
            dependencies: ["TinyVec"],
            path: "Sources/TinyVecDemo"
        )
    ]
)