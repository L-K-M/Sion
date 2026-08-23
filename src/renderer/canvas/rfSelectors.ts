/**
 * Doc → React Flow view-model selectors (PLAN.md §8.1: RF is controlled).
 * Lives in the renderer (React Flow types never enter src/shared — §11.7).
 */
import type { Edge, Node } from '@xyflow/react';
import type { ThalyxDoc, ThalyxEdge, ThalyxNode } from '../../shared/model/types';
import type { SessionState } from '../store/store';

export interface ThalyxNodeData extends Record<string, unknown> {
  node: ThalyxNode;
}

export interface ThalyxEdgeData extends Record<string, unknown> {
  edge: ThalyxEdge;
}

// Identity-stable `data` wrappers: unchanged model objects keep the same
// wrapper across selector recomputes, so RF skips re-rendering untouched
// nodes when the memo rebuilds (e.g. after a selection change).
const nodeDataCache = new WeakMap<ThalyxNode, ThalyxNodeData>();
const edgeDataCache = new WeakMap<ThalyxEdge, ThalyxEdgeData>();

function nodeData(n: ThalyxNode): ThalyxNodeData {
  let d = nodeDataCache.get(n);
  if (!d) {
    d = { node: n };
    nodeDataCache.set(n, d);
  }
  return d;
}

function edgeData(e: ThalyxEdge): ThalyxEdgeData {
  let d = edgeDataCache.get(e);
  if (!d) {
    d = { edge: e };
    edgeDataCache.set(e, d);
  }
  return d;
}

export function toReactFlowNodes(
  doc: ThalyxDoc,
  selection: SessionState['selection'],
): Node<ThalyxNodeData>[] {
  const selected = new Set(selection.nodeIds);
  return doc.nodes.map((n) => ({
    id: n.id,
    type: n.kind === 'mermaid' ? 'mermaid' : n.kind,
    position: { x: n.x, y: n.y },
    // Explicit wrapper size — custom node content is absolutely positioned and
    // cannot size the wrapper itself (RF hides unmeasured nodes).
    style: { width: n.width, height: n.height },
    ...(n.parentId !== undefined ? { parentId: n.parentId } : {}),
    ...(n.parentId !== undefined ? { extent: 'parent' as const } : {}),
    data: nodeData(n),
    selected: selected.has(n.id),
    hidden: n.hidden === true,
    draggable: n.locked !== true,
    selectable: n.locked !== true,
    deletable: true,
    dragHandle: undefined,
  }));
}

export function toReactFlowEdges(
  doc: ThalyxDoc,
  selection: SessionState['selection'],
): Edge<ThalyxEdgeData>[] {
  // M2: minimal straight-line edges so fixture docs read; the custom thalyx
  // edge (elbow/straight/curved, labels, arrowheads) lands in M3.
  const selected = new Set(selection.edgeIds);
  return doc.edges.map((e) => ({
    id: e.id,
    source: e.source,
    target: e.target,
    type: 'straight',
    selected: selected.has(e.id),
    hidden: e.hidden === true,
    data: edgeData(e),
  }));
}
