import CGtk
import CSionGtkShim
import Foundation
import SionKit

/// Shows editor feedback as a banner floating over the canvas, mirroring
/// `SionEditorFeedbackPresenter`: one banner at a time, dismissed by its
/// button or by a later success in the same context.
@MainActor
package final class SionGtkEditorFeedbackPresenter {
  package typealias AnnouncementHandler = @MainActor (String) -> Void

  private weak var overlayStorage: AnyObject?
  private var overlay: UnsafeMutablePointer<GtkWidget>?
  private var banner: UnsafeMutablePointer<GtkWidget>?
  private var pendingFeedback: SionEditorFeedback?
  package private(set) var presentedContext: SionEditorFeedback.Context?
  package private(set) var presentedMessage: String?
  private let announcementHandler: AnnouncementHandler?

  package init() {
    announcementHandler = nil
  }

  package init(announcementHandler: @escaping AnnouncementHandler) {
    self.announcementHandler = announcementHandler
  }

  /// Hosts the banner in a `GtkOverlay` above the scrolled canvas.
  package func attach(to overlay: UnsafeMutablePointer<GtkWidget>) {
    self.overlay = overlay

    guard let pendingFeedback else { return }

    self.pendingFeedback = nil
    show(pendingFeedback)
  }

  package func handle(_ request: SionEditorFeedbackRequest) {
    switch request {
    case .show(let feedback):
      present(feedback)
    case .clear(let context):
      clear(context)
    }
  }

  private func present(_ feedback: SionEditorFeedback) {
    guard overlay != nil else {
      pendingFeedback = feedback
      return
    }

    show(feedback)
  }

  private func clear(_ context: SionEditorFeedback.Context) {
    if pendingFeedback?.context == context {
      pendingFeedback = nil
    }

    guard presentedContext == context else { return }

    dismissFeedback()
  }

  package func invalidate() {
    pendingFeedback = nil
    dismissFeedback()
    overlay = nil
  }

  private func show(_ feedback: SionEditorFeedback) {
    guard let overlay else { return }
    dismissFeedback()

    let banner = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
    gtk_widget_add_css_class(banner, "osd")
    gtk_widget_add_css_class(banner, "toolbar")
    gtk_widget_set_halign(banner, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(banner, GTK_ALIGN_START)
    gtk_widget_set_margin_top(banner, 12)
    gtk_widget_set_margin_start(banner, 16)
    gtk_widget_set_margin_end(banner, 16)

    let label = gtk_label_new(feedback.message)!
    gtk_label_set_wrap(label.opaque, 1)
    gtk_label_set_xalign(label.opaque, 0)
    gtk_widget_set_margin_start(label, 8)
    gtk_widget_set_margin_top(label, 4)
    gtk_widget_set_margin_bottom(label, 4)
    gtk_box_append(banner.cast(), label)

    let dismiss = gtk_button_new_from_icon_name("window-close-symbolic")!
    gtk_widget_add_css_class(dismiss, "flat")
    gtk_widget_add_css_class(dismiss, "circular")
    gtk_widget_set_tooltip_text(dismiss, FeedbackCopy.dismiss)
    sion_accessible_set_label(dismiss.opaque, FeedbackCopy.dismiss)
    gtk_widget_set_valign(dismiss, GTK_ALIGN_CENTER)
    Signals.connect(dismiss.gobject, "clicked") { [weak self] in
      self?.dismissFeedback()
    }
    gtk_box_append(banner.cast(), dismiss)

    gtk_overlay_add_overlay(overlay.opaque, banner)
    self.banner = banner
    presentedContext = feedback.context
    presentedMessage = feedback.message

    if let announcementHandler {
      announcementHandler(feedback.message)
    } else {
      gtk_accessible_announce(
        label.opaque, feedback.message, GTK_ACCESSIBLE_ANNOUNCEMENT_PRIORITY_HIGH)
    }
  }

  package func dismissFeedback() {
    if let banner, let overlay {
      gtk_overlay_remove_overlay(overlay.opaque, banner)
    }
    banner = nil
    presentedContext = nil
    presentedMessage = nil
  }

  private enum FeedbackCopy {
    static let dismiss = "Dismiss notification"
  }
}
