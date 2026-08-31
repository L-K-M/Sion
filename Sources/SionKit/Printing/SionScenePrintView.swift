#if canImport(AppKit)
  import AppKit
  import SionCore

  /// Prints the drawing itself: the content bounds scaled to fit one page and
  /// centered, with no grid, selection handles, magnets, or marquee.
  ///
  /// The canvas color stays behind too. On screen it is the surface the drawing
  /// sits on; on paper it would be a slab of ink around the drawing, and paper
  /// is the surface already.
  ///
  /// The view is deliberately not flipped, so its coordinate system matches a
  /// plain bitmap context. The model's y-down flip is applied explicitly below,
  /// exactly as offscreen rendering does, which keeps printed output and test
  /// output identical.
  @MainActor
  final class SionScenePrintView: NSView {
    private let contentBounds: SionRect
    private let drawScene: SionSceneDrawing

    init(
      contentBounds: SionRect,
      pageSize: NSSize,
      drawScene: @escaping SionSceneDrawing
    ) {
      self.contentBounds = contentBounds.standardized
      self.drawScene = drawScene

      super.init(frame: NSRect(origin: .zero, size: pageSize))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is unavailable")
    }

    /// The paper area inside the margins Page Setup produced.
    static func printableSize(paperSize: NSSize, margins: NSEdgeInsets) -> NSSize {
      let width = paperSize.width - margins.left - margins.right
      let height = paperSize.height - margins.top - margins.bottom
      guard width > 0, height > 0 else { return paperSize }

      return NSSize(width: width, height: height)
    }

    static func printableSize(for printInfo: NSPrintInfo) -> NSSize {
      printableSize(
        paperSize: printInfo.paperSize,
        margins: NSEdgeInsets(
          top: printInfo.topMargin,
          left: printInfo.leftMargin,
          bottom: printInfo.bottomMargin,
          right: printInfo.rightMargin
        )
      )
    }

    /// The drawing is scaled to fit, never tiled, so there is exactly one page.
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
      range.pointee = NSRange(location: 1, length: 1)
      return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
      bounds
    }

    override func draw(_ dirtyRect: NSRect) {
      guard let context = NSGraphicsContext.current,
        contentBounds.width > 0,
        contentBounds.height > 0
      else {
        return
      }

      let scale = min(
        bounds.width / CGFloat(contentBounds.width),
        bounds.height / CGFloat(contentBounds.height)
      )
      guard scale.isFinite, scale > 0 else { return }

      let drawnWidth = CGFloat(contentBounds.width) * scale
      let drawnHeight = CGFloat(contentBounds.height) * scale
      let originX = bounds.minX + ((bounds.width - drawnWidth) / 2)
      let originY = bounds.minY + ((bounds.height - drawnHeight) / 2)

      defer { NSGraphicsContext.current = context }

      let cgContext = context.cgContext
      cgContext.saveGState()
      defer { cgContext.restoreGState() }

      // Map the y-down model into the page's y-up points.
      cgContext.translateBy(x: originX, y: originY + drawnHeight)
      cgContext.scaleBy(x: scale, y: -scale)
      cgContext.translateBy(
        x: CGFloat(-contentBounds.minX),
        y: CGFloat(-contentBounds.minY)
      )
      let drawingContext = NSGraphicsContext(cgContext: cgContext, flipped: true)
      NSGraphicsContext.current = drawingContext

      drawScene(contentBounds, false)
      drawingContext.flushGraphics()
    }
  }
#endif
