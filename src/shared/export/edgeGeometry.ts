import { edgeEndpoints, type Point } from '../geometry/anchors';
import { bezierCurve, bezierPointAtT, type BezierCurve } from '../geometry/bezier';
import { pointAtT, route } from '../geometry/elbow';
import { absolutePosition, type Bounds } from '../model/queries';
import type { ThalyxDoc, ThalyxEdge, ThalyxNode } from '../model/types';

export const EDGE_LABEL_CHAR_WIDTH = 6.8;
export const EDGE_LABEL_HORIZONTAL_PADDING = 4;
export const EDGE_LABEL_HEIGHT = 18;

const POLYNOMIAL_EPSILON = 1e-9;

export interface SvgEdgeGeometry {
  edge: ThalyxEdge;
  path: string;
  pathBounds: Bounds;
  labelPoint?: Point;
}

function polylinePath(points: Point[]): string {
  return points.map((point, index) => `${index === 0 ? 'M' : 'L'} ${point.x} ${point.y}`).join(' ');
}

function bezierPath(curve: BezierCurve): string {
  return `M ${curve.start.x} ${curve.start.y} C ${curve.sourceControl.x} ${curve.sourceControl.y} ${curve.targetControl.x} ${curve.targetControl.y} ${curve.end.x} ${curve.end.y}`;
}

function boundsOfPoints(points: Point[]): Bounds {
  let minX = Number.POSITIVE_INFINITY;
  let minY = Number.POSITIVE_INFINITY;
  let maxX = Number.NEGATIVE_INFINITY;
  let maxY = Number.NEGATIVE_INFINITY;

  for (const point of points) {
    minX = Math.min(minX, point.x);
    minY = Math.min(minY, point.y);
    maxX = Math.max(maxX, point.x);
    maxY = Math.max(maxY, point.y);
  }

  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

function cubicExtrema(
  start: number,
  sourceControl: number,
  targetControl: number,
  end: number,
): number[] {
  const quadratic = 3 * (-start + 3 * sourceControl - 3 * targetControl + end);
  const linear = 6 * (start - 2 * sourceControl + targetControl);
  const constant = 3 * (sourceControl - start);

  if (Math.abs(quadratic) < POLYNOMIAL_EPSILON) {
    if (Math.abs(linear) < POLYNOMIAL_EPSILON) return [];

    const root = -constant / linear;
    return root > 0 && root < 1 ? [root] : [];
  }

  const discriminant = linear * linear - 4 * quadratic * constant;
  if (discriminant < 0) return [];

  const rootOffset = Math.sqrt(discriminant);
  return [
    (-linear + rootOffset) / (2 * quadratic),
    (-linear - rootOffset) / (2 * quadratic),
  ].filter((root) => root > 0 && root < 1);
}

function boundsOfBezier(curve: BezierCurve): Bounds {
  // Cubic extrema keep the export tight while guaranteeing the curve is visible.
  const extrema = new Set([
    ...cubicExtrema(curve.start.x, curve.sourceControl.x, curve.targetControl.x, curve.end.x),
    ...cubicExtrema(curve.start.y, curve.sourceControl.y, curve.targetControl.y, curve.end.y),
  ]);
  const points = [curve.start, curve.end, ...[...extrema].map((t) => bezierPointAtT(curve, t))];

  return boundsOfPoints(points);
}

function unionBounds(left: Bounds, right: Bounds): Bounds {
  const minX = Math.min(left.x, right.x);
  const minY = Math.min(left.y, right.y);
  const maxX = Math.max(left.x + left.width, right.x + right.width);
  const maxY = Math.max(left.y + left.height, right.y + right.height);

  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

function labelBounds(label: string, point: Point): Bounds {
  const width = label.length * EDGE_LABEL_CHAR_WIDTH + EDGE_LABEL_HORIZONTAL_PADDING * 2;

  return {
    x: point.x - width / 2,
    y: point.y - EDGE_LABEL_HEIGHT / 2,
    width,
    height: EDGE_LABEL_HEIGHT,
  };
}

export function svgEdgeGeometry(
  doc: ThalyxDoc,
  edge: ThalyxEdge,
  nodesById: ReadonlyMap<string, ThalyxNode>,
): SvgEdgeGeometry | null {
  const sourceNode = nodesById.get(edge.source);
  const targetNode = nodesById.get(edge.target);
  if (!sourceNode || !targetNode) return null;

  const sourceAbsolute = absolutePosition(doc, sourceNode);
  const targetAbsolute = absolutePosition(doc, targetNode);
  const { source, target, sourceSide, targetSide } = edgeEndpoints(
    sourceNode,
    sourceAbsolute,
    targetNode,
    targetAbsolute,
    edge.sourceAnchor,
    edge.targetAnchor,
  );

  if (edge.kind === 'curved') {
    const curve = bezierCurve(source, target, sourceSide, targetSide);

    return {
      edge,
      path: bezierPath(curve),
      pathBounds: boundsOfBezier(curve),
      labelPoint: edge.label ? bezierPointAtT(curve, edge.labelT ?? 0.5) : undefined,
    };
  }

  const points =
    edge.kind === 'elbow'
      ? edge.waypoints && edge.waypoints.length > 0
        ? [source, ...edge.waypoints, target]
        : route(
            source,
            target,
            {
              x: sourceAbsolute.x,
              y: sourceAbsolute.y,
              width: sourceNode.width,
              height: sourceNode.height,
            },
            {
              x: targetAbsolute.x,
              y: targetAbsolute.y,
              width: targetNode.width,
              height: targetNode.height,
            },
            sourceSide,
            targetSide,
          )
      : [source, target];

  return {
    edge,
    path: polylinePath(points),
    pathBounds: boundsOfPoints(points),
    labelPoint: edge.label ? pointAtT(points, edge.labelT ?? 0.5) : undefined,
  };
}

export function boundsWithSvgEdges(base: Bounds, edges: SvgEdgeGeometry[]): Bounds {
  let bounds = base;
  for (const geometry of edges) {
    bounds = unionBounds(bounds, geometry.pathBounds);
    if (!geometry.edge.label || !geometry.labelPoint) continue;

    bounds = unionBounds(bounds, labelBounds(geometry.edge.label, geometry.labelPoint));
  }

  return bounds;
}
