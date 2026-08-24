/**
 * ThalyxEdge (PLAN.md §11.3): elbow / straight / curved rendering with
 * arrowhead markers, line styles, 6px corner rounding, a draggable label
 * chip at labelT, and manual waypoint dragging. Hidden edges render nothing.
 */
import { memo, useCallback, useMemo, useRef } from 'react';
import {
  BaseEdge,
  EdgeLabelRenderer,
  getBezierPath,
  getStraightPath,
  useReactFlow,
  type EdgeProps,
} from '@xyflow/react';
import { useStore } from '../../store/store';
import * as A from '../../store/actions';
import { absolutePosition } from '../../../shared/model/queries';
import { edgeEndpoints, type Point } from '../../../shared/geometry/anchors';
import { pointAtT, route } from '../../../shared/geometry/elbow';
import { colorStyle } from '../../theme/colorStyle';
import type { ThalyxEdgeData } from '../rfSelectors';

function toPolylineD(points: Point[], cornerRadius = 6): string {
  if (points.length < 2) return '';
  if (cornerRadius <= 0) {
    return points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ');
  }
  // Rounded-corner polyline: straight segments joined by quarter-circle arcs.
  let d = `M ${points[0]!.x} ${points[0]!.y}`;
  for (let i = 1; i < points.length - 1; i++) {
    const prev = points[i - 1]!;
    const corner = points[i]!;
    const next = points[i + 1]!;
    const lenIn = Math.hypot(corner.x - prev.x, corner.y - prev.y);
    const lenOut = Math.hypot(next.x - corner.x, next.y - corner.y);
    const r = Math.min(cornerRadius, lenIn / 2, lenOut / 2);
    if (r <= 0.01) {
      d += ` L ${corner.x} ${corner.y}`;
      continue;
    }
    const inUnit = { x: (corner.x - prev.x) / lenIn, y: (corner.y - prev.y) / lenIn };
    const outUnit = { x: (next.x - corner.x) / lenOut, y: (next.y - corner.y) / lenOut };
    const p1 = { x: corner.x - inUnit.x * r, y: corner.y - inUnit.y * r };
    const p2 = { x: corner.x + outUnit.x * r, y: corner.y + outUnit.y * r };
    d += ` L ${p1.x} ${p1.y} Q ${corner.x} ${corner.y} ${p2.x} ${p2.y}`;
  }
  const last = points[points.length - 1]!;
  d += ` L ${last.x} ${last.y}`;
  return d;
}

function nearestT(points: Point[], p: Point): number {
  if (points.length < 2) return 0.5;
  const lens: number[] = [];
  let total = 0;
  for (let i = 1; i < points.length; i++) {
    const l = Math.hypot(points[i]!.x - points[i - 1]!.x, points[i]!.y - points[i - 1]!.y);
    lens.push(l);
    total += l;
  }
  if (total === 0) return 0.5;
  let best = 0;
  let bestDist = Infinity;
  let acc = 0;
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1]!;
    const b = points[i]!;
    const abx = b.x - a.x;
    const aby = b.y - a.y;
    const l2 = abx * abx + aby * aby;
    const tSeg =
      l2 === 0 ? 0 : Math.min(1, Math.max(0, ((p.x - a.x) * abx + (p.y - a.y) * aby) / l2));
    const proj = { x: a.x + abx * tSeg, y: a.y + aby * tSeg };
    const dist = Math.hypot(p.x - proj.x, p.y - proj.y);
    if (dist < bestDist) {
      bestDist = dist;
      best = (acc + lens[i - 1]! * tSeg) / total;
    }
    acc += lens[i - 1]!;
  }
  return best;
}

