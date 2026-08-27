import type { Point, Side } from './anchors';

const DEFAULT_CURVATURE = 0.25;
const CONTROL_CURVATURE_SCALE = 25;
const BEZIER_PROJECTION_SEGMENTS = 64;

const SIDE_VECTOR: Record<Side, Point> = {
  n: { x: 0, y: -1 },
  e: { x: 1, y: 0 },
  s: { x: 0, y: 1 },
  w: { x: -1, y: 0 },
};

export interface BezierCurve {
  start: Point;
  sourceControl: Point;
  targetControl: Point;
  end: Point;
}

function controlOffset(distance: number, curvature: number): number {
  if (distance >= 0) return distance / 2;

  return curvature * CONTROL_CURVATURE_SCALE * Math.sqrt(-distance);
}

function controlPoint(point: Point, other: Point, side: Side, curvature: number): Point {
  const vector = SIDE_VECTOR[side];
  const directionalDistance = (other.x - point.x) * vector.x + (other.y - point.y) * vector.y;
  const offset = controlOffset(directionalDistance, curvature);

  return { x: point.x + vector.x * offset, y: point.y + vector.y * offset };
}

/** Mirrors React Flow's cubic controls for canvas labels and exports. */
export function bezierCurve(
  source: Point,
  target: Point,
  sourceSide: Side,
  targetSide: Side,
  curvature = DEFAULT_CURVATURE,
): BezierCurve {
  return {
    start: source,
    sourceControl: controlPoint(source, target, sourceSide, curvature),
    targetControl: controlPoint(target, source, targetSide, curvature),
    end: target,
  };
}

export function bezierPointAtT(curve: BezierCurve, rawT: number): Point {
  const t = Math.max(0, Math.min(1, rawT));
  const inverse = 1 - t;
  const startWeight = inverse * inverse * inverse;
  const sourceWeight = 3 * inverse * inverse * t;
  const targetWeight = 3 * inverse * t * t;
  const endWeight = t * t * t;

  return {
    x:
      startWeight * curve.start.x +
      sourceWeight * curve.sourceControl.x +
      targetWeight * curve.targetControl.x +
      endWeight * curve.end.x,
    y:
      startWeight * curve.start.y +
      sourceWeight * curve.sourceControl.y +
      targetWeight * curve.targetControl.y +
      endWeight * curve.end.y,
  };
}

export function nearestBezierT(curve: BezierCurve, point: Point): number {
  let nearestT = 0;
  let nearestDistance = Number.POSITIVE_INFINITY;
  for (let index = 1; index <= BEZIER_PROJECTION_SEGMENTS; index += 1) {
    const startT = (index - 1) / BEZIER_PROJECTION_SEGMENTS;
    const endT = index / BEZIER_PROJECTION_SEGMENTS;
    const start = bezierPointAtT(curve, startT);
    const end = bezierPointAtT(curve, endT);
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const lengthSquared = dx * dx + dy * dy;
    const segmentT =
      lengthSquared === 0
        ? 0
        : Math.max(
            0,
            Math.min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared),
          );
    const projected = { x: start.x + dx * segmentT, y: start.y + dy * segmentT };
    const distance = Math.hypot(point.x - projected.x, point.y - projected.y);
    if (distance >= nearestDistance) continue;

    nearestDistance = distance;
    nearestT = startT + (endT - startT) * segmentT;
  }

  return nearestT;
}
