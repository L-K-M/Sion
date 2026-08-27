import Foundation

public struct ZIPEntry: Equatable, Sendable {
  public let path: String
  public let data: Data

  public init(path: String, data: Data) {
    self.path = path
    self.data = data
  }
}

public enum ZIPArchiveError: Error, Equatable {
  case archiveTooLarge
  case corruptArchive
  case duplicatePath(String)
  case encryptedEntry(String)
  case invalidPath(String)
  case localHeaderMismatch(String)
  case spannedArchive
  case tooManyEntries
  case unsupportedFlags(path: String, flags: UInt16)
  case unsupportedCompression(path: String, method: UInt16)
  case unsupportedZIP64
  case checksumMismatch(String)
}

/// Dependency-free ZIP driver. Sion writes stored entries so any standard
/// unzip tool can recover a document without application code.
public enum StoredZIPArchive {
  private static let localFileSignature: UInt32 = 0x0403_4B50
  private static let centralDirectorySignature: UInt32 = 0x0201_4B50
  private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50
  private static let utf8Flag: UInt16 = 0x0800
  private static let encryptionFlag: UInt16 = 0x0001
  private static let storedMethod: UInt16 = 0
  private static let zipVersion: UInt16 = 20
  private static let fixedDOSDate: UInt16 = 0x0021
  private static let maximumEntryCount = 4_096
  private static let maximumEntrySize = 256 * 1_024 * 1_024
  private static let maximumExpandedSize = 1_024 * 1_024 * 1_024

  public static func encode(_ entries: [ZIPEntry]) throws -> Data {
    guard entries.count <= maximumEntryCount else {
      throw ZIPArchiveError.tooManyEntries
    }

    var seen = Set<String>()
    var output = Data()
    var centralRecords: [CentralRecord] = []
    var expandedSize = 0

    for entry in entries {
      try validate(path: entry.path)
      guard seen.insert(entry.path).inserted else {
        throw ZIPArchiveError.duplicatePath(entry.path)
      }
      guard entry.data.count <= maximumEntrySize else {
        throw ZIPArchiveError.archiveTooLarge
      }
      guard entry.data.count <= maximumExpandedSize - expandedSize else {
        throw ZIPArchiveError.archiveTooLarge
      }
      expandedSize += entry.data.count

      let name = Data(entry.path.utf8)
      let checksum = CRC32.checksum(entry.data)
      let offset = try UInt32(exactly: output.count).orThrowArchiveTooLarge()
      let size = try UInt32(exactly: entry.data.count).orThrowArchiveTooLarge()
      let nameLength = try UInt16(exactly: name.count).orThrowArchiveTooLarge()

      output.appendLittleEndian(localFileSignature)
      output.appendLittleEndian(zipVersion)
      output.appendLittleEndian(utf8Flag)
      output.appendLittleEndian(storedMethod)
      output.appendLittleEndian(UInt16.zero)
      output.appendLittleEndian(fixedDOSDate)
      output.appendLittleEndian(checksum)
      output.appendLittleEndian(size)
      output.appendLittleEndian(size)
      output.appendLittleEndian(nameLength)
      output.appendLittleEndian(UInt16.zero)
      output.append(name)
      output.append(entry.data)

      centralRecords.append(
        CentralRecord(
          name: name,
          checksum: checksum,
          size: size,
          localHeaderOffset: offset
        )
      )
    }

    let centralOffset = try UInt32(exactly: output.count).orThrowArchiveTooLarge()
    for record in centralRecords {
      appendCentralRecord(record, to: &output)
    }
    let centralSize = try UInt32(exactly: output.count - Int(centralOffset))
      .orThrowArchiveTooLarge()
    let entryCount = try UInt16(exactly: centralRecords.count).orThrowArchiveTooLarge()

    output.appendLittleEndian(endOfCentralDirectorySignature)
    output.appendLittleEndian(UInt16.zero)
    output.appendLittleEndian(UInt16.zero)
    output.appendLittleEndian(entryCount)
    output.appendLittleEndian(entryCount)
    output.appendLittleEndian(centralSize)
    output.appendLittleEndian(centralOffset)
    output.appendLittleEndian(UInt16.zero)

    return output
  }

  public static func decode(_ archive: Data) throws -> [ZIPEntry] {
    try decode(archive, checksumPolicy: .requireMatch)
  }

