import type { Point } from '../../../shared/geometry/anchors';
import type { ThalyxDoc, ThalyxNode } from '../../../shared/model/types';

const nodeIndexCache = new WeakMap<ThalyxDoc, Map<string, ThalyxNode>>();

function nodeIndex(doc: ThalyxDoc): Map<string, ThalyxNode> {
  const cached = nodeIndexCache.get(doc);
  if (cached) return cached;

  const index = new Map(doc.nodes.map((node) => [node.id, node]));
  nodeIndexCache.set(doc, index);
  return index;
}

/** Flat endpoint/ancestor list works with Zustand shallow comparison. */
export function edgeEndpointContext(
  doc: ThalyxDoc,
  sourceId: string,
  targetId: string,
): ThalyxNode[] {
  const index = nodeIndex(doc);
  const source = index.get(sourceId);
  const target = index.get(targetId);
  if (!source || !target) return [];

  const context = [source, target];
  const included = new Set(context.map((node) => node.id));
  for (const endpoint of [source, target]) {
    let parentId = endpoint.parentId;
    while (parentId) {
      const parent = index.get(parentId);
      if (!parent || included.has(parent.id)) break;

      context.push(parent);
      included.add(parent.id);
      parentId = parent.parentId;
    }
  }

  return context;
}

export function absoluteFromContext(context: ThalyxNode[], node: ThalyxNode): Point {
  const index = new Map(context.map((candidate) => [candidate.id, candidate]));
  let x = node.x;
  let y = node.y;
  let parentId = node.parentId;
  const visited = new Set<string>();
  while (parentId && !visited.has(parentId)) {
    visited.add(parentId);
    const parent = index.get(parentId);
    if (!parent) break;

    x += parent.x;
    y += parent.y;
    parentId = parent.parentId;
  }

  return { x, y };
}
