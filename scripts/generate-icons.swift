#!/usr/bin/env swift
import AppKit
import Foundation

private enum IconError: Error {
  case bitmapCreation
  case graphicsContextCreation
  case pngEncoding
  case iconutil(Int32)
  case usage
}

private let iconEntries: [(name: String, pixels: Int)] = [
  ("icon_16x16", 16),
  ("icon_16x16@2x", 32),
  ("icon_32x32", 32),
  ("icon_32x32@2x", 64),
  ("icon_128x128", 128),
  ("icon_128x128@2x", 256),
  ("icon_256x256", 256),
  ("icon_256x256@2x", 512),
  ("icon_512x512", 512),
  ("icon_512x512@2x", 1_024),
]

private func renderPNG(pixels: Int, drawing: (CGFloat) -> Void) throws -> Data {
  guard
    let representation = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixels,
      pixelsHigh: pixels,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )
  else {
    throw IconError.bitmapCreation
  }

  guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
    throw IconError.graphicsContextCreation
  }

  let size = CGFloat(pixels)
  representation.size = NSSize(width: size, height: size)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  drawing(size)
  NSGraphicsContext.restoreGraphicsState()

  guard let data = representation.representation(using: .png, properties: [:]) else {
    throw IconError.pngEncoding
  }

  return data
}

private func drawArtwork(in bounds: NSRect) {
  let x = bounds.minX
  let y = bounds.minY
  let width = bounds.width
  let height = bounds.height

  NSColor.black.setFill()
  NSColor.black.setStroke()

  // Sion's two castle hills also read as connected diagram nodes.
  let hills = NSBezierPath()
  hills.move(to: NSPoint(x: x, y: y + height * 0.12))
  hills.line(to: NSPoint(x: x + width * 0.08, y: y + height * 0.25))
  hills.line(to: NSPoint(x: x + width * 0.19, y: y + height * 0.31))
  hills.line(to: NSPoint(x: x + width * 0.31, y: y + height * 0.25))
  hills.line(to: NSPoint(x: x + width * 0.43, y: y + height * 0.42))
  hills.line(to: NSPoint(x: x + width * 0.55, y: y + height * 0.27))
  hills.line(to: NSPoint(x: x + width * 0.70, y: y + height * 0.36))
  hills.line(to: NSPoint(x: x + width * 0.84, y: y + height * 0.28))
  hills.line(to: NSPoint(x: x + width, y: y + height * 0.38))
  hills.line(to: NSPoint(x: x + width, y: y))
  hills.line(to: NSPoint(x: x, y: y))
  hills.close()
  hills.fill()

  drawValere(at: NSPoint(x: x + width * 0.30, y: y + height * 0.30), scale: width)
  drawTourbillon(at: NSPoint(x: x + width * 0.69, y: y + height * 0.34), scale: width)

  let connection = NSBezierPath()
  connection.move(to: NSPoint(x: x + width * 0.37, y: y + height * 0.53))
  connection.curve(
    to: NSPoint(x: x + width * 0.69, y: y + height * 0.50),
    controlPoint1: NSPoint(x: x + width * 0.47, y: y + height * 0.61),
    controlPoint2: NSPoint(x: x + width * 0.58, y: y + height * 0.42)
  )
  connection.lineWidth = max(1, width * 0.014)
  connection.lineCapStyle = .round
  connection.stroke()

  for point in [
    NSPoint(x: x + width * 0.37, y: y + height * 0.53),
    NSPoint(x: x + width * 0.69, y: y + height * 0.50),
  ] {
    NSBezierPath(
      ovalIn: NSRect(
        x: point.x - width * 0.018,
        y: point.y - width * 0.018,
        width: width * 0.036,
        height: width * 0.036
      )
    ).fill()
  }
}

private func drawValere(at origin: NSPoint, scale: CGFloat) {
  let body = NSRect(
    x: origin.x - scale * 0.09,
    y: origin.y,
    width: scale * 0.18,
    height: scale * 0.19
  )
  NSBezierPath(rect: body).fill()

  let roof = NSBezierPath()
  roof.move(to: NSPoint(x: body.minX - scale * 0.02, y: body.maxY))
  roof.line(to: NSPoint(x: body.midX, y: body.maxY + scale * 0.12))
  roof.line(to: NSPoint(x: body.maxX + scale * 0.02, y: body.maxY))
  roof.close()
  roof.fill()

  let tower = NSRect(
    x: body.midX - scale * 0.027,
    y: body.maxY,
    width: scale * 0.054,
    height: scale * 0.12
  )
  NSBezierPath(rect: tower).fill()

  let spire = NSBezierPath()
  spire.move(to: NSPoint(x: tower.minX - scale * 0.012, y: tower.maxY))
  spire.line(to: NSPoint(x: tower.midX, y: tower.maxY + scale * 0.10))
  spire.line(to: NSPoint(x: tower.maxX + scale * 0.012, y: tower.maxY))
  spire.close()
  spire.fill()
}

