#if canImport(AppKit)
  import AppKit

  @MainActor
  final class SionEditorFeedbackPresenter {
    typealias AnnouncementHandler = @MainActor (NSView, String) -> Void

    private weak var hostView: NSView?
    private var banner: NSView?
    private var pendingFeedback: SionEditorFeedback?
    private let announcementHandler: AnnouncementHandler

    init() {
      announcementHandler = Self.postAnnouncement
    }

    init(announcementHandler: @escaping AnnouncementHandler) {
      self.announcementHandler = announcementHandler
    }

    func attach(to hostView: NSView) {
      self.hostView = hostView

      guard let pendingFeedback else { return }

      self.pendingFeedback = nil
      show(pendingFeedback, in: hostView)
    }

    func present(_ feedback: SionEditorFeedback) {
      guard let hostView else {
        pendingFeedback = feedback
        return
      }

      show(feedback, in: hostView)
    }

    func invalidate() {
      pendingFeedback = nil
      dismissFeedback()
      hostView = nil
    }

    private func show(_ feedback: SionEditorFeedback, in hostView: NSView) {
      dismissFeedback()

      let messageLabel = NSTextField(wrappingLabelWithString: feedback.message)
      messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

      let dismissButton = NSButton(
        image: NSImage(
          systemSymbolName: "xmark",
          accessibilityDescription: FeedbackCopy.dismiss
        ) ?? NSImage(),
        target: self,
        action: #selector(dismissFeedback)
      )
      dismissButton.isBordered = false
      dismissButton.imagePosition = .imageOnly
      dismissButton.toolTip = FeedbackCopy.dismiss
      dismissButton.setAccessibilityLabel(FeedbackCopy.dismiss)
      dismissButton.setContentHuggingPriority(.required, for: .horizontal)

      let stack = NSStackView(views: [messageLabel, dismissButton])
      stack.alignment = .centerY
      stack.orientation = .horizontal
      stack.spacing = FeedbackMetrics.itemSpacing
      stack.translatesAutoresizingMaskIntoConstraints = false

      let banner = NSVisualEffectView()
      banner.blendingMode = .withinWindow
      banner.material = .popover
      banner.state = .active
      banner.translatesAutoresizingMaskIntoConstraints = false
      banner.wantsLayer = true
      banner.layer?.cornerRadius = FeedbackMetrics.cornerRadius
      banner.layer?.masksToBounds = true
      banner.addSubview(stack)

      // A scroll-view sibling stays fixed while the diagram pans underneath it.
      hostView.addSubview(banner, positioned: .above, relativeTo: nil)
      NSLayoutConstraint.activate([
        stack.topAnchor.constraint(
          equalTo: banner.topAnchor,
          constant: FeedbackMetrics.verticalInset
        ),
        stack.leadingAnchor.constraint(
          equalTo: banner.leadingAnchor,
          constant: FeedbackMetrics.horizontalInset
        ),
        stack.trailingAnchor.constraint(
          equalTo: banner.trailingAnchor,
          constant: -FeedbackMetrics.horizontalInset
        ),
        stack.bottomAnchor.constraint(
          equalTo: banner.bottomAnchor,
          constant: -FeedbackMetrics.verticalInset
        ),
        dismissButton.widthAnchor.constraint(equalToConstant: FeedbackMetrics.buttonSize),
        dismissButton.heightAnchor.constraint(equalToConstant: FeedbackMetrics.buttonSize),
        banner.topAnchor.constraint(
          equalTo: hostView.topAnchor,
          constant: FeedbackMetrics.topInset
        ),
        banner.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
        banner.leadingAnchor.constraint(
          greaterThanOrEqualTo: hostView.leadingAnchor,
          constant: FeedbackMetrics.hostInset
        ),
        banner.trailingAnchor.constraint(
          lessThanOrEqualTo: hostView.trailingAnchor,
          constant: -FeedbackMetrics.hostInset
        ),
      ])
      self.banner = banner

      announcementHandler(messageLabel, feedback.message)
    }

    @objc private func dismissFeedback() {
      banner?.removeFromSuperview()
      banner = nil
    }

    private static func postAnnouncement(on element: NSView, message: String) {
      NSAccessibility.post(
        element: element,
        notification: .announcementRequested,
        userInfo: [
          .announcement: message,
          .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ]
      )
    }
  }

  private enum FeedbackCopy {
    static let dismiss = "Dismiss notification"
  }

  private enum FeedbackMetrics {
    static let buttonSize: CGFloat = 20
    static let cornerRadius: CGFloat = 8
    static let horizontalInset: CGFloat = 12
    static let hostInset: CGFloat = 16
    static let itemSpacing: CGFloat = 8
    static let topInset: CGFloat = 12
    static let verticalInset: CGFloat = 8
  }
#endif
