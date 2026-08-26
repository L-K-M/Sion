/**
 * reconcileDocument (PLAN.md §9.6): position-preserving re-import.
 * Pure: match by meta.mermaid.id, keep positions/styles of matched nodes,
 * convert coordinates across parentId changes, place new nodes near graph
 * neighbors, delete absent ids (with edges), match edges by
 * (source, target, occurrenceIndex), keep waypoints only when endpoints
 * didn't move.
 */
import type { ThalyxDoc, ThalyxEdge, ThalyxNode } from '../model/types';
import { newEdge, newNode } from '../model/create';
import { absolutePosition, boundsOfNodes } from '../model/queries';

export interface ReconcileResult {
  doc: ThalyxDoc;
  added: number;
  removed: number;
  moved: number;
}

const GRID_GAP = 48;

export function reconcileDocument(
  current: ThalyxDoc,
  imported: { nodes: ThalyxNode[]; edges: ThalyxEdge[]; meta: ThalyxDoc['meta']['mermaid'] },
): ReconcileResult {
  let added = 0;
  let removed = 0;
  let moved = 0;

  const currentByMermaidId = new Map<string, ThalyxNode>();
  for (const n of current.nodes) {
    const mid = n.meta?.mermaid?.id;
    if (mid) currentByMermaidId.set(mid, n);
  }

  // --- nodes: match → keep position/style, update label/shape/link/etc. ---
  const keep: ThalyxNode[] = [];
  const importedIdToOld = new Map<string, string>();
  const matchedAbsolute = new Map<string, { x: number; y: number }>(); // new node id → matched old id
  for (const imp of imported.nodes) {
    const mid = imp.meta?.mermaid?.id ?? imp.id;
    const old = currentByMermaidId.get(mid);
    if (!old) {
      keep.push(imp); // new node — placement pass below
      added += 1;
      continue;
    }
    importedIdToOld.set(imp.id, old.id);
    const oldAbs = absolutePosition(current, old);
    // keep position (absolute), re-express under the NEW parentId
    const newParent = imp.parentId;
    const x = oldAbs.x;
    const y = oldAbs.y;
    // frame conversion happens in the deferred pass (after placement)
    void newParent;
    keep.push({
      ...imp,
      x,
      y, // ABSOLUTE for now — frame conversion runs after placement
      width: old.width,
      height: old.height,
      style: { ...old.style, ...(imp.style.fill !== 'surface' ? { fill: imp.style.fill } : {}) },
      // waypoints survive only per-edge below
    });
    matchedAbsolute.set(imp.id, { x, y });
    moved += 1;
  }

  // §9.6 step 3: current nodes WITHOUT a mermaid id (hand-drawn) are kept
  // untouched — they are not part of the text round-trip.
  const unmatchedCurrent = current.nodes.filter(
    (n) => n.meta?.mermaid?.id === undefined && !importedIdToOld.has(n.id),
  );

  // new-node placement: barycenter of placed graph neighbors, else below content
  const placedBounds = boundsOfNodes(current, current.nodes);
  const newlyPlaced = new Map<string, { x: number; y: number }>();
  for (const imp of imported.nodes) {
    if (importedIdToOld.has(imp.id) || !keep.includes(imp)) continue;
    const neighbors = imported.edges.filter((e) => e.source === imp.id || e.target === imp.id);
    let bx = 0;
    let by = 0;
    let count = 0;
    for (const e of neighbors) {
      const otherId = e.source === imp.id ? e.target : e.source;
      const otherOld = importedIdToOld.get(otherId);
      const otherNode = otherOld
        ? current.nodes.find((n) => n.id === otherOld)
        : currentByMermaidId.get(otherId);
      if (otherNode) {
        const p = absolutePosition(current, otherNode);
        bx += p.x;
        by += p.y;
        count += 1;
      }
    }
    if (count > 0) {
      newlyPlaced.set(imp.id, {
        x: Math.round(bx / count + GRID_GAP),
        y: Math.round(by / count + GRID_GAP),
      });
    } else if (placedBounds) {
      newlyPlaced.set(imp.id, {
        x: placedBounds.x,
        y: placedBounds.y + placedBounds.height + GRID_GAP,
      });
    }
  }
  // nudge until not overlapping
  const nodesFinal = keep.map((n) => {
    const p = newlyPlaced.get(n.id);
    if (!p) return n;
    let guard = 0;
    let x = p.x;
    let y = p.y;
    while (
      guard < 50 &&
      keep.some((o) => o !== n && Math.abs(o.x - x) < 32 && Math.abs(o.y - y) < 32)
    ) {
      x += 16;
      y += 16;
      guard += 1;
    }
    return { ...n, x, y };
  });
  // --- frame conversion: matched nodes move into their FINAL parent frame ---
  const absoluteOfFinal = (docNodes: ThalyxNode[], node: ThalyxNode): { x: number; y: number } => {
    let x = node.x;
    let y = node.y;
    let cursor = node.parentId;
    let steps = 0;
    while (cursor !== undefined && steps < 100) {
      const p = docNodes.find((n) => n.id === cursor);
      if (!p) break;
      x += p.x;
      y += p.y;
      cursor = p.parentId;
      steps += 1;
    }
    return { x, y };
  };
  const nodesFinal2 = nodesFinal.map((n) => {
    const abs = matchedAbsolute.get(n.id);
    if (!abs || n.parentId === undefined) return n;
    const parent = nodesFinal.find((p) => p.id === n.parentId);
    if (!parent) return { ...n, x: abs.x, y: abs.y, parentId: undefined };
    const pAbs = absoluteOfFinal(nodesFinal, parent);
    return { ...n, x: abs.x - pAbs.x, y: abs.y - pAbs.y };
  });

  // deletion count: olds with mermaid ids absent from the import
  const importedMids = new Set(imported.nodes.map((n) => n.meta?.mermaid?.id ?? n.id));
  for (const [mid, node] of currentByMermaidId) {
    if (!importedMids.has(mid)) {
      removed += 1;
      void node;
    }
  }

  // --- edges: match by (sourceOld, targetOld, occurrenceIndex) ---
  const oldEdgeKey = (e: ThalyxEdge): string => `${e.source}|${e.target}`;
  const oldOccurrences = new Map<string, number>();
  const oldEdgeById = new Map(current.edges.map((e) => [e.id, e]));
  for (const e of current.edges) {
    const k = oldEdgeKey(e);
    oldOccurrences.set(k, (oldOccurrences.get(k) ?? 0) + 1);
  }
  const seenOccurrences = new Map<string, number>();
  const edgesFinal: ThalyxEdge[] = [];
  const idRemap = new Map<string, string>(); // old node id → new (imported) id
  for (const [newId, oldId] of importedIdToOld) idRemap.set(oldId, newId);

  const keptIds = new Set(unmatchedCurrent.map((n) => n.id));
  const unmatchedEdges = current.edges.filter(
    (e) => keptIds.has(e.source) && keptIds.has(e.target),
  );

  for (const imp of imported.edges) {
    const impSourceOld = reverseLookup(importedIdToOld, imp.source) ?? imp.source;
    const impTargetOld = reverseLookup(importedIdToOld, imp.target) ?? imp.target;
    const k = `${impSourceOld}|${impTargetOld}`;
    const idx = seenOccurrences.get(k) ?? 0;
    seenOccurrences.set(k, idx + 1);
    // find the idx-th current edge with this key
    let seen = -1;
    let match: ThalyxEdge | undefined;
    for (const e of current.edges) {
      if (oldEdgeKey(e) === k) {
        seen += 1;
        if (seen === idx) {
          match = e;
          break;
        }
      }
    }
    if (match) {
      const oldEdge = oldEdgeById.get(match.id)!;
      const srcOld = current.nodes.find((n) => n.id === oldEdge.source);
      const tgtOld = current.nodes.find((n) => n.id === oldEdge.target);
      const srcNew = nodesFinal2.find((n) => n.id === imp.source);
      const tgtNew = nodesFinal2.find((n) => n.id === imp.target);
      const endpointsMoved =
        !srcOld || !tgtOld || !srcNew || !tgtNew
          ? true
          : absolutePosition(current, srcOld).x !==
              absolutePosition({ ...current, nodes: nodesFinal2 } as never, srcNew).x ||
            absolutePosition(current, tgtOld).y !==
              absolutePosition({ ...current, nodes: nodesFinal2 } as never, tgtNew).y;
      edgesFinal.push({
        ...imp,
        id: match.id,
        // waypoints survive only when endpoints didn't move
        ...(endpointsMoved ? {} : { waypoints: match.waypoints }),
        labelT: match.labelT,
      });
    } else {
      edgesFinal.push(imp);
    }
  }

  const doc: ThalyxDoc = {
    ...current,
    nodes: [...nodesFinal2, ...unmatchedCurrent],
    edges: [...edgesFinal, ...unmatchedEdges],
    meta: {
      ...current.meta,
      mermaid: imported.meta ?? current.meta.mermaid,
    },
  };
  return { doc, added, removed, moved };
}

function reverseLookup(map: Map<string, string>, value: string): string | undefined {
  for (const [k, v] of map) {
    if (v === value) return k;
  }
  return undefined;
}

void newEdge;
void newNode;
