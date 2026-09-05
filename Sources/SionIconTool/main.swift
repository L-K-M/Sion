import CGtk
import Foundation
import SionGtk

// Renders Sion's application and document icons into a freedesktop icon
// theme tree, so packaging never carries generated bitmaps.
// Usage: sion-icon-tool <output-directory>

let sizes = [16, 22, 24, 32, 48, 64, 128, 256, 512]
let appIconName = "ch.lkmc.Sion"
let documentIconName = "application-vnd.lkmc.sion+zip"

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("Usage: sion-icon-tool <output-directory>\n".utf8))
  exit(2)
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
  .appendingPathComponent("hicolor", isDirectory: true)

func writePNG(
  named name: String, category: String, pixels: Int,
  drawing: (OpaquePointer, Double) -> Void
) throws {
  let directory = root.appendingPathComponent("\(pixels)x\(pixels)/\(category)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(pixels), Int32(pixels)),
    let context = cairo_create(surface)
  else {
    throw IconToolError.surface
  }
  defer {
    cairo_destroy(context)
    cairo_surface_destroy(surface)
  }
  drawing(context, Double(pixels))
  let path = directory.appendingPathComponent("\(name).png").path
  guard cairo_surface_write_to_png(surface, path) == CAIRO_STATUS_SUCCESS else {
    throw IconToolError.png(path)
  }
}

func writeSVG(named name: String, category: String, drawing: (OpaquePointer, Double) -> Void)
  throws
{
  let directory = root.appendingPathComponent("scalable/\(category)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let path = directory.appendingPathComponent("\(name).svg").path
  let size = 512.0
  guard let surface = cairo_svg_surface_create(path, size, size),
    let context = cairo_create(surface)
  else {
    throw IconToolError.surface
  }
  drawing(context, size)
  cairo_destroy(context)
  cairo_surface_finish(surface)
  let status = cairo_surface_status(surface)
  cairo_surface_destroy(surface)
  guard status == CAIRO_STATUS_SUCCESS else {
    throw IconToolError.png(path)
  }
}

enum IconToolError: Error {
  case surface
  case png(String)
}

do {
  for pixels in sizes {
    try writePNG(
      named: appIconName, category: "apps", pixels: pixels, drawing: SionIconArtwork.drawAppIcon)
    try writePNG(
      named: documentIconName, category: "mimetypes", pixels: pixels,
      drawing: SionIconArtwork.drawDocumentIcon)
  }
  try writeSVG(named: appIconName, category: "apps", drawing: SionIconArtwork.drawAppIcon)
  try writeSVG(
    named: documentIconName, category: "mimetypes", drawing: SionIconArtwork.drawDocumentIcon)
} catch {
  FileHandle.standardError.write(Data("sion-icon-tool: \(error)\n".utf8))
  exit(1)
}
