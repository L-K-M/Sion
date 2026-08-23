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

export function toReactFlowNodes(doc: ThalyxDoc, session: SessionState): Node<ThalyxNodeData>[] {
  const selected = new Set(session.selection.nodeIds);
  return doc.nodes.map((n) => ({
    id: n.id,
    type: n.kind === 'mermaid' ? 'mermaid' : n.kind,
    position: { x: n.x, y: n.y },
    // Explicit wrapper size — custom node content is absolutely positioned and
    // cannot size the wrapper itself (RF hides unmeasured nodes).
    style: { width: n.width, height: n.height },
    ...(n.parentId !== undefined ? { parentId: n.parentId } : {}),
    ...(n.parentId !== undefined ? { extent: 'parent' as const } : {}),
    data: { node: n },
    selected: selected.has(n.id),
    hidden: n.hidden === true,
    draggable: n.locked !== true,
    selectable: n.locked !== true,
    deletable: true,
    dragHandle: undefined,
  }));
}

export function toReactFlowEdges(doc: ThalyxDoc, session: SessionState): Edge<ThalyxEdgeData>[] {
  // M2: minimal straight-line edges so fixture docs read; the custom thalyx
  // edge (elbow/straight/curved, labels, arrowheads) lands in M3.
  const selected = new Set(session.selection.edgeIds);
  void selected;
  return doc.edges.map((e) => ({
    id: e.id,
    source: e.source,
    target: e.target,
    type: 'straight',
    hidden: e.hidden === true,
    data: { edge: e },
  }));
}
