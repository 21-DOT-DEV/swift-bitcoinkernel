//
//  JSONRPCService.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

public class JSONRPCService {
    private let url: URL
    private let session: URLSession

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    func send<T: Codable>(request: JSONRPCRequest) async throws -> T {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("text/plain", forHTTPHeaderField: "Content-Type")

        do {
            let requestData = try JSONEncoder().encode(request)
            urlRequest.httpBody = requestData
        } catch {
            throw error
        }

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print(response)
            throw URLError(.badServerResponse)
        }

        do {
            let response = try JSONDecoder().decode(JSONRPCResponse<T>.self, from: data)
            if let result = response.result {
                return result
            } else if let error = response.error {
                throw NSError(domain: "", code: error.code, userInfo: [NSLocalizedDescriptionKey: error.message])
            } else {
                throw URLError(.cannotParseResponse)
            }
        } catch {
            throw error
        }
    }
}
