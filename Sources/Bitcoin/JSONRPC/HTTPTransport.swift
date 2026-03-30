//
//  HTTPTransport.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Sends JSON-RPC requests over HTTP to a Bitcoin node.
public struct HTTPTransport: RPCTransport {
    private let url: URL
    private let username: String
    private let password: String
    private let session: URLSession

    public init(url: URL, username: String, password: String, session: URLSession = .shared) {
        self.url = url
        self.username = username
        self.password = password
        self.session = session
    }

    public func send(request: JSONRPCRequest) async throws -> Data {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        let requestData = try JSONEncoder().encode(request)
        urlRequest.httpBody = requestData

        let loginString = "\(username):\(password)"
        let loginData = loginString.data(using: .utf8)!
        let base64LoginString = loginData.base64EncodedString()
        urlRequest.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        return data
    }
}
