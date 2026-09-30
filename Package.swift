// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "MaosRec",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .executable(name: "MaosRec", targets: ["MaosRec"])
    ],
    targets: [
        .target(
            name: "MaosRec",
            dependencies: [],
            path: "Sources/MaosRec"
        )
    ]
)
