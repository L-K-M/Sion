/**
 * Actions catalog (PLAN.md §8.3). ALL doc mutations live here — every mutation
 * is a named function over plain data, wrapped by `tracked` (one history
 * entry) or `transient` (drag frames). One user intent = one history entry:
 * multi-step actions (delete node + its edges; duplicate + re-id; group…)
 * mutate once inside a single produce.
 *
 * Mermaid/layout actions (importMermaidAsNew, applyMermaidText, autoLayout,
 * tidyUp, ensureMermaidIds) arrive with milestones M4–M8 per the plan.
 */
import { produce } from 'immer';
import {
  newDoc as newDocFactory,
  newEdge as newEdgeFactory,
  newId,
  newNode as newNodeFactory,
} from '../../shared/model/create';
import { restoreDocument } from '../../shared/model/restore';
import { importMermaid } from '../../shared/mermaid/import';
import { layoutAll, layoutSubset } from '../../shared/layout/dagreLayout';
import { tidyUp } from '../../shared/layout/tidy';
import {
  absolutePosition,
  boundsOfNodes,
  depthOfNode,
  descendantIdsOf,
  descendantsOf,
  edgesAmong,
  getNode,
  positionUnderParent,
} from '../../shared/model/queries';
import type { GuideLine } from '../../shared/snap/snap';
import { LABEL_MAX } from '../../shared/model/schema';
import { MIN_CONTAINER_HEIGHT, MIN_CONTAINER_WIDTH } from '../../shared/model/nodeSizes';
import type {
  ArrowHead,
  EdgeKind,
  EdgeStyle,
  NodeStyle,
  ShapeKind,
  ThalyxDoc,
  ThalyxEdge,
  ThalyxNode,
  Tool,
} from '../../shared/model/types';
import { getStore, setStore } from './store';
import type { SessionState } from './store';
import * as H from './history';

// ---------------------------------------------------------------------------
// wrappers
// ---------------------------------------------------------------------------

type Producer = (doc: ThalyxDoc) => void;
type SessionPatch = Partial<SessionState> | ((s: SessionState) => Partial<SessionState>);

function applySessionPatch(s: SessionState, patch: SessionPatch | undefined): SessionState {
  if (!patch) return s;
  return { ...s, ...(typeof patch === 'function' ? patch(s) : patch) };
}

/** Tracked mutation: one history entry; marks the doc dirty. */
function tracked(producer: Producer, sessionPatch?: SessionPatch): void {
  const prev = getStore().doc;
  const next = produce(prev, producer);
  if (next === prev) return;
  setStore((s) => ({
    doc: next,
    history: H.commit(s.history, prev),
    session: applySessionPatch({ ...s.session, dirtySinceSave: true }, sessionPatch),
  }));
}

/** Transient mutation (drag frames): no history entry. */
function transient(producer: Producer): void {
  setStore((s) => {
    const next = produce(s.doc, producer);
    if (next === s.doc) return s; // nothing changed — do not dirty the doc
    return {
      doc: next,
      // Any doc change invalidates redo; the in-flight gesture (pending) is kept.
      history: { ...s.history, future: [] },
      session: { ...s.session, dirtySinceSave: true },
    };
  });
}

// ---------------------------------------------------------------------------
// history gestures + undo/redo
// ---------------------------------------------------------------------------

export function beginGesture(): void {
  setStore((s) => ({ history: H.beginGesture(s.history, s.doc) }));
}

export function endGesture(): void {
  setStore((s) => ({ history: H.endGesture(s.history, s.doc) }));
}

function pruneSelection(
  session: SessionState,
  doc: ThalyxDoc,
): { nodeIds: string[]; edgeIds: string[] } {
  return {
    nodeIds: session.selection.nodeIds.filter((id) => doc.nodes.some((n) => n.id === id)),
    edgeIds: session.selection.edgeIds.filter((id) => doc.edges.some((e) => e.id === id)),
  };
}

export function undo(): void {
  const { doc, history } = getStore();
  const res = H.undo(history, doc);
  if (!res) return;
  setStore((s) => ({
    doc: res.doc,
    history: res.history,
    session: { ...s.session, selection: pruneSelection(s.session, res.doc), editingLabel: null },
  }));
}

export function redo(): void {
  const { doc, history } = getStore();
  const res = H.redo(history, doc);
  if (!res) return;
  setStore((s) => ({
    doc: res.doc,
    history: res.history,
    session: { ...s.session, selection: pruneSelection(s.session, res.doc), editingLabel: null },
  }));
}

// ---------------------------------------------------------------------------
// node actions
// ---------------------------------------------------------------------------

function clampLabel(label: string): string {
  return label.slice(0, LABEL_MAX);
}

export function addNode(init: Parameters<typeof newNodeFactory>[0]): string {
  const node = newNodeFactory(init);
  tracked(
    (d) => {
      d.nodes.push(node);
    },
    { selection: { nodeIds: [node.id], edgeIds: [] } },
  );
  return node.id;
}

export function updateNodeLabel(id: string, label: string): void {
  tracked((d) => {
    const n = d.nodes.find((x) => x.id === id);
    if (n) n.label = clampLabel(label);
  });
}

export function updateNodesStyle(ids: string[], patch: Partial<NodeStyle>): void {
  tracked((d) => {
    for (const n of d.nodes) {
      if (ids.includes(n.id)) Object.assign(n.style, patch);
    }
  });
}

export function setNodeShape(id: string, shape: ShapeKind): void {
  tracked((d) => {
    const n = d.nodes.find((x) => x.id === id);
    if (n && n.kind === 'shape') n.shape = shape;
  });
}

/** Set/clear a node's mermaid link (§10.3 context panel). */
export function setNodeLink(id: string, link: string | undefined): void {
  // Normalize/validate BEFORE touching the doc (§14.4): empty clears,
  // http/https/mailto pass through, anything else is refused — a no-change
  // call then produces a no-op draft and no history entry.
  let safe: string | null = null;
  if (link !== undefined && link.trim().length > 0) {
    safe = link.trim().slice(0, 2048);
    try {
      const scheme = new URL(safe).protocol;
      if (!['https:', 'http:', 'mailto:'].includes(scheme)) return; // refused
    } catch {
      safe = `https://${safe}`;
      // re-validate the synthesized URL with the parser
      try {
        new URL(safe);
      } catch {
        return;
      }
    }
  }
  tracked((d) => {
    const n = d.nodes.find((x) => x.id === id);
    if (!n) return;
    const current = n.meta?.mermaid?.link;
    if (current === (safe ?? undefined)) return; // no-op
    n.meta ??= {};
    n.meta.mermaid ??= {};
    if (safe === null) {
      delete n.meta.mermaid.link;
      // prune empty meta objects so the model stays clean
      if (Object.keys(n.meta.mermaid).length === 0) delete n.meta.mermaid;
      if (n.meta && Object.keys(n.meta).length === 0) delete n.meta;
      return;
    }
    n.meta.mermaid.link = safe;
  });
}

export function setNodesLocked(ids: string[], locked: boolean): void {
  tracked((d) => {
    for (const n of d.nodes) {
      if (ids.includes(n.id)) n.locked = locked;
    }
  });
}

enum WaypointInvalidationScope {
  Node = 'node',
  Subtree = 'subtree',
}

