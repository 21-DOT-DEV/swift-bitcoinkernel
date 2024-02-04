// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bitcoin",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(name: "Bitcoin", targets: ["Bitcoin"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "Bitcoin", dependencies: ["Configure"]),
//        .testTarget(name: "BitcoinTests", dependencies: ["Bitcoin"]),
        // Plugins
        .plugin(
            name: "Configure",
            capability: .command(
                intent: .custom(
                    verb: "configure",
                    description: "Configures the Bitcoin node."
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "")
                ]
            )
        ),
//        .plugin(
//            name: "ConfigurePlugin",
//            capability: .buildTool()
//        )
    ]
)
