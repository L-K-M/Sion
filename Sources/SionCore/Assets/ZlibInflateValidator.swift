import Foundation

/// Validates a bounded zlib stream without exposing decompressed bytes.
enum ZlibInflateValidator {
  static func validates(
    _ data: Data,
    outputByteCount: Int,
    byteValidator: @escaping (Int, UInt8) -> Bool
  ) -> Bool {
    guard data.count >= ZlibLayout.minimumByteCount,
      outputByteCount >= 0,
      validHeader(data)
    else {
      return false
    }

    let checksumOffset = data.count - ZlibLayout.checksumByteCount
    var reader = DeflateBitReader(
      data: data,
      start: ZlibLayout.headerByteCount,
      end: checksumOffset
    )
    var output = InflateOutput(limit: outputByteCount, byteValidator: byteValidator)
    var isFinalBlock = false

    repeat {
      guard let finalFlag = reader.readBits(1),
        let blockType = reader.readBits(2)
      else {
        return false
      }

      isFinalBlock = finalFlag == 1
      switch blockType {
      case DeflateBlockType.uncompressed:
        guard inflateUncompressed(reader: &reader, output: &output) else { return false }
      case DeflateBlockType.fixedHuffman:
        guard
          inflateCompressed(
            reader: &reader,
            output: &output,
            literalTree: fixedLiteralTree,
            distanceTree: fixedDistanceTree
          )
        else {
          return false
        }
      case DeflateBlockType.dynamicHuffman:
        guard let trees = dynamicTrees(reader: &reader),
          inflateCompressed(
            reader: &reader,
            output: &output,
            literalTree: trees.literal,
            distanceTree: trees.distance
          )
        else {
          return false
        }
      default:
        return false
      }
    } while !isFinalBlock

    reader.alignToByteBoundary()
    guard reader.isAtEnd,
      output.count == outputByteCount,
      output.adler32 == uint32(data, at: checksumOffset)
    else {
      return false
    }

    return true
  }

  private static func validHeader(_ data: Data) -> Bool {
    let compression = data[data.startIndex]
    let flags = data[data.startIndex + 1]
    let header = (Int(compression) << 8) | Int(flags)

    return compression & ZlibLayout.compressionMethodMask == ZlibLayout.deflateMethod
      && compression >> ZlibLayout.windowSizeShift <= ZlibLayout.maximumWindowSize
      && flags & ZlibLayout.presetDictionaryFlag == 0
      && header.isMultiple(of: ZlibLayout.headerCheckDivisor)
  }

  private static func inflateUncompressed(
    reader: inout DeflateBitReader,
    output: inout InflateOutput
  ) -> Bool {
    reader.alignToByteBoundary()
    guard let length = reader.readLittleEndianUInt16(),
      let complement = reader.readLittleEndianUInt16(),
      length ^ complement == UInt16.max
    else {
      return false
    }

    for _ in 0..<Int(length) {
      guard let byte = reader.readAlignedByte(), output.emit(byte) else { return false }
    }

    return true
  }

  private static func inflateCompressed(
    reader: inout DeflateBitReader,
    output: inout InflateOutput,
    literalTree: HuffmanTree,
    distanceTree: HuffmanTree?
  ) -> Bool {
    while let symbol = literalTree.decode(from: &reader) {
      if symbol < DeflateSymbol.endOfBlock {
        guard output.emit(UInt8(symbol)) else { return false }
        continue
      }

      if symbol == DeflateSymbol.endOfBlock {
        return true
      }

      let lengthIndex = symbol - DeflateSymbol.firstLength
      guard lengthBases.indices.contains(lengthIndex),
        let length = decodedValue(
          base: lengthBases[lengthIndex],
          extraBits: lengthExtraBits[lengthIndex],
          reader: &reader
        ),
        let distanceTree,
        let distanceSymbol = distanceTree.decode(from: &reader),
        distanceBases.indices.contains(distanceSymbol),
        let distance = decodedValue(
          base: distanceBases[distanceSymbol],
          extraBits: distanceExtraBits[distanceSymbol],
          reader: &reader
        ),
        output.copy(distance: distance, length: length)
      else {
        return false
      }
    }

    return false
  }

  private static func decodedValue(
    base: Int,
    extraBits: Int,
    reader: inout DeflateBitReader
  ) -> Int? {
    guard extraBits > 0 else { return base }
    guard let extra = reader.readBits(extraBits) else { return nil }

    return base + extra
  }

