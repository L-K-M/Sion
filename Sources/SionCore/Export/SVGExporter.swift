import Foundation

public enum SVGExportError: Error, Equatable {
  case missingAsset(AssetID)
  case invalidDisplayAsset(AssetID)
  case outputTooLarge
}

public enum SVGExporter {
  public static func export(
    document: SionDocument,
    assets: [AssetID: SionAsset]
  ) throws -> String {
    let bounds = SceneRenderGeometry.contentBounds(of: document.scene)
    var definitions = [markerDefinitions]
    var definitionByteCount = markerDefinitions.utf8.count
    try appendImageDefinitions(
      document: document,
      assets: assets,
      definitions: &definitions,
      byteCount: &definitionByteCount
    )
    var body = [
      "<rect id=\"canvas-background\" x=\"\(number(bounds.minX))\" y=\"\(number(bounds.minY))\" width=\"\(number(bounds.width))\" height=\"\(number(bounds.height))\" fill=\"\(document.scene.canvas.background.hex)\"/>"
    ]
    var bodyByteCount = body[0].utf8.count

    for element in document.scene.elements where element.visibility == .visible {
      let previousDefinitionCount = definitions.count
      let rendered = try render(
        element,
        scene: document.scene,
        assets: assets,
        definitions: &definitions
      )
      guard !rendered.isEmpty else {
        continue
      }

      for definition in definitions[previousDefinitionCount...] {
        definitionByteCount += definition.utf8.count
      }
      bodyByteCount += rendered.utf8.count
      guard
        fitsOutputBudget(
          definitionByteCount: definitionByteCount,
          bodyByteCount: bodyByteCount
        )
      else {
        throw SVGExportError.outputTooLarge
      }

      body.append(rendered)
    }

    let components = [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(number(bounds.width))\" height=\"\(number(bounds.height))\" viewBox=\"\(number(bounds.minX)) \(number(bounds.minY)) \(number(bounds.width)) \(number(bounds.height))\" role=\"img\" aria-label=\"\(escape(document.title))\">",
      "<defs>\(definitions.joined())</defs>",
      body.joined(separator: "\n"),
      "</svg>",
      "",
    ]
    guard
      components.reduce(components.count - 1, { $0 + $1.utf8.count })
        <= SionArchiveConstants.maximumEntryByteCount
    else {
      throw SVGExportError.outputTooLarge
    }

    return components.joined(separator: "\n")
  }

  private static func appendImageDefinitions(
    document: SionDocument,
    assets: [AssetID: SionAsset],
    definitions: inout [String],
    byteCount: inout Int
  ) throws {
    var embedded = Set<AssetID>()

    for element in document.scene.elements where element.visibility == .visible {
      guard case .image(let content) = element.content,
        embedded.insert(content.displayAssetID).inserted
      else {
        continue
      }
      guard let asset = assets[content.displayAssetID] else {
        throw SVGExportError.missingAsset(content.displayAssetID)
      }
      guard SafeDisplayImage.validates(asset) else {
        throw SVGExportError.invalidDisplayAsset(asset.id)
      }

      let sourceSize = validTileSize(asset.pixelSize) ?? SVGDefaults.fallbackImageSize
      let prefix =
        "<image id=\"\(imageDefinitionID(asset.id))\" width=\"\(number(sourceSize.width))\" height=\"\(number(sourceSize.height))\" href=\"data:image/png;base64,"
      let suffix = "\"/>"
      let encodedByteCount = ((asset.data.count + 2) / 3) * 4
      guard
        byteCount <= SionArchiveConstants.maximumEntryByteCount
          - prefix.utf8.count
          - suffix.utf8.count
          - encodedByteCount
      else {
        throw SVGExportError.outputTooLarge
      }

      let definition = prefix + asset.data.base64EncodedString() + suffix
      definitions.append(definition)
      byteCount += definition.utf8.count
    }
  }

