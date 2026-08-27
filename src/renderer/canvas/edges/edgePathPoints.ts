import type { EdgeKind } from '../../../shared/model/types';
import type { Point } from '../../../shared/geometry/anchors';

/** Manual rails belong only to elbow connectors. */
export function edgePathPoints(
  kind: EdgeKind,
  source: Point,
  target: Point,
  waypoints: Point[] | undefined,
  autoElbow: () => Point[],
): Point[] {
  if (kind !== 'elbow') return [source, target];
  if (waypoints && waypoints.length > 0) return [source, ...waypoints, target];

  return autoElbow();
}
