import Foundation

/// Lightweight test harness that works without XCTest/Xcode.
class TestHarness {
    var passed = 0
    var failed = 0
    var errors: [(test: String, message: String)] = []
    private var currentTest = ""

    func run(_ name: String, _ body: () throws -> Void) {
        currentTest = name
        do {
            try body()
            passed += 1
        } catch {
            failed += 1
            errors.append((name, "\(error)"))
        }
    }

    func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
        guard a == b else {
            let msg = message.isEmpty ? "Expected \(a) == \(b)" : message
            failed += 1
            passed -= 1  // will be incremented by run() on return, so pre-decrement
            errors.append((currentTest, "\(msg) (line \(line))"))
            // Don't throw — continue running remaining assertions in this test
            return
        }
    }

    func assertTrue(_ value: Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
        guard value else {
            let msg = message.isEmpty ? "Expected true, got false" : message
            failed += 1
            passed -= 1
            errors.append((currentTest, "\(msg) (line \(line))"))
            return
        }
    }

    func assertFalse(_ value: Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
        try assertTrue(!value, message.isEmpty ? "Expected false, got true" : message, file: file, line: line)
    }

    func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) throws {
        guard value != nil else {
            let msg = message.isEmpty ? "Expected non-nil" : message
            failed += 1
            passed -= 1
            errors.append((currentTest, "\(msg) (line \(line))"))
            return
        }
    }

    func assertNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) throws {
        guard value == nil else {
            let msg = message.isEmpty ? "Expected nil, got \(value!)" : message
            failed += 1
            passed -= 1
            errors.append((currentTest, "\(msg) (line \(line))"))
            return
        }
    }

    func printResults() {
        let total = passed + failed
        print("\n--- Test Results ---")
        print("\(total) tests: \(passed) passed, \(failed) failed")

        if !errors.isEmpty {
            print("\nFailures:")
            for (test, message) in errors {
                print("  FAIL \(test): \(message)")
            }
        }

        if failed == 0 {
            print("\nAll tests passed.")
        }
    }
}
