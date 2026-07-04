// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GorillaTranslate",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "GorillaTranslate",
            targets: ["GorillaTranslate"]
        )
    ],
    targets: [
        .target(
            name: "GorillaTranslate",
            path: "GorillaTranslate"
        )
    ]
)
