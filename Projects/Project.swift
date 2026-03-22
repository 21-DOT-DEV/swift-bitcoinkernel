import ProjectDescription

/// List app targets
let targets: [Target]

let project = Project(
    name: "NodeApp",
    packages: [
        .package(path: "..")
    ],
    settings: .settings(
        configurations: [
            .debug(
                name: ConfigurationName(stringLiteral: "Debug"),
                xcconfig: Path(stringLiteral: "Resources/NodeApp/Debug.xcconfig")
            )
        ]
    ),
    targets: [
        .target(
            name: "NodeApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.21.NodeApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                ]
            ),
            sources: ["Sources/NodeApp/**"],
            resources: [
                "Resources/NodeApp/Assets.xcassets",
                "Resources/NodeApp/Preview Content/**",
                "Resources/NodeApp/LaunchScreen.storyboard"
            ],
            entitlements: "Resources/NodeApp/NodeApp.entitlements",
            dependencies: [
                .package(product: "Bitcoin")
            ]
        )
    ]
)
