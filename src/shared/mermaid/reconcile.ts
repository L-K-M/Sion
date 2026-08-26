/**
 * reconcileDocument (PLAN.md §9.6): position-preserving re-import.
 * Pure: match by meta.mermaid.id, keep positions/styles of matched nodes,
 * convert coordinates across parentId changes, place new nodes near graph
 * neighbors, delete absent ids (with edges), match edges by
 * (source, target, occurrenceIndex), keep waypoints only when endpoints
 * didn't move.
 */
import type { ThalyxDoc, ThalyxEdge, ThalyxNode } from '../model/types';
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
      id: old.id, // matched nodes keep their identity (edges/selection survive)
      x,
      y, // ABSOLUTE for now — frame conversion runs after placement
      width: old.width,
      height: old.height,
      style: { ...old.style, ...(imp.style.fill !== 'surface' ? { fill: imp.style.fill } : {}) },
      // waypoints survive only per-edge below
    });
    matchedAbsolute.set(old.id, { x, y }); // keyed by the SURVIVING id
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
  const nodesPlaced = keep.map((n) => {
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
  // imported id → surviving doc id (matched nodes kept their old ids)
  const surviveAs = new Map<string, string>();
  for (const [impId, oldId] of importedIdToOld) surviveAs.set(impId, oldId);

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
  // remap parent links to surviving ids, then convert matched coordinates
  const withParents = nodesPlaced.map((n) => ({
    ...n,
    ...(n.parentId !== undefined ? { parentId: surviveAs.get(n.parentId) ?? n.parentId } : {}),
  }));
  // Convert in document order so parents are converted before children:
  // a converted child's coords are parent-relative, so computing a parent's
  // absolute position AFTER its own conversion uses parent-relative chains.
  const nodesFinal2: ThalyxNode[] = [];
  const absOfConverted = (
    id: string | undefined,
    fallbackDoc: ThalyxDoc,
  ): { x: number; y: number } => {
    const idx = nodesFinal2.findIndex((n) => n.id === id);
    if (idx !== -1) return absoluteOfFinal(nodesFinal2, nodesFinal2[idx]!);
    const orig = fallbackDoc.nodes.find((n) => n.id === id);
    return orig ? absolutePosition(fallbackDoc, orig) : { x: 0, y: 0 };
  };
  // Order-independent: convert any node whose parent's conversion is
  // already final; repeat until no progress (handles child-before-parent).
  const pending = [...withParents];
  const finalById = new Map<string, ThalyxNode>();
  let progressed = true;
  while (pending.length > 0 && progressed) {
    progressed = false;
    for (let i = pending.length - 1; i >= 0; i--) {
      const n = pending[i]!;
      const parent = n.parentId !== undefined ? finalById.get(n.parentId) : null;
      const parentPending =
        n.parentId !== undefined && !parent && withParents.some((p) => p.id === n.parentId);
      if (parentPending) continue; // parent not converted yet — wait
      pending.splice(i, 1);
      progressed = true;
      convert(n, parent ?? null);
    }
  }
  // anything left (cycles) falls back to top-level absolute, KEEPING the
  // parent link when the parent IS in the final set (the link stays valid;
  // only its frame conversion was unresolvable)
  for (const n of pending) {
    const parent = n.parentId !== undefined ? finalById.get(n.parentId) : null;
    convert(n, parent ?? null);
  }

  function convert(n: ThalyxNode, parent: ThalyxNode | null): void {
    const abs = matchedAbsolute.get(n.id);
    if (parent) {
      // parent is already CONVERTED (top-level frame) — subtract its absolute
      const pAbs = absoluteOfFinal(nodesFinal2, parent);
      nodesFinal2.push({
        ...n,
        x: abs ? abs.x - pAbs.x : n.x - pAbs.x,
        y: abs ? abs.y - pAbs.y : n.y - pAbs.y,
      });
      finalById.set(n.id, nodesFinal2[nodesFinal2.length - 1]!);
      return;
    }
    // no (convertible) parent: absolute frame
    nodesFinal2.push({ ...n, x: abs ? abs.x : n.x, y: abs ? abs.y : n.y, parentId: undefined });
    finalById.set(n.id, nodesFinal2[nodesFinal2.length - 1]!);
  }

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

  for (const rawImp of imported.edges) {
    // remap endpoints to SURVIVING ids (matched nodes kept their old ids)
    const imp = {
      ...rawImp,
      source: surviveAs.get(rawImp.source) ?? rawImp.source,
      target: surviveAs.get(rawImp.target) ?? rawImp.target,
    };
    const k = `${imp.source}|${imp.target}`;
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
      const endpointsMoved = (() => {
        const srcA = srcOld ? absolutePosition(current, srcOld) : null;
        const tgtA = tgtOld ? absolutePosition(current, tgtOld) : null;
        const srcB = srcNew ? absOfConverted(srcNew.id, current) : null;
        const tgtB = tgtNew ? absOfConverted(tgtNew.id, current) : null;
        if (!srcA || !tgtA || !srcB || !tgtB) return true;
        return srcA.x !== srcB.x || srcA.y !== srcB.y || tgtA.x !== tgtB.x || tgtA.y !== tgtB.y;
      })();
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

  // hand-drawn nodes whose container vanished promote to top level with
  // absolute-position preservation
  const survivingIds = new Set([...nodesFinal2, ...unmatchedCurrent].map((n) => n.id));
  const promotedUnmatched = unmatchedCurrent.map((n) => {
    if (n.parentId === undefined || survivingIds.has(n.parentId)) return n;
    const abs = absolutePosition(current, n);
    return { ...n, parentId: undefined, x: abs.x, y: abs.y };
  });

  const doc: ThalyxDoc = {
    ...current,
    nodes: [...nodesFinal2, ...promotedUnmatched],
    edges: [...edgesFinal, ...unmatchedEdges],
    meta: {
      ...current.meta,
      mermaid: imported.meta ?? current.meta.mermaid,
    },
  };
  return { doc, added, removed, moved };
}
