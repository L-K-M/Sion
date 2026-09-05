import CGtk
import Foundation

/// Sion's icon artwork, drawn with Cairo exactly as the macOS build draws it
/// with AppKit: two castle hills that also read as connected diagram nodes.
///
/// The AppKit original works in a y-up coordinate space, so every routine here
/// draws under a flip transform and shares the original's proportions.
public enum SionIconArtwork {
  /// Draws the application icon into a `size` × `size` square at the origin.
  public static func drawAppIcon(_ context: OpaquePointer, size: Double) {
    flipped(context, size: size) {
      let tile = Box(x: size * 0.04, y: size * 0.04, width: size * 0.92, height: size * 0.92)
      cairo_save(context)
      addRoundedRect(context, tile, radius: tile.width * 0.2237)
      cairo_set_source_rgb(context, 1, 1, 1)
      cairo_fill_preserve(context)
      cairo_clip(context)
      drawArtwork(context, in: tile.insetBy(dx: tile.width * 0.08, dy: tile.height * 0.08))
      cairo_restore(context)

      addRoundedRect(context, tile, radius: tile.width * 0.2237)
      cairo_set_line_width(context, max(1, size * 0.004))
      cairo_set_source_rgb(context, 0.82, 0.82, 0.82)
      cairo_stroke(context)
    }
  }

  /// Draws the document icon: a page with a folded corner around the artwork.
  public static func drawDocumentIcon(_ context: OpaquePointer, size: Double) {
    flipped(context, size: size) {
      let page = Box(x: size * 0.19, y: size * 0.10, width: size * 0.62, height: size * 0.80)
      let fold = page.width * 0.23

      func addOutline() {
        cairo_move_to(context, page.minX, page.minY)
        cairo_line_to(context, page.minX, page.maxY)
        cairo_line_to(context, page.maxX - fold, page.maxY)
        cairo_line_to(context, page.maxX, page.maxY - fold)
        cairo_line_to(context, page.maxX, page.minY)
        cairo_close_path(context)
      }

      cairo_save(context)
      addOutline()
      cairo_set_source_rgb(context, 1, 1, 1)
      cairo_fill_preserve(context)
      cairo_clip(context)
      drawArtwork(context, in: page.insetBy(dx: page.width * 0.08, dy: page.height * 0.08))
      cairo_restore(context)

      cairo_move_to(context, page.maxX - fold, page.maxY)
      cairo_line_to(context, page.maxX - fold, page.maxY - fold)
      cairo_line_to(context, page.maxX, page.maxY - fold)
      cairo_close_path(context)
      cairo_set_source_rgb(context, 0.90, 0.90, 0.90)
      cairo_fill(context)

      addOutline()
      cairo_set_line_width(context, max(1, size * 0.006))
      cairo_set_source_rgb(context, 0.76, 0.76, 0.76)
      cairo_stroke(context)
    }
  }

  private struct Box {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midX: Double { x + width / 2 }

    func insetBy(dx: Double, dy: Double) -> Box {
      Box(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
    }
  }

  private static func flipped(_ context: OpaquePointer, size: Double, _ body: () -> Void) {
    cairo_save(context)
    cairo_translate(context, 0, size)
    cairo_scale(context, 1, -1)
    body()
    cairo_restore(context)
  }

  private static func addRoundedRect(_ context: OpaquePointer, _ box: Box, radius: Double) {
    let r = min(radius, box.width / 2, box.height / 2)
    cairo_new_sub_path(context)
    cairo_arc(context, box.maxX - r, box.maxY - r, r, 0, .pi / 2)
    cairo_arc(context, box.minX + r, box.maxY - r, r, .pi / 2, .pi)
    cairo_arc(context, box.minX + r, box.minY + r, r, .pi, 3 * .pi / 2)
    cairo_arc(context, box.maxX - r, box.minY + r, r, 3 * .pi / 2, 2 * .pi)
    cairo_close_path(context)
  }

