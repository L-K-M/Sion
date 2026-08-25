/**
 * Auto-layout via dagre (PLAN.md §11.5, D3). Pure module over the doc model.
 *
 * - compound:true graph (setParent requires it), default edge labels (dagre
 *   throws on label-less edges otherwise)
 * - edges to/from containers are NOT added to the dagre graph (cluster edges
 *   are unsupported; they are re-routed by our own elbow router afterwards)
 * - output converts centers → top-left, preserving parent-relative storage
 */
import dagre from '@dagrejs/dagre';
import type { ThalyxDoc, ThalyxNode } from '../model/types';
import { absolutePosition } from '../model/queries';

export interface LayoutOptions {
  rankdir?: 'TB' | 'BT' | 'LR' | 'RL';
  nodesep?: number;
  ranksep?: number;
}

const DEFAULT_OPTS: Required<LayoutOptions> = {
  rankdir: 'TB',
  nodesep: 40,
  ranksep: 60,
};

/**
 * Compute new positions for the (subset of) nodes in `doc`.
 * Returns a Map nodeId → {x, y} in the SAME coordinate frame each node
 * currently uses (parent-relative for children). Nodes not in `subset`
 * are treated as fixed anchors (still laid out around, but not moved).
 */
export function dagreLayout(
  doc: ThalyxDoc,
  subset: Set<string> | null,
  options: LayoutOptions = {},
): Map<string, { x: number; y: number }> {
  const opts = { ...DEFAULT_OPTS, ...options };
  const g = new dagre.graphlib.Graph({ compound: true, multigraph: true });
  g.setGraph({
    rankdir: opts.rankdir,
    nodesep: opts.nodesep,
    ranksep: opts.ranksep,
    marginx: 24,
    marginy: 24,
  });
  g.setDefaultEdgeLabel(() => ({}));

  const containers = doc.nodes.filter((n) => n.kind === 'container');
  const containerIds = new Set(containers.map((c) => c.id));

  for (const n of doc.nodes) {
    if (n.kind === 'mermaid') continue; // islands don't participate
    const abs = absolutePosition(doc, n);
    g.setNode(n.id, { width: n.width, height: n.height });
    // store absolute position for the container-extent computation below
    g.node(n.id).absX = abs.x;
    g.node(n.id).absY = abs.y;
  }

  for (const n of doc.nodes) {
    if (n.parentId && containerIds.has(n.parentId) && g.hasNode(n.parentId)) {
      g.setParent(n.id, n.parentId);
    }
  }

  // Containers need sizes for dagre's cluster layout; derive from members.
  for (const c of containers) {
    if (!g.hasNode(c.id)) continue;
    const members = doc.nodes.filter((n) => n.parentId === c.id);
    if (members.length > 0) {
      // bounds of members (absolute) + padding
      let minX = Infinity;
      let minY = Infinity;
      let maxX = -Infinity;
      let maxY = -Infinity;
      for (const m of members) {
        const abs = absolutePosition(doc, m);
        minX = Math.min(minX, abs.x);
        minY = Math.min(minY, abs.y);
        maxX = Math.max(maxX, abs.x + m.width);
        maxY = Math.max(maxY, abs.y + m.height);
      }
      g.setNode(c.id, {
        width: Math.max(c.width, maxX - minX + 48),
        height: Math.max(c.height, maxY - minY + 48),
      });
    }
  }

  for (const e of doc.edges) {
    if (e.hidden) continue;
    if (containerIds.has(e.source) || containerIds.has(e.target)) continue; // cluster edges unsupported
    if (!g.hasNode(e.source) || !g.hasNode(e.target)) continue;
    g.setEdge(e.source, e.target, { minlen: e.meta?.mermaid?.minlen ?? 1 }, e.id);
  }

  dagre.layout(g);

  const out = new Map<string, { x: number; y: number }>();
  for (const n of doc.nodes) {
    if (n.kind === 'mermaid') continue;
    if (subset && !subset.has(n.id)) continue;
    const ln = g.node(n.id);
    if (!ln) continue;
    // dagre gives centers in absolute space; convert to the node's storage frame
    let cx = ln.x - n.width / 2;
    let cy = ln.y - n.height / 2;
    if (n.parentId) {
      const parent = g.node(n.parentId);
      const parentDoc = doc.nodes.find((p) => p.id === n.parentId);
      if (parent && parentDoc) {
        // dagre cluster coordinates are relative to the cluster's own origin
        cx -= parent.x - parent.width / 2;
        cy -= parent.y - parent.height / 2;
      }
    }
    out.set(n.id, { x: Math.round(cx), y: Math.round(cy) });
  }
  return out;
}

/** Whole-doc entry point: positions for every layoutable node. */
export function layoutAll(
  doc: ThalyxDoc,
  options?: LayoutOptions,
): Map<string, { x: number; y: number }> {
  return dagreLayout(doc, null, options);
}

export function layoutSubset(
  doc: ThalyxDoc,
  nodeIds: string[],
  options?: LayoutOptions,
): Map<string, { x: number; y: number }> {
  const subset = new Set(nodeIds);
  for (const id of nodeIds) {
    const node = doc.nodes.find((n) => n.id === id);
    if (!node) continue;
    // include edges-connected neighbors so the subset lays out coherently?
    // §11.5: selection's connected subgraph — include only selected + their
    // intra-selection edges; neighbors stay as fixed anchors.
  }
  return dagreLayout(doc, subset, options);
}

export type { ThalyxNode };
