//
//  JSONRPCService.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative 
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// A service for sending JSON-RPC requests to a Bitcoin node.
///
/// `JSONRPCService` handles the low-level details of constructing HTTP requests,
/// sending them to the specified URL, and processing the responses.
public class JSONRPCService {
    /// The URL of the Bitcoin node's JSON-RPC endpoint.
    private let url: URL
    
    /// The username for authentication.
    private let username: String
    
    /// The password for authentication.
    private let password: String
    
    /// The URLSession used for network requests.
    private let session: URLSession
    
    /// The coder used for encoding requests and decoding responses.
    public var coder: JSONRPCCoder

    /// Initializes a new JSON-RPC service with the specified URL, credentials, and session.
    ///
    /// - Parameters:
    ///   - url: The URL of the Bitcoin node's JSON-RPC endpoint.
    ///   - username: The username for authentication.
    ///   - password: The password for authentication.
    ///   - session: The URLSession to use for network requests. Defaults to `.shared`.
    public init(url: URL, username: String, password: String, session: URLSession = .shared) {
        self.url = url
        self.username = username
        self.password = password
        self.session = session
        self.coder = JSONRPCCoder()
    }

    /// Sends a JSON-RPC request and returns the decoded response.
    ///
    /// - Parameter request: The JSON-RPC request to send.
    /// - Returns: The decoded response of type `T`, which must conform to `Codable`.
    /// - Throws: An error if the request fails, the response is invalid, or decoding fails.
    func send<T>(request: JSONRPCRequest) async throws -> T {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        // Encode request body
        let encoder = JSONEncoder()
        let requestData = try encoder.encode(request)
        urlRequest.httpBody = requestData

        print("Request Body: \(String(data: requestData, encoding: .utf8) ?? "Invalid Request data")")

        // Add Basic Authentication
        let loginString = "\(username):\(password)"
        let loginData = loginString.data(using: .utf8)!
        let base64LoginString = loginData.base64EncodedString()
        urlRequest.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")

        print("Sending request: \(String(data: requestData, encoding: .utf8) ?? "Invalid request data")")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        print("Response Status Code: \(httpResponse.statusCode)")
        print("Response Body: \(String(data: data, encoding: .utf8) ?? "Invalid response data")")

        if httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        let jsonResponse = try decoder.decode(JSONRPCResponse.self, from: data)

        if let error = jsonResponse.error {
            throw NSError(domain: "JSONRPCError", code: error.code, userInfo: [NSLocalizedDescriptionKey: error.message])
        }

        switch jsonResponse.result {
        case .integer(let intValue):
            if T.self == Int.self {
                return intValue as! T
            }
        case .string(let stringValue):
            if T.self == String.self {
                return stringValue as! T
            }
        case .blockchainInfo(let blockchainInfo):
            if T.self == BlockchainInfo.self {
                return blockchainInfo as! T
            }
        case .blockWithTransactions(let blockWithTransactions):
            if T.self == BlockWithTransactions.self {
                return blockWithTransactions as! T
            }
        case .block(let block):
            if T.self == Block.self {
                return block as! T
            }
        case .null:
            if T.self == Void.self {
                return () as! T
            }
        }

        throw URLError(.cannotParseResponse)
    }
}
