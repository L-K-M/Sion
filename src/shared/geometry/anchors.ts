/**
 * Floating attachment anchors (PLAN.md §11.2).
 *
 * Endpoints are DERIVED from the graph (D12): for 'auto', the endpoint is the
 * intersection of the center-to-center segment with the node's shape boundary
 * (analytic for rect/ellipse/diamond; bounding rect otherwise). Pinned sides
 * (M9) use the side midpoint. Pure module.
 */
import { shapeBoundaryIntersection } from './shapes';
import type { ShapeKind, ThalyxEdge, ThalyxNode } from '../model/types';

export type Side = 'n' | 's' | 'e' | 'w';
export type AnchorSpec = 'auto' | Side;

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface Point {
  x: number;
  y: number;
}

export function rectOf(node: ThalyxNode, absolute: Point): Rect {
  return { x: absolute.x, y: absolute.y, width: node.width, height: node.height };
}

export function centerOf(r: Rect): Point {
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
}

function sideMidpoint(r: Rect, side: Side): Point {
  const c = centerOf(r);
  switch (side) {
    case 'n':
      return { x: c.x, y: r.y };
    case 's':
      return { x: c.x, y: r.y + r.height };
    case 'w':
      return { x: r.x, y: c.y };
    case 'e':
      return { x: r.x + r.width, y: c.y };
  }
}

function boundaryPoint(node: ThalyxNode, r: Rect, aimAt: Point): Point {
  const shape: ShapeKind = node.shape ?? 'rect';
  const localAim = { x: aimAt.x - r.x, y: aimAt.y - r.y };
  const p = shapeBoundaryIntersection(shape, r.width, r.height, localAim);
  return { x: r.x + p.x, y: r.y + p.y };
}

export interface EdgeEndpointPair {
  source: Point;
  target: Point;
  sourceSide: Side;
  targetSide: Side;
}

/**
 * Compute both edge endpoints + the facing sides (used by the elbow router).
 * `sourceAbs`/`targetAbs` are the nodes' absolute canvas positions.
 */
export function edgeEndpoints(
  sourceNode: ThalyxNode,
  sourceAbs: Point,
  targetNode: ThalyxNode,
  targetAbs: Point,
  sourceAnchor: AnchorSpec,
  targetAnchor: AnchorSpec,
): EdgeEndpointPair {
  const sRect = rectOf(sourceNode, sourceAbs);
  const tRect = rectOf(targetNode, targetAbs);
  const sC = centerOf(sRect);
  const tC = centerOf(tRect);

  const source =
    sourceAnchor === 'auto'
      ? boundaryPoint(sourceNode, sRect, tC)
      : sideMidpoint(sRect, sourceAnchor);
  const target =
    targetAnchor === 'auto'
      ? boundaryPoint(targetNode, tRect, sC)
      : sideMidpoint(tRect, targetAnchor);

  const sourceSide: Side = facingSide(sourceAnchor, sRect, tC);
  const targetSide: Side = facingSide(targetAnchor, tRect, sC);

  return { source, target, sourceSide, targetSide };
}

/** Side of `r` that faces `towards` (unless explicitly pinned). */
export function facingSide(anchor: AnchorSpec, r: Rect, towards: Point): Side {
  if (anchor !== 'auto') return anchor;
  const c = centerOf(r);
  const dx = towards.x - c.x;
  const dy = towards.y - c.y;
  if (Math.abs(dx) > Math.abs(dy)) return dx > 0 ? 'e' : 'w';
  return dy > 0 ? 's' : 'n';
}

/** Convenience: endpoints for an edge between two nodes of a doc. */
export function endpointsForEdge(
  doc: import('../model/types').ThalyxDoc,
  absolutePosition: (node: ThalyxNode) => Point,
  edge: ThalyxEdge,
): EdgeEndpointPair {
  const source = doc.nodes.find((n) => n.id === edge.source);
  const target = doc.nodes.find((n) => n.id === edge.target);
  if (!source || !target) {
    return { source: { x: 0, y: 0 }, target: { x: 0, y: 0 }, sourceSide: 'e', targetSide: 'w' };
  }
  return edgeEndpoints(
    source,
    absolutePosition(source),
    target,
    absolutePosition(target),
    edge.sourceAnchor,
    edge.targetAnchor,
  );
}
