//
//  CommandListViewModel.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Bitcoin
import Foundation
import Observation

@MainActor @Observable
final class CommandsViewModel {
    let commands: [RPCCommand] = RPCCommand.parameterFreeCommands
    private let client = RPCClient(
        url: InternalRPC.url,
        cookieFile: InternalRPC.cookieFileURL
    )

    var searchText = ""
    var responses: [String: String] = [:]
    var errors: [String: String] = [:]
    private(set) var executingCommandIDs = Set<String>()

    var hasActiveExecutions: Bool { !executingCommandIDs.isEmpty }

    func isExecuting(_ command: RPCCommand) -> Bool {
        executingCommandIDs.contains(command.id)
    }

    var filteredCommands: [RPCCommand] {
        if searchText.isEmpty {
            return commands
        }
        return commands.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.description.localizedCaseInsensitiveContains(searchText)
                || $0.category.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var commandsByCategory: [(category: RPCCategory, commands: [RPCCommand])] {
        let grouped = Dictionary(grouping: filteredCommands, by: \.category)
        return RPCCategory.allCases.compactMap { category in
            guard let commands = grouped[category], !commands.isEmpty else { return nil }
            return (category: category, commands: commands)
        }
    }

    func response(for command: RPCCommand) -> String? {
        responses[command.id]
    }

    func error(for command: RPCCommand) -> String? {
        errors[command.id]
    }

    func execute(_ command: RPCCommand) async {
        executingCommandIDs.insert(command.id)
        defer { executingCommandIDs.remove(command.id) }
        errors[command.id] = nil
        responses[command.id] = nil

        do {
            let data = try await client.call(command.methodName)
            responses[command.id] = prettyPrintJSON(data)
        } catch {
            errors[command.id] = error.localizedDescription
        }
    }

    private func prettyPrintJSON(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: pretty, encoding: .utf8)
        {
            return string
        }
        return String(data: data, encoding: .utf8) ?? "Unable to decode response"
    }
}