  /// Higher layers verify SHA-256 by authority and may regenerate derived entries.
  static func decodeDeferringChecksums(_ archive: Data) throws -> [ZIPEntry] {
    try decode(archive, checksumPolicy: .deferToContainer)
  }

  private static func decode(
    _ archive: Data,
    checksumPolicy: ChecksumPolicy
  ) throws -> [ZIPEntry] {
    let endOffset = try locateEndRecord(in: archive)
    let diskNumber = try archive.readUInt16(at: endOffset + 4)
    let centralDiskNumber = try archive.readUInt16(at: endOffset + 6)
    let diskEntryCount = try archive.readUInt16(at: endOffset + 8)
    let totalEntryCount = try archive.readUInt16(at: endOffset + 10)
    guard diskNumber == 0,
      centralDiskNumber == 0,
      diskEntryCount == totalEntryCount
    else {
      throw ZIPArchiveError.spannedArchive
    }
    guard totalEntryCount != UInt16.max else {
      throw ZIPArchiveError.unsupportedZIP64
    }

    let entryCount = Int(totalEntryCount)
    guard entryCount <= maximumEntryCount else {
      throw ZIPArchiveError.tooManyEntries
    }

    let centralSizeValue = try archive.readUInt32(at: endOffset + 12)
    let centralOffsetValue = try archive.readUInt32(at: endOffset + 16)
    guard centralSizeValue != UInt32.max, centralOffsetValue != UInt32.max else {
      throw ZIPArchiveError.unsupportedZIP64
    }

    let centralSize = Int(centralSizeValue)
    let centralOffset = Int(centralOffsetValue)
    guard centralOffset >= 0,
      centralSize >= 0,
      centralOffset <= endOffset,
      centralSize == endOffset - centralOffset
    else {
      throw ZIPArchiveError.corruptArchive
    }

    var entries: [ZIPEntry] = []
    var seen = Set<String>()
    var expandedSize = 0
    var cursor = centralOffset
    var expectedLocalOffset = 0

    for _ in 0..<entryCount {
      _ = try archive.checkedRange(start: cursor, count: centralHeaderLength)
      guard try archive.readUInt32(at: cursor) == centralDirectorySignature else {
        throw ZIPArchiveError.corruptArchive
      }

      let flags = try archive.readUInt16(at: cursor + 8)
      let method = try archive.readUInt16(at: cursor + 10)
      let checksum = try archive.readUInt32(at: cursor + 16)
      let compressedSize = Int(try archive.readUInt32(at: cursor + 20))
      let expandedEntrySize = Int(try archive.readUInt32(at: cursor + 24))
      let nameLength = Int(try archive.readUInt16(at: cursor + 28))
      let extraLength = Int(try archive.readUInt16(at: cursor + 30))
      let commentLength = Int(try archive.readUInt16(at: cursor + 32))
      let startDisk = try archive.readUInt16(at: cursor + 34)
      let localHeaderOffset = Int(try archive.readUInt32(at: cursor + 42))
      let nameRange = try archive.checkedRange(start: cursor + 46, count: nameLength)
      let extraRange = try archive.checkedRange(
        start: nameRange.upperBound,
        count: extraLength
      )
      try rejectZIP64Extra(in: archive[extraRange])

      guard let path = String(data: archive[nameRange], encoding: .utf8) else {
        throw ZIPArchiveError.corruptArchive
      }
      try validate(path: path)
      guard seen.insert(path).inserted else {
        throw ZIPArchiveError.duplicatePath(path)
      }
      guard startDisk == 0 else {
        throw ZIPArchiveError.spannedArchive
      }
      guard flags & encryptionFlag == 0 else {
        throw ZIPArchiveError.encryptedEntry(path)
      }
      guard flags == utf8Flag else {
        throw ZIPArchiveError.unsupportedFlags(path: path, flags: flags)
      }
      guard method == storedMethod else {
        throw ZIPArchiveError.unsupportedCompression(path: path, method: method)
      }
      guard compressedSize != Int(UInt32.max),
        expandedEntrySize != Int(UInt32.max),
        localHeaderOffset != Int(UInt32.max)
      else {
        throw ZIPArchiveError.unsupportedZIP64
      }
      guard compressedSize == expandedEntrySize,
        expandedEntrySize <= maximumEntrySize
      else {
        throw ZIPArchiveError.archiveTooLarge
      }

      expandedSize += expandedEntrySize
      guard expandedSize <= maximumExpandedSize else {
        throw ZIPArchiveError.archiveTooLarge
      }

      guard localHeaderOffset == expectedLocalOffset else {
        throw ZIPArchiveError.corruptArchive
      }

      let local = try readLocalEntry(
        from: archive,
        offset: localHeaderOffset,
        centralOffset: centralOffset,
        expected: LocalEntryMetadata(
          path: path,
          name: Data(archive[nameRange]),
          flags: flags,
          method: method,
          checksum: checksum,
          compressedSize: compressedSize,
          expandedSize: expandedEntrySize
        )
      )
      let checksumMatches = CRC32.checksum(local.data) == checksum
      guard checksumMatches || checksumPolicy == .deferToContainer else {
        throw ZIPArchiveError.checksumMismatch(path)
      }

      entries.append(ZIPEntry(path: path, data: local.data))
      expectedLocalOffset = local.endOffset

      let recordLength = centralHeaderLength + nameLength + extraLength + commentLength
      let recordRange = try archive.checkedRange(start: cursor, count: recordLength)
      cursor = recordRange.upperBound
      guard cursor <= endOffset else {
        throw ZIPArchiveError.corruptArchive
      }
    }

    guard cursor == endOffset, expectedLocalOffset == centralOffset else {
      throw ZIPArchiveError.corruptArchive
    }

    return entries
  }

