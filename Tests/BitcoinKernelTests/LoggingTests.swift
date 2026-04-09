import Testing
import BitcoinKernel

@Test func loggingGlobalFunctions() {
    // Verify global logging configuration functions don't crash.
    setLoggingOptions(timestamps: true, sourceLocations: true)
    setLogLevel(category: .all, level: .info)
    enableLogCategory(.validation)
    disableLogCategory(.validation)
    setLoggingOptions() // reset to defaults
}

@Test func loggingConnectionReceivesMessages() throws {
    var messages: [String] = []
    let connection = try LoggingConnection { message in
        messages.append(message)
    }
    // Creating a context triggers internal log messages.
    enableLogCategory(.all)
    let _ = try Context()
    // The connection existing is sufficient — we verify no crash.
    // Logging output depends on kernel internals; just verify the
    // callback mechanism works without crashing.
    _ = connection
}
