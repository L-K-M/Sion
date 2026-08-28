import Foundation
import XCTest

@testable import SionCore

final class SceneCommandPropertyTests: XCTestCase {
  func testFixedSeedCommandSequencesRemainValidAndDeterministic() throws {
    XCTAssertGreaterThanOrEqual(
      PropertyCorpus.commandCount,
      GeneratedOperation.allCases.count
    )

    for seed in PropertyCorpus.seeds {
      let firstTrace = try commandTrace(seed: seed)
      let secondTrace = try commandTrace(seed: seed)

      XCTAssertEqual(firstTrace, secondTrace, "Nondeterministic sequence for seed \(seed)")
    }
  }

  private func commandTrace(seed: UInt64) throws -> [Data] {
    var generator = FixedGenerator(seed: seed)
    var idSequence = ElementIDSequence()
    let initialElements = [
      SceneElement.shape(
        id: idSequence.next(),
        frame: SionRect(x: -160, y: -80, width: 120, height: 80),
        kind: .rectangle
      ),
      SceneElement.shape(
        id: idSequence.next(),
        frame: SionRect(x: 40, y: -60, width: 100, height: 100),
        kind: .ellipse
      ),
      SceneElement.shape(
        id: idSequence.next(),
        frame: SionRect(x: -40, y: 80, width: 140, height: 90),
        kind: .diamond
      ),
    ]
    var editor = try SceneEditor(
      document: SionDocument(
        id: PropertyCorpus.documentID,
        title: "Property Corpus",
        scene: SionScene(elements: initialElements)
      )
    )
    var trace = [Data]()

    for step in 0..<PropertyCorpus.commandCount {
      let operation =
        step < GeneratedOperation.allCases.count
        ? GeneratedOperation.allCases[step]
        : generator.element(in: GeneratedOperation.allCases)

      do {
        try apply(
          operation,
          to: &editor,
          generator: &generator,
          idSequence: &idSequence
        )
        try editor.document.validate()

        // Checkpoint serialization without making the corpus dominate CI time.
        guard (step + 1).isMultiple(of: PropertyCorpus.serializationStride) else {
          continue
        }

        let encoded = try CanonicalJSON.encode(editor.document)
        let decoded = try CanonicalJSON.decodeStrict(SionDocument.self, from: encoded)
        XCTAssertEqual(
          decoded,
          editor.document,
          "Round-trip mismatch for seed \(seed), step \(step)"
        )
        trace.append(encoded)
      } catch {
        XCTFail("Seed \(seed), step \(step), operation \(operation): \(error)")
        throw error
      }
    }

    return trace
  }

  private func apply(
    _ operation: GeneratedOperation,
    to editor: inout SceneEditor,
    generator: inout FixedGenerator,
    idSequence: inout ElementIDSequence
  ) throws {
    switch operation {
    case .insertShape:
      try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
    case .insertConnector:
      try insertConnector(into: &editor, generator: &generator, idSequence: &idSequence)
    case .remove:
      guard let element = generator.optionalElement(in: editor.document.scene.elements) else {
        try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
        return
      }

      try perform(.remove(elementIDs: [element.id]), operation: operation, on: &editor)
    case .translate:
      guard let element = generator.optionalElement(in: shapeElements(in: editor.document)) else {
        try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
        return
      }

      let offset = SionVector(
        dx: generator.double(in: -40...40),
        dy: generator.double(in: -40...40)
      )
      try perform(
        .translate(elementIDs: [element.id], by: offset), operation: operation, on: &editor)
    case .setFrame:
      guard let element = generator.optionalElement(in: shapeElements(in: editor.document)) else {
        try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
        return
      }

      try perform(
        .setFrame(elementID: element.id, frame: randomFrame(generator: &generator)),
        operation: operation,
        on: &editor
      )
    case .setRotation:
      guard let element = generator.optionalElement(in: shapeElements(in: editor.document)) else {
        try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
        return
      }

      try perform(
        .setRotation(
          elementID: element.id,
          radians: generator.double(in: -Double.pi...Double.pi)
        ),
        operation: operation,
        on: &editor
      )
    case .setShapeKind:
      guard let element = generator.optionalElement(in: shapeElements(in: editor.document)) else {
        try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
        return
      }

      try perform(
        .setShapeKind(elementID: element.id, kind: randomShapeKind(generator: &generator)),
        operation: operation,
        on: &editor
      )
    case .setStyle:
      guard let element = generator.optionalElement(in: shapeElements(in: editor.document)) else {
        try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
        return
      }

      try perform(
        .setStyle(elementID: element.id, style: randomStyle(generator: &generator)),
        operation: operation,
        on: &editor
      )
    case .setText:
      guard let element = generator.optionalElement(in: shapeElements(in: editor.document)) else {
        try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
        return
      }

      try perform(
        .setText(elementID: element.id, text: "Label \(generator.next() % 1_000)"),
        operation: operation,
        on: &editor
      )
    case .reorder:
      guard let element = generator.optionalElement(in: editor.document.scene.elements) else {
        try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
        return
      }

      let remainingCount = editor.document.scene.elements.count - 1
      let destination = generator.integer(through: remainingCount)
      try perform(
        .reorder(elementIDs: [element.id], destinationIndex: destination),
        operation: operation,
        on: &editor
      )
    case .rename:
      guard let element = generator.optionalElement(in: editor.document.scene.elements) else {
        try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
        return
      }

      let name = generator.integer(through: 3) == 0 ? nil : "Node \(generator.next() % 1_000)"
      try perform(
        .rename(elementID: element.id, name: name),
        operation: operation,
        on: &editor
      )
    case .setVisibility:
      guard let element = generator.optionalElement(in: editor.document.scene.elements) else {
        try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
        return
      }

      try perform(
        .setVisibility(
          elementID: element.id,
          visibility: generator.element(in: ElementVisibility.allCases)
        ),
        operation: operation,
        on: &editor
      )
    case .setCanvas:
      try perform(
        .setCanvas(randomCanvas(generator: &generator)),
        operation: operation,
        on: &editor
      )
    case .undo:
      guard editor.canUndo else {
        try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
        return
      }

      _ = editor.undo()
    case .redo:
      guard editor.canRedo else {
        try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
        return
      }

      _ = editor.redo()
    }
  }

