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
            path: "Genevieve"
        )
    ]
)