function invalidateWaypointsForMovedNodes(
  doc: ThalyxDoc,
  nodeIds: Iterable<string>,
  scope: WaypointInvalidationScope = WaypointInvalidationScope.Subtree,
): void {
  if (!doc.edges.some((edge) => edge.waypoints && edge.waypoints.length > 0)) return;

  const roots = [...nodeIds];
  const affected = new Set(roots);
  if (scope === WaypointInvalidationScope.Subtree) {
    for (const id of descendantIdsOf(doc, roots)) affected.add(id);
  }
  if (affected.size === 0) return;

  for (const edge of doc.edges) {
    if (edge.waypoints && (affected.has(edge.source) || affected.has(edge.target))) {
      delete edge.waypoints;
    }
  }
}

/** Drag frames: apply positions without history entries. */
export function moveNodesTransient(positions: Array<{ id: string; x: number; y: number }>): void {
  transient((d) => {
    const map = new Map(positions.map((p) => [p.id, p]));
    const affected = new Set(descendantIdsOf(d, map.keys()));
    for (const id of map.keys()) affected.add(id);

    const before = indexNodeGeometry(d.nodes).positions;
    for (const n of d.nodes) {
      const p = map.get(n.id);
      if (p && !n.locked) {
        if (n.x === p.x && n.y === p.y) continue;
        n.x = p.x;
        n.y = p.y;
      }
    }

    const after = indexNodeGeometry(d.nodes).positions;
    const moved = [...affected].filter((id) => {
      const oldPosition = before.get(id);
      const newPosition = after.get(id);

      return oldPosition?.x !== newPosition?.x || oldPosition?.y !== newPosition?.y;
    });

    invalidateWaypointsForMovedNodes(d, moved, WaypointInvalidationScope.Node);
  });
}

interface IndexedNodeGeometry {
  byId: Map<string, ThalyxNode>;
  positions: Map<string, { x: number; y: number }>;
}

/** Resolve every absolute position once; parent lookup stays constant-time. */
function indexNodeGeometry(nodes: ThalyxNode[]): IndexedNodeGeometry {
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const positions = new Map<string, { x: number; y: number }>();

  for (const node of nodes) {
    if (positions.has(node.id)) continue;

    const chain: ThalyxNode[] = [];
    const seen = new Set<string>();
    let cursor: ThalyxNode | undefined = node;
    while (cursor && !positions.has(cursor.id) && !seen.has(cursor.id)) {
      seen.add(cursor.id);
      chain.push(cursor);
      cursor = cursor.parentId ? byId.get(cursor.parentId) : undefined;
    }

    let position = cursor ? (positions.get(cursor.id) ?? { x: 0, y: 0 }) : { x: 0, y: 0 };
    while (chain.length > 0) {
      const current = chain.pop()!;
      position = { x: position.x + current.x, y: position.y + current.y };
      positions.set(current.id, position);
    }
  }

  return { byId, positions };
}

function ancestorIds(node: ThalyxNode, byId: Map<string, ThalyxNode>): Set<string> {
  const ancestors = new Set<string>();
  let cursor = node.parentId;
  while (cursor !== undefined && !ancestors.has(cursor)) {
    ancestors.add(cursor);
    cursor = byId.get(cursor)?.parentId;
  }

  return ancestors;
}

function parentsBeforeChildren(nodes: ThalyxNode[]): ThalyxNode[] {
  const ordered: ThalyxNode[] = [];
  const emitted = new Set<string>();
  let pending = nodes;

  while (pending.length > 0) {
    const deferred: ThalyxNode[] = [];
    for (const node of pending) {
      if (node.parentId !== undefined && !emitted.has(node.parentId)) {
        deferred.push(node);
        continue;
      }

      emitted.add(node.id);
      ordered.push(node);
    }
    if (deferred.length === pending.length) return nodes;

    pending = deferred;
  }

  return ordered;
}

/** Reparent dropped nodes by full containment while preserving absolute positions. */
export function reparentNodesTransient(ids: string[]): void {
  transient((doc) => {
    const { byId, positions } = indexNodeGeometry(doc.nodes);
    const containers = doc.nodes
      .filter((node) => node.kind === 'container')
      .map((node) => ({
        node,
        position: positions.get(node.id)!,
        ancestors: ancestorIds(node, byId),
        area: node.width * node.height,
      }));
    let changed = false;

    for (const id of new Set(ids)) {
      const node = byId.get(id);
      const absolute = positions.get(id);
      if (!node || !absolute || node.locked) continue;

      let destination: (typeof containers)[number] | undefined;
      for (const candidate of containers) {
        if (candidate.node.id === id || candidate.ancestors.has(id)) continue;

        const contains =
          absolute.x >= candidate.position.x &&
          absolute.y >= candidate.position.y &&
          absolute.x + node.width <= candidate.position.x + candidate.node.width &&
          absolute.y + node.height <= candidate.position.y + candidate.node.height;
        if (!contains || (destination && candidate.area >= destination.area)) continue;

        destination = candidate;
      }

      const nextParentId = destination?.node.id;
      if (node.parentId === nextParentId) continue;

      node.parentId = nextParentId;
      node.x = absolute.x - (destination?.position.x ?? 0);
      node.y = absolute.y - (destination?.position.y ?? 0);
      changed = true;
    }

    if (changed) doc.nodes = parentsBeforeChildren(doc.nodes);
  });
}

export function resizeNodeTransient(
  id: string,
  box: { x?: number; y?: number; width: number; height: number },
): void {
  transient((d) => {
    const n = d.nodes.find((x) => x.id === id);
    if (!n || n.locked) return;
    const minWidth = n.kind === 'container' ? MIN_CONTAINER_WIDTH : 8;
    const minHeight = n.kind === 'container' ? MIN_CONTAINER_HEIGHT : 8;
    const nextWidth = Math.max(minWidth, box.width);
    const nextHeight = Math.max(minHeight, box.height);
    const positionChanged =
      (box.x !== undefined && box.x !== n.x) || (box.y !== undefined && box.y !== n.y);
    const dimensionsChanged = nextWidth !== n.width || nextHeight !== n.height;
    if (!positionChanged && !dimensionsChanged) return;

    if (box.x !== undefined) n.x = box.x;
    if (box.y !== undefined) n.y = box.y;
    n.width = nextWidth;
    n.height = nextHeight;
    invalidateWaypointsForMovedNodes(
      d,
      [id],
      positionChanged ? WaypointInvalidationScope.Subtree : WaypointInvalidationScope.Node,
    );
  });
}

/** Tracked position set — used by layout actions (M4) and tests. */
export function setNodesPosition(
  ids: string[],
  pos: (node: ThalyxNode) => { x: number; y: number },
): void {
  tracked((d) => {
    const moved: string[] = [];
    for (const n of d.nodes) {
      if (ids.includes(n.id) && !n.locked) {
        const p = pos(n);
        if (n.x === p.x && n.y === p.y) continue;
        n.x = p.x;
        n.y = p.y;
        moved.push(n.id);
      }
    }
    invalidateWaypointsForMovedNodes(d, moved);
  });
}

// ---------------------------------------------------------------------------
// selection / delete / duplicate
// ---------------------------------------------------------------------------

function selectedNodes(d: ThalyxDoc, sel: SessionState): ThalyxNode[] {
  return d.nodes.filter((n) => sel.selection.nodeIds.includes(n.id));
}

function expandedSelectionNodeIds(doc: ThalyxDoc, selectedIds: Iterable<string>): Set<string> {
  const nodeIds = new Set(selectedIds);
  const containerIds = doc.nodes
    .filter((node) => node.kind === 'container' && nodeIds.has(node.id))
    .map((node) => node.id);
  for (const id of descendantIdsOf(doc, containerIds)) nodeIds.add(id);

  return nodeIds;
}