  private func insertShape(
    into editor: inout SceneEditor,
    generator: inout FixedGenerator,
    idSequence: inout ElementIDSequence
  ) throws {
    guard editor.document.scene.elements.count < PropertyCorpus.maximumElementCount else {
      guard let element = generator.optionalElement(in: editor.document.scene.elements) else {
        return
      }

      try perform(.remove(elementIDs: [element.id]), operation: .remove, on: &editor)
      return
    }

    let element = SceneElement.shape(
      id: idSequence.next(),
      frame: randomFrame(generator: &generator),
      kind: randomShapeKind(generator: &generator)
    )
    try perform(.insert(elements: [element], at: nil), operation: .insertShape, on: &editor)
  }

  private func insertConnector(
    into editor: inout SceneEditor,
    generator: inout FixedGenerator,
    idSequence: inout ElementIDSequence
  ) throws {
    let shapes = shapeElements(in: editor.document)
    guard editor.document.scene.elements.count < PropertyCorpus.maximumElementCount,
      shapes.count > 1
    else {
      try insertShape(into: &editor, generator: &generator, idSequence: &idSequence)
      return
    }

    let sourceIndex = generator.integer(through: shapes.count - 1)
    let targetOffset = generator.integer(through: shapes.count - 2) + 1
    let targetIndex = (sourceIndex + targetOffset) % shapes.count
    let source = shapes[sourceIndex]
    let target = shapes[targetIndex]
    let connector = SceneElement.connector(
      id: idSequence.next(),
      source: .element(
        source.id,
        attachment: .automatic,
        fallbackPoint: source.geometry.frame.center
      ),
      target: .element(
        target.id,
        attachment: .automatic,
        fallbackPoint: target.geometry.frame.center
      ),
      routingStyle: generator.element(in: ConnectorRoutingStyle.allCases)
    )
    try perform(
      .insert(elements: [connector], at: nil),
      operation: .insertConnector,
      on: &editor
    )
  }

  private func perform(
    _ command: SceneCommand,
    operation: GeneratedOperation,
    on editor: inout SceneEditor
  ) throws {
    _ = try editor.perform(
      SceneTransaction(name: "Property \(operation)", command: command)
    )
  }

  private func shapeElements(in document: SionDocument) -> [SceneElement] {
    document.scene.elements.filter { element in
      guard case .shape = element.content else { return false }

      return true
    }
  }

  private func randomFrame(generator: inout FixedGenerator) -> SionRect {
    SionRect(
      x: generator.double(in: -1_000...1_000),
      y: generator.double(in: -1_000...1_000),
      width: generator.double(in: 1...300),
      height: generator.double(in: 1...300)
    )
  }

  private func randomShapeKind(generator: inout FixedGenerator) -> ShapeKind {
    generator.element(in: [
      .rectangle,
      .roundedRectangle(radius: generator.double(in: 0...80)),
      .ellipse,
      .diamond,
      .triangle,
      .hexagon,
      .capsule,
      .cylinder,
    ])
  }