  private static func render(
    _ element: SceneElement,
    scene: SionScene,
    assets: [AssetID: SionAsset],
    definitions: inout [String]
  ) throws -> String {
    switch element.content {
    case .shape(let shape):
      return renderShape(shape, element: element, definitions: &definitions)
    case .path(let path):
      return renderPath(path, element: element, definitions: &definitions)
    case .text(let text):
      return wrapped(
        renderText(text, in: element.geometry.frame),
        element: element,
        definitions: &definitions
      )
    case .image(let image):
      guard let asset = assets[image.displayAssetID] else {
        throw SVGExportError.missingAsset(image.displayAssetID)
      }
      return renderImage(asset, content: image, element: element, definitions: &definitions)
    case .group:
      return ""
    case .connector(let connector):
      guard let route = SceneRenderGeometry.connectorRoute(for: element, in: scene) else {
        return ""
      }
      return renderConnector(
        connector,
        route: route,
        element: element,
        definitions: &definitions
      )
    }
  }

  private static func renderShape(
    _ shape: ShapeContent,
    element: SceneElement,
    definitions: inout [String]
  ) -> String {
    let frame = element.geometry.frame.standardized
    let path = shapePath(shape.kind, frame: frame)
    var content =
      "<path d=\"\(path)\" \(styleAttributes(element, definitions: &definitions))/>"

    if let label = shape.label {
      content += renderText(label, in: frame)
    }

    return wrapped(content, element: element, definitions: &definitions, style: .omit)
  }

  private static func renderPath(
    _ content: PathContent,
    element: SceneElement,
    definitions: inout [String]
  ) -> String {
    let path = vectorPath(content.path, frame: element.geometry.frame.standardized)
    let fillRule = content.path.fillRule == .evenOdd ? "evenodd" : "nonzero"
    let rendered =
      "<path d=\"\(path)\" fill-rule=\"\(fillRule)\" \(styleAttributes(element, definitions: &definitions))/>"

    return wrapped(rendered, element: element, definitions: &definitions, style: .omit)
  }

  private static func renderImage(
    _ asset: SionAsset,
    content: ImageContent,
    element: SceneElement,
    definitions: inout [String]
  ) -> String {
    let frame = element.geometry.frame.standardized
    let description = content.accessibilityDescription.map(escape) ?? "Image"
    let definitionID = imageDefinitionID(asset.id)
    let sourceSize = validTileSize(asset.pixelSize) ?? SVGDefaults.fallbackImageSize
    let aspect: String
    switch content.scalingMode {
    case .fit:
      aspect = "xMidYMid meet"
    case .fill:
      aspect = "xMidYMid slice"
    case .stretch:
      aspect = "none"
    case .tile:
      let patternID = "image-pattern-\(element.id)"
      let tileSize = validTileSize(asset.pixelSize) ?? frame.size
      definitions.append(
        "<pattern id=\"\(patternID)\" patternUnits=\"userSpaceOnUse\" width=\"\(number(tileSize.width))\" height=\"\(number(tileSize.height))\"><svg width=\"\(number(tileSize.width))\" height=\"\(number(tileSize.height))\" viewBox=\"0 0 \(number(sourceSize.width)) \(number(sourceSize.height))\" preserveAspectRatio=\"none\"><use href=\"#\(definitionID)\"/></svg></pattern>"
      )
      let tiled =
        "<rect x=\"\(number(frame.minX))\" y=\"\(number(frame.minY))\" width=\"\(number(frame.width))\" height=\"\(number(frame.height))\" fill=\"url(#\(patternID))\" aria-label=\"\(description)\"/>"
      return wrapped(tiled, element: element, definitions: &definitions)
    }

    let image =
      "<svg x=\"\(number(frame.minX))\" y=\"\(number(frame.minY))\" width=\"\(number(frame.width))\" height=\"\(number(frame.height))\" viewBox=\"0 0 \(number(sourceSize.width)) \(number(sourceSize.height))\" preserveAspectRatio=\"\(aspect)\" aria-label=\"\(description)\"><use href=\"#\(definitionID)\"/></svg>"
    return wrapped(image, element: element, definitions: &definitions)
  }

