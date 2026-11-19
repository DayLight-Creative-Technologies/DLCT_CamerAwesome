// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "camerawesome",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(name: "camerawesome", targets: ["camerawesome"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/jpsim/JPSVolumeButtonHandler.git", branch: "master")
    ],
    targets: [
        .target(
            name: "camerawesome",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "JPSVolumeButtonHandler"
            ],
            resources: [],
            publicHeadersPath: "",
            cSettings: [
                .headerSearchPath("include")
            ]
        )
    ]
)