function deleteSelectionIds(selectedNodeIds: string[], selectedEdgeIds: string[]): void {
  if (selectedNodeIds.length === 0 && selectedEdgeIds.length === 0) return;

  tracked(
    (doc) => {
      const nodeIds = expandedSelectionNodeIds(doc, selectedNodeIds);
      const edgeIds = new Set(selectedEdgeIds);
      for (const edge of doc.edges) {
        if (nodeIds.has(edge.source) || nodeIds.has(edge.target)) edgeIds.add(edge.id);
      }

      const nodes = doc.nodes.filter((node) => !nodeIds.has(node.id));
      const edges = doc.edges.filter((edge) => !edgeIds.has(edge.id));
      if (nodes.length !== doc.nodes.length) doc.nodes = nodes;
      if (edges.length !== doc.edges.length) doc.edges = edges;
    },
    { selection: { nodeIds: [], edgeIds: [] }, editingLabel: null },
  );
}

/** Delete the current selection and contained descendants as one intent. */
export function deleteSelection(): void {
  const selection = getStore().session.selection;
  deleteSelectionIds(selection.nodeIds, selection.edgeIds);
}

export interface ReIdResult {
  nodes: ThalyxNode[];
  edges: ThalyxEdge[];
  /** original id → fresh id (for callers that must map positions etc.) */
  idMap: Map<string, string>;
}

/** Detach copied roots without losing their absolute canvas position. */
function detachedSubgraphRoots(doc: ThalyxDoc, nodes: ThalyxNode[]): ThalyxNode[] {
  const included = new Set(nodes.map((node) => node.id));
  return nodes.map((node) => {
    if (node.parentId !== undefined && included.has(node.parentId)) return node;

    const position = absolutePosition(doc, node);
    const detached = { ...node, x: position.x, y: position.y };
    delete detached.parentId;
    return detached;
  });
}

/** Re-id a set of nodes + intra-set edges with fresh ids (paste/duplicate core). */
function reIdSubgraph(
  nodes: ThalyxNode[],
  edges: ThalyxEdge[],
  dx: number,
  dy: number,
): ReIdResult {
  // Pass 1: assign ALL fresh ids first, so parentId remapping in pass 2 sees
  // the complete map regardless of input order (child may precede parent).
  const idMap = new Map<string, string>();
  for (const n of nodes) idMap.set(n.id, newId());
  const remapId = (id: string): string => idMap.get(id) ?? id;
  const connectableIds = new Set(
    nodes.filter((node) => node.kind !== 'mermaid').map((node) => node.id),
  );
  const newNodes = nodes.map((n) => ({
    ...n,
    id: idMap.get(n.id)!,
    x: n.x + (n.parentId !== undefined && idMap.has(n.parentId) ? 0 : dx),
    y: n.y + (n.parentId !== undefined && idMap.has(n.parentId) ? 0 : dy),
    // Containment must stay within the pasted subgraph — a parentId pointing
    // outside it would dangle (invariant §7.2.2).
    parentId:
      n.parentId !== undefined && idMap.has(n.parentId) ? idMap.get(n.parentId)! : undefined,
    meta: n.meta ? JSON.parse(JSON.stringify(n.meta)) : undefined,
  }));
  // Edges must resolve inside the pasted subgraph (invariant §7.2.1).
  const newEdges = edges
    .filter(
      (edge) =>
        edge.source !== edge.target &&
        connectableIds.has(edge.source) &&
        connectableIds.has(edge.target),
    )
    .map((e) => ({
      ...e,
      id: newId(),
      source: remapId(e.source),
      target: remapId(e.target),
      waypoints: e.waypoints?.map((p) => ({ x: p.x + dx, y: p.y + dy })),
      meta: e.meta ? JSON.parse(JSON.stringify(e.meta)) : undefined,
    }));
  return { nodes: parentsBeforeChildren(newNodes), edges: newEdges, idMap };
}

/**
 * Duplicate the current selection: fresh ids, +16/+16 px offset, intra-selection
 * edges preserved (others not), duplicates become the new selection. One entry.
 */
export function duplicateSelection(): void {
  const state = getStore();
  const sel = state.session;
  const selected = selectedNodes(state.doc, sel);
  if (selected.length === 0) return;
  // containers duplicate with their descendants iff descendants are selected too;
  // a partially-selected container still duplicates whole (children re-id)
  const included = expandedSelectionNodeIds(
    state.doc,
    selected.map((node) => node.id),
  );
  const withDescendants = state.doc.nodes.filter((node) => included.has(node.id));
  const intra = edgesAmong(state.doc, new Set(withDescendants.map((n) => n.id)));
  const detached = detachedSubgraphRoots(state.doc, withDescendants);
  const dup = reIdSubgraph(detached, intra, 16, 16);
  tracked(
    (d) => {
      d.nodes.push(...dup.nodes);
      d.edges.push(...dup.edges);
    },
    { selection: { nodeIds: dup.nodes.map((n) => n.id), edgeIds: [] } },
  );
}

/**
 * Auto-layout (§11.5): one shot, one history entry. Lays out the selection's
 * connected subgraph, or the whole document when nothing is selected.
 * Direction from doc.meta unless overridden.
 */
export function autoLayout(directionOverride?: 'TB' | 'BT' | 'LR' | 'RL'): void {
  const state = getStore();
  const sel = state.session.selection.nodeIds;
  const direction = directionOverride ?? state.doc.meta.mermaid?.direction ?? 'TB';
  // Whole-doc layout only when NOTHING is selected; a partial selection
  // (even 1 node) lays out its subgraph (§11.5).
  const positions =
    sel.length > 0
      ? layoutSubset(state.doc, sel, { rankdir: direction })
      : layoutAll(state.doc, { rankdir: direction });
  if (positions.size === 0) return; // empty canvas: no no-op undo entry
  tracked((d) => {
    const moved: string[] = [];
    for (const n of d.nodes) {
      const p = positions.get(n.id);
      if (p && !n.locked) {
        if (n.x === p.x && n.y === p.y) continue;
        n.x = p.x;
        n.y = p.y;
        moved.push(n.id);
      }
    }
    invalidateWaypointsForMovedNodes(d, moved);
  });
}

/** Tidy Up (§11.5): even distribution of the selected unconnected shapes. */
export function tidyUpSelection(): void {
  const state = getStore();
  const sel = state.session.selection.nodeIds;
  const nodes = state.doc.nodes.filter((n) => sel.includes(n.id) && !n.locked && !n.hidden);
  if (nodes.length < 2) return;
  const { positions } = tidyUp(state.doc, nodes);
  tracked((d) => {
    const moved: string[] = [];
    for (const n of d.nodes) {
      const p = positions.get(n.id);
      if (p) {
        if (n.x === p.x && n.y === p.y) continue;
        n.x = p.x;
        n.y = p.y;
        moved.push(n.id);
      }
    }
    invalidateWaypointsForMovedNodes(d, moved);
  });
}

/**
 * Grow gesture (§11.6): create a connected node in `dir` from the source —
 * new node inherits style/size, edge inherits the last-used edge style,
 * gap 48 px (snapped to grid when on). ONE history entry; select + open the
 * label editor. If a node already sits within the corridor, connect to it
 * instead (draw.io rule).
 */
