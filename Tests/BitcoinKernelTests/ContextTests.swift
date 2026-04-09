import Testing
import BitcoinKernel

@Test func contextCreateWithDefaults() throws {
    // Default context (mainnet, no callbacks) — verifies create + destroy lifecycle.
    let context = try Context()
    #expect(context.interrupt())
}

@Test func contextWithChainParams() throws {
    let params = ChainParameters(.regtest)
    let options = ContextOptions()
    options.setChainParams(params)
    let context = try Context(options: options)
    #expect(context.interrupt())
    // All objects auto-destroyed by ARC when scope ends.
}

@Test func contextAllChainTypes() throws {
    for chainType in [ChainType.mainnet, .testnet, .testnet4, .signet, .regtest] {
        let params = ChainParameters(chainType)
        let options = ContextOptions()
        options.setChainParams(params)
        let context = try Context(options: options)
        #expect(context.interrupt())
    }
}

@Test func chainParametersLifecycle() {
    // Verifies create + destroy via ARC — no crash = success.
    let _ = ChainParameters(.mainnet)
    let _ = ChainParameters(.regtest)
}

@Test func contextOptionsLifecycle() {
    // Verifies create + destroy via ARC — no crash = success.
    let _ = ContextOptions()
}

// MARK: - Notification Callbacks

@Test func contextWithNotificationCallbacks() throws {
    let notifications = NotificationCallbacks(
        fatalError: { message in
            // Would be called on unrecoverable error — just verify wiring.
            _ = message
        }
    )
    let options = ContextOptions()
    options.setNotifications(notifications)
    let context = try Context(options: options)
    #expect(context.interrupt())
}

@Test func contextWithAllNotificationCallbacks() throws {
    let notifications = NotificationCallbacks(
        blockTip: { state, entry, progress in
            _ = (state, entry, progress)
        },
        headerTip: { state, height, timestamp, presync in
            _ = (state, height, timestamp, presync)
        },
        progress: { title, percent, resumePossible in
            _ = (title, percent, resumePossible)
        },
        warningSet: { warning, message in
            _ = (warning, message)
        },
        warningUnset: { warning in
            _ = warning
        },
        flushError: { message in
            _ = message
        },
        fatalError: { message in
            _ = message
        }
    )
    let options = ContextOptions()
    options.setNotifications(notifications)
    let context = try Context(options: options)
    #expect(context.interrupt())
}

@Test func contextWithValidationInterfaceCallbacks() throws {
    let validation = ValidationInterfaceCallbacks(
        blockChecked: { block, state in
            _ = (block, state)
        },
        blockConnected: { block, entry in
            _ = (block, entry)
        }
    )
    let options = ContextOptions()
    options.setValidationInterface(validation)
    let context = try Context(options: options)
    #expect(context.interrupt())
}

@Test func contextWithBothCallbackTypes() throws {
    let notifications = NotificationCallbacks(fatalError: { _ in })
    let validation = ValidationInterfaceCallbacks(blockChecked: { _, _ in })

    let params = ChainParameters(.regtest)
    let options = ContextOptions()
    options.setChainParams(params)
    options.setNotifications(notifications)
    options.setValidationInterface(validation)
    let context = try Context(options: options)
    #expect(context.interrupt())
}

@Test func contextOptionsSetChainParamsDoesNotRetain() throws {
    // The C API copies params internally, so the Swift ChainParameters
    // object can be deallocated before the context is created.
    let options = ContextOptions()
    do {
        let params = ChainParameters(.regtest)
        options.setChainParams(params)
        // params deallocated here
    }
    let context = try Context(options: options)
    #expect(context.interrupt())
}