  private static func fillRect(_ context: OpaquePointer, _ box: Box) {
    cairo_rectangle(context, box.x, box.y, box.width, box.height)
    cairo_fill(context)
  }

  private static func drawArtwork(_ context: OpaquePointer, in bounds: Box) {
    let x = bounds.minX
    let y = bounds.minY
    let width = bounds.width
    let height = bounds.height

    cairo_set_source_rgb(context, 0, 0, 0)

    cairo_move_to(context, x, y + height * 0.12)
    cairo_line_to(context, x + width * 0.08, y + height * 0.25)
    cairo_line_to(context, x + width * 0.19, y + height * 0.31)
    cairo_line_to(context, x + width * 0.31, y + height * 0.25)
    cairo_line_to(context, x + width * 0.43, y + height * 0.42)
    cairo_line_to(context, x + width * 0.55, y + height * 0.27)
    cairo_line_to(context, x + width * 0.70, y + height * 0.36)
    cairo_line_to(context, x + width * 0.84, y + height * 0.28)
    cairo_line_to(context, x + width, y + height * 0.38)
    cairo_line_to(context, x + width, y)
    cairo_line_to(context, x, y)
    cairo_close_path(context)
    cairo_fill(context)

    drawValere(context, atX: x + width * 0.30, y: y + height * 0.30, scale: width)
    drawTourbillon(context, atX: x + width * 0.69, y: y + height * 0.34, scale: width)

    cairo_move_to(context, x + width * 0.37, y + height * 0.53)
    cairo_curve_to(
      context,
      x + width * 0.47, y + height * 0.61,
      x + width * 0.58, y + height * 0.42,
      x + width * 0.69, y + height * 0.50
    )
    cairo_set_line_width(context, max(1, width * 0.014))
    cairo_set_line_cap(context, CAIRO_LINE_CAP_ROUND)
    cairo_stroke(context)

    for point in [
      (x + width * 0.37, y + height * 0.53),
      (x + width * 0.69, y + height * 0.50),
    ] {
      cairo_new_sub_path(context)
      cairo_arc(context, point.0, point.1, width * 0.018, 0, 2 * .pi)
      cairo_fill(context)
    }
  }

  private static func drawValere(
    _ context: OpaquePointer, atX ox: Double, y oy: Double, scale: Double
  ) {
    let body = Box(x: ox - scale * 0.09, y: oy, width: scale * 0.18, height: scale * 0.19)
    fillRect(context, body)

    cairo_move_to(context, body.minX - scale * 0.02, body.maxY)
    cairo_line_to(context, body.midX, body.maxY + scale * 0.12)
    cairo_line_to(context, body.maxX + scale * 0.02, body.maxY)
    cairo_close_path(context)
    cairo_fill(context)

    let tower = Box(
      x: body.midX - scale * 0.027, y: body.maxY, width: scale * 0.054, height: scale * 0.12)
    fillRect(context, tower)

    cairo_move_to(context, tower.minX - scale * 0.012, tower.maxY)
    cairo_line_to(context, tower.midX, tower.maxY + scale * 0.10)
    cairo_line_to(context, tower.maxX + scale * 0.012, tower.maxY)
    cairo_close_path(context)
    cairo_fill(context)
  }

  private static func drawTourbillon(
    _ context: OpaquePointer, atX ox: Double, y oy: Double, scale: Double
  ) {
    let wall = Box(x: ox - scale * 0.105, y: oy, width: scale * 0.21, height: scale * 0.13)
    fillRect(context, wall)

    let merlonWidth = scale * 0.036
    let gap = scale * 0.016
    for index in 0..<4 {
      fillRect(
        context,
        Box(
          x: wall.minX + Double(index) * (merlonWidth + gap),
          y: wall.maxY,
          width: merlonWidth,
          height: scale * 0.04
        )
      )
    }

    fillRect(
      context,
      Box(x: wall.maxX - scale * 0.062, y: wall.maxY, width: scale * 0.062, height: scale * 0.13))
  }
}
