import Foundation

enum TestFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self {
        case .failed(let msg): return msg
        }
    }
}

final class TestSuite {
    private var passed = 0
    private var failed = 0

    func test(_ name: String, _ block: () throws -> Void) {
        do {
            try block()
            passed += 1
            print("  PASS: \(name)")
        } catch {
            failed += 1
            print("  FAIL: \(name) -> \(error)")
        }
    }

    func summaryAndExit() -> Never {
        print("\nResults: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Condition was false", file: StaticString = #file, line: UInt = #line) throws {
    if !condition() {
        throw TestFailure.failed("\(message) (\(file):\(line))")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ context: String = "", file: StaticString = #file, line: UInt = #line) throws {
    if actual != expected {
        throw TestFailure.failed("\(context) expected \(expected), got \(actual) (\(file):\(line))")
    }
}
