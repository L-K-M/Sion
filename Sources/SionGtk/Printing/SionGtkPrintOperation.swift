import CGtk
import CSionGtkShim
import Foundation
import SionCore

/// Prints the drawing itself: the content bounds scaled to fit one page and
/// centred, with no grid, selection handles, magnets, or marquee, and without
/// the canvas colour, because paper is the surface already. Page Setup edits
/// the page setup and print settings the document keeps between jobs.
@MainActor
package final class SionGtkPrintOperation {
  private var pageSetup: OpaquePointer?
  private var printSettings: OpaquePointer?

  package init() {}

  deinit {
    if let pageSetup { g_object_unref(pageSetup.gobject) }
    if let printSettings { g_object_unref(printSettings.gobject) }
  }

  package func runPageSetup(parent: UnsafeMutablePointer<GtkWindow>?) {
    ensureSettings()
    let updated = gtk_print_run_page_setup_dialog(parent, pageSetup, printSettings)
    if let pageSetup { g_object_unref(pageSetup.gobject) }
    pageSetup = updated
  }

  /// The paper area inside the margins Page Setup produced.
  package static func printableSize(
    paperSize: SionSize, margins: (top: Double, left: Double, bottom: Double, right: Double)
  )
    -> SionSize
  {
    let width = paperSize.width - margins.left - margins.right
    let height = paperSize.height - margins.top - margins.bottom
    guard width > 0, height > 0 else { return paperSize }

    return SionSize(width: width, height: height)
  }

  /// The transform that fits `content` into a page of `pageSize`, centred.
  package static func fittedPlacement(content: SionRect, pageSize: SionSize)
    -> (scale: Double, origin: SionPoint)?
  {
    let bounds = content.standardized
    guard bounds.width > 0, bounds.height > 0, pageSize.width > 0, pageSize.height > 0 else {
      return nil
    }
    let scale = min(pageSize.width / bounds.width, pageSize.height / bounds.height)
    guard scale.isFinite, scale > 0 else { return nil }
    let drawnWidth = bounds.width * scale
    let drawnHeight = bounds.height * scale
    return (
      scale,
      SionPoint(x: (pageSize.width - drawnWidth) / 2, y: (pageSize.height - drawnHeight) / 2)
    )
  }

  /// Draws `content` fitted and centred into a Cairo context of `pageSize`.
  package static func drawPage(
    _ context: OpaquePointer, content: SionRect, pageSize: SionSize, draw: SionGtkSceneDrawing
  ) {
    guard let placement = fittedPlacement(content: content, pageSize: pageSize) else { return }
    let bounds = content.standardized
    cairo_save(context)
    cairo_translate(context, placement.origin.x, placement.origin.y)
    cairo_scale(context, placement.scale, placement.scale)
    cairo_translate(context, -bounds.minX, -bounds.minY)
    draw(context, bounds, false)
    cairo_restore(context)
  }

  package func print(
    jobTitle: String,
    contentBounds: SionRect,
    draw: @escaping SionGtkSceneDrawing,
    parent: UnsafeMutablePointer<GtkWindow>?,
    completion: @escaping @MainActor (Error?) -> Void
  ) {
    ensureSettings()
    guard let operation = gtk_print_operation_new() else {
      completion(SionExportError.contextUnavailable)
      return
    }
    gtk_print_operation_set_n_pages(operation, 1)
    gtk_print_operation_set_job_name(operation, jobTitle)
    gtk_print_operation_set_embed_page_setup(operation, 1)
    gtk_print_operation_set_default_page_setup(operation, pageSetup)
    gtk_print_operation_set_print_settings(operation, printSettings)

    let content = contentBounds.standardized
    Self.connectDrawPage(operation.gobject) { printContext in
      guard let printContext, let cairo = gtk_print_context_get_cairo_context(printContext) else {
        return
      }
      let pageSize = SionSize(
        width: gtk_print_context_get_width(printContext),
        height: gtk_print_context_get_height(printContext))
      Self.drawPage(cairo, content: content, pageSize: pageSize, draw: draw)
    }
    Self.connectDone(operation.gobject) { [weak self] result in
      defer { g_object_unref(operation.gobject) }
      if result == GTK_PRINT_OPERATION_RESULT_ERROR {
        var raw: UnsafeMutablePointer<GError>?
        gtk_print_operation_get_error(operation, &raw)
        if let raw {
          let swiftError = GLibError(raw)
          g_error_free(raw)
          completion(swiftError)
        } else {
          completion(SionExportError.contextUnavailable)
        }
        return
      }
      if result == GTK_PRINT_OPERATION_RESULT_APPLY, let self,
        let settings = gtk_print_operation_get_print_settings(operation)
      {
        if let old = self.printSettings { g_object_unref(old.gobject) }
        g_object_ref(settings.gobject)
        self.printSettings = settings
      }
      completion(nil)
    }
    gtk_print_operation_set_allow_async(operation, 1)
    g_object_ref(operation.gobject)
    let result = try? GLibError.check { error in
      gtk_print_operation_run(operation, GTK_PRINT_OPERATION_ACTION_PRINT_DIALOG, parent, error)
    }
    if result == nil {
      g_object_unref(operation.gobject)
      completion(SionExportError.contextUnavailable)
    }
  }

  private func ensureSettings() {
    if pageSetup == nil {
      pageSetup = gtk_page_setup_new()
    }
    if printSettings == nil {
      printSettings = gtk_print_settings_new()
    }
  }

  /// `(operation, GtkPrintContext *, int page, user_data)`.
  private static func connectDrawPage(
    _ instance: gpointer, handler: @escaping @MainActor (OpaquePointer?) -> Void
  ) {
    typealias Handler = @MainActor (OpaquePointer?) -> Void
    let trampoline: @convention(c) (gpointer?, OpaquePointer?, gint, gpointer?) -> Void = {
      _, context, _, data in
      let box = SignalBox<Handler>.from(data)
      MainActor.assumeIsolated { box.handler(context) }
    }
    _ = sion_signal_connect(
      instance, "draw-page", unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, 0)
  }

  /// `(operation, GtkPrintOperationResult, user_data)`.
  private static func connectDone(
    _ instance: gpointer, handler: @escaping @MainActor (GtkPrintOperationResult) -> Void
  ) {
    typealias Handler = @MainActor (GtkPrintOperationResult) -> Void
    let trampoline: @convention(c) (gpointer?, GtkPrintOperationResult, gpointer?) -> Void = {
      _, result, data in
      let box = SignalBox<Handler>.from(data)
      MainActor.assumeIsolated { box.handler(result) }
    }
    _ = sion_signal_connect(
      instance, "done", unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, 0)
  }
}
