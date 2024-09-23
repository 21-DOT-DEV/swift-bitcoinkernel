import Foundation

public struct BitcoinNodeConfig {
    let url: URL
    let username: String?
    let password: String?
    
    public init(url: URL, username: String? = nil, password: String? = nil) {
        self.url = url
        self.username = username
        self.password = password
    }
    
    /// Convenience initializer for local node with default port
    public init(username: String? = nil, password: String? = nil) {
        self.init(url: URL(string: "http://127.0.0.1:8332")!, username: username, password: password)
    }
}