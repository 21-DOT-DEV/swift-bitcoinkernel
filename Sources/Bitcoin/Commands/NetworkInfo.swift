import Foundation

public struct NetworkInfo: Codable {
    public struct Network: Codable {
        public let name: String
        public let limited: Bool
        public let reachable: Bool
        public let proxy: String
        public let proxyRandomizeCredentials: Bool
        
        enum CodingKeys: String, CodingKey {
            case name, limited, reachable, proxy
            case proxyRandomizeCredentials = "proxy_randomize_credentials"
        }
    }
    
    public struct LocalAddress: Codable {
        public let address: String
        public let port: Int
        public let score: Int
    }
    
    public let version: Int
    public let subversion: String
    public let protocolversion: Int
    public let localservices: String
    public let localservicesnames: [String]
    public let localrelay: Bool
    public let timeoffset: Int
    public let connections: Int
    public let connectionsIn: Int
    public let connectionsOut: Int
    public let networkactive: Bool
    public let networks: [Network]
    public let relayfee: Double
    public let incrementalfee: Double
    public let localaddresses: [LocalAddress]
    public let warnings: String
    
    enum CodingKeys: String, CodingKey {
        case version, subversion, protocolversion, localservices, localservicesnames, localrelay, timeoffset, connections, networkactive, networks, relayfee, incrementalfee, localaddresses, warnings
        case connectionsIn = "connections_in"
        case connectionsOut = "connections_out"
    }
}