  private func randomStyle(generator: inout FixedGenerator) -> ElementStyle {
    let fill: FillStyle
    switch generator.integer(through: 2) {
    case 0:
      fill = .none
    case 1:
      fill = .solid(randomColor(generator: &generator))
    default:
      fill = .linearGradient(
        LinearGradientFill(
          stops: [
            GradientStop(color: randomColor(generator: &generator), location: 0),
            GradientStop(color: randomColor(generator: &generator), location: 1),
          ],
          start: randomUnitPoint(generator: &generator),
          end: randomUnitPoint(generator: &generator)
        )
      )
    }

    let stroke: StrokeStyle?
    if generator.integer(through: 3) == 0 {
      stroke = nil
    } else {
      stroke = StrokeStyle(
        color: randomColor(generator: &generator),
        width: generator.double(in: 0...20),
        dashPattern: generator.element(in: PropertyCorpus.dashPatterns),
        lineCap: generator.element(in: StrokeLineCap.allCases),
        lineJoin: generator.element(in: StrokeLineJoin.allCases)
      )
    }

    let shadows: [ShadowStyle]
    if generator.integer(through: 2) == 0 {
      shadows = []
    } else {
      shadows = [
        ShadowStyle(
          color: randomColor(generator: &generator),
          offset: SionVector(
            dx: generator.double(in: -20...20),
            dy: generator.double(in: -20...20)
          ),
          blurRadius: generator.double(in: 0...20),
          spread: generator.double(in: -10...10)
        )
      ]
    }

    return ElementStyle(
      fill: fill,
      stroke: stroke,
      shadows: shadows,
      opacity: generator.unitInterval(),
      blendMode: generator.element(in: BlendMode.allCases)
    )
  }

  private func randomCanvas(generator: inout FixedGenerator) -> SionCanvas {
    let extent: CanvasExtent
    if generator.integer(through: 1) == 0 {
      extent = .infinite
    } else {
      extent = .fixed(
        SionSize(
          width: generator.double(in: 100...2_000),
          height: generator.double(in: 100...2_000)
        )
      )
    }

    return SionCanvas(
      extent: extent,
      background: randomColor(generator: &generator),
      grid: CanvasGrid(
        visibility: generator.element(in: GridVisibility.allCases),
        spacing: generator.double(in: 4...64),
        subdivisions: generator.integer(in: 1...8)
      )
    )
  }

  private func randomColor(generator: inout FixedGenerator) -> SionColor {
    SionColor(
      red: generator.unitInterval(),
      green: generator.unitInterval(),
      blue: generator.unitInterval(),
      alpha: generator.unitInterval()
    )
  }

  private func randomUnitPoint(generator: inout FixedGenerator) -> SionPoint {
    SionPoint(x: generator.unitInterval(), y: generator.unitInterval())
  }
}

private enum GeneratedOperation: CaseIterable {
  case insertShape
  case insertConnector
  case remove
  case translate
  case setFrame
  case setRotation
  case setShapeKind
  case setStyle
  case setText
  case reorder
  case rename
  case setVisibility
  case setCanvas
  case undo
  case redo
}

private enum PropertyCorpus {
  static let commandCount = 96
  static let maximumElementCount = 24
  static let serializationStride = 16
  static let documentID = DocumentID("00000000-0000-0000-0000-000000000001")!
  static let dashPatterns: [[Double]] = [[], [0, 8], [4, 4], [2, 6, 8]]

  private static let baseSeed: UInt64 = 0x510D_2026_0000_0000
  private static let seedCount = 16

  static let seeds = (0..<seedCount).map { baseSeed | UInt64($0) }
}

private struct ElementIDSequence {
  private var nextValue: UInt64 = 1

  mutating func next() -> ElementID {
    defer { nextValue += 1 }

    let suffix = String(format: "%012llx", nextValue)
    return ElementID("00000000-0000-0000-0000-\(suffix)")!
  }
}

private struct FixedGenerator {
  private static let multiplier: UInt64 = 6_364_136_223_846_793_005
  private static let increment: UInt64 = 1_442_695_040_888_963_407
  private static let unitIntervalShift = 11
  private static let unitIntervalScale = Double(UInt64(1) << 53)

  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    // A fixed LCG makes each failing seed and step portable across toolchains.
    state = state &* Self.multiplier &+ Self.increment
    return state
  }

  mutating func integer(through upperBound: Int) -> Int {
    Int(next() % UInt64(upperBound + 1))
  }

  mutating func integer(in range: ClosedRange<Int>) -> Int {
    range.lowerBound + integer(through: range.upperBound - range.lowerBound)
  }

  mutating func unitInterval() -> Double {
    Double(next() >> Self.unitIntervalShift) / Self.unitIntervalScale
  }

  mutating func double(in range: ClosedRange<Double>) -> Double {
    range.lowerBound + (unitInterval() * (range.upperBound - range.lowerBound))
  }

  mutating func element<Element>(in elements: [Element]) -> Element {
    elements[integer(through: elements.count - 1)]
  }

  mutating func optionalElement<Element>(in elements: [Element]) -> Element? {
    guard !elements.isEmpty else { return nil }

    return elements[integer(through: elements.count - 1)]
  }
}
