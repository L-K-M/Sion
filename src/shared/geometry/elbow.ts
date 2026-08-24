/**
 * Elbow router (PLAN.md §11.3) — the FigJam-quality heuristic.
 *
 * Pure function; NOT obstacle-avoiding (that's M9). Manual waypoints
 * override the route entirely (D12: cleared whenever an endpoint moves).
 */
import type { Point, Rect, Side } from './anchors';

/** Perpendicular stub length out of each side. */
export const STUB = 16;

function stubPoint(rect: Rect, side: Side): Point {
  switch (side) {
    case 'n':
      return { x: rect.x + rect.width / 2, y: rect.y - STUB };
    case 's':
      return { x: rect.x + rect.width / 2, y: rect.y + rect.height + STUB };
    case 'w':
      return { x: rect.x - STUB, y: rect.y + rect.height / 2 };
    case 'e':
      return { x: rect.x + rect.width + STUB, y: rect.y + rect.height / 2 };
  }
}

function mid(a: number, b: number): number {
  return (a + b) / 2;
}

/** Collapse consecutive collinear points (keeps polylines minimal). */
export function collapseCollinear(points: Point[]): Point[] {
  if (points.length <= 2) return points;
  const out: Point[] = [points[0]!];
  for (let i = 1; i < points.length - 1; i++) {
    const a = out[out.length - 1]!;
    const b = points[i]!;
    const c = points[i + 1]!;
    const collinear =
      (a.x === b.x && b.x === c.x && (b.y - a.y) * (c.y - b.y) >= 0) ||
      (a.y === b.y && b.y === c.y && (b.x - a.x) * (c.x - b.x) >= 0);
    if (!collinear) out.push(b);
  }
  out.push(points[points.length - 1]!);
  return out;
}

/**
 * Route from `source` (boundary point on sourceSide) to `target` (boundary
 * point on targetSide). Returns the polyline INCLUDING both endpoints.
 *
 * Side cases (§11.3):
 *  - orthogonal sides → L (3 points after collapse)
 *  - opposite sides   → Z via the midline rail
 *  - same side        → U via a rail 16px beyond the outermost bound
 *  - non-facing variants naturally produce S/C shapes with the same rails
 */
export function route(
  source: Point,
  target: Point,
  sourceRect: Rect,
  targetRect: Rect,
  sourceSide: Side,
  targetSide: Side,
): Point[] {
  const sStub = stubPoint(sourceRect, sourceSide);
  const tStub = stubPoint(targetRect, targetSide);

  const horizontalFirst = sourceSide === 'e' || sourceSide === 'w'; // stub points along x first

  if (sourceSide === targetSide) {
    // Same side: U around the outermost bound (two same-direction stubs can
    // never close in 3 points).
    let rail: number;
    switch (sourceSide) {
      case 'e':
        rail = Math.max(sourceRect.x + sourceRect.width, targetRect.x + targetRect.width) + STUB;
        break;
      case 'w':
        rail = Math.min(sourceRect.x, targetRect.x) - STUB;
        break;
      case 's':
        rail = Math.max(sourceRect.y + sourceRect.height, targetRect.y + targetRect.height) + STUB;
        break;
      case 'n':
        rail = Math.min(sourceRect.y, targetRect.y) - STUB;
        break;
    }
    if (sourceSide === 'e' || sourceSide === 'w') {
      return collapseCollinear([
        source,
        { x: rail, y: source.y },
        { x: rail, y: target.y },
        target,
      ]);
    }
    return collapseCollinear([source, { x: source.x, y: rail }, { x: target.x, y: rail }, target]);
  }

  if ((sourceSide === 'e' && targetSide === 'w') || (sourceSide === 'w' && targetSide === 'e')) {
    // Opposite horizontally: Z through the vertical midline.
    const railX = mid(sStub.x, tStub.x);
    return collapseCollinear([
      source,
      { x: railX, y: source.y },
      { x: railX, y: target.y },
      target,
    ]);
  }
  if ((sourceSide === 's' && targetSide === 'n') || (sourceSide === 'n' && targetSide === 's')) {
    // Opposite vertically: Z through the horizontal midline.
    const railY = mid(sStub.y, tStub.y);
    return collapseCollinear([
      source,
      { x: source.x, y: railY },
      { x: target.x, y: railY },
      target,
    ]);
  }

  // Orthogonal sides: L through the corner where the stubs meet.
  if (horizontalFirst) {
    // first travel along x (out of source), then along y (into target)
    return collapseCollinear([source, { x: tStub.x, y: source.y }, target]);
  }
  return collapseCollinear([source, { x: source.x, y: tStub.y }, target]);
}

/** Polyline length. */
export function polylineLength(points: Point[]): number {
  let len = 0;
  for (let i = 1; i < points.length; i++) {
    len += Math.hypot(points[i]!.x - points[i - 1]!.x, points[i]!.y - points[i - 1]!.y);
  }
  return len;
}

/** Point at parameter t (0..1) along the polyline by arc length. */
export function pointAtT(points: Point[], t: number): Point {
  if (points.length === 0) return { x: 0, y: 0 };
  if (points.length === 1) return points[0]!;
  const total = polylineLength(points);
  if (total === 0) return points[0]!;
  let target = Math.min(1, Math.max(0, t)) * total;
  for (let i = 1; i < points.length; i++) {
    const seg = Math.hypot(points[i]!.x - points[i - 1]!.x, points[i]!.y - points[i - 1]!.y);
    if (target <= seg) {
      const f = seg === 0 ? 0 : target / seg;
      return {
        x: points[i - 1]!.x + (points[i]!.x - points[i - 1]!.x) * f,
        y: points[i - 1]!.y + (points[i]!.y - points[i - 1]!.y) * f,
      };
    }
    target -= seg;
  }
  return points[points.length - 1]!;
}
