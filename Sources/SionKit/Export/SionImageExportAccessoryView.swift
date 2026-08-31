#if canImport(AppKit)
  import AppKit

  /// Format, scale, and background controls hosted by the export save panel.
  /// The document owns presentation; this view only reports chosen options.
  @MainActor
  final class SionImageExportAccessoryView: NSView {
    /// Called whenever the user changes a control.
    var onChange: (@MainActor (SionImageExportOptions) -> Void)?

    private(set) var options = SionImageExportOptions()

    private let formatPopUp = NSPopUpButton()
    private let scalePopUp = NSPopUpButton()
    private let transparencyButton = NSButton(
      checkboxWithTitle: "Transparent Background",
      target: nil,
      action: nil
    )

    init() {
      // The final frame needs the stack, so it is set once that exists.
      super.init(frame: .zero)

      formatPopUp.addItems(withTitles: SionImageExportFormat.allCases.map(\.title))
      formatPopUp.selectItem(at: options.format.rawValue)
      formatPopUp.setAccessibilityLabel("Export format")
      scalePopUp.addItems(withTitles: SionImageExportScale.allCases.map(\.title))
      scalePopUp.selectItem(at: options.scale.rawValue)
      scalePopUp.setAccessibilityLabel("Export scale")
      transparencyButton.state = options.hasTransparentBackground ? .on : .off
      transparencyButton.setAccessibilityLabel("Transparent background")

      for control in [formatPopUp, scalePopUp, transparencyButton] as [NSControl] {
        control.target = self
        control.action = #selector(controlChanged(_:))
      }

      let stack = NSStackView(views: [
        label("Format:"),
        formatPopUp,
        label("Scale:"),
        scalePopUp,
        transparencyButton,
      ])
      stack.orientation = .horizontal
      stack.alignment = .centerY
      stack.spacing = AccessoryMetrics.spacing
      stack.translatesAutoresizingMaskIntoConstraints = false
      addSubview(stack)
      // Centering only: the save panel resizes this view, so a pinned edge
      // would fight the frame-derived constraints it installs.
      NSLayoutConstraint.activate([
        stack.centerXAnchor.constraint(equalTo: centerXAnchor),
        stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      ])
      setFrameSize(
        NSSize(
          width: AccessoryMetrics.width,
          height: stack.fittingSize.height + (AccessoryMetrics.inset * 2)
        )
      )
      synchronizeEnabledState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is unavailable")
    }

    /// Applies a control change and reports the resulting options.
    @objc func controlChanged(_ sender: Any?) {
      options.format =
        SionImageExportFormat(rawValue: formatPopUp.indexOfSelectedItem) ?? options.format
      options.scale =
        SionImageExportScale(rawValue: scalePopUp.indexOfSelectedItem) ?? options.scale
      options.hasTransparentBackground = transparencyButton.state == .on
      synchronizeEnabledState()
      onChange?(options)
    }

    /// Vector output ignores scale, and a format without alpha stays opaque.
    private func synchronizeEnabledState() {
      scalePopUp.isEnabled = options.format.supportsScale
      transparencyButton.isEnabled = options.format.supportsTransparency
    }

    private func label(_ title: String) -> NSTextField {
      let field = NSTextField(labelWithString: title)
      field.textColor = .secondaryLabelColor
      field.setContentHuggingPriority(.required, for: .horizontal)
      return field
    }
  }

  private enum AccessoryMetrics {
    static let width: CGFloat = 520
    static let spacing: CGFloat = 8
    static let inset: CGFloat = 12
  }
#endif