  private static func imageDefinitionID(_ id: AssetID) -> String {
    "image-asset-"
      + id.rawValue.map { character in
        character.isLetter || character.isNumber || character == "-" || character == "_"
          ? character
          : "-"
      }
  }

  private static func fitsOutputBudget(
    definitionByteCount: Int,
    bodyByteCount: Int
  ) -> Bool {
    let budget = SionArchiveConstants.maximumEntryByteCount
    guard definitionByteCount <= budget - SVGDefaults.envelopeByteAllowance else {
      return false
    }

    return bodyByteCount <= budget - SVGDefaults.envelopeByteAllowance - definitionByteCount
  }

  private static func renderConnector(
    _ connector: ConnectorContent,
    route: ConnectorRoute,
    element: SceneElement,
    definitions: inout [String]
  ) -> String {
    let markerStart = markerAttribute(connector.sourceDecoration, position: .start)
    let markerEnd = markerAttribute(connector.targetDecoration, position: .end)
    let path =
      "<path d=\"\(routePath(route))\" fill=\"none\" \(styleAttributes(element, route: route, definitions: &definitions)) \(markerStart) \(markerEnd)/>"

    guard let label = connector.label else {
      return path
    }

    let point = point(on: route, fraction: connector.labelPosition)
    let labelFrame = SionRect(
      x: point.x - SVGDefaults.connectorLabelWidth / 2,
      y: point.y - SVGDefaults.connectorLabelHeight / 2,
      width: SVGDefaults.connectorLabelWidth,
      height: SVGDefaults.connectorLabelHeight
    )
    return path + renderText(label, in: labelFrame)
  }

  private static func wrapped(
    _ content: String,
    element: SceneElement,
    definitions: inout [String],
    style: WrappedStyle = .apply
  ) -> String {
    let frame = element.geometry.frame.standardized
    let reducedRotation = element.geometry.rotationRadians.truncatingRemainder(
      dividingBy: 2 * .pi
    )
    let rotation = reducedRotation * 180 / .pi
    let transform =
      rotation == 0
      ? ""
      : " transform=\"rotate(\(number(rotation)) \(number(frame.center.x)) \(number(frame.center.y)))\""
    let renderedStyle: String
    switch style {
    case .apply:
      renderedStyle =
        " \(styleAttributes(element, definitions: &definitions))"
    case .omit:
      renderedStyle = ""
    }
    return "<g id=\"element-\(element.id)\"\(transform)\(renderedStyle)>\(content)</g>"
  }

