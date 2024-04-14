import XCTest
import Bitcoin
import CxxStdlib
//import BitcoinWrapper

final class BitcoinTests: XCTestCase {
    func testExample() throws {
        // XCTest Documentation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods



        // Beyond this point, `cStringPointers` and `argv` are not valid, and Swift's ARC will clean up the memory.
    }
}


final class TestBitcionWrapper {
    func appInit() -> Int {

//        var exitStatus: Int

    }
//    int test_app_init(int argc, char* argv[]) {
//        node::NodeContext node;
//        int exit_status;
//        std::unique_ptr<interfaces::Init> init = interfaces::MakeNodeInit(node, argc, argv, exit_status);
//        if (!init) {
//            return exit_status;
//        }
//
//        SetupEnvironment();
//
//        // Connect bitcoind signal handlers
//        noui_connect();
//
//        util::ThreadSetInternalName("init");
//
//        // Interpret command line arguments
//        ArgsManager& args = *Assert(node.args);
//        if (!ParseArgs(args, argc, argv)) return EXIT_FAILURE;
//        // Process early info return commands such as -help or -version
//        if (ProcessInitCommands(args)) return EXIT_SUCCESS;
//
//        // Start application
//        if (AppInit(node)) {
//            WaitForShutdown();
//        } else {
//            node.exit_status = EXIT_FAILURE;
//        }
//        Interrupt(node);
//        Shutdown(node);
//
//        return node.exit_status;
//    }
}