private func drawTourbillon(at origin: NSPoint, scale: CGFloat) {
  let wall = NSRect(
    x: origin.x - scale * 0.105,
    y: origin.y,
    width: scale * 0.21,
    height: scale * 0.13
  )
  NSBezierPath(rect: wall).fill()

  let merlonWidth = scale * 0.036
  let gap = scale * 0.016
  for index in 0..<4 {
    let merlon = NSRect(
      x: wall.minX + CGFloat(index) * (merlonWidth + gap),
      y: wall.maxY,
      width: merlonWidth,
      height: scale * 0.04
    )
    NSBezierPath(rect: merlon).fill()
  }

  let tower = NSRect(
    x: wall.maxX - scale * 0.062,
    y: wall.maxY,
    width: scale * 0.062,
    height: scale * 0.13
  )
  NSBezierPath(rect: tower).fill()
}

private func drawAppIcon(size: CGFloat) {
  let tile = NSRect(x: size * 0.04, y: size * 0.04, width: size * 0.92, height: size * 0.92)
  let outline = NSBezierPath(
    roundedRect: tile,
    xRadius: tile.width * 0.2237,
    yRadius: tile.height * 0.2237
  )

  NSColor.white.setFill()
  outline.fill()
  NSGraphicsContext.saveGraphicsState()
  outline.addClip()
  drawArtwork(in: tile.insetBy(dx: tile.width * 0.08, dy: tile.height * 0.08))
  NSGraphicsContext.restoreGraphicsState()

  outline.lineWidth = max(1, size * 0.004)
  NSColor(calibratedWhite: 0.82, alpha: 1).setStroke()
  outline.stroke()
}

private func drawDocumentIcon(size: CGFloat) {
  let page = NSRect(x: size * 0.19, y: size * 0.10, width: size * 0.62, height: size * 0.80)
  let fold = page.width * 0.23
  let outline = NSBezierPath()
  outline.move(to: page.origin)
  outline.line(to: NSPoint(x: page.minX, y: page.maxY))
  outline.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
  outline.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
  outline.line(to: NSPoint(x: page.maxX, y: page.minY))
  outline.close()

  NSColor.white.setFill()
  outline.fill()
  NSGraphicsContext.saveGraphicsState()
  outline.addClip()
  drawArtwork(in: page.insetBy(dx: page.width * 0.08, dy: page.height * 0.08))
  NSGraphicsContext.restoreGraphicsState()

  let corner = NSBezierPath()
  corner.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
  corner.line(to: NSPoint(x: page.maxX - fold, y: page.maxY - fold))
  corner.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
  corner.close()
  NSColor(calibratedWhite: 0.90, alpha: 1).setFill()
  corner.fill()

  outline.lineWidth = max(1, size * 0.006)
  NSColor(calibratedWhite: 0.76, alpha: 1).setStroke()
  outline.stroke()
}

private func buildIcon(
  named name: String,
  in outputDirectory: URL,
  drawing: @escaping (CGFloat) -> Void
) throws {
  let manager = FileManager.default
  let iconset = manager.temporaryDirectory
    .appendingPathComponent("Sion-\(name)-\(UUID().uuidString).iconset")
  try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
  defer { try? manager.removeItem(at: iconset) }

  for entry in iconEntries {
    let data = try renderPNG(pixels: entry.pixels, drawing: drawing)
    try data.write(to: iconset.appendingPathComponent("\(entry.name).png"))
  }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
  process.arguments = [
    "-c", "icns",
    "-o", outputDirectory.appendingPathComponent("\(name).icns").path,
    iconset.path,
  ]
  try process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0 else {
    throw IconError.iconutil(process.terminationStatus)
  }
}

guard CommandLine.arguments.count == 2 else {
  throw IconError.usage
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try buildIcon(named: "AppIcon", in: outputDirectory, drawing: drawAppIcon)
try buildIcon(named: "DocumentIcon", in: outputDirectory, drawing: drawDocumentIcon)
