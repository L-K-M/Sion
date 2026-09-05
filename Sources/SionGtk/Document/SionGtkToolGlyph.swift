import CGtk
import Foundation
import SionKit

/// Draws a tool's glyph with Cairo in the widget's foreground colour, so the
/// toolbar needs no icon-theme entries of its own.
enum SionGtkToolGlyph {
  static let size = 16.0

  @MainActor
  static func makeWidget(for tool: SionEditorController.Tool) -> UnsafeMutablePointer<GtkWidget> {
    let area = gtk_drawing_area_new()!
    gtk_drawing_area_set_content_width(area.cast(), Int32(size))
    gtk_drawing_area_set_content_height(area.cast(), Int32(size))
    gtk_widget_set_valign(area, GTK_ALIGN_CENTER)
    gtk_widget_set_halign(area, GTK_ALIGN_CENTER)
    let box = SignalBox<SionEditorController.Tool>(tool)
    let drawFunction: GtkDrawingAreaDrawFunc = { area, context, width, height, data in
      guard let context, let data else { return }
      let tool = Unmanaged<SignalBox<SionEditorController.Tool>>.fromOpaque(data)
        .takeUnretainedValue().handler
      var color = GdkRGBA()
      if let area {
        gtk_widget_get_color(area.cast(), &color)
      }
      cairo_set_source_rgba(
        context, Double(color.red), Double(color.green), Double(color.blue), Double(color.alpha))
      SionGtkToolGlyph.draw(tool, in: context, width: Double(width), height: Double(height))
    }
    gtk_drawing_area_set_draw_func(
      area.cast(), drawFunction, Unmanaged.passRetained(box).toOpaque(),
      { data in
        guard let data else { return }
        Unmanaged<AnyObject>.fromOpaque(data).release()
      })
    return area
  }

  nonisolated static func draw(
    _ tool: SionEditorController.Tool, in context: OpaquePointer, width: Double, height: Double
  ) {
    let scale = min(width, height) / size
    cairo_translate(context, (width - size * scale) / 2, (height - size * scale) / 2)
    cairo_scale(context, scale, scale)
    cairo_set_line_width(context, 1.5)
    cairo_set_line_cap(context, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_join(context, CAIRO_LINE_JOIN_ROUND)

    switch tool {
    case .select:
      cairo_move_to(context, 3, 2)
      cairo_line_to(context, 13, 8.5)
      cairo_line_to(context, 8.8, 9.6)
      cairo_line_to(context, 11, 14)
      cairo_line_to(context, 9, 15)
      cairo_line_to(context, 6.8, 10.6)
      cairo_line_to(context, 3, 13.5)
      cairo_close_path(context)
      cairo_fill(context)
    case .rectangle:
      addRoundedRectangle(context, x: 1.75, y: 3.25, width: 12.5, height: 9.5, radius: 2.5)
      cairo_stroke(context)
    case .circle:
      cairo_new_sub_path(context)
      cairo_arc(context, 8, 8, 6.25, 0, 2 * .pi)
      cairo_stroke(context)
    case .text:
      cairo_set_line_width(context, 1.8)
      cairo_move_to(context, 3, 3)
      cairo_line_to(context, 13, 3)
      cairo_move_to(context, 8, 3)
      cairo_line_to(context, 8, 14)
      cairo_move_to(context, 5.5, 14)
      cairo_line_to(context, 10.5, 14)
      cairo_stroke(context)
    case .connector:
      cairo_move_to(context, 3, 4)
      cairo_curve_to(context, 10, 4, 6, 12, 13, 12)
      cairo_stroke(context)
      cairo_new_sub_path(context)
      cairo_arc(context, 3, 4, 1.75, 0, 2 * .pi)
      cairo_fill(context)
      cairo_new_sub_path(context)
      cairo_arc(context, 13, 12, 1.75, 0, 2 * .pi)
      cairo_fill(context)
    }
  }

  nonisolated static func addRoundedRectangle(
    _ context: OpaquePointer, x: Double, y: Double, width: Double, height: Double, radius: Double
  ) {
    let r = min(radius, width / 2, height / 2)
    cairo_new_sub_path(context)
    cairo_arc(context, x + width - r, y + r, r, -.pi / 2, 0)
    cairo_arc(context, x + width - r, y + height - r, r, 0, .pi / 2)
    cairo_arc(context, x + r, y + height - r, r, .pi / 2, .pi)
    cairo_arc(context, x + r, y + r, r, .pi, 3 * .pi / 2)
    cairo_close_path(context)
  }
}