const OPPOSITE_ANCHOR: Record<
  Exclude<ThalyxEdge['sourceAnchor'], 'auto'>,
  Exclude<ThalyxEdge['targetAnchor'], 'auto'>
> = { n: 's', s: 'n', e: 'w', w: 'e' };

export function growConnectedNode(
  sourceId: string,
  dir: 'n' | 's' | 'e' | 'w',
  opts: { shape?: ShapeKind; grid?: boolean } = {},
): string | null {
  const state = getStore();
  const doc = state.doc;
  const source = doc.nodes.find((n) => n.id === sourceId);
  if (!source || source.kind !== 'shape') return null;
  const sAbs = absolutePosition(doc, source);
  const GAP = 48;

  const sourceRect = { x: sAbs.x, y: sAbs.y, w: source.width, h: source.height };
  const oppositeAnchor = OPPOSITE_ANCHOR[dir];
  let best: { id: string; dist: number } | null = null;
  for (const n of doc.nodes) {
    if (n.id === sourceId || n.hidden || n.kind === 'mermaid' || n.kind === 'container') continue;
    const abs = absolutePosition(doc, n);
    const r = { x: abs.x, y: abs.y, w: n.width, h: n.height };
    const gapAlong =
      dir === 'e'
        ? r.x - (sourceRect.x + sourceRect.w)
        : dir === 'w'
          ? sourceRect.x - (r.x + r.w)
          : dir === 's'
            ? r.y - (sourceRect.y + sourceRect.h)
            : sourceRect.y - (r.y + r.h);
    // corridor reach: the new node we would create occupies GAP + width;
    // accept an existing node up to that reach along the direction
    const reach = (dir === 'e' || dir === 'w' ? source.width : source.height) + GAP * 1.5;
    if (gapAlong < -8 || gapAlong > reach) continue;
    const overlapPerp =
      dir === 'e' || dir === 'w'
        ? Math.min(sourceRect.y + sourceRect.h, r.y + r.h) - Math.max(sourceRect.y, r.y)
        : Math.min(sourceRect.x + sourceRect.w, r.x + r.w) - Math.max(sourceRect.x, r.x);
    if (overlapPerp <= 0) continue;
    if (!best || gapAlong < best.dist) best = { id: n.id, dist: gapAlong };
  }

  if (best) {
    // draw.io rule: the corridor connects — but never duplicates an edge
    const exists = doc.edges.some(
      (e) =>
        !e.hidden &&
        ((e.source === sourceId && e.target === best!.id) ||
          (e.source === best!.id && e.target === sourceId)),
    );
    if (!exists) {
      connectEdge(sourceId, best.id, 'arrow', {
        sourceAnchor: dir,
        targetAnchor: oppositeAnchor,
      });
    }
    setStore((s) => ({
      session: { ...s.session, selection: { nodeIds: [best!.id], edgeIds: [] } },
    }));
    return best.id;
  }

  // create a new node in the direction
  let nx = sAbs.x;
  let ny = sAbs.y;
  if (dir === 'e') nx = sourceRect.x + sourceRect.w + GAP;
  if (dir === 'w') nx = sourceRect.x - GAP - source.width;
  if (dir === 's') ny = sourceRect.y + sourceRect.h + GAP;
  if (dir === 'n') ny = sourceRect.y - GAP - source.height;
  if (opts.grid) {
    nx = Math.round(nx / 8) * 8;
    ny = Math.round(ny / 8) * 8;
  }
  const shape = opts.shape ?? (source.kind === 'shape' ? (source.shape ?? 'rounded') : 'rounded');
  const grown = newNodeFactory({
    kind: 'shape',
    shape,
    x: nx,
    y: ny,
    width: source.width,
    height: source.height,
    style: { ...source.style },
  });
  let ancestorId = source.parentId;
  while (ancestorId !== undefined) {
    const ancestor = getNode(doc, ancestorId);
    if (!ancestor) break;

    const ancestorAbsolute = absolutePosition(doc, ancestor);
    const fitsAncestor =
      grown.x >= ancestorAbsolute.x &&
      grown.y >= ancestorAbsolute.y &&
      grown.x + grown.width <= ancestorAbsolute.x + ancestor.width &&
      grown.y + grown.height <= ancestorAbsolute.y + ancestor.height;
    if (fitsAncestor) {
      grown.x -= ancestorAbsolute.x;
      grown.y -= ancestorAbsolute.y;
      grown.parentId = ancestor.id;
      break;
    }

    ancestorId = ancestor.parentId;
  }

  const session = getStore().session;
  const arrowEnd = session.lastEdgeStyle.arrowEnd;
  const line = session.lastEdgeStyle.line;
  const edge = newEdgeFactory({
    source: sourceId,
    target: grown.id,
    sourceAnchor: dir,
    targetAnchor: oppositeAnchor,
    arrowStart: 'none',
    arrowEnd,
    style: { line },
  });
  tracked(
    (d) => {
      d.nodes.push(grown);
      d.edges.push(edge);
    },
    {
      selection: { nodeIds: [grown.id], edgeIds: [] },
      editingLabel: { kind: 'node', id: grown.id },
    },
  );
  return grown.id;
}

export function pasteInternal(nodes: ThalyxNode[], edges: ThalyxEdge[]): void {
  if (nodes.length === 0) return;
  const pasted = reIdSubgraph(nodes, edges, 16, 16);
  tracked(
    (d) => {
      d.nodes.push(...pasted.nodes);
      d.edges.push(...pasted.edges);
    },
    { selection: { nodeIds: pasted.nodes.map((n) => n.id), edgeIds: [] } },
  );
}

export type AlignEdge = 'left' | 'hcenter' | 'right' | 'top' | 'vcenter' | 'bottom';

/** Align selected nodes along `edge` (absolute math; parent-relative restored). */
export function alignSelection(edge: AlignEdge): void {
  tracked((d) => {
    const sel = getStore().session;
    const nodes = d.nodes.filter((n) => sel.selection.nodeIds.includes(n.id) && !n.locked);
    if (nodes.length < 2) return;
    const bounds = boundsOfNodes(d, nodes);
    if (!bounds) return;
    const moved: string[] = [];
    for (const n of nodes) {
      let target: number;
      switch (edge) {
        case 'left':
          target = bounds.x;
          break;
        case 'hcenter':
          target = bounds.x + bounds.width / 2 - n.width / 2;
          break;
        case 'right':
          target = bounds.x + bounds.width - n.width;
          break;
        case 'top':
          target = bounds.y;
          break;
        case 'vcenter':
          target = bounds.y + bounds.height / 2 - n.height / 2;
          break;
        case 'bottom':
          target = bounds.y + bounds.height - n.height;
          break;
      }
      // convert absolute target back to the node's parent-relative frame
      const parent = n.parentId ? getNode(d, n.parentId) : undefined;
      const parentAbs = parent ? absolutePosition(d, parent) : { x: 0, y: 0 };
      if (edge === 'left' || edge === 'hcenter' || edge === 'right') {
        const x = target - parentAbs.x;
        if (n.x === x) continue;
        n.x = x;
      } else {
        const y = target - parentAbs.y;
        if (n.y === y) continue;
        n.y = y;
      }
      moved.push(n.id);
    }
    invalidateWaypointsForMovedNodes(d, moved);
  });
}

// ---------------------------------------------------------------------------
// z-order
// ---------------------------------------------------------------------------

export type ZOrderOp = 'forward' | 'backward' | 'front' | 'back';

