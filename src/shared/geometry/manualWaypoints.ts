import type { Point, Rect, Side } from './anchors';

const MANUAL_ENDPOINT_STUB = 16;

const SIDE_VECTOR: Record<Side, Point> = {
  n: { x: 0, y: -1 },
  e: { x: 1, y: 0 },
  s: { x: 0, y: 1 },
  w: { x: -1, y: 0 },
};

function stub(point: Point, side: Side): Point {
  const vector = SIDE_VECTOR[side];
  return {
    x: point.x + vector.x * MANUAL_ENDPOINT_STUB,
    y: point.y + vector.y * MANUAL_ENDPOINT_STUB,
  };
}

function withoutDuplicatePoints(points: Point[]): Point[] {
  return points.filter((point, index) => {
    const previous = points[index - 1];
    return !previous || point.x !== previous.x || point.y !== previous.y;
  });
}

function segmentEntersRect(start: Point, end: Point, rect: Rect): boolean {
  if (start.y === end.y) {
    const overlapStart = Math.max(Math.min(start.x, end.x), rect.x);
    const overlapEnd = Math.min(Math.max(start.x, end.x), rect.x + rect.width);
    return overlapStart < overlapEnd && start.y > rect.y && start.y < rect.y + rect.height;
  }

  const overlapStart = Math.max(Math.min(start.y, end.y), rect.y);
  const overlapEnd = Math.min(Math.max(start.y, end.y), rect.y + rect.height);
  return overlapStart < overlapEnd && start.x > rect.x && start.x < rect.x + rect.width;
}

export function routeClearsEndpoints(points: Point[], sourceRect: Rect, targetRect: Rect): boolean {
  for (let index = 1; index < points.length; index += 1) {
    const start = points[index - 1]!;
    const end = points[index]!;
    const leavesSource = index === 1;
    const entersTarget = index === points.length - 1;
    // Curved-shape anchors lie inside their bounding boxes; their outward stubs are still clear.
    if (!leavesSource && segmentEntersRect(start, end, sourceRect)) return false;
    if (!entersTarget && segmentEntersRect(start, end, targetRect)) return false;
  }

  return true;
}

function nearestClearRoute(
  routes: Array<{ coordinate: number; points: Point[] }>,
  draggedCoordinate: number,
  sourceRect: Rect,
  targetRect: Rect,
): Point[] | null {
  const clear = routes.filter((candidate) =>
    routeClearsEndpoints(candidate.points, sourceRect, targetRect),
  );
  clear.sort(
    (left, right) =>
      Math.abs(left.coordinate - draggedCoordinate) -
      Math.abs(right.coordinate - draggedCoordinate),
  );
  return clear[0]?.points ?? null;
}

/** Build one draggable orthogonal rail without entering either endpoint. */
export function manualElbowWaypoints(
  source: Point,
  target: Point,
  sourceSide: Side,
  targetSide: Side,
  sourceRect: Rect,
  targetRect: Rect,
  dragged: Point,
): Point[] {
  const sourceStub = stub(source, sourceSide);
  const targetStub = stub(target, targetSide);
  const leftRail = Math.min(sourceRect.x, targetRect.x) - MANUAL_ENDPOINT_STUB;
  const rightRail =
    Math.max(sourceRect.x + sourceRect.width, targetRect.x + targetRect.width) +
    MANUAL_ENDPOINT_STUB;
  const topRail = Math.min(sourceRect.y, targetRect.y) - MANUAL_ENDPOINT_STUB;
  const bottomRail =
    Math.max(sourceRect.y + sourceRect.height, targetRect.y + targetRect.height) +
    MANUAL_ENDPOINT_STUB;
  const xCoordinates = [Math.round(dragged.x), leftRail, rightRail];
  const yCoordinates = [Math.round(dragged.y), topRail, bottomRail];
  const verticalRoutes = xCoordinates.map((x) => ({
    coordinate: x,
    points: withoutDuplicatePoints([
      source,
      sourceStub,
      { x, y: sourceStub.y },
      { x, y: targetStub.y },
      targetStub,
      target,
    ]),
  }));
  const horizontalRoutes = yCoordinates.map((y) => ({
    coordinate: y,
    points: withoutDuplicatePoints([
      source,
      sourceStub,
      { x: sourceStub.x, y },
      { x: targetStub.x, y },
      targetStub,
      target,
    ]),
  }));
  const horizontalSource = sourceSide === 'e' || sourceSide === 'w';
  const preferred = horizontalSource ? verticalRoutes : horizontalRoutes;
  const fallback = horizontalSource ? horizontalRoutes : verticalRoutes;
  const route =
    nearestClearRoute(
      preferred,
      horizontalSource ? dragged.x : dragged.y,
      sourceRect,
      targetRect,
    ) ??
    nearestClearRoute(fallback, horizontalSource ? dragged.y : dragged.x, sourceRect, targetRect);

  return (route ?? [source, sourceStub, targetStub, target]).slice(1, -1);
}