  private static func dynamicTrees(
    reader: inout DeflateBitReader
  ) -> (literal: HuffmanTree, distance: HuffmanTree?)? {
    guard let literalCountBits = reader.readBits(5),
      let distanceCountBits = reader.readBits(5),
      let codeLengthCountBits = reader.readBits(4)
    else {
      return nil
    }

    let literalCount = literalCountBits + DeflateLayout.minimumLiteralCodeCount
    let distanceCount = distanceCountBits + DeflateLayout.minimumDistanceCodeCount
    let codeLengthCount = codeLengthCountBits + DeflateLayout.minimumCodeLengthCodeCount
    var codeLengthLengths = [Int](repeating: 0, count: DeflateLayout.codeLengthAlphabetCount)

    for index in 0..<codeLengthCount {
      guard let length = reader.readBits(3) else { return nil }

      codeLengthLengths[codeLengthOrder[index]] = length
    }

    guard let codeLengthTree = HuffmanTree(codeLengths: codeLengthLengths) else { return nil }

    let totalCount = literalCount + distanceCount
    var lengths: [Int] = []
    lengths.reserveCapacity(totalCount)

    while lengths.count < totalCount {
      guard let symbol = codeLengthTree.decode(from: &reader) else { return nil }

      switch symbol {
      case 0...15:
        lengths.append(symbol)
      case DeflateSymbol.repeatPreviousLength:
        guard let previous = lengths.last,
          let extra = reader.readBits(2),
          appendRepeated(previous, count: extra + 3, totalCount: totalCount, to: &lengths)
        else {
          return nil
        }
      case DeflateSymbol.repeatZeroShort:
        guard let extra = reader.readBits(3),
          appendRepeated(0, count: extra + 3, totalCount: totalCount, to: &lengths)
        else {
          return nil
        }
      case DeflateSymbol.repeatZeroLong:
        guard let extra = reader.readBits(7),
          appendRepeated(0, count: extra + 11, totalCount: totalCount, to: &lengths)
        else {
          return nil
        }
      default:
        return nil
      }
    }

    let literalLengths = Array(lengths[..<literalCount])
    guard literalLengths[DeflateSymbol.endOfBlock] > 0,
      let literalTree = HuffmanTree(codeLengths: literalLengths)
    else {
      return nil
    }

    let distanceLengths = Array(lengths[literalCount...])
    let distanceTree =
      distanceLengths.contains(where: { $0 > 0 })
      ? HuffmanTree(codeLengths: distanceLengths)
      : nil
    return (literalTree, distanceTree)
  }

  private static func appendRepeated(
    _ value: Int,
    count: Int,
    totalCount: Int,
    to lengths: inout [Int]
  ) -> Bool {
    guard lengths.count + count <= totalCount else { return false }

    lengths.append(contentsOf: repeatElement(value, count: count))
    return true
  }

  private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
    let start = data.startIndex + offset
    return UInt32(data[start]) << 24
      | UInt32(data[start + 1]) << 16
      | UInt32(data[start + 2]) << 8
      | UInt32(data[start + 3])
  }

  private static let fixedLiteralTree = HuffmanTree(
    codeLengths: [Int](repeating: 8, count: 144)
      + [Int](repeating: 9, count: 112)
      + [Int](repeating: 7, count: 24)
      + [Int](repeating: 8, count: 8)
  )!
  private static let fixedDistanceTree = HuffmanTree(
    codeLengths: [Int](repeating: 5, count: 32)
  )!
  private static let codeLengthOrder = [
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
  ]
  private static let lengthBases = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83,
    99, 115, 131, 163, 195, 227, 258,
  ]
  private static let lengthExtraBits = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5,
    5, 5, 0,
  ]
  private static let distanceBases = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
    1_025, 1_537, 2_049, 3_073, 4_097, 6_145, 8_193, 12_289, 16_385, 24_577,
  ]
  private static let distanceExtraBits = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10,
    11, 11, 12, 12, 13, 13,
  ]
}

private struct HuffmanTree {
  private let symbolsByCode: [Int: Int]
  private let maximumLength: Int

  init?(codeLengths: [Int]) {
    let maximumLength = codeLengths.max() ?? 0
    guard maximumLength > 0, maximumLength <= DeflateLayout.maximumCodeBitCount else {
      return nil
    }

    var counts = [Int](repeating: 0, count: maximumLength + 1)
    for length in codeLengths where length > 0 {
      guard length <= maximumLength else { return nil }

      counts[length] += 1
    }

    var availableCodes = 1
    for length in 1...maximumLength {
      availableCodes = (availableCodes << 1) - counts[length]
      guard availableCodes >= 0 else { return nil }
    }

    var nextCodes = [Int](repeating: 0, count: maximumLength + 1)
    var code = 0
    for length in 1...maximumLength {
      code = (code + counts[length - 1]) << 1
      nextCodes[length] = code
    }

    var symbolsByCode: [Int: Int] = [:]
    for (symbol, length) in codeLengths.enumerated() where length > 0 {
      let key = Self.key(length: length, code: nextCodes[length])
      symbolsByCode[key] = symbol
      nextCodes[length] += 1
    }

    self.symbolsByCode = symbolsByCode
    self.maximumLength = maximumLength
  }

