import ProjectDescription

let project = Project(
    name: "BitcoinNodeApp",
    packages: [
        .package(path: "..")
    ],
    targets: [
        Target.target(
            name: "BitcoinNodeApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.21.Bitcoin-Node-App",
            infoPlist: nil,
            sources: ["BitcoinNodeApp/**"],
            dependencies: [
                .package(product: "Bitcoin")
            ],
            settings: Settings.settings(
                configurations: [
                    .debug(
                        name: "Debug",
                        xcconfig: "BitcoinNodeApp/BitcoinNodeApp.xcconfig"
                    )
                ]
            )
        )
    ]
)
