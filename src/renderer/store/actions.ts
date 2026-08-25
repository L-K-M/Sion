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
import { importMermaid } from '../../shared/mermaid/import';
import { layoutAll, layoutSubset } from '../../shared/layout/dagreLayout';
import { tidyUp } from '../../shared/layout/tidy';
import {
  absolutePosition,
  boundsOfNodes,
  depthOfNode,
  descendantsOf,
  edgesAmong,
  getNode,
  positionUnderParent,
} from '../../shared/model/queries';
import type { GuideLine } from '../../shared/snap/snap';
import { LABEL_MAX } from '../../shared/model/schema';
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

/** Drag frames: apply positions without history entries. */
export function moveNodesTransient(positions: Array<{ id: string; x: number; y: number }>): void {
  transient((d) => {
    const map = new Map(positions.map((p) => [p.id, p]));
    for (const n of d.nodes) {
      const p = map.get(n.id);
      if (p && !n.locked) {
        n.x = p.x;
        n.y = p.y;
      }
    }
  });
}

/** Resize frames (NodeResizer). Also transient; wrap in a gesture. */
export function resizeNodeTransient(
  id: string,
  box: { x?: number; y?: number; width: number; height: number },
): void {
  transient((d) => {
    const n = d.nodes.find((x) => x.id === id);
    if (!n || n.locked) return;
    if (box.x !== undefined) n.x = box.x;
    if (box.y !== undefined) n.y = box.y;
    n.width = Math.max(8, box.width);
    n.height = Math.max(8, box.height);
  });
}

/** Tracked position set — used by layout actions (M4) and tests. */
export function setNodesPosition(
  ids: string[],
  pos: (node: ThalyxNode) => { x: number; y: number },
): void {
  tracked((d) => {
    for (const n of d.nodes) {
      if (ids.includes(n.id) && !n.locked) {
        const p = pos(n);
        n.x = p.x;
        n.y = p.y;
      }
    }
  });
}

// ---------------------------------------------------------------------------
// selection / delete / duplicate
// ---------------------------------------------------------------------------

function selectedNodes(d: ThalyxDoc, sel: SessionState): ThalyxNode[] {
  return d.nodes.filter((n) => sel.selection.nodeIds.includes(n.id));
}

/**
 * Delete the current selection. Deleting a node deletes its edges AND its
 * descendants (containers take their children with them) — all in ONE history
 * entry (invariant §7.2.1).
 */
export function deleteSelection(): void {
  tracked(
    (d) => {
      const sel = getStore().session;
      const nodeIds = new Set(sel.selection.nodeIds);
      // expand containers to include descendants
      for (const id of [...nodeIds]) {
        const n = getNode(d, id);
        if (n && n.kind === 'container') {
          for (const desc of descendantsOf(d, id)) nodeIds.add(desc.id);
        }
      }
      const edgeIds = new Set(sel.selection.edgeIds);
      for (const e of d.edges) {
        if (nodeIds.has(e.source) || nodeIds.has(e.target)) edgeIds.add(e.id);
      }
      d.nodes = d.nodes.filter((n) => !nodeIds.has(n.id));
      d.edges = d.edges.filter((e) => !edgeIds.has(e.id));
    },
    { selection: { nodeIds: [], edgeIds: [] }, editingLabel: null },
  );
}

export interface ReIdResult {
  nodes: ThalyxNode[];
  edges: ThalyxEdge[];
  /** original id → fresh id (for callers that must map positions etc.) */
  idMap: Map<string, string>;
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
  const newNodes = nodes.map((n) => ({
    ...n,
    id: idMap.get(n.id)!,
    x: n.x + dx,
    y: n.y + dy,
    // Containment must stay within the pasted subgraph — a parentId pointing
    // outside it would dangle (invariant §7.2.2).
    parentId:
      n.parentId !== undefined && idMap.has(n.parentId) ? idMap.get(n.parentId)! : undefined,
    meta: n.meta ? JSON.parse(JSON.stringify(n.meta)) : undefined,
  }));
  // Edges must resolve inside the pasted subgraph (invariant §7.2.1).
  const newEdges = edges
    .filter((e) => idMap.has(e.source) && idMap.has(e.target))
    .map((e) => ({
      ...e,
      id: newId(),
      source: remapId(e.source),
      target: remapId(e.target),
      waypoints: e.waypoints?.map((p) => ({ ...p })),
      meta: e.meta ? JSON.parse(JSON.stringify(e.meta)) : undefined,
    }));
  return { nodes: newNodes, edges: newEdges, idMap };
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
  const withDescendants: ThalyxNode[] = [];
  const seen = new Set<string>();
  for (const n of selected) {
    for (const m of [n, ...descendantsOf(state.doc, n.id)]) {
      if (!seen.has(m.id)) {
        seen.add(m.id);
        withDescendants.push(m);
      }
    }
  }
  const intra = edgesAmong(state.doc, new Set(withDescendants.map((n) => n.id)));
  const dup = reIdSubgraph(withDescendants, intra, 16, 16);
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
    for (const n of d.nodes) {
      const p = positions.get(n.id);
      if (p && !n.locked) {
        n.x = p.x;
        n.y = p.y;
      }
    }
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
    for (const n of d.nodes) {
      const p = positions.get(n.id);
      if (p) {
        n.x = p.x;
        n.y = p.y;
      }
    }
  });
}