  func decode(from reader: inout DeflateBitReader) -> Int? {
    var code = 0
    for length in 1...maximumLength {
      guard let bit = reader.readBits(1) else { return nil }

      code = (code << 1) | bit
      if let symbol = symbolsByCode[Self.key(length: length, code: code)] {
        return symbol
      }
    }

    return nil
  }

  private static func key(length: Int, code: Int) -> Int {
    (length << DeflateLayout.codeKeyShift) | code
  }
}

private struct DeflateBitReader {
  private let data: Data
  private let end: Int
  private var byteOffset: Int
  private var bitOffset = 0

  init(data: Data, start: Int, end: Int) {
    self.data = data
    byteOffset = start
    self.end = end
  }

  var isAtEnd: Bool {
    byteOffset == end && bitOffset == 0
  }

  mutating func readBits(_ count: Int) -> Int? {
    var value = 0
    for shift in 0..<count {
      guard byteOffset < end else { return nil }

      let index = data.startIndex + byteOffset
      let bit = (data[index] >> bitOffset) & 1
      value |= Int(bit) << shift
      bitOffset += 1

      if bitOffset == 8 {
        byteOffset += 1
        bitOffset = 0
      }
    }

    return value
  }

  mutating func alignToByteBoundary() {
    guard bitOffset > 0 else { return }

    byteOffset += 1
    bitOffset = 0
  }

  mutating func readAlignedByte() -> UInt8? {
    guard bitOffset == 0, byteOffset < end else { return nil }

    defer { byteOffset += 1 }
    return data[data.startIndex + byteOffset]
  }

  mutating func readLittleEndianUInt16() -> UInt16? {
    guard let low = readAlignedByte(), let high = readAlignedByte() else { return nil }

    return UInt16(low) | (UInt16(high) << 8)
  }
}

private struct InflateOutput {
  private(set) var count = 0
  private(set) var adler32: UInt32 = 1

  private let limit: Int
  private let byteValidator: (Int, UInt8) -> Bool
  private var window = [UInt8](repeating: 0, count: DeflateLayout.windowByteCount)
  private var checksumA: UInt32 = 1
  private var checksumB: UInt32 = 0

  init(limit: Int, byteValidator: @escaping (Int, UInt8) -> Bool) {
    self.limit = limit
    self.byteValidator = byteValidator
  }

  mutating func emit(_ byte: UInt8) -> Bool {
    guard count < limit, byteValidator(count, byte) else { return false }

    window[count & DeflateLayout.windowIndexMask] = byte
    count += 1

    checksumA += UInt32(byte)
    if checksumA >= Adler32.modulus { checksumA -= Adler32.modulus }
    checksumB += checksumA
    if checksumB >= Adler32.modulus { checksumB -= Adler32.modulus }
    adler32 = (checksumB << 16) | checksumA
    return true
  }

  mutating func copy(distance: Int, length: Int) -> Bool {
    guard distance > 0,
      distance <= min(count, DeflateLayout.windowByteCount),
      length <= limit - count
    else {
      return false
    }

    for _ in 0..<length {
      let source = (count - distance) & DeflateLayout.windowIndexMask
      guard emit(window[source]) else { return false }
    }

    return true
  }
}

private enum ZlibLayout {
  static let headerByteCount = 2
  static let checksumByteCount = 4
  static let minimumByteCount = headerByteCount + checksumByteCount
  static let compressionMethodMask: UInt8 = 0x0F
  static let deflateMethod: UInt8 = 8
  static let windowSizeShift = 4
  static let maximumWindowSize: UInt8 = 7
  static let presetDictionaryFlag: UInt8 = 0x20
  static let headerCheckDivisor = 31
}

private enum DeflateLayout {
  static let windowByteCount = 32_768
  static let windowIndexMask = windowByteCount - 1
  static let maximumCodeBitCount = 15
  static let codeKeyShift = 16
  static let minimumLiteralCodeCount = 257
  static let minimumDistanceCodeCount = 1
  static let minimumCodeLengthCodeCount = 4
  static let codeLengthAlphabetCount = 19
}

private enum DeflateBlockType {
  static let uncompressed = 0
  static let fixedHuffman = 1
  static let dynamicHuffman = 2
}

private enum DeflateSymbol {
  static let endOfBlock = 256
  static let firstLength = 257
  static let repeatPreviousLength = 16
  static let repeatZeroShort = 17
  static let repeatZeroLong = 18
}

private enum Adler32 {
  static let modulus: UInt32 = 65_521
}