export const ThalyxEdgeComponent = memo(function ThalyxEdgeComponent({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  data,
}: EdgeProps) {
  const edgeModel = (data as ThalyxEdgeData | undefined)?.edge;
  const doc = useStore((s) => s.doc);
  const rf = useReactFlow();
  const gestureRef = useRef(false);

  const geometry = useMemo(() => {
    if (!edgeModel) return null;
    const sourceNode = doc.nodes.find((n) => n.id === edgeModel.source);
    const targetNode = doc.nodes.find((n) => n.id === edgeModel.target);
    if (!sourceNode || !targetNode) return null;
    const sAbs = absolutePosition(doc, sourceNode);
    const tAbs = absolutePosition(doc, targetNode);
    const { source, target, sourceSide, targetSide } = edgeEndpoints(
      sourceNode,
      sAbs,
      targetNode,
      tAbs,
      edgeModel.sourceAnchor,
      edgeModel.targetAnchor,
    );
    const sRect = { x: sAbs.x, y: sAbs.y, width: sourceNode.width, height: sourceNode.height };
    const tRect = { x: tAbs.x, y: tAbs.y, width: targetNode.width, height: targetNode.height };

    let points: Point[];
    if (edgeModel.waypoints && edgeModel.waypoints.length > 0) {
      points = [source, ...edgeModel.waypoints, target];
    } else if (edgeModel.kind === 'elbow') {
      points = route(source, target, sRect, tRect, sourceSide, targetSide);
    } else {
      points = [source, target];
    }
    return { points };
  }, [doc, edgeModel]);

  const strokeColor = edgeModel ? colorStyle(edgeModel.style.stroke, 'stroke') : 'var(--ink)';

  const pathD = useMemo(() => {
    if (!geometry || !edgeModel) return '';
    if (edgeModel.kind === 'straight') {
      const [p0, p1] = geometry.points;
      const [straightPath] = getStraightPath({
        sourceX: p0?.x ?? sourceX,
        sourceY: p0?.y ?? sourceY,
        targetX: p1?.x ?? targetX,
        targetY: p1?.y ?? targetY,
      });
      return straightPath;
    }
    if (edgeModel.kind === 'curved') {
      const [p0, p1] = geometry.points;
      const [bezierPath] = getBezierPath({
        sourceX: p0?.x ?? sourceX,
        sourceY: p0?.y ?? sourceY,
        sourcePosition,
        targetX: p1?.x ?? targetX,
        targetY: p1?.y ?? targetY,
        targetPosition,
      });
      return bezierPath;
    }
    return toPolylineD(geometry.points, edgeModel.style.rounded ? 6 : 0);
  }, [geometry, edgeModel, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition]);

  const labelPos = useMemo(() => {
    if (!geometry || !edgeModel?.label) return null;
    return pointAtT(geometry.points, edgeModel.labelT ?? 0.5);
  }, [geometry, edgeModel]);

  const runPointerDrag = useCallback(
    (e: React.PointerEvent, onMove: (flowPoint: Point) => void) => {
      e.stopPropagation();
      if (!gestureRef.current) {
        gestureRef.current = true;
        A.beginGesture();
      }
      const move = (ev: PointerEvent) => {
        onMove(rf.screenToFlowPosition({ x: ev.clientX, y: ev.clientY }));
      };
      const up = () => {
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', up);
        if (gestureRef.current) {
          gestureRef.current = false;
          A.endGesture();
        }
      };
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', up);
    },
    [rf],
  );

  /** Label chip drag: update labelT to the nearest point on the route. */
  const onLabelPointerDown = useCallback(
    (e: React.PointerEvent) => {
      if (!geometry) return;
      runPointerDrag(e, (p) => {
        A.updateEdge(id, { labelT: nearestT(geometry.points, p) });
      });
    },
    [geometry, id, runPointerDrag],
  );

  /**
   * Manual waypoints (§11.3): dragging the edge body perpendicular to itself
   * inserts a waypoint at the drag position (gesture-coalesced). Cleared
   * automatically when either endpoint moves (D12).
   */
  const onEdgePointerDown = useCallback(
    (e: React.PointerEvent) => {
      if (!geometry || !edgeModel) return;
      if (edgeModel.kind !== 'elbow') return;
      runPointerDrag(e, (p) => {
        A.setEdgeWaypoints(id, [{ x: Math.round(p.x), y: Math.round(p.y) }], { transient: true });
      });
    },
    [geometry, edgeModel, id, runPointerDrag],
  );

  if (!edgeModel || edgeModel.hidden || !geometry || !pathD) {
    return null;
  }

  const strokeWidth = edgeModel.style.line === 'thick' ? 4 : 2;
  const dash = edgeModel.style.line === 'dashed' ? '6 4' : undefined;
  const markerFor = (end: 'start' | 'end'): string | undefined => {
    const head = end === 'start' ? edgeModel!.arrowStart : edgeModel!.arrowEnd;
    if (head === 'none') return undefined;
    return `marker-${id}-${end}`;
  };

  return (
    <>
      <defs>
        {(['start', 'end'] as const).map((end) => {
          const head = end === 'start' ? edgeModel.arrowStart : edgeModel.arrowEnd;
          if (head === 'none') return null;
          const markerId = `marker-${id}-${end}`;
          const size = 8;
          const orient = end === 'end' ? 'auto' : 'auto-start-reverse';
          return (
            <marker
              key={end}
              id={markerId}
              viewBox={`0 0 ${size} ${size}`}
              markerWidth={size}
              markerHeight={size}
              refX={end === 'end' ? size - 1 : 1}
              refY={size / 2}
              orient={orient}
              markerUnits="userSpaceOnUse"
            >
              {head === 'arrow' ? (
                <path
                  d={`M 0 ${size / 4} L ${size - 1} ${size / 2} L 0 ${(size * 3) / 4} Z`}
                  fill={strokeColor}
                />
              ) : head === 'circle' ? (
                <circle cx={size / 2} cy={size / 2} r={size / 2 - 1} fill={strokeColor} />
              ) : (
                <path
                  d={`M 0 0 L ${size - 1} ${size / 2} L 0 ${size} M ${size} 0 L 1 ${size / 2} L ${size} ${size}`}
                  stroke={strokeColor}
                  strokeWidth={1.5}
                  fill="none"
                />
              )}
            </marker>
          );
        })}
      </defs>
      {/* invisible wide path for easier grabbing */}
      <path
        d={pathD}
        fill="none"
        stroke="transparent"
        strokeWidth={16}
        style={{ pointerEvents: 'stroke', cursor: 'move' }}
        onPointerDown={onEdgePointerDown}
      />
      <BaseEdge
        id={id}
        path={pathD}
        style={{ stroke: strokeColor, strokeWidth, strokeDasharray: dash }}
        markerStart={markerFor('start')}
        markerEnd={markerFor('end')}
      />
      {edgeModel.label ? (
        <EdgeLabelRenderer>
          <div
            className="thalyx-edge-label nodrag nopan"
            style={{
              transform: `translate(-50%, -50%) translate(${labelPos!.x}px, ${labelPos!.y}px)`,
            }}
            onPointerDown={onLabelPointerDown}
          >
            {edgeModel.label}
          </div>
        </EdgeLabelRenderer>
      ) : null}
    </>
  );
});
