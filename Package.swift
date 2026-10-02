// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DynamicLighting",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CUSB",
            path: "Sources/CUSB",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(
            name: "DynamicLighting",
            dependencies: ["CUSB"],
            path: "Sources/DynamicLighting",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement")]
        ),
    ]
)
