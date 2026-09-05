#if !canImport(ObjectiveC)
  import XCTest

  /// swift-corelibs-xctest discovers test methods as plain function values and
  /// force-casts a `@MainActor` method to a nonisolated one at load time, which
  /// the runtime rejects. Offering exact overloads keeps the cast out; the
  /// runner already executes every test on the main thread, so hopping onto the
  /// main actor is a check rather than a dispatch.
  func testCase<T: XCTestCase>(
    _ allTests: [(String, (T) -> @MainActor () throws -> Void)]
  ) -> XCTestCaseEntry {
    let hoisted: [(String, (T) -> () throws -> Void)] = allTests.map { name, method in
      (
        name,
        { instance in
          {
            try MainActor.assumeIsolated {
              try method(instance)()
            }
          }
        }
      )
    }
    return testCase(hoisted)
  }

  func testCase<T: XCTestCase>(
    _ allTests: [(String, (T) -> @MainActor () -> Void)]
  ) -> XCTestCaseEntry {
    let hoisted: [(String, (T) -> () throws -> Void)] = allTests.map { name, method in
      (
        name,
        { instance in
          {
            MainActor.assumeIsolated {
              method(instance)()
            }
          }
        }
      )
    }
    return testCase(hoisted)
  }

  func testCase<T: XCTestCase>(
    _ allTests: [(String, (T) -> @MainActor () async throws -> Void)]
  ) -> XCTestCaseEntry {
    let hoisted: [(String, (T) -> () async throws -> Void)] = allTests.map { name, method in
      (
        name,
        { instance in
          {
            try await method(instance)()
          }
        }
      )
    }
    return testCase(hoisted)
  }

  func testCase<T: XCTestCase>(
    _ allTests: [(String, (T) -> @MainActor () async -> Void)]
  ) -> XCTestCaseEntry {
    let hoisted: [(String, (T) -> () async throws -> Void)] = allTests.map { name, method in
      (
        name,
        { instance in
          {
            await method(instance)()
          }
        }
      )
    }
    return testCase(hoisted)
  }
#endif
