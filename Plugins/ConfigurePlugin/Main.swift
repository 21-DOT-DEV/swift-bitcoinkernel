//
//  Main.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2023 TWENTY ONE DEV LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import PackagePlugin

@main
struct Plugin: BuildToolPlugin {
    func createBuildCommands(
        context: PackagePlugin.PluginContext,
        target: PackagePlugin.Target
    ) async throws -> [PackagePlugin.Command] {
        let path = try context.tool(named: "zsh").path

        return [
//            .buildCommand(
//                displayName: "Running ./autogen.sh",
//                executable: path,
//                arguments: [
//                    "-c",
//                    "(cd Submodules/bitcoin && echo \"\(path)\" && ./autogen.sh)", /*context.pluginWorkDirectory.appending($0.name)*/
//                    //$0.type,
//                ],
//                environment: [
//                    "PATH": "/opt/homebrew/bin:/opt/homebrew/sbin",
//                    "TARGET_NAME": "\(target.name)",
//                    "DERIVED_SOURCES_DIR": "\(genSourcesDir)",
//                ]
//            )
        ]
    }
    
//    func performCommand(
//        context: PackagePlugin.PluginContext,
//        arguments: [String]
//    ) async throws {
//        // Create a Process to run the shell command
//        let autogenProcess = Process()
//        let configureProcess = Process()
//
//        // Define the shell command you want to execute
//        let autogenCommand = "(cd Submodules/bitcoin && ./autogen.sh)"
//        let configureCommand = "(cd Submodules/bitcoin && ./configure --with-gui=no)"
//
//        autogenProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
//        autogenProcess.arguments = ["-c", autogenCommand]
//
//        configureProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
//        configureProcess.arguments = ["-c", configureCommand]
//
//        // Run the process
//        try autogenProcess.run()
//        autogenProcess.waitUntilExit()
//
//        // Run the process
//        try configureProcess.run()
//        configureProcess.waitUntilExit()
//
//        // Check the exit status
//        if autogenProcess.terminationStatus != 0 {
//            print("Shell command failed")
//        } else {
//            print("Shell command executed successfully")
//        }
//    }
}
