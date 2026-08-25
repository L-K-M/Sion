/**
 * Round-trip comparison (§15.1): semantic equality modulo canonicalization +
 * the fixpoint property. Shared by the corpus and property tests.
 */
import type { ThalyxDoc } from '../model/types';
import { canonicalizeHeads } from './tables';

interface RoundNode {
  id: string;
  label: string;
  shape: string | undefined;
  parentId: string | undefined;
  link: string | undefined;
  dir: string | undefined; // containers
  fill: string;
  strokeWidth: number;
}
interface RoundEdge {
  source: string;
  target: string;
  label: string | undefined;
  line: string;
  arrowStart: string;
  arrowEnd: string;
  minlen: number;
  hidden: boolean;
}

export function semanticModel(doc: ThalyxDoc): {
  nodes: RoundNode[];
  edges: RoundEdge[];
  direction: string;
} {
  const nodes: RoundNode[] = doc.nodes
    .filter((n) => n.kind !== 'mermaid')
    .map((n) => ({
      id: n.meta?.mermaid?.id ?? n.id,
      label: n.label,
      shape: n.kind === 'shape' ? n.shape : undefined,
      parentId: n.parentId
        ? (doc.nodes.find((p) => p.id === n.parentId)?.meta?.mermaid?.id ?? n.parentId)
        : undefined,
      link: n.meta?.mermaid?.link,
      dir: n.meta?.mermaid?.dir,
      fill: n.style.fill,
      strokeWidth: n.style.strokeWidth,
    }))
    .sort((a, b) => a.id.localeCompare(b.id));
  const edges: RoundEdge[] = doc.edges
    .map((e) => {
      const [s, t] = [
        doc.nodes.find((n) => n.id === e.source)?.meta?.mermaid?.id ?? e.source,
        doc.nodes.find((n) => n.id === e.target)?.meta?.mermaid?.id ?? e.target,
      ];
      const [cs, ct] = canonicalizeHeads(e.arrowStart, e.arrowEnd);
      return {
        source: s!,
        target: t!,
        label: e.label,
        line: e.style.line,
        arrowStart: cs,
        arrowEnd: ct,
        minlen: e.meta?.mermaid?.minlen ?? 1,
        hidden: e.hidden === true,
      };
    })
    .sort(
      (a, b) =>
        a.source.localeCompare(b.source) ||
        a.target.localeCompare(b.target) ||
        (a.label ?? '').localeCompare(b.label ?? ''),
    );
  return { nodes, edges, direction: doc.meta.mermaid?.direction ?? 'TB' };
}

/** Semantic equality modulo canonicalization (§15.1). */
export function semanticallyEqual(a: ThalyxDoc, b: ThalyxDoc): { equal: boolean; diff: string } {
  const ma = semanticModel(a);
  const mb = semanticModel(b);
  if (ma.direction !== mb.direction) {
    return { equal: false, diff: `direction ${ma.direction} != ${mb.direction}` };
  }
  if (ma.nodes.length !== mb.nodes.length || ma.edges.length !== mb.edges.length) {
    return {
      equal: false,
      diff: `counts: ${ma.nodes.length}/${ma.edges.length} != ${mb.nodes.length}/${mb.edges.length}`,
    };
  }
  for (let i = 0; i < ma.nodes.length; i++) {
    const x = ma.nodes[i]!;
    const y = mb.nodes[i]!;
    if (
      x.id !== y.id ||
      x.label !== y.label ||
      x.shape !== y.shape ||
      x.parentId !== y.parentId ||
      x.link !== y.link ||
      x.dir !== y.dir ||
      x.fill !== y.fill ||
      x.strokeWidth !== y.strokeWidth
    ) {
      return {
        equal: false,
        diff: `node ${x.id} vs ${y.id} (${JSON.stringify(x)} != ${JSON.stringify(y)})`,
      };
    }
  }
  for (let i = 0; i < ma.edges.length; i++) {
    const x = ma.edges[i]!;
    const y = mb.edges[i]!;
    if (
      x.source !== y.source ||
      x.target !== y.target ||
      x.label !== y.label ||
      x.line !== y.line ||
      x.arrowStart !== y.arrowStart ||
      x.arrowEnd !== y.arrowEnd ||
      x.minlen !== y.minlen ||
      x.hidden !== y.hidden
    ) {
      return { equal: false, diff: `edge ${JSON.stringify(x)} != ${JSON.stringify(y)}` };
    }
  }
  return { equal: true, diff: '' };
}