  private static func styleAttributes(
    _ element: SceneElement,
    route: ConnectorRoute? = nil,
    definitions: inout [String]
  ) -> String {
    let style = element.style
    let fill: String
    switch style.fill {
    case .none:
      fill = "none"
    case .solid(let color):
      fill = color.hex
    case .linearGradient(let gradient):
      let gradientID = "gradient-\(element.id)"
      let stops = gradient.stops.map { stop in
        "<stop offset=\"\(number(stop.location * 100))%\" stop-color=\"\(stop.color.hex)\"/>"
      }.joined()
      definitions.append(
        "<linearGradient id=\"\(gradientID)\" x1=\"\(number(gradient.start.x * 100))%\" y1=\"\(number(gradient.start.y * 100))%\" x2=\"\(number(gradient.end.x * 100))%\" y2=\"\(number(gradient.end.y * 100))%\">\(stops)</linearGradient>"
      )
      fill = "url(#\(gradientID))"
    }

    let stroke: String
    if let value = style.stroke {
      let dash =
        value.dashPattern.isEmpty
        ? ""
        : " stroke-dasharray=\"\(value.dashPattern.map(number).joined(separator: " "))\""
      stroke =
        "stroke=\"\(value.color.hex)\" stroke-width=\"\(number(value.width))\" stroke-linecap=\"\(value.lineCap.rawValue)\" stroke-linejoin=\"\(value.lineJoin.rawValue)\"\(dash)"
    } else {
      stroke = "stroke=\"none\""
    }

    var filter = ""
    if let shadow = style.shadows.first {
      let filterID = "shadow-\(element.id)"
      let filterBounds = SceneRenderGeometry.unrotatedPaintedBounds(
        of: element,
        route: route
      )
      definitions.append(
        "<filter id=\"\(filterID)\" filterUnits=\"userSpaceOnUse\" x=\"\(number(filterBounds.minX))\" y=\"\(number(filterBounds.minY))\" width=\"\(number(filterBounds.width))\" height=\"\(number(filterBounds.height))\"><feDropShadow dx=\"\(number(shadow.offset.dx))\" dy=\"\(number(shadow.offset.dy))\" stdDeviation=\"\(number(shadow.blurRadius / 2))\" flood-color=\"\(shadow.color.hex)\"/></filter>"
      )
      filter = " filter=\"url(#\(filterID))\""
    }

    return
      "fill=\"\(fill)\" \(stroke) opacity=\"\(number(style.opacity))\" style=\"mix-blend-mode:\(style.blendMode.rawValue)\"\(filter)"
  }

  private static func renderText(_ text: TextContent, in frame: SionRect) -> String {
    let style = text.style
    let lines = text.string.split(separator: "\n", omittingEmptySubsequences: false).map(
      String.init)
    let lineHeight = style.font.size * SVGDefaults.lineHeightMultiplier
    let textHeight = max(style.font.size, lineHeight * Double(lines.count))

    let x: Double
    let anchor: String
    switch style.horizontalAlignment {
    case .leading, .justified:
      x = frame.minX + style.insets.leading
      anchor = "start"
    case .center:
      x = frame.center.x
      anchor = "middle"
    case .trailing:
      x = frame.maxX - style.insets.trailing
      anchor = "end"
    }

    let firstBaseline: Double
    switch style.verticalAlignment {
    case .top:
      firstBaseline = frame.minY + style.insets.top + style.font.size
    case .center:
      firstBaseline = frame.center.y - (textHeight / 2) + style.font.size
    case .bottom:
      firstBaseline = frame.maxY - style.insets.bottom - textHeight + style.font.size
    }

    let family: String
    switch style.font.family {
    case .system:
      family = "-apple-system, BlinkMacSystemFont, sans-serif"
    case .named(let name):
      family = "\(escapeAttribute(name)), sans-serif"
    }

    let spans = lines.enumerated().map { index, line in
      let y = firstBaseline + (Double(index) * lineHeight)
      return "<tspan x=\"\(number(x))\" y=\"\(number(y))\">\(escape(line))</tspan>"
    }.joined()

    return
      "<text text-anchor=\"\(anchor)\" font-family=\"\(family)\" font-size=\"\(number(style.font.size))\" font-weight=\"\(fontWeight(style.font.weight))\" fill=\"\(style.color.hex)\">\(spans)</text>"
  }

