import Foundation
import XCTest

@testable import SionCore

final class ArchiveMutationTests: XCTestCase {
  func testEveryTruncatedArchivePrefixIsRejected() throws {
    let archive = try encodedArchive()
    XCTAssertNoThrow(try SionArchive.decode(archive).validate())

    for byteCount in 0..<archive.count {
      XCTAssertThrowsError(
        try SionArchive.decode(Data(archive.prefix(byteCount))),
        "Accepted truncated prefix ending at byte \(byteCount)"
      )
    }
  }

  func testFixedSeedSingleByteMutationsAreDeterministic() throws {
    let archive = try encodedArchive()
    var acceptedCount = 0
    var rejectedCount = 0
    var seenMutations = Set<Data>()

    for seed in MutationCorpus.seeds {
      let mutated = mutateOneByte(in: archive, seed: seed)
      guard seenMutations.insert(mutated).inserted else {
        XCTFail("Duplicate archive mutation for seed \(seed)")
        continue
      }

      let first = decodeOutcome(mutated)
      let second = decodeOutcome(mutated)

      XCTAssertEqual(first, second, "Nondeterministic decode for seed \(seed)")
      switch first {
      case .validPackage:
        acceptedCount += 1
      case .invalidPackage(let error):
        XCTFail("Seed \(seed) decoded an invalid package: \(error)")
      case .rejected:
        rejectedCount += 1
      }
    }

    // The archive intentionally recovers from corrupt derived entries.
    XCTAssertGreaterThan(
      acceptedCount,
      0,
      "Expected recovery from at least one corrupt derived entry"
    )
    XCTAssertGreaterThan(
      rejectedCount,
      0,
      "Expected rejection of at least one unrecoverable mutation"
    )
  }

  func testErrorIdentityDistinguishesArchiveFailures() {
    XCTAssertNotEqual(
      errorIdentity(SionArchiveError.invalidMimetype),
      errorIdentity(SionArchiveError.sceneDescriptorMismatch)
    )
  }

  private func encodedArchive() throws -> Data {
    try SionArchive.encode(
      package: SionPackage(),
      intent: .manual,
      at: MutationCorpus.date,
      generator: testArchiveGenerator
    ).data
  }

  private func mutateOneByte(in archive: Data, seed: UInt64) -> Data {
    var generator = FixedGenerator(seed: seed)
    let index = Int(generator.next() % UInt64(archive.count))
    let mask = UInt8(truncatingIfNeeded: generator.next()) | 1
    var mutated = archive
    mutated[index] ^= mask

    return mutated
  }

  private func decodeOutcome(_ data: Data) -> DecodeOutcome {
    do {
      let package = try SionArchive.decode(data)

      do {
        try package.validate()
        return .validPackage
      } catch {
        return .invalidPackage(errorIdentity(error))
      }
    } catch {
      return .rejected(errorIdentity(error))
    }
  }

  private func errorIdentity(_ error: Error) -> ErrorIdentity {
    if let error = error as? ZIPArchiveError {
      return .zip(error)
    }
    if let error = error as? SionArchiveError {
      return .archive(error)
    }
    if let error = error as? CanonicalJSONError {
      return .canonicalJSON(error)
    }
    if let error = error as? SionPackageError {
      return .package(error)
    }
    if let error = error as? SceneValidationError {
      return .sceneValidation(error)
    }

    guard let decodingError = error as? DecodingError else {
      let bridged = error as NSError
      return .bridged(domain: bridged.domain, code: bridged.code)
    }

    // Foundation error dictionaries have no stable print order across platforms.
    switch decodingError {
    case .dataCorrupted(let context):
      return .decoding(.dataCorrupted, path: codingPath(context))
    case .keyNotFound(let key, let context):
      return .decoding(.keyNotFound(key.stringValue), path: codingPath(context))
    case .typeMismatch(let type, let context):
      return .decoding(.typeMismatch(String(reflecting: type)), path: codingPath(context))
    case .valueNotFound(let type, let context):
      return .decoding(.valueNotFound(String(reflecting: type)), path: codingPath(context))
    @unknown default:
      return .unknownDecoding(String(reflecting: type(of: error)))
    }
  }

  private func codingPath(_ context: DecodingError.Context) -> [String] {
    context.codingPath.map(\.stringValue)
  }
}

private enum DecodeOutcome: Equatable {
  case validPackage
  case invalidPackage(ErrorIdentity)
  case rejected(ErrorIdentity)
}

private enum ErrorIdentity: Equatable {
  case archive(SionArchiveError)
  case bridged(domain: String, code: Int)
  case canonicalJSON(CanonicalJSONError)
  case decoding(DecodingFailure, path: [String])
  case package(SionPackageError)
  case sceneValidation(SceneValidationError)
  case unknownDecoding(String)
  case zip(ZIPArchiveError)
}

private enum DecodingFailure: Equatable {
  case dataCorrupted
  case keyNotFound(String)
  case typeMismatch(String)
  case valueNotFound(String)
}

private enum MutationCorpus {
  private static let baseSeed: UInt64 = 0x5A10_2026_0000_0000
  private static let mutationCount = 256

  static let date = Date(timeIntervalSince1970: 1_787_830_522)
  static let seeds = (0..<mutationCount).map { baseSeed | UInt64($0) }
}

private struct FixedGenerator {
  private static let multiplier: UInt64 = 6_364_136_223_846_793_005
  private static let increment: UInt64 = 1_442_695_040_888_963_407

  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    // This fixed LCG keeps mutation cases stable across Swift versions.
    state = state &* Self.multiplier &+ Self.increment
    return state
  }
}