/**
 * Reorder the selected nodes in the z-order array. A selection block moves
 * together with its descendants; containers always stay before their children
 * (invariant §7.2.3). One history entry.
 */
export function reorderZ(op: ZOrderOp): void {
  tracked((d) => {
    const sel = getStore().session;
    const selected = d.nodes.filter((n) => sel.selection.nodeIds.includes(n.id));
    if (selected.length === 0) return;
    const blockIds = new Set<string>();
    for (const n of selected) {
      blockIds.add(n.id);
      for (const desc of descendantsOf(d, n.id)) blockIds.add(desc.id);
    }
    // Ancestors of block members that are NOT part of the block: every one of
    // them must stay BEFORE the block (invariant §7.2.3) no matter how far the
    // block travels.
    const ancestors = new Set<string>();
    for (const id of blockIds) {
      let cursor = d.nodes.find((n) => n.id === id)?.parentId;
      let steps = 0;
      while (cursor !== undefined && !blockIds.has(cursor) && steps < 1000) {
        ancestors.add(cursor);
        cursor = d.nodes.find((n) => n.id === cursor)?.parentId;
        steps += 1;
      }
    }
    const block = d.nodes.filter((n) => blockIds.has(n.id));
    const rest = d.nodes.filter((n) => !blockIds.has(n.id));
    if (op === 'front') {
      // End of array: ancestors remain earlier — always safe.
      d.nodes = [...rest, ...block];
      return;
    }
    if (op === 'back') {
      // Clamp below the outermost ancestor: insert right after the LAST
      // ancestor in array order (start of array when there are none).
      let afterIdx = -1;
      for (const anc of ancestors) {
        const i = rest.findIndex((n) => n.id === anc);
        if (i > afterIdx) afterIdx = i;
      }
      const insertAt = afterIdx + 1;
      d.nodes = [...rest.slice(0, insertAt), ...block, ...rest.slice(insertAt)];
      return;
    }
    // one-step moves swap the block past the element adjacent in rest
    const lastBlockIdx = d.nodes.reduce((acc, n, i) => (blockIds.has(n.id) ? i : acc), -1);
    const firstBlockIdx = d.nodes.findIndex((n) => blockIds.has(n.id));
    if (op === 'forward' && lastBlockIdx >= 0 && lastBlockIdx < d.nodes.length - 1) {
      const after = d.nodes[lastBlockIdx + 1] as ThalyxNode;
      // ancestors always precede the block, so after can never be one;
      // descendants are inside the block — safe to move past.
      const insertAt = rest.indexOf(after) + 1;
      d.nodes = [...rest.slice(0, insertAt), ...block, ...rest.slice(insertAt)];
    } else if (op === 'backward' && firstBlockIdx > 0) {
      const before = d.nodes[firstBlockIdx - 1] as ThalyxNode;
      if (ancestors.has(before.id)) return; // moving past an ancestor is forbidden
      const insertAt = rest.indexOf(before);
      d.nodes = [...rest.slice(0, insertAt), ...block, ...rest.slice(insertAt)];
    }
  });
}

// ---------------------------------------------------------------------------
// containers
// ---------------------------------------------------------------------------

const CONTAINER_PADDING = 24;

/**
 * Wrap the current node selection in a new container (D5). Children keep their
 * ABSOLUTE positions (invariant §7.2.7): stored coords become parent-relative.
 * The container's parent is the shared parent of the members (top level when
 * they differ). One history entry.
 */
export function groupIntoContainer(label = ''): void {
  const state = getStore();
  const members = selectedNodes(state.doc, state.session);
  if (members.length === 0) return;
  const doc = state.doc;
  const bounds = boundsOfNodes(doc, members);
  if (!bounds) return;
  const parents = new Set(members.map((m) => m.parentId ?? null));
  const containerParent = parents.size === 1 ? [...parents][0] : null;

  const container = newNodeFactory({
    kind: 'container',
    label,
    x: 0,
    y: 0,
    width: Math.max(8, bounds.width + CONTAINER_PADDING * 2),
    height: Math.max(8, bounds.height + CONTAINER_PADDING * 2),
    parentId: containerParent ?? undefined,
    style: { fill: 'surface', stroke: 'ink' },
  });
  // position the container so padded bounds match (absolute frame first)
  const containerAbs = {
    x: bounds.x - CONTAINER_PADDING,
    y: bounds.y - CONTAINER_PADDING,
  };
  if (containerParent) {
    const p = getNode(doc, containerParent);
    if (p) {
      const pAbs = absolutePosition(doc, p);
      container.x = containerAbs.x - pAbs.x;
      container.y = containerAbs.y - pAbs.y;
    }
  } else {
    container.x = containerAbs.x;
    container.y = containerAbs.y;
  }

  tracked(
    (d) => {
      const firstIdx = d.nodes.findIndex((n) => members.some((m) => m.id === n.id));
      const insertIdx = firstIdx === -1 ? d.nodes.length : firstIdx;
      d.nodes.splice(insertIdx, 0, container);
      for (const m of members) {
        const node = d.nodes.find((n) => n.id === m.id);
        if (!node) continue;
        const rel = positionUnderParent(d, node, container.id);
        node.parentId = container.id;
        node.x = rel.x;
        node.y = rel.y;
      }
    },
    { selection: { nodeIds: [container.id], edgeIds: [] } },
  );
}

/**
 * Dissolve the selected container(s): children are re-parented to the
 * container's parent (or top level) with coordinates converted so ABSOLUTE
 * positions are unchanged (invariant §7.2.7). The container node and its own
 * edges are removed; the freed children become the selection. One history
 * entry. Nested selected containers dissolve deepest-first.
 */
export function dissolveContainer(): void {
  const state = getStore();
  const containers = state.doc.nodes.filter(
    (n) => n.kind === 'container' && state.session.selection.nodeIds.includes(n.id),
  );
  if (containers.length === 0) return;

  // deepest-first: dissolving an inner container first re-parents its children
  // to the outer (dissolved later), then outward — absolute positions preserved.
  const ordered = [...containers].sort(
    (a, b) => depthOfNode(state.doc, b.id) - depthOfNode(state.doc, a.id),
  );
  const containerIds = new Set(ordered.map((c) => c.id));
  const freedChildIds: string[] = [];

  tracked(
    (d) => {
      for (const c of ordered) {
        for (const child of d.nodes.filter((n) => n.parentId === c.id)) {
          const rel = positionUnderParent(d, child, c.parentId);
          child.parentId = c.parentId;
          child.x = rel.x;
          child.y = rel.y;
          freedChildIds.push(child.id);
        }
      }
      d.nodes = d.nodes.filter((n) => !containerIds.has(n.id));
      d.edges = d.edges.filter((e) => !containerIds.has(e.source) && !containerIds.has(e.target));
    },
    // function form: freedChildIds is filled during the produce pass above
    () => ({ selection: { nodeIds: [...new Set(freedChildIds)], edgeIds: [] } }),
  );
}

// ---------------------------------------------------------------------------
// edges
// ---------------------------------------------------------------------------

export interface AddEdgeInit {
  source: string;
  target: string;
  sourceAnchor?: ThalyxEdge['sourceAnchor'];
  targetAnchor?: ThalyxEdge['targetAnchor'];
  kind?: EdgeKind;
  label?: string;
  arrowStart?: ArrowHead;
  arrowEnd?: ArrowHead;
  style?: Partial<EdgeStyle>;
}