/**
 * Grow gesture (§11.6): create a connected node in `dir` from the source —
 * new node inherits style/size, edge inherits the last-used edge style,
 * gap 48 px (snapped to grid when on). ONE history entry; select + open the
 * label editor. If a node already sits within the corridor, connect to it
 * instead (draw.io rule).
 */
export function growConnectedNode(
  sourceId: string,
  dir: 'n' | 's' | 'e' | 'w',
  opts: { shape?: ShapeKind; grid?: boolean } = {},
): string | null {
  const state = getStore();
  const doc = state.doc;
  const source = doc.nodes.find((n) => n.id === sourceId);
  if (!source || source.kind === 'mermaid') return null;
  const sAbs = absolutePosition(doc, source);
  const GAP = 48;

  const sourceRect = { x: sAbs.x, y: sAbs.y, w: source.width, h: source.height };
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
    if (!exists) connectEdge(sourceId, best.id, 'arrow');
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
  const session = getStore().session;
  const arrowEnd = session.lastEdgeStyle.arrowEnd;
  const line = session.lastEdgeStyle.line;
  const edge = newEdgeFactory({
    source: sourceId,
    target: grown.id,
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
        n.x = target - parentAbs.x;
      } else {
        n.y = target - parentAbs.y;
      }
    }
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
export function connectEdge(source: string, target: string, tool: Tool): string {
  const session = getStore().session;
  const arrowEnd = tool === 'line' ? 'none' : session.lastEdgeStyle.arrowEnd;
  const line = session.lastEdgeStyle.line;
  const id = addEdge({ source, target, arrowStart: 'none', arrowEnd, style: { line } });
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

/** Nudge (§10.2): move the selection by dx/dy (1 px, or 8 with Shift). */
export function nudgeSelection(dx: number, dy: number): void {
  tracked((d) => {
    const sel = getStore().session;
    for (const n of d.nodes) {
      if (sel.selection.nodeIds.includes(n.id) && !n.locked) {
        n.x += dx;
        n.y += dy;
      }
    }
  });
}

export function setLastEdgeStyle(style: {
  arrowEnd: 'none' | 'arrow';
  line: 'solid' | 'dashed' | 'thick';
}): void {
  setStore((s) => ({ session: { ...s.session, lastEdgeStyle: style } }));
}

export function updateEdge(
  id: string,
  patch: Partial<Omit<ThalyxEdge, 'id' | 'source' | 'target'>>,
): void {
  tracked((d) => {
    const e = d.edges.find((x) => x.id === id);
    if (!e) return;
    const p = { ...patch }; // never mutate the caller's object
    if (p.label !== undefined) p.label = p.label.slice(0, LABEL_MAX);
    Object.assign(e, p);
    if (e.labelT !== undefined) e.labelT = Math.min(1, Math.max(0, e.labelT));
  });
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
  setStore((s) => ({ session: { ...s.session, tool } }));
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

export function setHelpOpen(open: boolean): void {
  setStore((s) => ({ session: { ...s.session, helpOpen: open } }));
}

/** Q toggle (§10.2): quick-connect chevrons visibility. */
export function toggleChevrons(): void {
  setStore((s) => ({ session: { ...s.session, chevronsEnabled: !s.session.chevronsEnabled } }));
}

export function setFilePath(filePath: string | null): void {
  setStore((s) => ({ session: { ...s.session, filePath } }));
}

export function markSaved(): void {
  setStore((s) => ({ session: { ...s.session, dirtySinceSave: false } }));
}
