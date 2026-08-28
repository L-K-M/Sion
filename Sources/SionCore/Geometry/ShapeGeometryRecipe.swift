import Foundation

/// Vector artwork shared by renderers, hit testing, and connection geometry.
package struct ShapeGeometryRecipe: Equatable, Sendable {
  package let outerOutline: VectorPath
  package let detailStrokes: [VectorPath]
  package let magnetOutline: [SionPoint]
  package let vertexMagnets: [Magnet]

  package static let cylinder = ShapeGeometryRecipe(
    outerOutline: VectorPath(commands: [
      .move(to: CylinderPoint.leftRim),
      .cubic(
        control1: CylinderPoint.leftBackControl,
        control2: CylinderPoint.centerLeftBackControl,
        to: CylinderPoint.top
      ),
      .cubic(
        control1: CylinderPoint.centerRightBackControl,
        control2: CylinderPoint.rightBackControl,
        to: CylinderPoint.rightRim
      ),
      .line(to: CylinderPoint.rightBottomRim),
      .cubic(
        control1: CylinderPoint.rightBottomControl,
        control2: CylinderPoint.centerRightBottomControl,
        to: CylinderPoint.bottom
      ),
      .cubic(
        control1: CylinderPoint.centerLeftBottomControl,
        control2: CylinderPoint.leftBottomControl,
        to: CylinderPoint.leftBottomRim
      ),
      .close,
    ]),
    detailStrokes: [
      VectorPath(commands: [
        .move(to: CylinderPoint.leftRim),
        .cubic(
          control1: CylinderPoint.leftFrontControl,
          control2: CylinderPoint.centerLeftFrontControl,
          to: CylinderPoint.front
        ),
        .cubic(
          control1: CylinderPoint.centerRightFrontControl,
          control2: CylinderPoint.rightFrontControl,
          to: CylinderPoint.rightRim
        ),
      ])
    ],
    magnetOutline: [
      CylinderPoint.leftRim,
      CylinderPoint.top,
      CylinderPoint.rightRim,
      CylinderPoint.rightBottomRim,
      CylinderPoint.bottom,
      CylinderPoint.leftBottomRim,
    ],
    vertexMagnets: [
      // Preserve legacy corner IDs without deriving normals from ID order.
      Magnet(
        id: "vertex-0",
        normalizedPosition: CylinderPoint.leftRim,
        outwardDirection: .west
      ),
      Magnet(
        id: "vertex-1",
        normalizedPosition: CylinderPoint.rightRim,
        outwardDirection: .east
      ),
      Magnet(
        id: "vertex-2",
        normalizedPosition: CylinderPoint.rightBottomRim,
        outwardDirection: .east
      ),
      Magnet(
        id: "vertex-3",
        normalizedPosition: CylinderPoint.leftBottomRim,
        outwardDirection: .west
      ),
      Magnet(
        id: "vertex-4",
        normalizedPosition: CylinderPoint.top,
        outwardDirection: .north
      ),
      Magnet(
        id: "vertex-5",
        normalizedPosition: CylinderPoint.bottom,
        outwardDirection: .south
      ),
    ]
  )
}

private enum CylinderPoint {
  // Half-arcs use the standard quarter-ellipse cubic approximation.
  private static let curveControlFactor = 0.552_284_749_8
  private static let rim = ShapeGeometryDefaults.cylinderArcFraction
  private static let verticalControl = rim * curveControlFactor
  private static let horizontalControl = 0.5 * curveControlFactor

  static let leftRim = SionPoint(x: 0, y: rim)
  static let top = SionPoint(x: 0.5, y: 0)
  static let rightRim = SionPoint(x: 1, y: rim)
  static let rightBottomRim = SionPoint(x: 1, y: 1 - rim)
  static let bottom = SionPoint(x: 0.5, y: 1)
  static let leftBottomRim = SionPoint(x: 0, y: 1 - rim)
  static let front = SionPoint(x: 0.5, y: 2 * rim)

  static let leftBackControl = SionPoint(x: 0, y: rim - verticalControl)
  static let centerLeftBackControl = SionPoint(x: 0.5 - horizontalControl, y: 0)
  static let centerRightBackControl = SionPoint(x: 0.5 + horizontalControl, y: 0)
  static let rightBackControl = SionPoint(x: 1, y: rim - verticalControl)

  static let rightBottomControl = SionPoint(x: 1, y: 1 - rim + verticalControl)
  static let centerRightBottomControl = SionPoint(x: 0.5 + horizontalControl, y: 1)
  static let centerLeftBottomControl = SionPoint(x: 0.5 - horizontalControl, y: 1)
  static let leftBottomControl = SionPoint(x: 0, y: 1 - rim + verticalControl)

  static let leftFrontControl = SionPoint(x: 0, y: rim + verticalControl)
  static let centerLeftFrontControl = SionPoint(
    x: 0.5 - horizontalControl,
    y: 2 * rim
  )
  static let centerRightFrontControl = SionPoint(
    x: 0.5 + horizontalControl,
    y: 2 * rim
  )
  static let rightFrontControl = SionPoint(x: 1, y: rim + verticalControl)
}
