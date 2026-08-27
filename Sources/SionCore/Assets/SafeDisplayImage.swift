import Foundation

extension SionAsset {
  /// Caps worst-case decoding while the exact original remains recoverable.
  public static let maximumSafeDisplayPixelDimension = 8_192.0
  public static let maximumSafeDisplayPixelCount: UInt64 = 16_777_216

  /// Builds the inert rendition used by editors and recovery exports.
  public static func safeDisplayPNG(
    data: Data,
    pixelSize: SionSize? = nil
  ) throws -> SionAsset {
    let asset = try SionAsset(
      data: data,
      mediaType: SafeDisplayImage.mediaType,
      fileExtension: SafeDisplayImage.fileExtension,
      pixelSize: pixelSize
    )
    guard SafeDisplayImage.validates(asset) else {
      throw SionPackageError.invalidDisplayAsset(asset.id)
    }

    return asset
  }
}

enum SafeDisplayImage {
  static let mediaType = "image/png"
  static let fileExtension = "png"

  static func validates(_ asset: SionAsset) -> Bool {
    asset.mediaType == mediaType
      && asset.fileExtension == fileExtension
      && asset.data.count <= SionArchiveConstants.maximumEntryByteCount
      && PNGFile.validates(asset.data)
  }
}

/// Parses PNG structure without decoding attacker-controlled pixels.
private enum PNGFile {
  static func validates(_ data: Data) -> Bool {
    data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Bool in
      guard hasSignature(bytes) else { return false }

      var offset = signature.count
      var header: Header?
      var sawPalette = false
      var sawImageData = false
      var finishedImageData = false
      var compressedImageData = Data()

      while offset < bytes.count {
        guard bytes.count - offset >= chunkOverhead else { return false }

        let length = Int(uint32(bytes, at: offset))
        guard length <= bytes.count - offset - chunkOverhead else { return false }

        let typeOffset = offset + lengthFieldSize
        let dataOffset = typeOffset + chunkTypeSize
        let checksumOffset = dataOffset + length
        let nextOffset = checksumOffset + checksumSize
        guard validChunkType(bytes, at: typeOffset) else { return false }

        let type = uint32(bytes, at: typeOffset)
        let checksum = uint32(bytes, at: checksumOffset)
        guard checksum == PNGChecksum.checksum(bytes, in: typeOffset..<checksumOffset) else {
          return false
        }

        if sawImageData, type != ChunkType.imageData, type != ChunkType.end {
          finishedImageData = true
        }

        switch type {
        case ChunkType.header:
          guard header == nil, offset == signature.count, length == headerLength,
            let decoded = Header(bytes, at: dataOffset)
          else {
            return false
          }

          header = decoded

        case ChunkType.palette:
          guard let header, !sawPalette, !sawImageData,
            header.allowsPalette,
            (minimumPaletteLength...maximumPaletteLength).contains(length),
            length.isMultiple(of: paletteEntrySize)
          else {
            return false
          }

          sawPalette = true

        case ChunkType.imageData:
          guard let header, !finishedImageData,
            header.colorType != indexedColorType || sawPalette
          else {
            return false
          }

          sawImageData = true
          compressedImageData.append(contentsOf: bytes[dataOffset..<(dataOffset + length)])

        case ChunkType.end:
          guard let header, sawImageData, length == 0, nextOffset == bytes.count,
            header.colorType != indexedColorType || sawPalette,
            PNGScanlines(header: header).validates(compressedImageData)
          else {
            return false
          }

          return true

        default:
          guard header != nil, !isCriticalChunk(bytes[typeOffset]) else { return false }
        }

        offset = nextOffset
      }

      return false
    }
  }

  private static func hasSignature(_ bytes: UnsafeRawBufferPointer) -> Bool {
    guard bytes.count >= minimumFileLength else { return false }

    return signature.indices.allSatisfy { bytes[$0] == signature[$0] }
  }

  private static func validChunkType(
    _ bytes: UnsafeRawBufferPointer,
    at offset: Int
  ) -> Bool {
    for index in 0..<chunkTypeSize {
      let value = bytes[offset + index]
      guard asciiUppercase.contains(value) || asciiLowercase.contains(value) else {
        return false
      }
    }

    // PNG reserves the third type bit; lowercase means another format version.
    return asciiUppercase.contains(bytes[offset + reservedTypeByteIndex])
  }

  private static func isCriticalChunk(_ firstTypeByte: UInt8) -> Bool {
    asciiUppercase.contains(firstTypeByte)
  }

  private static func uint32(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
    UInt32(bytes[offset]) << 24
      | UInt32(bytes[offset + 1]) << 16
      | UInt32(bytes[offset + 2]) << 8
      | UInt32(bytes[offset + 3])
  }

  private struct Header {
    let width: UInt32
    let height: UInt32
    let bitDepth: UInt8
    let colorType: UInt8
    let interlace: UInt8

    init?(_ bytes: UnsafeRawBufferPointer, at offset: Int) {
      let width = PNGFile.uint32(bytes, at: offset)
      let height = PNGFile.uint32(bytes, at: offset + dimensionFieldSize)
      let bitDepth = bytes[offset + bitDepthOffset]
      let colorType = bytes[offset + colorTypeOffset]
      let compression = bytes[offset + compressionOffset]
      let filter = bytes[offset + filterOffset]
      let interlace = bytes[offset + interlaceOffset]

      guard width > 0, height > 0,
        Double(width) <= SionAsset.maximumSafeDisplayPixelDimension,
        Double(height) <= SionAsset.maximumSafeDisplayPixelDimension,
        UInt64(width) * UInt64(height) <= SionAsset.maximumSafeDisplayPixelCount,
        validBitDepths[colorType]?.contains(bitDepth) == true,
        compression == standardCompression,
        filter == standardFilter,
        supportedInterlaceMethods.contains(interlace)
      else {
        return nil
      }

      self.width = width
      self.height = height
      self.bitDepth = bitDepth
      self.colorType = colorType
      self.interlace = interlace
    }

    var allowsPalette: Bool {
      colorType != grayscaleColorType && colorType != grayscaleAlphaColorType
    }
  }

  private struct PNGScanlines {
    private let rows: [Row]
    private let expectedByteCount: Int

    init(header: Header) {
      let channels = channelCounts[header.colorType] ?? 0
      let bitsPerPixel = UInt64(header.bitDepth) * UInt64(channels)
      let passes = header.interlace == 0 ? [Adam7.fullImage] : Adam7.passes
      var rows: [Row] = []
      var expectedByteCount: UInt64 = 0

      for pass in passes {
        let width = pass.sampleCount(total: header.width, start: pass.startX, step: pass.stepX)
        let height = pass.sampleCount(total: header.height, start: pass.startY, step: pass.stepY)
        guard width > 0, height > 0 else { continue }

        let payloadByteCount = ((UInt64(width) * bitsPerPixel) + 7) / 8
        let rowByteCount = payloadByteCount + 1
        rows.append(Row(count: Int(height), byteCount: Int(rowByteCount)))
        expectedByteCount += UInt64(height) * rowByteCount
      }

      self.rows = rows
      self.expectedByteCount = Int(expectedByteCount)
    }

    func validates(_ compressedData: Data) -> Bool {
      guard expectedByteCount <= maximumDecodedByteCount else { return false }

      var rowGroupIndex = 0
      var rowIndex = 0
      var byteIndex = 0
      let result = ZlibInflateValidator.validates(
        compressedData,
        outputByteCount: expectedByteCount
      ) { _, byte in
        guard rowGroupIndex < rows.count else { return false }

        if byteIndex == 0, byte > maximumFilterType { return false }

        byteIndex += 1
        guard byteIndex == rows[rowGroupIndex].byteCount else { return true }

        byteIndex = 0
        rowIndex += 1
        if rowIndex == rows[rowGroupIndex].count {
          rowIndex = 0
          rowGroupIndex += 1
        }
        return true
      }

      return result && rowGroupIndex == rows.count && rowIndex == 0 && byteIndex == 0
    }

    private struct Row {
      let count: Int
      let byteCount: Int
    }
  }

  private struct Adam7 {
    let startX: UInt32
    let startY: UInt32
    let stepX: UInt32
    let stepY: UInt32

    func sampleCount(total: UInt32, start: UInt32, step: UInt32) -> UInt32 {
      guard total > start else { return 0 }

      return ((total - start) + step - 1) / step
    }

    static let fullImage = Adam7(startX: 0, startY: 0, stepX: 1, stepY: 1)
    static let passes = [
      Adam7(startX: 0, startY: 0, stepX: 8, stepY: 8),
      Adam7(startX: 4, startY: 0, stepX: 8, stepY: 8),
      Adam7(startX: 0, startY: 4, stepX: 4, stepY: 8),
      Adam7(startX: 2, startY: 0, stepX: 4, stepY: 4),
      Adam7(startX: 0, startY: 2, stepX: 2, stepY: 4),
      Adam7(startX: 1, startY: 0, stepX: 2, stepY: 2),
      Adam7(startX: 0, startY: 1, stepX: 1, stepY: 2),
    ]
  }

  private enum ChunkType {
    static let header: UInt32 = 0x4948_4452
    static let palette: UInt32 = 0x504C_5445
    static let imageData: UInt32 = 0x4944_4154
    static let end: UInt32 = 0x4945_4E44
  }

  private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
  private static let minimumFileLength = 57
  private static let lengthFieldSize = 4
  private static let chunkTypeSize = 4
  private static let checksumSize = 4
  private static let chunkOverhead = lengthFieldSize + chunkTypeSize + checksumSize
  private static let headerLength = 13
  private static let dimensionFieldSize = 4
  private static let bitDepthOffset = 8
  private static let colorTypeOffset = 9
  private static let compressionOffset = 10
  private static let filterOffset = 11
  private static let interlaceOffset = 12
  private static let reservedTypeByteIndex = 2
  private static let paletteEntrySize = 3
  private static let minimumPaletteLength = paletteEntrySize
  private static let maximumPaletteLength = 256 * paletteEntrySize
  private static let grayscaleColorType: UInt8 = 0
  private static let indexedColorType: UInt8 = 3
  private static let grayscaleAlphaColorType: UInt8 = 4
  private static let standardCompression: UInt8 = 0
  private static let standardFilter: UInt8 = 0
  private static let supportedInterlaceMethods: Set<UInt8> = [0, 1]
  private static let channelCounts: [UInt8: UInt8] = [0: 1, 2: 3, 3: 1, 4: 2, 6: 4]
  private static let maximumFilterType: UInt8 = 4
  private static let maximumDecodedByteCount = 128 * 1_024 * 1_024
  private static let asciiUppercase: ClosedRange<UInt8> = 65...90
  private static let asciiLowercase: ClosedRange<UInt8> = 97...122
  private static let validBitDepths: [UInt8: Set<UInt8>] = [
    0: [1, 2, 4, 8, 16],
    2: [8, 16],
    3: [1, 2, 4, 8],
    4: [8, 16],
    6: [8, 16],
  ]
}

private enum PNGChecksum {
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

  static func checksum(
    _ bytes: UnsafeRawBufferPointer,
    in range: Range<Int>
  ) -> UInt32 {
    var checksum = UInt32.max
    for index in range {
      let tableIndex = Int((checksum ^ UInt32(bytes[index])) & 0xFF)
      checksum = table[tableIndex] ^ (checksum >> 8)
    }
    return checksum ^ UInt32.max
  }
}
