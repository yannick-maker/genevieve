// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Genevieve",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Genevieve", targets: ["Genevieve"])
    ],
    targets: [
        .executableTarget(
            name: "Genevieve",
            path: "Genevieve",
            exclude: [
                "Services/DataExportService.swift.disabled",
                "Resources/Genevieve.entitlements",
                "Resources/Info.plist"
            ],
            resources: [
                .process("Resources/Assets.xcassets")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Combine")
            ]
        ),
        .testTarget(
            name: "GenevieveTests",
            dependencies: ["Genevieve"],
            path: "GenevieveTests"
        )
    ]
)
