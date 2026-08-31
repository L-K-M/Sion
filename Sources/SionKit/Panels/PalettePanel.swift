#if canImport(AppKit)
  import AppKit

  private enum PaletteMetrics {
    static let headerHeight: CGFloat = 24
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 1
    static let closeButtonSize: CGFloat = 18
    static let horizontalInset: CGFloat = 7
    /// Past any display, but stated rather than left to whatever an unset
    /// `contentMaxSize` reports: the drag below clamps against it.
    static let maximumContentSize = NSSize(width: 10_000, height: 10_000)
  }

  /// Native, compact chrome around a borderless palette panel.
  @MainActor
  final class PalettePanelViewController: NSViewController {
    var onClose: (@MainActor () -> Void)? {
      didSet { chrome.onClose = onClose }
    }

    private let chrome: PaletteChromeView
    private var embeddedController: NSViewController?

    init(title: String, contentSize: NSSize, isResizable: Bool) {
      chrome = PaletteChromeView(
        title: title,
        contentSize: contentSize,
        isResizable: isResizable
      )

      super.init(nibName: nil, bundle: nil)

      // A borderless panel has no title bar of its own to size it, so the
      // chrome states the size the window should open at.
      preferredContentSize = NSSize(
        width: contentSize.width,
        height: contentSize.height + PaletteMetrics.headerHeight
      )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
      view = chrome
    }

    func embed(_ controller: NSViewController) {
      guard embeddedController !== controller else { return }

      embeddedController?.removeFromParent()
      embeddedController = controller
      addChild(controller)
      chrome.embed(controller.view)
    }
  }

  /// A nonactivating utility window that becomes key only for controls that need it.
  @MainActor
  final class PalettePanel: NSPanel {
    private static let frameAutosavePrefix = "Sion.palette."

    private let paletteViewController: PalettePanelViewController

    init(definition: PaletteDefinition) {
      var styleMask: NSWindow.StyleMask = [.borderless, .closable, .nonactivatingPanel]
      var isResizable = false
      if case .resizable = definition.sizing {
        styleMask.insert(.resizable)
        isResizable = true
      }

      paletteViewController = PalettePanelViewController(
        title: definition.title,
        contentSize: definition.contentSize,
        isResizable: isResizable
      )

      let panelSize = NSSize(
        width: definition.contentSize.width,
        height: definition.contentSize.height + PaletteMetrics.headerHeight
      )

      super.init(
        contentRect: NSRect(origin: .zero, size: panelSize),
        styleMask: styleMask,
        backing: .buffered,
        defer: false
      )

      title = definition.title
      isFloatingPanel = true
      level = .floating
      becomesKeyOnlyIfNeeded = true
      hidesOnDeactivate = true
      isOpaque = false
      backgroundColor = .clear
      hasShadow = true
      isReleasedWhenClosed = false
      isMovable = true
      isMovableByWindowBackground = false
      collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
      animationBehavior = .utilityWindow

      // The limits go in before the content view controller, which resizes the
      // window to the controller's preferred size as it is attached.
      configureSizing(definition.sizing, preferredContentSize: panelSize)
      contentViewController = paletteViewController

      // Center first; setFrameAutosaveName restores a previous placement.
      center()
      _ = setFrameAutosaveName(Self.frameAutosavePrefix + definition.kind.identifier)
      growToMinimumContentSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is unavailable")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performClose(_ sender: Any?) {
      close()
    }

    override func cancelOperation(_ sender: Any?) {
      close()
    }

    func embed(_ controller: NSViewController) {
      paletteViewController.embed(controller)
    }

    func setCloseHandler(_ handler: @escaping @MainActor () -> Void) {
      paletteViewController.onClose = handler
    }

    private func configureSizing(_ sizing: PaletteSizing, preferredContentSize: NSSize) {
      switch sizing {
      case .fixed:
        contentMinSize = preferredContentSize
        contentMaxSize = preferredContentSize

      case .resizable(let minimumContentSize):
        contentMinSize = NSSize(
          width: minimumContentSize.width,
          height: minimumContentSize.height + PaletteMetrics.headerHeight
        )
        contentMaxSize = PaletteMetrics.maximumContentSize
      }
    }

    /// A frame restored from user defaults can be smaller than the palette can
    /// show anything in — one saved by a build that collapsed the panel, say.
    /// Growing back is the only way out for a palette the user cannot resize.
    private func growToMinimumContentSize() {
      let current = contentRect(forFrameRect: frame).size
      guard current.width < contentMinSize.width || current.height < contentMinSize.height else {
        return
      }

      let grown = frameRect(
        forContentRect: NSRect(
          origin: .zero,
          size: NSSize(
            width: max(current.width, contentMinSize.width),
            height: max(current.height, contentMinSize.height)
          )
        )
      )

      // Anchored at the top-left, then held on screen: the position the frame
      // grew from is as arbitrary as its size was, and a palette hanging off
      // the edge is as far out of reach as one collapsed to its header. The
      // window may be on no screen at all, which is why the main one stands in.
      let anchored = NSRect(
        x: frame.minX,
        y: frame.maxY - grown.height,
        width: grown.width,
        height: grown.height
      )
      let visible = (screen ?? NSScreen.main)?.visibleFrame

      // One frame change, so nothing observing the window sees it half moved.
      setFrame(visible.map { Self.constrained(anchored, to: $0) } ?? anchored, display: false)
    }

    /// Slides `rect` inside `visible` without resizing it.
    ///
    /// A rect that does not fit gives up a different edge per axis. Too wide
    /// starts at the leading edge, since the header runs the whole width and
    /// stays grabbable from either end. Too tall keeps its top edge on screen
    /// and lets the body hang off the bottom: the body scrolls, and the header
    /// is the only handle the panel has.
    static func constrained(_ rect: NSRect, to visible: NSRect) -> NSRect {
      NSRect(
        origin: NSPoint(
          x: min(max(rect.minX, visible.minX), max(visible.minX, visible.maxX - rect.width)),
          y: min(max(rect.minY, visible.minY), visible.maxY - rect.height)
        ),
        size: rect.size
      )
    }
  }

  /// The header uses standard controls so keyboard focus and VoiceOver stay native.
  @MainActor
  private final class PaletteChromeView: NSView {
    var onClose: (@MainActor () -> Void)?

    private let header = PaletteHeaderView()
    private let titleLabel: NSTextField
    private let closeButton = PaletteCloseButton()
    private let contentHost = NSView()
    private weak var embeddedView: NSView?

    init(title: String, contentSize: NSSize, isResizable: Bool) {
      titleLabel = NSTextField(labelWithString: title)

      super.init(frame: .zero)

      configureAppearance()
      configureHeader(title: title)
      configureLayout(contentSize: contentSize)

      guard isResizable else { return }

      installResizeBorder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is unavailable")
    }

    override func viewDidChangeEffectiveAppearance() {
      super.viewDidChangeEffectiveAppearance()

      updateLayerColors()
    }

    func embed(_ view: NSView) {
      guard embeddedView !== view else { return }

      embeddedView?.removeFromSuperview()
      embeddedView = view
      view.translatesAutoresizingMaskIntoConstraints = false
      contentHost.addSubview(view)

      NSLayoutConstraint.activate([
        view.topAnchor.constraint(equalTo: contentHost.topAnchor),
        view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
        view.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
      ])
    }

    private func configureAppearance() {
      wantsLayer = true
      layer?.cornerRadius = PaletteMetrics.cornerRadius
      layer?.borderWidth = PaletteMetrics.borderWidth
      layer?.masksToBounds = true
      setAccessibilityElement(false)
      updateLayerColors()
    }

    private func updateLayerColors() {
      effectiveAppearance.performAsCurrentDrawingAppearance {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
      }
    }

    private func configureHeader(title: String) {
      header.material = .headerView
      header.blendingMode = .withinWindow
      header.state = .active
      header.setAccessibilityElement(true)
      header.setAccessibilityRole(.group)
      header.setAccessibilityLabel("\(title) palette header")

      titleLabel.alignment = .center
      titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
      titleLabel.lineBreakMode = .byTruncatingTail
      titleLabel.maximumNumberOfLines = 1

      closeButton.image = NSImage(
        systemSymbolName: "xmark.circle.fill",
        accessibilityDescription: "Close \(title) palette"
      )
      closeButton.imagePosition = .imageOnly
      closeButton.isBordered = false
      closeButton.contentTintColor = .secondaryLabelColor
      closeButton.focusRingType = .default
      closeButton.toolTip = "Close \(title) Palette"
      closeButton.target = self
      closeButton.action = #selector(closePalette)
      closeButton.setAccessibilityLabel("Close \(title) palette")
      header.interactiveControl = closeButton
    }

    private func configureLayout(contentSize: NSSize) {
      for child in [header, contentHost] {
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
      }

      for child in [closeButton, titleLabel] {
        child.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(child)
      }

      NSLayoutConstraint.activate([
        header.topAnchor.constraint(equalTo: topAnchor),
        header.leadingAnchor.constraint(equalTo: leadingAnchor),
        header.trailingAnchor.constraint(equalTo: trailingAnchor),
        header.heightAnchor.constraint(equalToConstant: PaletteMetrics.headerHeight),

        closeButton.leadingAnchor.constraint(
          equalTo: header.leadingAnchor,
          constant: PaletteMetrics.horizontalInset
        ),
        closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        closeButton.widthAnchor.constraint(equalToConstant: PaletteMetrics.closeButtonSize),
        closeButton.heightAnchor.constraint(equalToConstant: PaletteMetrics.closeButtonSize),

        titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor),
        titleLabel.trailingAnchor.constraint(
          equalTo: header.trailingAnchor,
          constant: -(PaletteMetrics.closeButtonSize + PaletteMetrics.horizontalInset)
        ),
        titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

        contentHost.topAnchor.constraint(equalTo: header.bottomAnchor),
        contentHost.leadingAnchor.constraint(equalTo: leadingAnchor),
        contentHost.trailingAnchor.constraint(equalTo: trailingAnchor),
        contentHost.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])

      applyDeclaredSize(contentSize)
    }

    /// A borderless window has no frame view to resize it from, so the panel
    /// grows its own edges: an overlay that claims only a band along the sides
    /// and the bottom and lets every other point through to the palette below.
    /// The top edge is left to the header, which drags the panel.
    private func installResizeBorder() {
      let border = PaletteResizeBorderView()
      border.translatesAutoresizingMaskIntoConstraints = false
      addSubview(border)

      NSLayoutConstraint.activate([
        border.topAnchor.constraint(equalTo: topAnchor),
        border.leadingAnchor.constraint(equalTo: leadingAnchor),
        border.trailingAnchor.constraint(equalTo: trailingAnchor),
        border.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    /// The embedded palette bodies scroll, so they contribute no height of
    /// their own: left at that, the chrome fits its header alone and a panel
    /// that takes its size from its content opens as a bare title bar.
    ///
    /// The priority sits below `windowSizeStayPut`, so a resizable panel's own
    /// frame still wins once the user drags its edge.
    private func applyDeclaredSize(_ contentSize: NSSize) {
      let size = [
        contentHost.widthAnchor.constraint(equalToConstant: contentSize.width),
        contentHost.heightAnchor.constraint(equalToConstant: contentSize.height),
      ]
      for constraint in size {
        constraint.priority = .defaultLow
      }

      NSLayoutConstraint.activate(size)
    }

    @objc private func closePalette() {
      onClose?()
    }
  }

  /// Empty header regions drag the panel; controls retain normal event handling.
  @MainActor
  private final class PaletteHeaderView: NSVisualEffectView {
    weak var interactiveControl: NSControl?

    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
      true
    }

    /// `point` arrives in the superview's coordinates, so it has to be
    /// converted before it means anything here: comparing it against `bounds`
    /// as it stands misses every header that is not at the origin, which is
    /// every header on a panel taller than its own title bar.
    override func hitTest(_ point: NSPoint) -> NSView? {
      let localPoint = convert(point, from: superview)
      guard bounds.contains(localPoint) else { return nil }
      guard let interactiveControl else { return self }

      // The control is a subview, so it hit-tests in this view's coordinates.
      return interactiveControl.hitTest(localPoint) ?? self
    }

    override func mouseDown(with event: NSEvent) {
      window?.performDrag(with: event)
    }
  }

  /// Drags the window's own edges, standing in for the frame view a borderless
  /// window does not have.
  @MainActor
  final class PaletteResizeBorderView: NSView {
    /// How far in from an edge still counts as that edge.
    static let bandWidth: CGFloat = 5

    struct Edges: OptionSet {
      let rawValue: Int

      static let left = Edges(rawValue: 1 << 0)
      static let right = Edges(rawValue: 1 << 1)
      static let bottom = Edges(rawValue: 1 << 2)
    }

    private struct ResizeDrag {
      let edges: Edges
      let startFrame: NSRect
      let startLocation: NSPoint
    }

    private var drag: ResizeDrag?

    /// The overlay covers the whole palette, so anything that is not on a band
    /// has to fall through to the content underneath it.
    override func hitTest(_ point: NSPoint) -> NSView? {
      let localPoint = convert(point, from: superview)
      guard !Self.edges(at: localPoint, in: bounds).isEmpty else { return nil }

      return self
    }

    override func resetCursorRects() {
      let band = Self.bandWidth

      addCursorRect(
        NSRect(x: bounds.minX, y: bounds.minY, width: band, height: bounds.height),
        cursor: .resizeLeftRight
      )
      addCursorRect(
        NSRect(x: bounds.maxX - band, y: bounds.minY, width: band, height: bounds.height),
        cursor: .resizeLeftRight
      )
      // Added last so the corners, where the bands overlap, read as the edge
      // that is only ever dragged one way.
      addCursorRect(
        NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: band),
        cursor: .resizeUpDown
      )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
      true
    }

    /// The header above this view moves the panel on mouse-down; a band has to
    /// keep the press for itself to resize with it.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
      guard let window else { return }

      let edges = Self.edges(at: convert(event.locationInWindow, from: nil), in: bounds)
      guard !edges.isEmpty else { return }

      drag = ResizeDrag(
        edges: edges,
        startFrame: window.frame,
        startLocation: window.convertPoint(toScreen: event.locationInWindow)
      )
    }

    override func mouseDragged(with event: NSEvent) {
      guard let drag, let window else { return }

      // Screen coordinates, because resizing from a leading or bottom edge
      // moves the window's own origin out from under the pointer.
      let location = window.convertPoint(toScreen: event.locationInWindow)
      let frame = Self.resizedFrame(
        drag.startFrame,
        edges: drag.edges,
        translation: NSSize(
          width: location.x - drag.startLocation.x,
          height: location.y - drag.startLocation.y
        ),
        minimum: Self.frameSize(forContentSize: window.contentMinSize, of: window),
        maximum: Self.frameSize(forContentSize: window.contentMaxSize, of: window)
      )

      window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
      drag = nil
    }

    /// The bands a point lies on, empty everywhere else. The top is missing on
    /// purpose: the header owns it, and dragging it moves the panel.
    static func edges(
      at point: NSPoint,
      in bounds: NSRect,
      bandWidth: CGFloat = PaletteResizeBorderView.bandWidth
    ) -> Edges {
      guard bounds.contains(point) else { return [] }

      var edges = Edges()
      if point.x - bounds.minX <= bandWidth {
        edges.insert(.left)
      }
      if bounds.maxX - point.x <= bandWidth {
        edges.insert(.right)
      }
      if point.y - bounds.minY <= bandWidth {
        edges.insert(.bottom)
      }

      return edges
    }

    /// The edges opposite the dragged ones stay put, so the palette grows away
    /// from the pointer rather than sliding under it. The top edge is opposite
    /// every band there is, which is what keeps the header in place.
    static func resizedFrame(
      _ startFrame: NSRect,
      edges: Edges,
      translation: NSSize,
      minimum: NSSize,
      maximum: NSSize
    ) -> NSRect {
      var width = startFrame.width
      if edges.contains(.left) {
        width -= translation.width
      }
      if edges.contains(.right) {
        width += translation.width
      }

      var height = startFrame.height
      if edges.contains(.bottom) {
        height -= translation.height
      }

      width = clamped(width, minimum: minimum.width, maximum: maximum.width)
      height = clamped(height, minimum: minimum.height, maximum: maximum.height)

      return NSRect(
        x: edges.contains(.left) ? startFrame.maxX - width : startFrame.minX,
        y: startFrame.maxY - height,
        width: width,
        height: height
      )
    }

    /// A maximum below the minimum would otherwise pin the palette under the
    /// size it needs; an unset one is already larger than any screen.
    private static func clamped(
      _ value: CGFloat,
      minimum: CGFloat,
      maximum: CGFloat
    ) -> CGFloat {
      min(max(value, minimum), max(minimum, maximum))
    }

    private static func frameSize(forContentSize contentSize: NSSize, of window: NSWindow) -> NSSize
    {
      window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    }
  }

  /// Floating palettes close on the first click without activating the app window.
  @MainActor
  private final class PaletteCloseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
      true
    }
  }
#endif
