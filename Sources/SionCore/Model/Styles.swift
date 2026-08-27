import Foundation

public struct SionColor: Codable, Equatable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public static let clear = SionColor(red: 0, green: 0, blue: 0, alpha: 0)
  public static let white = SionColor(red: 1, green: 1, blue: 1)
  public static let black = SionColor(red: 0, green: 0, blue: 0)

  public static let canvas = SionColor(red: 0.965, green: 0.969, blue: 0.976)
  public static let primaryInk = SionColor(red: 0.105, green: 0.122, blue: 0.153)
  public static let accent = SionColor(red: 0.216, green: 0.443, blue: 0.965)
  public static let accentFill = SionColor(red: 0.902, green: 0.929, blue: 1)
}

public struct GradientStop: Codable, Equatable, Sendable {
  public var color: SionColor
  public var location: Double

  public init(color: SionColor, location: Double) {
    self.color = color
    self.location = location
  }
}

public struct LinearGradientFill: Codable, Equatable, Sendable {
  public var stops: [GradientStop]
  public var start: SionPoint
  public var end: SionPoint

  public init(stops: [GradientStop], start: SionPoint, end: SionPoint) {
    self.stops = stops
    self.start = start
    self.end = end
  }
}

public enum FillStyle: Codable, Equatable, Sendable {
  case none
  case solid(SionColor)
  case linearGradient(LinearGradientFill)
}

public enum StrokeLineCap: String, Codable, CaseIterable, Sendable {
  case butt
  case round
  case square
}

public enum StrokeLineJoin: String, Codable, CaseIterable, Sendable {
  case bevel
  case miter
  case round
}

public struct StrokeStyle: Codable, Equatable, Sendable {
  public var color: SionColor
  public var width: Double
  public var dashPattern: [Double]
  public var lineCap: StrokeLineCap
  public var lineJoin: StrokeLineJoin

  public init(
    color: SionColor,
    width: Double,
    dashPattern: [Double] = [],
    lineCap: StrokeLineCap = .round,
    lineJoin: StrokeLineJoin = .round
  ) {
    self.color = color
    self.width = width
    self.dashPattern = dashPattern
    self.lineCap = lineCap
    self.lineJoin = lineJoin
  }
}

public struct ShadowStyle: Codable, Equatable, Sendable {
  public var color: SionColor
  public var offset: SionVector
  public var blurRadius: Double
  public var spread: Double

  public init(
    color: SionColor,
    offset: SionVector,
    blurRadius: Double,
    spread: Double = 0
  ) {
    self.color = color
    self.offset = offset
    self.blurRadius = blurRadius
    self.spread = spread
  }
}

public enum BlendMode: String, Codable, CaseIterable, Sendable {
  case normal
  case multiply
  case screen
  case overlay
}

public struct ElementStyle: Codable, Equatable, Sendable {
  public var fill: FillStyle
  public var stroke: StrokeStyle?
  public var shadows: [ShadowStyle]
  public var opacity: Double
  public var blendMode: BlendMode

  public init(
    fill: FillStyle,
    stroke: StrokeStyle? = nil,
    shadows: [ShadowStyle] = [],
    opacity: Double = 1,
    blendMode: BlendMode = .normal
  ) {
    self.fill = fill
    self.stroke = stroke
    self.shadows = shadows
    self.opacity = opacity
    self.blendMode = blendMode
  }

  public static let shapeDefault = ElementStyle(
    fill: .solid(.accentFill),
    stroke: StrokeStyle(color: .accent, width: SionStyleDefaults.shapeStrokeWidth),
    shadows: [defaultElevationShadow]
  )

  public static let textDefault = ElementStyle(fill: .none)
  public static let imageDefault = ElementStyle(
    fill: .none,
    shadows: [defaultElevationShadow]
  )
  public static let groupDefault = ElementStyle(fill: .none)
  public static let connectorDefault = ElementStyle(
    fill: .none,
    stroke: StrokeStyle(color: .primaryInk, width: SionStyleDefaults.connectorStrokeWidth)
  )

  private static let defaultElevationShadow = ShadowStyle(
    color: SionColor(red: 0.05, green: 0.08, blue: 0.15, alpha: 0.16),
    offset: SionVector(dx: 0, dy: 2),
    blurRadius: SionStyleDefaults.shapeShadowBlur
  )
}

public enum FontFamily: Codable, Equatable, Sendable {
  case system
  case named(String)
}

public enum FontWeight: String, Codable, CaseIterable, Sendable {
  case light
  case regular
  case medium
  case semibold
  case bold
}

public struct FontDescriptor: Codable, Equatable, Sendable {
  public var family: FontFamily
  public var size: Double
  public var weight: FontWeight

  public init(family: FontFamily = .system, size: Double, weight: FontWeight = .regular) {
    self.family = family
    self.size = size
    self.weight = weight
  }
}

public enum HorizontalTextAlignment: String, Codable, CaseIterable, Sendable {
  case leading
  case center
  case trailing
  case justified
}

public enum VerticalTextAlignment: String, Codable, CaseIterable, Sendable {
  case top
  case center
  case bottom
}

public enum TextAutoSizing: String, Codable, CaseIterable, Sendable {
  case fixed
  case fitHeight
  case fitWidthAndHeight
}

public struct TextInsets: Codable, Equatable, Sendable {
  public var top: Double
  public var leading: Double
  public var bottom: Double
  public var trailing: Double

  public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
    self.top = top
    self.leading = leading
    self.bottom = bottom
    self.trailing = trailing
  }

  public init(all value: Double) {
    self.init(top: value, leading: value, bottom: value, trailing: value)
  }
}

public struct TextStyle: Codable, Equatable, Sendable {
  public var font: FontDescriptor
  public var color: SionColor
  public var horizontalAlignment: HorizontalTextAlignment
  public var verticalAlignment: VerticalTextAlignment
  public var lineSpacing: Double
  public var paragraphSpacing: Double
  public var insets: TextInsets
  public var autoSizing: TextAutoSizing

  public init(
    font: FontDescriptor,
    color: SionColor,
    horizontalAlignment: HorizontalTextAlignment,
    verticalAlignment: VerticalTextAlignment,
    lineSpacing: Double = 0,
    paragraphSpacing: Double = 0,
    insets: TextInsets,
    autoSizing: TextAutoSizing
  ) {
    self.font = font
    self.color = color
    self.horizontalAlignment = horizontalAlignment
    self.verticalAlignment = verticalAlignment
    self.lineSpacing = lineSpacing
    self.paragraphSpacing = paragraphSpacing
    self.insets = insets
    self.autoSizing = autoSizing
  }

  public static let shapeLabelDefault = TextStyle(
    font: FontDescriptor(size: SionStyleDefaults.labelFontSize, weight: .medium),
    color: .primaryInk,
    horizontalAlignment: .center,
    verticalAlignment: .center,
    insets: TextInsets(all: SionStyleDefaults.labelInset),
    autoSizing: .fixed
  )

  public static let standaloneDefault = TextStyle(
    font: FontDescriptor(size: SionStyleDefaults.textFontSize),
    color: .primaryInk,
    horizontalAlignment: .leading,
    verticalAlignment: .top,
    insets: TextInsets(all: 0),
    autoSizing: .fitHeight
  )
}

private enum SionStyleDefaults {
  static let shapeStrokeWidth = 1.5
  static let connectorStrokeWidth = 2.0
  static let shapeShadowBlur = 8.0
  static let labelFontSize = 15.0
  static let textFontSize = 16.0
  static let labelInset = 12.0
}
