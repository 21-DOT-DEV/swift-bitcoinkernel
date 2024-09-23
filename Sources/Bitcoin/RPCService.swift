import Foundation

public struct RPCService {
    private let config: BitcoinNodeConfig
    private let urlSession: URLSession
    
    public init(config: BitcoinNodeConfig) {
        self.config = config
        self.urlSession = URLSession(configuration: .default)
    }
    
    public func send<T: Codable>(request: JSONRPCRequest) async throws -> T {
        var urlRequest = URLRequest(url: config.url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let username = config.username, let password = config.password {
            let loginString = "\(username):\(password)"
            let loginData = loginString.data(using: .utf8)!
            let base64LoginString = loginData.base64EncodedString()
            urlRequest.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        }
        
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await urlSession.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BitcoinError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw BitcoinError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        let jsonRPCResponse = try decoder.decode(JSONRPCResponse<T>.self, from: data)
        
        if let error = jsonRPCResponse.error {
            throw BitcoinError.rpcError(code: error.code, message: error.message)
        }
        
        guard let result = jsonRPCResponse.result else {
            throw BitcoinError.missingResult
        }
        
        return result
    }
}

public struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let method: String
    let params: [AnyCodable]
    let id: Int
}

public struct JSONRPCResponse<T: Codable>: Codable {
    let result: T?
    let error: JSONRPCError?
    let id: Int
}

public struct JSONRPCError: Codable {
    let code: Int
    let message: String
}

public enum BitcoinError: Error {
    case invalidResponse
    case httpError(statusCode: Int)
    case rpcError(code: Int, message: String)
    case missingResult
}