  private static func shapePath(_ kind: ShapeKind, frame: SionRect) -> String {
    let x = frame.minX
    let y = frame.minY
    let width = frame.width
    let height = frame.height
    let centerX = frame.center.x
    let centerY = frame.center.y

    switch kind {
    case .rectangle:
      return "M\(number(x)) \(number(y))H\(number(frame.maxX))V\(number(frame.maxY))H\(number(x))Z"
    case .roundedRectangle(let radius):
      return roundedRectanglePath(
        frame: frame,
        radius: radius.isFinite ? radius : 0
      )
    case .ellipse:
      return
        "M\(number(x)) \(number(centerY))A\(number(width / 2)) \(number(height / 2)) 0 1 0 \(number(frame.maxX)) \(number(centerY))A\(number(width / 2)) \(number(height / 2)) 0 1 0 \(number(x)) \(number(centerY))Z"
    case .capsule:
      return roundedRectanglePath(frame: frame, radius: min(width, height) / 2)
    case .diamond:
      return
        "M\(number(centerX)) \(number(y))L\(number(frame.maxX)) \(number(centerY))L\(number(centerX)) \(number(frame.maxY))L\(number(x)) \(number(centerY))Z"
    case .triangle:
      return
        "M\(number(centerX)) \(number(y))L\(number(frame.maxX)) \(number(frame.maxY))L\(number(x)) \(number(frame.maxY))Z"
    case .hexagon:
      let inset = width * ShapeGeometryDefaults.hexagonInsetFraction
      return
        "M\(number(x + inset)) \(number(y))H\(number(frame.maxX - inset))L\(number(frame.maxX)) \(number(centerY))L\(number(frame.maxX - inset)) \(number(frame.maxY))H\(number(x + inset))L\(number(x)) \(number(centerY))Z"
    case .cylinder:
      let arcHeight = min(height * ShapeGeometryDefaults.cylinderArcFraction, height / 2)
      return
        "M\(number(x)) \(number(y + arcHeight))A\(number(width / 2)) \(number(arcHeight)) 0 0 1 \(number(frame.maxX)) \(number(y + arcHeight))V\(number(frame.maxY - arcHeight))A\(number(width / 2)) \(number(arcHeight)) 0 0 1 \(number(x)) \(number(frame.maxY - arcHeight))Z"
    case .custom(let path):
      return vectorPath(path, frame: frame)
    }
  }

  private static func roundedRectanglePath(frame: SionRect, radius: Double) -> String {
    let r = min(max(0, radius), min(frame.width, frame.height) / 2)
    return
      "M\(number(frame.minX + r)) \(number(frame.minY))H\(number(frame.maxX - r))Q\(number(frame.maxX)) \(number(frame.minY)) \(number(frame.maxX)) \(number(frame.minY + r))V\(number(frame.maxY - r))Q\(number(frame.maxX)) \(number(frame.maxY)) \(number(frame.maxX - r)) \(number(frame.maxY))H\(number(frame.minX + r))Q\(number(frame.minX)) \(number(frame.maxY)) \(number(frame.minX)) \(number(frame.maxY - r))V\(number(frame.minY + r))Q\(number(frame.minX)) \(number(frame.minY)) \(number(frame.minX + r)) \(number(frame.minY))Z"
  }

  private static func vectorPath(_ path: VectorPath, frame: SionRect) -> String {
    func point(_ point: SionPoint) -> SionPoint {
      switch path.coordinateSpace {
      case .normalized:
        return frame.point(atNormalized: point)
      case .localPoints:
        return SionPoint(x: frame.minX + point.x, y: frame.minY + point.y)
      }
    }

    return path.commands.map { command in
      switch command {
      case .move(let to):
        let value = point(to)
        return "M\(number(value.x)) \(number(value.y))"
      case .line(let to):
        let value = point(to)
        return "L\(number(value.x)) \(number(value.y))"
      case .quadratic(let control, let to):
        let first = point(control)
        let second = point(to)
        return "Q\(number(first.x)) \(number(first.y)) \(number(second.x)) \(number(second.y))"
      case .cubic(let control1, let control2, let to):
        let first = point(control1)
        let second = point(control2)
        let third = point(to)
        return
          "C\(number(first.x)) \(number(first.y)) \(number(second.x)) \(number(second.y)) \(number(third.x)) \(number(third.y))"
      case .close:
        return "Z"
      }
    }.joined()
  }

