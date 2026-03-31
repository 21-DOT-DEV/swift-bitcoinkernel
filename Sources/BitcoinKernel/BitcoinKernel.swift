import libbitcoinkernel

public enum BitcoinKernel {
    public static func createContextOptions() -> OpaquePointer? {
        btck_context_options_create()
    }

    public static func destroyContextOptions(_ options: OpaquePointer) {
        btck_context_options_destroy(options)
    }
}
