//
//  Project.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import ProjectDescription

let deploymentTargets = ProjectDescription.DeploymentTargets.multiplatform(
    iOS: "18.0",
    macOS: "15.0"
)

let project = Project(
    name: "Bitcoin",
    packages: [
        .package(path: ".."),
        .remote(url: "https://github.com/21-DOT-DEV/swift-tor.git", requirement: .exact("0.1.1")),
        // Test-only: `TestClock` virtualizes `TorViewModel`'s retry backoff so the
        // race-condition suites are deterministic. Linked into the `*Tests` targets
        // only — production uses the stdlib `Clock` — and absent from `Package.swift`,
        // so downstream package consumers never resolve it.
        .remote(url: "https://github.com/pointfreeco/swift-clocks.git", requirement: .upToNextMajor(from: "1.0.0")),
    ],
    settings: .settings(
        configurations: [
            .debug(name: "Debug", xcconfig: "Resources/Project/Debug.xcconfig"),
            .release(name: "Release", xcconfig: "Resources/Project/Release.xcconfig")
        ]
    ),
    targets: [
        // MARK: - Example Apps

        .target(
            name: "NodeApp",
            destinations: [.iPhone, .iPad, .mac],
            product: .app,
            bundleId: "dev.21.NodeApp",
            deploymentTargets: deploymentTargets,
            sources: ["Sources/NodeApp/**", "Sources/Shared/**"],
            resources: [
                "Resources/NodeApp/Assets.xcassets/**",
                "Resources/NodeApp/Preview Content/**",
                "Resources/NodeApp/AppIcon.icon",
                "Resources/NodeApp/PrivacyInfo.xcprivacy"
            ],
            entitlements: "Resources/NodeApp/NodeApp.entitlements",
            dependencies: [
                .package(product: "Bitcoin"),
                .package(product: "Tor"),
            ],
            settings: .settings(
                base: [
                    "CODE_SIGN_IDENTITY": "Apple Development",
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) Xcode",
                    "SWIFT_OBJC_INTEROP_MODE": "objcxx",
                ],
                configurations: [
                    .debug(name: "Debug", xcconfig: "Resources/NodeApp/Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "Resources/NodeApp/Release.xcconfig")
                ]
            )
        ),

        .target(
            name: "KernelApp",
            destinations: [.iPhone, .iPad, .mac],
            product: .app,
            bundleId: "dev.21.KernelApp",
            deploymentTargets: deploymentTargets,
            sources: ["Sources/KernelApp/**", "Sources/Shared/**"],
            resources: [
                "Resources/KernelApp/Assets.xcassets/**",
                "Resources/KernelApp/Preview Content/**",
                "Resources/KernelApp/AppIcon.icon",
                "Resources/KernelApp/PrivacyInfo.xcprivacy"
            ],
            entitlements: "Resources/KernelApp/KernelApp.entitlements",
            dependencies: [
                .package(product: "BitcoinKernel"),
                .package(product: "Tor"),
            ],
            settings: .settings(
                base: [
                    "CODE_SIGN_IDENTITY": "Apple Development",
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) Xcode",
                ],
                configurations: [
                    .debug(name: "Debug", xcconfig: "Resources/KernelApp/Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "Resources/KernelApp/Release.xcconfig")
                ]
            )
        ),
        
        // MARK: - Tests

        .target(
            name: "NodeAppTests",
            destinations: [.iPhone, .iPad, .mac],
            product: .unitTests,
            bundleId: "dev.21.NodeAppTests",
            deploymentTargets: deploymentTargets,
            sources: ["Sources/NodeAppTests/**", "Sources/SharedTests/**"],
            dependencies: [.target(name: "NodeApp"), .package(product: "Clocks")],
            settings: .settings(
                base: [
                    "SWIFT_OBJC_INTEROP_MODE": "objcxx",
                ],
                configurations: [
                    .debug(name: "Debug", xcconfig: "Resources/NodeAppTests/Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "Resources/NodeAppTests/Release.xcconfig")
                ]
            )
        ),
        .target(
            name: "KernelAppTests",
            destinations: [.iPhone, .iPad, .mac],
            product: .unitTests,
            bundleId: "dev.21.KernelAppTests",
            deploymentTargets: deploymentTargets,
            // The last two entries reach up into the Swift package's own test
            // helpers rather than duplicating them. `.kernelSerialized` makes
            // engine-touching tests take turns across ALL suites in a bundle;
            // Apple's built-in `.serialized` only orders tests within one suite,
            // which is why four suites here could each build a Bitcoin engine
            // simultaneously. Referenced (not copied) so a fix lands once.
            // Listed as explicit files, not a wildcard: that folder also holds a
            // `MockBlockSource.swift` that would collide with this bundle's own.
            sources: [
                "Sources/KernelAppTests/**",
                "Sources/SharedTests/**",
                "../Tests/BitcoinKernelTests/Support/KernelSerialization.swift",
                "../Tests/BitcoinKernelTests/Support/AsyncSemaphore.swift",
            ],
            dependencies: [.target(name: "KernelApp"), .package(product: "Clocks")],
            settings: .settings(
                configurations: [
                    .debug(name: "Debug", xcconfig: "Resources/KernelAppTests/Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "Resources/KernelAppTests/Release.xcconfig")
                ]
            )
        ),
    ]
)
