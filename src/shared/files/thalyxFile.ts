/**
 * `.thalyx` file format (PLAN.md §7.4): the ThalyxDoc JSON, pretty-printed
 * 2-space, UTF-8, trailing newline (diff-friendly). MIME:
 * application/vnd.thalyx+json.
 */
import { restoreDocument } from '../model/restore';
import type { ThalyxDoc, ThalyxEdge, ThalyxNode } from '../model/types';

/** Rebuild a node with known fields only — strips runtime-only data. */
function pickNode(n: ThalyxNode): ThalyxNode {
  const out: ThalyxNode = {
    id: n.id,
    kind: n.kind,
    x: n.x,
    y: n.y,
    width: n.width,
    height: n.height,
    label: n.label,
    style: { ...n.style },
  };
  if (n.shape !== undefined) out.shape = n.shape;
  if (n.parentId !== undefined) out.parentId = n.parentId;
  if (n.locked !== undefined) out.locked = n.locked;
  if (n.hidden !== undefined) out.hidden = n.hidden;
  if (n.mermaidSource !== undefined) out.mermaidSource = n.mermaidSource;
  if (n.meta !== undefined) out.meta = structuredCloneSafe(n.meta);
  return out;
}

function pickEdge(e: ThalyxEdge): ThalyxEdge {
  const out: ThalyxEdge = {
    id: e.id,
    source: e.source,
    target: e.target,
    sourceAnchor: e.sourceAnchor,
    targetAnchor: e.targetAnchor,
    kind: e.kind,
    arrowStart: e.arrowStart,
    arrowEnd: e.arrowEnd,
    style: { ...e.style },
  };
  if (e.label !== undefined) out.label = e.label;
  if (e.labelT !== undefined) out.labelT = e.labelT;
  if (e.hidden !== undefined) out.hidden = e.hidden;
  if (e.waypoints !== undefined) out.waypoints = e.waypoints.map((p) => ({ ...p }));
  if (e.meta !== undefined) out.meta = structuredCloneSafe(e.meta);
  return out;
}

function structuredCloneSafe<T>(v: T): T {
  return JSON.parse(JSON.stringify(v)) as T;
}

/**
 * Serialize a doc. Strips runtime-only fields (v1: none defined, but the
 * pick-rebuild keeps this the single choke point), sorts nothing — array
 * order is data (z-order).
 */
export function serializeDoc(doc: ThalyxDoc): string {
  const clean: ThalyxDoc = {
    type: 'thalyx',
    version: 1,
    source: doc.source,
    nodes: doc.nodes.map(pickNode),
    edges: doc.edges.map(pickEdge),
    canvas: { ...doc.canvas },
    meta: structuredCloneSafe(doc.meta),
  };
  return JSON.stringify(clean, null, 2) + '\n';
}

/**
 * Parse `.thalyx` text. Throws SyntaxError for invalid JSON (not a document);
 * everything else is normalized by restoreDocument (§7.5: never throws on
 * merely-weird data; DocTooNewError for future versions).
 */
export function parseDoc(text: string): ThalyxDoc {
  const raw: unknown = JSON.parse(text);
  return restoreDocument(raw);
}