/** Add an edge; endpoints must exist and not be islands (§7.2.1/5). */
export function addEdge(init: AddEdgeInit): string {
  const doc = getStore().doc;
  const source = getNode(doc, init.source);
  const target = getNode(doc, init.target);
  if (!source || !target)
    throw new Error(`addEdge: unknown endpoint (${init.source} → ${init.target})`);
  if (init.source === init.target) throw new Error('addEdge: self-connections are not allowed');
  if (source.kind === 'mermaid' || target.kind === 'mermaid') {
    throw new Error('addEdge: mermaid islands cannot participate in edges');
  }
  const edge = newEdgeFactory(init);
  tracked(
    (d) => {
      d.edges.push(edge);
    },
    { selection: { nodeIds: [], edgeIds: [edge.id] } },
  );
  return edge.id;
}

/**
 * Connect two nodes (the arrow/line tools and handle drags land here).
 * Inherits the last-used edge style (§10.1 delta 1) and records it back.
 */
export interface ConnectionAnchors {
  sourceAnchor?: ThalyxEdge['sourceAnchor'];
  targetAnchor?: ThalyxEdge['targetAnchor'];
}

export function connectEdge(
  source: string,
  target: string,
  tool: Tool,
  anchors: ConnectionAnchors = {},
): string {
  const session = getStore().session;
  const arrowEnd =
    tool === 'line' ? 'none' : tool === 'arrow' ? 'arrow' : session.lastEdgeStyle.arrowEnd;
  const line = session.lastEdgeStyle.line;
  const id = addEdge({
    source,
    target,
    ...anchors,
    arrowStart: 'none',
    arrowEnd,
    style: { line },
  });
  setStore((s) => ({
    session: { ...s.session, lastEdgeStyle: { arrowEnd, line } },
  }));
  return id;
}

/**
 * Alt-drag duplicate (I11): the user alt-dragged the selection — the ORIGINALS
 * return to their pre-drag positions and fresh duplicates land where the drag
 * ended. Net effect: one gesture leaves a copy behind. One history entry.
 */
export function altDragDuplicate(
  selectedIds: string[],
  finalPositions: Map<string, { x: number; y: number }>,
): void {
  const state = getStore();
  const doc = state.doc;
  const selected = doc.nodes.filter((n) => selectedIds.includes(n.id));
  if (selected.length === 0) return;
  const withDescendants: ThalyxNode[] = [];
  const seen = new Set<string>();
  for (const n of selected) {
    for (const m of [n, ...descendantsOf(doc, n.id)]) {
      if (!seen.has(m.id)) {
        seen.add(m.id);
        withDescendants.push(m);
      }
    }
  }
  const intra = edgesAmong(doc, new Set(withDescendants.map((n) => n.id)));
  const dup = reIdSubgraph(withDescendants, intra, 0, 0);
  // place each duplicate at the dragged final position (offset 0 — the user
  // chose the spot); originals keep their pre-drag coordinates (untouched).
  for (const orig of withDescendants) {
    const dupId = dup.idMap.get(orig.id);
    const dupNode = dup.nodes.find((n) => n.id === dupId);
    const fin = finalPositions.get(orig.id);
    if (dupNode && fin) {
      dupNode.x = fin.x;
      dupNode.y = fin.y;
    }
  }
  tracked(
    (dr) => {
      dr.nodes.push(...dup.nodes);
      dr.edges.push(...dup.edges);
    },
    { selection: { nodeIds: dup.nodes.map((n) => n.id), edgeIds: [] } },
  );
}

/** Finish Alt-drag inside its existing history gesture. */
export function finishAltDragDuplicate(selectedIds: string[]): string[] {
  const state = getStore();
  const original = state.history.pending;
  if (!original) return [];

  const selected = original.nodes.filter((node) => selectedIds.includes(node.id));
  if (selected.length === 0) {
    endGesture();
    return [];
  }

  const selectedSet = expandedSelectionNodeIds(
    original,
    selected.map((node) => node.id),
  );
  const selectedNodes = original.nodes.filter((node) => selectedSet.has(node.id));

  const roots = selectedNodes.filter(
    (node) => node.parentId === undefined || !selectedSet.has(node.parentId),
  );
  const currentById = new Map(state.doc.nodes.map((node) => [node.id, node]));
  const firstRoot = roots[0];
  const currentRoot = firstRoot ? currentById.get(firstRoot.id) : undefined;
  const originalAbsolute = firstRoot ? absolutePosition(original, firstRoot) : { x: 0, y: 0 };
  const currentAbsolute = currentRoot ? absolutePosition(state.doc, currentRoot) : originalAbsolute;
  const dx = currentAbsolute.x - originalAbsolute.x;
  const dy = currentAbsolute.y - originalAbsolute.y;

  const originalEdges = edgesAmong(original, selectedSet);
  const duplicate = reIdSubgraph(selectedNodes, originalEdges, 0, 0);
  for (const edge of duplicate.edges) {
    if (!edge.waypoints) continue;
    edge.waypoints = edge.waypoints.map((point) => ({
      x: point.x + dx,
      y: point.y + dy,
    }));
  }

  for (const root of roots) {
    const copyId = duplicate.idMap.get(root.id);
    const copy = duplicate.nodes.find((node) => node.id === copyId);
    const moved = currentById.get(root.id);
    if (!copy || !moved) continue;

    const absolute = absolutePosition(state.doc, moved);
    delete copy.parentId;
    copy.x = absolute.x;
    copy.y = absolute.y;
  }

  transient((doc) => {
    doc.nodes = [...original.nodes, ...duplicate.nodes];
    doc.edges = [...original.edges, ...duplicate.edges];
  });

  const copyRootIds = roots.flatMap((root) => {
    const id = duplicate.idMap.get(root.id);
    return id ? [id] : [];
  });
  reparentNodesTransient(copyRootIds);
  setStore((store) => ({
    session: {
      ...store.session,
      selection: { nodeIds: duplicate.nodes.map((node) => node.id), edgeIds: [] },
    },
  }));
  endGesture();
  return duplicate.nodes.map((node) => node.id);
}

/** Nudge (§10.2): move the selection by dx/dy (1 px, or 8 with Shift). */
export function nudgeSelection(dx: number, dy: number): void {
  tracked((d) => {
    const sel = getStore().session;
    const moved: string[] = [];
    for (const n of d.nodes) {
      if (sel.selection.nodeIds.includes(n.id) && !n.locked) {
        n.x += dx;
        n.y += dy;
        moved.push(n.id);
      }
    }
    invalidateWaypointsForMovedNodes(d, moved);
  });
}

export function setLastEdgeStyle(style: {
  arrowEnd: 'none' | 'arrow';
  line: 'solid' | 'dashed' | 'thick';
}): void {
  setStore((s) => ({ session: { ...s.session, lastEdgeStyle: style } }));
}

type EdgePatch = Partial<Omit<ThalyxEdge, 'id' | 'source' | 'target'>>;

function applyEdgeModelPatch(edge: ThalyxEdge, patch: EdgePatch): void {
  const next = { ...patch };
  if (next.label !== undefined) next.label = next.label.slice(0, LABEL_MAX);
  Object.assign(edge, next);
  if (edge.labelT !== undefined) edge.labelT = Math.min(1, Math.max(0, edge.labelT));
}

function applyEdgePatch(doc: ThalyxDoc, id: string, patch: EdgePatch): void {
  const edge = doc.edges.find((candidate) => candidate.id === id);
  if (edge) applyEdgeModelPatch(edge, patch);
}

