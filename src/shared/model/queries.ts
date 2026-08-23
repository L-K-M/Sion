/**
 * Selectors over the document model (PLAN.md §6). Pure functions.
 */
import type { ThalyxDoc, ThalyxEdge, ThalyxNode } from './types';

export function getNode(doc: ThalyxDoc, id: string): ThalyxNode | undefined {
  return doc.nodes.find((n) => n.id === id);
}

export function getEdge(doc: ThalyxDoc, id: string): ThalyxEdge | undefined {
  return doc.edges.find((e) => e.id === id);
}

/** Containment depth of a node (top level = 0). Guarded against cycles. */
export function depthOfNode(doc: ThalyxDoc, id: string): number {
  let depth = 0;
  let cursor = getNode(doc, id)?.parentId;
  const seen = new Set<string>();
  while (cursor !== undefined && !seen.has(cursor)) {
    seen.add(cursor);
    depth += 1;
    cursor = getNode(doc, cursor)?.parentId;
  }
  return depth;
}

/** Direct children of a container (array order). */
export function childrenOf(doc: ThalyxDoc, parentId: string): ThalyxNode[] {
  return doc.nodes.filter((n) => n.parentId === parentId);
}

/** All descendants (children, recursively), in array order. */
export function descendantsOf(doc: ThalyxDoc, id: string): ThalyxNode[] {
  const out: ThalyxNode[] = [];
  const walk = (pid: string) => {
    for (const n of doc.nodes) {
      if (n.parentId === pid) {
        out.push(n);
        if (n.kind === 'container') walk(n.id);
      }
    }
  };
  walk(id);
  return out;
}

export function isAncestorOf(doc: ThalyxDoc, ancestorId: string, nodeId: string): boolean {
  let cursor = getNode(doc, nodeId)?.parentId;
  let steps = 0;
  while (cursor !== undefined && steps < 1000) {
    if (cursor === ancestorId) return true;
    cursor = getNode(doc, cursor)?.parentId;
    steps += 1;
  }
  return false;
}

export function edgesOfNode(doc: ThalyxDoc, nodeId: string): ThalyxEdge[] {
  return doc.edges.filter((e) => e.source === nodeId || e.target === nodeId);
}

/** Edges with BOTH endpoints inside the given set (intra-selection edges). */
export function edgesAmong(doc: ThalyxDoc, nodeIds: Set<string>): ThalyxEdge[] {
  return doc.edges.filter((e) => nodeIds.has(e.source) && nodeIds.has(e.target));
}

export interface AbsolutePoint {
  x: number;
  y: number;
}

/**
 * Absolute canvas position of a node: own (parent-relative) x/y plus the sum
 * of ancestor offsets (invariant §7.2.2/§7.2.7).
 */
export function absolutePosition(doc: ThalyxDoc, node: ThalyxNode): AbsolutePoint {
  let x = node.x;
  let y = node.y;
  let cursor = node.parentId;
  let steps = 0;
  while (cursor !== undefined && steps < 1000) {
    const parent = getNode(doc, cursor);
    if (!parent) break;
    x += parent.x;
    y += parent.y;
    cursor = parent.parentId;
    steps += 1;
  }
  return { x, y };
}

export interface Bounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** Union bounds of nodes in ABSOLUTE coordinates. Returns null if empty. */
export function boundsOfNodes(doc: ThalyxDoc, nodes: ThalyxNode[]): Bounds | null {
  if (nodes.length === 0) return null;
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const n of nodes) {
    const p = absolutePosition(doc, n);
    minX = Math.min(minX, p.x);
    minY = Math.min(minY, p.y);
    maxX = Math.max(maxX, p.x + n.width);
    maxY = Math.max(maxY, p.y + n.height);
  }
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

/** Bounds of all VISIBLE content (for zoom-to-fit; hidden nodes excluded). */
export function contentBounds(doc: ThalyxDoc): Bounds | null {
  return boundsOfNodes(
    doc,
    doc.nodes.filter((n) => !n.hidden),
  );
}

/**
 * Convert a node's stored (parent-relative) coordinates to the equivalent
 * coordinates under `newParentId` (or top level when undefined) such that the
 * node's ABSOLUTE position is unchanged — invariant §7.2.7. Pure: returns a
 * new {x,y}, does not mutate.
 */
export function positionUnderParent(
  doc: ThalyxDoc,
  node: ThalyxNode,
  newParentId: string | undefined,
): AbsolutePoint {
  const abs = absolutePosition(doc, node);
  if (newParentId === undefined) return abs;
  const parentAbs = getNode(doc, newParentId);
  if (!parentAbs) return abs;
  const p = absolutePosition(doc, parentAbs);
  return { x: abs.x - p.x, y: abs.y - p.y };
}
