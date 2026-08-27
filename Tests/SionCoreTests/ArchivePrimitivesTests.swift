import Foundation
import XCTest

@testable import SionCore

final class ArchivePrimitivesTests: XCTestCase {
  func testSHA256MatchesKnownVector() {
    let digest = SHA256.hexDigest(Data("abc".utf8))

    XCTAssertEqual(
      digest,
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
  }

  func testStoredZIPRoundTripsDeterministically() throws {
    let entries = [
      ZIPEntry(path: "mimetype", data: Data("application/vnd.lkmc.sion+zip".utf8)),
      ZIPEntry(path: "scene.json", data: Data("{}\n".utf8)),
    ]

    let first = try StoredZIPArchive.encode(entries)
    let second = try StoredZIPArchive.encode(entries)

    XCTAssertEqual(first, second)
    XCTAssertEqual(try StoredZIPArchive.decode(first), entries)
  }

  func testStoredZIPRejectsUnsafeAndDuplicatePaths() {
    XCTAssertThrowsError(
      try StoredZIPArchive.encode([ZIPEntry(path: "../scene.json", data: Data())])
    ) { error in
      XCTAssertEqual(error as? ZIPArchiveError, .invalidPath("../scene.json"))
    }

    XCTAssertThrowsError(
      try StoredZIPArchive.encode([ZIPEntry(path: "C:/scene.json", data: Data())])
    ) { error in
      XCTAssertEqual(error as? ZIPArchiveError, .invalidPath("C:/scene.json"))
    }

    XCTAssertThrowsError(
      try StoredZIPArchive.encode([
        ZIPEntry(path: "scene.json", data: Data()),
        ZIPEntry(path: "scene.json", data: Data()),
      ])
    ) { error in
      XCTAssertEqual(error as? ZIPArchiveError, .duplicatePath("scene.json"))
    }
  }

  func testStoredZIPDetectsChangedEntryBytes() throws {
    let entry = ZIPEntry(path: "scene.json", data: Data("document".utf8))
    var archive = try StoredZIPArchive.encode([entry])
    let payloadOffset = 30 + Data(entry.path.utf8).count
    archive[payloadOffset] ^= 0x01

    XCTAssertThrowsError(try StoredZIPArchive.decode(archive)) { error in
      XCTAssertEqual(error as? ZIPArchiveError, .checksumMismatch("scene.json"))
    }
  }

  func testStoredZIPRejectsTrailingDataAndSpanning() throws {
    let entry = ZIPEntry(path: "scene.json", data: Data("document".utf8))
    let archive = try StoredZIPArchive.encode([entry])

    var trailing = archive
    trailing.append(0)
    XCTAssertThrowsError(try StoredZIPArchive.decode(trailing)) { error in
      XCTAssertEqual(error as? ZIPArchiveError, .corruptArchive)
    }

    var spanned = archive
    let endOffset = spanned.count - ZIPLayout.endRecordLength
    writeUInt16(1, to: &spanned, at: endOffset + ZIPLayout.endDiskOffset)
    XCTAssertThrowsError(try StoredZIPArchive.decode(spanned)) { error in
      XCTAssertEqual(error as? ZIPArchiveError, .spannedArchive)
    }
  }

  func testStoredZIPRejectsUnsupportedFlags() throws {
    let path = "scene.json"
    var archive = try StoredZIPArchive.encode([
      ZIPEntry(path: path, data: Data("document".utf8))
    ])
    let centralOffset = try centralDirectoryOffset(in: archive)
    let unsupportedFlags = ZIPLayout.utf8Flag | ZIPLayout.dataDescriptorFlag
    writeUInt16(
      unsupportedFlags,
      to: &archive,
      at: centralOffset + ZIPLayout.centralFlagsOffset
    )

    XCTAssertThrowsError(try StoredZIPArchive.decode(archive)) { error in
      XCTAssertEqual(
        error as? ZIPArchiveError,
        .unsupportedFlags(path: path, flags: unsupportedFlags)
      )
    }
  }

  func testStoredZIPRejectsLocalMetadataAndNameMismatch() throws {
    let path = "scene.json"
    let original = try StoredZIPArchive.encode([
      ZIPEntry(path: path, data: Data("document".utf8))
    ])

    var metadataMismatch = original
    writeUInt16(
      ZIPLayout.deflateMethod,
      to: &metadataMismatch,
      at: ZIPLayout.localMethodOffset
    )
    XCTAssertThrowsError(try StoredZIPArchive.decode(metadataMismatch)) { error in
      XCTAssertEqual(error as? ZIPArchiveError, .localHeaderMismatch(path))
    }

    var nameMismatch = original
    nameMismatch[ZIPLayout.localHeaderLength] = UInt8(ascii: "x")
    XCTAssertThrowsError(try StoredZIPArchive.decode(nameMismatch)) { error in
      XCTAssertEqual(error as? ZIPArchiveError, .localHeaderMismatch(path))
    }
  }

  func testStoredZIPRejectsLocalDataCrossingCentralDirectory() throws {
    let path = "scene.json"
    var archive = try StoredZIPArchive.encode([
      ZIPEntry(path: path, data: Data("document".utf8))
    ])
    let centralOffset = try centralDirectoryOffset(in: archive)
    let crossingSize = UInt32(centralOffset - ZIPLayout.localHeaderLength - path.utf8.count + 1)

    writeUInt32(crossingSize, to: &archive, at: ZIPLayout.localCompressedSizeOffset)
    writeUInt32(crossingSize, to: &archive, at: ZIPLayout.localExpandedSizeOffset)
    writeUInt32(
      crossingSize,
      to: &archive,
      at: centralOffset + ZIPLayout.centralCompressedSizeOffset
    )
    writeUInt32(
      crossingSize,
      to: &archive,
      at: centralOffset + ZIPLayout.centralExpandedSizeOffset
    )

    XCTAssertThrowsError(try StoredZIPArchive.decode(archive)) { error in
      XCTAssertEqual(error as? ZIPArchiveError, .corruptArchive)
    }
  }

  func testStoredZIPRejectsCentralDirectorySizeMismatch() throws {
    var archive = try StoredZIPArchive.encode([
      ZIPEntry(path: "scene.json", data: Data("document".utf8))
    ])
    let endOffset = archive.count - ZIPLayout.endRecordLength
    let centralSize = readUInt32(from: archive, at: endOffset + ZIPLayout.endCentralSizeOffset)
    writeUInt32(
      centralSize - 1,
      to: &archive,
      at: endOffset + ZIPLayout.endCentralSizeOffset
    )

    XCTAssertThrowsError(try StoredZIPArchive.decode(archive)) { error in
      XCTAssertEqual(error as? ZIPArchiveError, .corruptArchive)
    }
  }

  private func centralDirectoryOffset(in archive: Data) throws -> Int {
    let endOffset = archive.count - ZIPLayout.endRecordLength
    return Int(readUInt32(from: archive, at: endOffset + ZIPLayout.endCentralOffsetOffset))
  }

  private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset])
      | UInt32(data[offset + 1]) << 8
      | UInt32(data[offset + 2]) << 16
      | UInt32(data[offset + 3]) << 24
  }

  private func writeUInt16(_ value: UInt16, to data: inout Data, at offset: Int) {
    data[offset] = UInt8(truncatingIfNeeded: value)
    data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
  }

  private func writeUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
    data[offset] = UInt8(truncatingIfNeeded: value)
    data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    data[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
    data[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
  }
}

private enum ZIPLayout {
  static let localHeaderLength = 30
  static let localMethodOffset = 8
  static let localCompressedSizeOffset = 18
  static let localExpandedSizeOffset = 22
  static let centralFlagsOffset = 8
  static let centralCompressedSizeOffset = 20
  static let centralExpandedSizeOffset = 24
  static let endRecordLength = 22
  static let endDiskOffset = 4
  static let endCentralSizeOffset = 12
  static let endCentralOffsetOffset = 16
  static let utf8Flag: UInt16 = 0x0800
  static let dataDescriptorFlag: UInt16 = 0x0008
  static let deflateMethod: UInt16 = 8
}
