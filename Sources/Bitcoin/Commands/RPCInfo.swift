import Foundation

public struct RPCInfo: Codable {
    public struct ActiveCommand: Codable {
        public let method: String
        public let duration: Int
    }
    
    public let active_commands: [ActiveCommand]
    public let logpath: String
    
    public init(active_commands: [ActiveCommand], logpath: String) {
        self.active_commands = active_commands
        self.logpath = logpath
    }
}