export function updateEdge(id: string, patch: EdgePatch): void {
  tracked((doc) => applyEdgePatch(doc, id, patch));
}

/** Update a connector selection as one user action and Undo entry. */
export function updateEdges(ids: string[], patch: (edge: ThalyxEdge) => EdgePatch): void {
  if (ids.length === 0) return;
  const selected = new Set(ids);

  tracked((doc) => {
    for (const edge of doc.edges) {
      if (selected.has(edge.id)) applyEdgeModelPatch(edge, patch(edge));
    }
  });
}

/** Pointer-frame edge patch; the surrounding gesture owns its undo entry. */
export function updateEdgeTransient(id: string, patch: EdgePatch): void {
  transient((doc) => applyEdgePatch(doc, id, patch));
}

/** Waypoint drag: transient frames inside a gesture; tracked on drop. */
export function setEdgeWaypoints(
  id: string,
  waypoints: { x: number; y: number }[] | undefined,
  opts: { transient?: boolean } = {},
): void {
  const producer: Producer = (d) => {
    const e = d.edges.find((x) => x.id === id);
    if (!e) return;
    if (waypoints === undefined || waypoints.length === 0) {
      delete e.waypoints;
    } else {
      e.waypoints = waypoints.slice(0, 64);
    }
  };
  if (opts.transient) transient(producer);
  else tracked(producer);
}

export function clearEdgeWaypoints(id: string): void {
  setEdgeWaypoints(id, undefined);
}

/**
 * D12: moving or resizing either endpoint node clears manual waypoints.
 * Called by moveNodesTransient/resizeNodeTransient via their callers; exposed
 * for the canvas layer (M2+) and tests.
 */
export function clearWaypointsOfNodeEndpoints(nodeIds: string[]): void {
  if (nodeIds.length === 0) return;
  transient((d) => {
    const ids = new Set(nodeIds);
    for (const e of d.edges) {
      if (e.waypoints && (ids.has(e.source) || ids.has(e.target))) delete e.waypoints;
    }
  });
}

// ---------------------------------------------------------------------------
// canvas / doc-level
// ---------------------------------------------------------------------------

export function setCanvas(patch: Partial<ThalyxDoc['canvas']>): void {
  tracked((d) => {
    Object.assign(d.canvas, patch);
  });
}

export function toggleGrid(): void {
  tracked((d) => {
    d.canvas.grid = !d.canvas.grid;
  });
}

export function setDirection(dir: 'TB' | 'BT' | 'LR' | 'RL'): void {
  tracked((d) => {
    d.meta.mermaid ??= { direction: 'TB' };
    d.meta.mermaid.direction = dir;
  });
}

// ---------------------------------------------------------------------------
// session setters (not history-tracked)
// ---------------------------------------------------------------------------

export function setSelection(nodeIds: string[], edgeIds: string[] = []): void {
  setStore((s) => ({ session: { ...s.session, selection: { nodeIds, edgeIds } } }));
}

export function addToSelection(nodeIds: string[], edgeIds: string[] = []): void {
  setStore((s) => ({
    session: {
      ...s.session,
      selection: {
        nodeIds: [...new Set([...s.session.selection.nodeIds, ...nodeIds])],
        edgeIds: [...new Set([...s.session.selection.edgeIds, ...edgeIds])],
      },
    },
  }));
}

/** Select all nodes and edges (§10.2 Mod+A). */
export function selectAll(): void {
  const doc = getStore().doc;
  setStore((s) => ({
    session: {
      ...s.session,
      selection: {
        nodeIds: doc.nodes.filter((n) => !n.hidden).map((n) => n.id),
        edgeIds: doc.edges.filter((e) => !e.hidden).map((e) => e.id),
      },
    },
  }));
}

export function clearSelection(): void {
  setStore((s) => ({ session: { ...s.session, selection: { nodeIds: [], edgeIds: [] } } }));
}

export function setTool(tool: Tool): void {
  setStore((state) => ({
    session: { ...state.session, tool, toolLocked: false },
  }));
}

export enum ToolActivationMode {
  ToggleLock = 'toggle-lock',
  ResetLock = 'reset-lock',
  Lock = 'lock',
}

const LOCKABLE_TOOLS = new Set<Tool>(['shape', 'text', 'container']);

export function activateTool(
  tool: Tool,
  mode: ToolActivationMode = ToolActivationMode.ToggleLock,
): void {
  setStore((state) => {
    if (!LOCKABLE_TOOLS.has(tool)) {
      return { session: { ...state.session, tool, toolLocked: false } };
    }

    const repeated = state.session.tool === tool;
    const toolLocked =
      mode === ToolActivationMode.Lock
        ? true
        : mode === ToolActivationMode.ResetLock
          ? false
          : repeated
            ? !state.session.toolLocked
            : false;

    return { session: { ...state.session, tool, toolLocked } };
  });
}

export function setPendingShape(shape: ShapeKind): void {
  setStore((s) => ({ session: { ...s.session, pendingShape: shape } }));
}

export function setToolLocked(locked: boolean): void {
  setStore((s) => ({ session: { ...s.session, toolLocked: locked } }));
}

export function setEditingLabel(editing: SessionState['editingLabel']): void {
  setStore((s) => ({ session: { ...s.session, editingLabel: editing } }));
}

export function setViewport(viewport: SessionState['viewport']): void {
  setStore((s) => ({ session: { ...s.session, viewport } }));
}

export function setTheme(theme: SessionState['theme']): void {
  setStore((s) => ({ session: { ...s.session, theme } }));
}

export function setGuides(guides: GuideLine[]): void {
  setStore((s) => ({ session: { ...s.session, guides } }));
}

/**
 * TEST-ONLY (e2e hooks): apply a surgical patch to the current doc — unlike
 * loadDoc/resetStore it preserves the session (selection, editor state), so
 * specs can tweak a label/shape mid-flow without killing gestures.
 */
export function applyDocPatch(patch: (doc: ThalyxDoc) => void): void {
  tracked((d) => {
    patch(d);
  });
}

/**
 * importMermaidAsNew (§9.3 step 5): one history entry; replaces the document
 * content with the import (native flowchart → dagre layout; other types → a
 * mermaid island). Selects the result; the caller zooms to fit.
 */
export async function importMermaidAsNew(text: string, parse: ParseMermaidFn): Promise<boolean> {
  const result = await importMermaid(text, parse);
  if (result.kind === 'error') return false;
  if (result.kind === 'island') {
    const node = newNodeFactory({
      kind: 'mermaid',
      x: 0,
      y: 0,
      width: 480,
      height: 360,
      label: '',
      mermaidSource: text,
    });
    tracked(
      (d) => {
        d.nodes = [node];
        d.edges = [];
        d.meta.mermaid = { direction: 'TB', sourceText: text };
      },
      { selection: { nodeIds: [node.id], edgeIds: [] } },
    );
    return true;
  }
  // flowchart: seed positions (import gives parentId-relative coords; dagre
  // re-places everything)
  const positions = layoutAll(
    { ...newDocFactory(), nodes: result.nodes, edges: result.edges } as never,
    { rankdir: result.meta.direction },
  );
  tracked(
    (d) => {
      d.nodes = result.nodes.map((n) => {
        const p = positions.get(n.id);
        return p ? { ...n, x: p.x, y: p.y } : n;
      });
      d.edges = result.edges;
      d.meta.mermaid = {
        direction: result.meta.direction,
        ...(result.meta.frontmatter ? { frontmatter: result.meta.frontmatter } : {}),
        ...(result.meta.classDefs ? { classDefs: result.meta.classDefs } : {}),
        sourceText: result.meta.sourceText,
      };
    },
    { selection: { nodeIds: result.nodes.map((n) => n.id), edgeIds: [] } },
  );
  return true;
}