  private static func routePath(_ route: ConnectorRoute) -> String {
    var result = "M\(number(route.start.x)) \(number(route.start.y))"
    for segment in route.segments {
      switch segment {
      case .line(let to):
        result += "L\(number(to.x)) \(number(to.y))"
      case .quadratic(let control, let to):
        result += "Q\(number(control.x)) \(number(control.y)) \(number(to.x)) \(number(to.y))"
      case .cubic(let control1, let control2, let to):
        result +=
          "C\(number(control1.x)) \(number(control1.y)) \(number(control2.x)) \(number(control2.y)) \(number(to.x)) \(number(to.y))"
      }
    }
    return result
  }

  private static func point(on route: ConnectorRoute, fraction: Double) -> SionPoint {
    route.point(atFraction: fraction)
  }

  private enum MarkerPosition: Equatable {
    case start
    case end
  }

  private static func markerAttribute(
    _ decoration: ConnectorDecoration,
    position: MarkerPosition
  ) -> String {
    guard decoration != .none else {
      return ""
    }
    let attribute = position == .start ? "marker-start" : "marker-end"
    return "\(attribute)=\"url(#marker-\(decoration.rawValue))\""
  }

  private static func fontWeight(_ weight: FontWeight) -> Int {
    switch weight {
    case .light: 300
    case .regular: 400
    case .medium: 500
    case .semibold: 600
    case .bold: 700
    }
  }

  private static func number(_ value: Double) -> String {
    guard value.isFinite else {
      return "0"
    }

    let maximumPreciselyRoundedValue = Double(Int.max) / SVGDefaults.numberPrecision
    guard abs(value) <= maximumPreciselyRoundedValue else {
      return String(value)
    }

    let rounded =
      (value * SVGDefaults.numberPrecision).rounded()
      / SVGDefaults.numberPrecision
    if rounded == rounded.rounded(), abs(rounded) <= Double(Int.max) {
      return String(Int(rounded))
    }
    return String(rounded)
  }

  private static func validTileSize(_ size: SionSize?) -> SionSize? {
    guard let size,
      size.isFinite,
      size.width > 0,
      size.height > 0
    else {
      return nil
    }

    return size
  }

  private static func escape(_ value: String) -> String {
    let validXML = value.unicodeScalars.map { scalar in
      XMLScalar.isAllowed(scalar) ? String(scalar) : XMLScalar.replacement
    }.joined()

    return
      validXML
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }

  private static func escapeAttribute(_ value: String) -> String {
    escape(value).replacingOccurrences(of: "'", with: "&apos;")
  }

  private static let markerDefinitions = """
    <marker id="marker-openArrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M1 1L9 5L1 9" fill="none" stroke="context-stroke" stroke-width="1.5"/></marker>
    <marker id="marker-filledArrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10Z" fill="context-stroke"/></marker>
    <marker id="marker-circle" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="7" markerHeight="7"><circle cx="5" cy="5" r="3.5" fill="context-stroke"/></marker>
    <marker id="marker-diamond" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M5 0L10 5L5 10L0 5Z" fill="context-stroke"/></marker>
    """
}

private enum WrappedStyle {
  case apply
  case omit
}

private enum XMLScalar {
  static let replacement = "\u{FFFD}"

  static func isAllowed(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x09, 0x0A, 0x0D,
      0x20...0xD7FF,
      0xE000...0xFFFD,
      0x1_0000...0x10_FFFF:
      return true
    default:
      return false
    }
  }
}

private enum SVGDefaults {
  static let lineHeightMultiplier = 1.2
  static let connectorLabelWidth = 160.0
  static let connectorLabelHeight = 32.0
  static let numberPrecision = 1_000.0
  static let fallbackImageSize = SionSize(width: 1, height: 1)
  static let envelopeByteAllowance = 4_096
}

extension SionColor {
  fileprivate var hex: String {
    let components = [red, green, blue, alpha].map { component in
      Int((min(1, max(0, component)) * 255).rounded())
    }
    return String(
      format: "#%02x%02x%02x%02x",
      components[0],
      components[1],
      components[2],
      components[3]
    )
  }
}
