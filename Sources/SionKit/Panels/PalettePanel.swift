#if canImport(AppKit)
  import AppKit

  private enum PaletteMetrics {
    static let headerHeight: CGFloat = 24
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 1
    static let closeButtonSize: CGFloat = 18
    static let horizontalInset: CGFloat = 7
  }

  /// Native, compact chrome around a borderless palette panel.
  @MainActor
  final class PalettePanelViewController: NSViewController {
    var onClose: (@MainActor () -> Void)? {
      didSet { chrome.onClose = onClose }
    }

    private let chrome: PaletteChromeView
    private var embeddedController: NSViewController?

    init(title: String) {
      chrome = PaletteChromeView(title: title)

      super.init(nibName: nil, bundle: nil)
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
      paletteViewController = PalettePanelViewController(title: definition.title)

      var styleMask: NSWindow.StyleMask = [.borderless, .closable, .nonactivatingPanel]
      if case .resizable = definition.sizing {
        styleMask.insert(.resizable)
      }

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
      contentViewController = paletteViewController

      configureSizing(definition.sizing, preferredContentSize: panelSize)

      // Center first; setFrameAutosaveName restores a previous placement.
      center()
      _ = setFrameAutosaveName(Self.frameAutosavePrefix + definition.kind.identifier)
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
      }
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

    init(title: String) {
      titleLabel = NSTextField(labelWithString: title)

      super.init(frame: .zero)

      configureAppearance()
      configureHeader(title: title)
      configureLayout()
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

    private func configureLayout() {
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

    override func hitTest(_ point: NSPoint) -> NSView? {
      guard bounds.contains(point) else { return nil }
      guard let interactiveControl else { return self }

      let controlPoint = convert(point, to: interactiveControl)
      return interactiveControl.hitTest(controlPoint) ?? self
    }

    override func mouseDown(with event: NSEvent) {
      window?.performDrag(with: event)
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