  private static func appendCentralRecord(_ record: CentralRecord, to output: inout Data) {
    output.appendLittleEndian(centralDirectorySignature)
    output.appendLittleEndian(zipVersion)
    output.appendLittleEndian(zipVersion)
    output.appendLittleEndian(utf8Flag)
    output.appendLittleEndian(storedMethod)
    output.appendLittleEndian(UInt16.zero)
    output.appendLittleEndian(fixedDOSDate)
    output.appendLittleEndian(record.checksum)
    output.appendLittleEndian(record.size)
    output.appendLittleEndian(record.size)
    output.appendLittleEndian(UInt16(record.name.count))
    output.appendLittleEndian(UInt16.zero)
    output.appendLittleEndian(UInt16.zero)
    output.appendLittleEndian(UInt16.zero)
    output.appendLittleEndian(UInt16.zero)
    output.appendLittleEndian(UInt32.zero)
    output.appendLittleEndian(record.localHeaderOffset)
    output.append(record.name)
  }

  private static func locateEndRecord(in archive: Data) throws -> Int {
    guard archive.count >= endRecordLength else {
      throw ZIPArchiveError.corruptArchive
    }

    let offset = archive.count - endRecordLength
    guard try archive.readUInt32(at: offset) == endOfCentralDirectorySignature,
      try archive.readUInt16(at: offset + 20) == 0
    else {
      throw ZIPArchiveError.corruptArchive
    }

    return offset
  }

  private static func readLocalEntry(
    from archive: Data,
    offset: Int,
    centralOffset: Int,
    expected: LocalEntryMetadata
  ) throws -> (data: Data, endOffset: Int) {
    _ = try archive.checkedRange(start: offset, count: localHeaderLength)
    guard try archive.readUInt32(at: offset) == localFileSignature else {
      throw ZIPArchiveError.corruptArchive
    }

    let flags = try archive.readUInt16(at: offset + 6)
    let method = try archive.readUInt16(at: offset + 8)
    let checksum = try archive.readUInt32(at: offset + 14)
    let compressedSize = Int(try archive.readUInt32(at: offset + 18))
    let expandedSize = Int(try archive.readUInt32(at: offset + 22))
    let nameLength = Int(try archive.readUInt16(at: offset + 26))
    let extraLength = Int(try archive.readUInt16(at: offset + 28))
    let nameRange = try archive.checkedRange(start: offset + localHeaderLength, count: nameLength)
    let extraRange = try archive.checkedRange(start: nameRange.upperBound, count: extraLength)
    try rejectZIP64Extra(in: archive[extraRange])
    let name = Data(archive[nameRange])

    guard flags == expected.flags,
      method == expected.method,
      checksum == expected.checksum,
      compressedSize == expected.compressedSize,
      expandedSize == expected.expandedSize,
      name == expected.name
    else {
      throw ZIPArchiveError.localHeaderMismatch(expected.path)
    }

    let dataStart = extraRange.upperBound
    guard dataStart <= centralOffset,
      expandedSize <= centralOffset - dataStart
    else {
      throw ZIPArchiveError.corruptArchive
    }

    let range = try archive.checkedRange(start: dataStart, count: expandedSize)
    return (Data(archive[range]), range.upperBound)
  }

