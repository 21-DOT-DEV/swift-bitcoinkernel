//
//  ContentView.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = CommandListViewModel()

    var body: some View {
        ScrollView {
            // Header
            Text("Bitcoin Commands")
                .font(.largeTitle)
                .padding()

            LazyVStack {
                ForEach(viewModel.commands.indices, id: \.self) { index in
                    let command = viewModel.commands[index]
                    Button(action: command.action) {
                        Text(command.title)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(5)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