export type ParseMermaidFn = import('../../shared/mermaid/import').ParseFn;

/** Replace an island's mermaid source (§9.8 dialog Apply). One entry. */
export function updateNodeMermaidSource(id: string, source: string): void {
  tracked((d) => {
    const n = d.nodes.find((x) => x.id === id);
    if (n && n.kind === 'mermaid') n.mermaidSource = source.slice(0, 1_000_000);
  });
}

export async function copySelectionInternal(
  nodeIds: string[],
  edgeIds: string[],
): Promise<boolean> {
  void edgeIds; // An edge is portable only when both endpoint nodes are copied.
  const state = getStore();
  const include = expandedSelectionNodeIds(state.doc, nodeIds);
  const nodes = state.doc.nodes.filter((node) => include.has(node.id));
  if (nodes.length === 0) return false;

  const detached = detachedSubgraphRoots(state.doc, nodes);
  const edges = edgesAmong(state.doc, include);
  const payload = JSON.stringify({ type: 'thalyx/clipboard', version: 1, nodes: detached, edges });
  try {
    await navigator.clipboard.writeText(payload);
    return true;
  } catch {
    console.warn('clipboard unavailable');
    return false;
  }
}

export async function cutSelectionInternal(nodeIds: string[], edgeIds: string[]): Promise<boolean> {
  if (nodeIds.length === 0) {
    const selectedEdgeIds = new Set(edgeIds);
    const hasSelectedEdge = getStore().doc.edges.some((edge) => selectedEdgeIds.has(edge.id));
    if (!hasSelectedEdge) return false;

    deleteSelectionIds([], edgeIds);
    return true;
  }

  const copied = await copySelectionInternal(nodeIds, edgeIds);
  if (!copied) return false;

  deleteSelectionIds(nodeIds, edgeIds);
  return true;
}

export async function pasteFromClipboard(): Promise<void> {
  let text: string;
  try {
    text = await navigator.clipboard.readText();
  } catch {
    return;
  }
  try {
    const parsed = JSON.parse(text) as {
      type?: unknown;
      nodes?: unknown;
      edges?: unknown;
    };
    if (parsed.type === 'thalyx/clipboard' && Array.isArray(parsed.nodes)) {
      const normalized = restoreDocument({
        version: 1,
        source: 'thalyx/clipboard',
        nodes: parsed.nodes,
        edges: Array.isArray(parsed.edges) ? parsed.edges : [],
      });
      pasteInternal(normalized.nodes, normalized.edges);
      return;
    }
  } catch {
    // not JSON — fall through
  }
  // mermaid detection (§9.7) — the paste event path already handles this for
  // real user pastes; this fallback covers the menu item.
  const { isProbablyMermaid } = await import('../../shared/mermaid/detect');
  if (isProbablyMermaid(text)) {
    const { parseMermaid } = await import('../mermaid/runtime');
    await importMermaidAsNew(text, parseMermaid);
  } else if (text.length > 0) {
    addNode({ kind: 'text', x: 100, y: 100, label: text.slice(0, 4000) });
  }
}

export function setMermaidPanelOpen(open: boolean): void {
  setStore((s) => ({ session: { ...s.session, mermaidPanelOpen: open } }));
}

/** Copy the selection (or doc) as Mermaid text to the clipboard (§13.3). */
export async function copyAsMermaid(): Promise<string | null> {
  const state = getStore();
  const { exportMermaid } = await import('../../shared/mermaid/export');
  const out = exportMermaid(state.doc, {
    selection:
      state.session.selection.nodeIds.length > 0
        ? { nodeIds: state.session.selection.nodeIds, edgeIds: state.session.selection.edgeIds }
        : undefined,
  });
  ensureMermaidIds(out.idAssignments);
  try {
    await navigator.clipboard.writeText(out.text);
  } catch {
    // browser fallback — dev/test contexts
    console.warn('clipboard unavailable');
  }
  return out.text;
}

/**
 * ensureMermaidIds (§8.3): applies idAssignments returned by exportMermaid —
 * the ONE deliberate exception to history tracking: idempotent bookkeeping
 * metadata, a fixpoint after one pass, triggered by merely VIEWING the
 * Mermaid panel. NEVER pollutes undo. (This is the only untracked doc
 * mutation in the app.)
 */
export function ensureMermaidIds(idAssignments: Record<string, string>): void {
  if (Object.keys(idAssignments).length === 0) return; // fixpoint — nothing to do
  setStore((s) => ({
    doc: produce(s.doc, (d) => {
      for (const n of d.nodes) {
        const mid = idAssignments[n.id];
        if (mid) {
          n.meta ??= {};
          n.meta.mermaid ??= {};
          n.meta.mermaid.id = mid;
        }
      }
    }),
    // no history commit, no dirty flag change (pure metadata)
  }));
}

/**
 * applyMermaidText (§9.6): re-import edited text and RECONCILE into the
 * current doc — matched nodes keep positions, new ones placed, absent ids
 * deleted, all in ONE history entry. Island docs: replaces the source.
 */
export async function applyMermaidText(text: string): Promise<boolean> {
  if (text.length > 1_000_000) {
    throw new Error('mermaid text exceeds the 1 MB limit');
  }
  const { importMermaid } = await import('../../shared/mermaid/import');
  const { reconcileDocument } = await import('../../shared/mermaid/reconcile');
  const { parseMermaid } = await import('../mermaid/runtime');
  const result = await importMermaid(text, parseMermaid);
  if (result.kind === 'error') return false;

  // re-read AFTER the async parse — the user may have edited meanwhile
  const state = getStore();
  const doc = state.doc;

  if (result.kind === 'island') {
    const island = doc.nodes.find((n) => n.kind === 'mermaid');
    if (island) {
      tracked((d) => {
        const n = d.nodes.find((x) => x.id === island.id);
        if (n) n.mermaidSource = text.slice(0, 1_000_000);
      });
      return true;
    }
    return false;
  }

  const rec = reconcileDocument(doc, result);
  tracked((d) => {
    d.nodes = rec.doc.nodes;
    d.edges = rec.doc.edges;
    d.meta = rec.doc.meta;
  });
  return true;
}

export function setExportDialogOpen(open: boolean): void {
  setStore((s) => ({ session: { ...s.session, exportDialogOpen: open } }));
}

export function setHelpOpen(open: boolean): void {
  setStore((s) => ({ session: { ...s.session, helpOpen: open } }));
}

/** Q toggle (§10.2): quick-connect chevrons visibility. */
export function toggleChevrons(): void {
  setStore((s) => ({ session: { ...s.session, chevronsEnabled: !s.session.chevronsEnabled } }));
}

export function setDirtySinceSave(): void {
  setStore((s) => ({ session: { ...s.session, dirtySinceSave: true } }));
}

/** Open a file into the session: set path + clean (lifecycle helper). */
export function openFilePath(path: string | null): void {
  setStore((s) => ({ session: { ...s.session, filePath: path, dirtySinceSave: false } }));
}

export function setFilePath(filePath: string | null): void {
  setStore((s) => ({ session: { ...s.session, filePath } }));
}

export function markSaved(): void {
  setStore((s) => ({ session: { ...s.session, dirtySinceSave: false } }));
}