  private static func validate(path: String) throws {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !path.isEmpty,
      !path.hasPrefix("/"),
      !path.contains(":"),
      !path.contains("\\"),
      !path.contains("\0"),
      !parts.contains(".."),
      !parts.contains("."),
      !parts.contains("")
    else {
      throw ZIPArchiveError.invalidPath(path)
    }
  }

  private static func rejectZIP64Extra(in bytes: Data.SubSequence) throws {
    var cursor = bytes.startIndex
    while cursor < bytes.endIndex {
      guard bytes.distance(from: cursor, to: bytes.endIndex) >= extraFieldHeaderLength else {
        throw ZIPArchiveError.corruptArchive
      }

      let identifier = UInt16(bytes[cursor]) | UInt16(bytes[cursor + 1]) << 8
      let size = Int(UInt16(bytes[cursor + 2]) | UInt16(bytes[cursor + 3]) << 8)
      cursor += extraFieldHeaderLength
      guard bytes.distance(from: cursor, to: bytes.endIndex) >= size else {
        throw ZIPArchiveError.corruptArchive
      }
      guard identifier != zip64ExtraIdentifier else {
        throw ZIPArchiveError.unsupportedZIP64
      }

      cursor += size
    }
  }

  private static let localHeaderLength = 30
  private static let centralHeaderLength = 46
  private static let endRecordLength = 22
  private static let extraFieldHeaderLength = 4
  private static let zip64ExtraIdentifier: UInt16 = 0x0001
}

private enum ChecksumPolicy {
  case requireMatch
  case deferToContainer
}

private struct CentralRecord {
  let name: Data
  let checksum: UInt32
  let size: UInt32
  let localHeaderOffset: UInt32
}

private struct LocalEntryMetadata {
  let path: String
  let name: Data
  let flags: UInt16
  let method: UInt16
  let checksum: UInt32
  let compressedSize: Int
  let expandedSize: Int
}

private enum CRC32 {
  private static let polynomial: UInt32 = 0xEDB8_8320
  private static let table: [UInt32] = (0..<256).map { value in
    var checksum = UInt32(value)
    for _ in 0..<8 {
      checksum =
        checksum & 1 == 1
        ? polynomial ^ (checksum >> 1)
        : checksum >> 1
    }
    return checksum
  }

  static func checksum(_ data: Data) -> UInt32 {
    var checksum = UInt32.max
    for byte in data {
      let index = Int((checksum ^ UInt32(byte)) & 0xFF)
      checksum = table[index] ^ (checksum >> 8)
    }
    return checksum ^ UInt32.max
  }
}

extension Data {
  fileprivate mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { bytes in
      append(contentsOf: bytes)
    }
  }

  fileprivate func readUInt16(at offset: Int) throws -> UInt16 {
    let range = try checkedRange(start: offset, count: 2)
    return UInt16(self[range.lowerBound])
      | UInt16(self[range.lowerBound + 1]) << 8
  }

  fileprivate func readUInt32(at offset: Int) throws -> UInt32 {
    let range = try checkedRange(start: offset, count: 4)
    return UInt32(self[range.lowerBound])
      | UInt32(self[range.lowerBound + 1]) << 8
      | UInt32(self[range.lowerBound + 2]) << 16
      | UInt32(self[range.lowerBound + 3]) << 24
  }

  fileprivate func checkedRange(start: Int, count: Int) throws -> Range<Int> {
    guard start >= 0, count >= 0, start <= self.count - count else {
      throw ZIPArchiveError.corruptArchive
    }
    return start..<start + count
  }
}

extension Optional where Wrapped: FixedWidthInteger {
  fileprivate func orThrowArchiveTooLarge() throws -> Wrapped {
    guard let value = self else {
      throw ZIPArchiveError.archiveTooLarge
    }
    return value
  }
}
