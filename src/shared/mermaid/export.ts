/**
 * exportMermaid (PLAN.md §9.4): pure serializer — doc (or selection) →
 * {text, idAssignments}. Never mutates the doc; callers apply assignments
 * via the untracked ensureMermaidIds action (§8.3).
 *
 * Emit rules (§9.2/§9.4):
 *  - the 22-body emit table exactly (plus degrade canonicalization)
 *  - labels: encodeLabel (order-sensitive), always quoted
 *  - ids: [A-Za-z_][A-Za-z0-9_]*, blocklist excluded, collision-suffixed
 *  - nodes in z-order; containers as subgraph blocks (direction when stored)
 *  - standalone declaration skipped ONLY when label==id && shape is rect &&
 *    the node appears in an emitted edge
 */
import type { ThalyxDoc, ThalyxEdge, ThalyxNode } from '../model/types';
import {
  canonicalizeHeads,
  EMIT_TABLE,
  extendBody,
  HIDDEN_BODY,
  MERMAID_ID_BLOCKLIST,
  SHAPE_TO_BRACKETS,
} from './tables';
import { encodeLabel } from './entities';

export interface ExportResult {
  text: string;
  idAssignments: Record<string, string>;
}

const ID_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;

interface ExportCtx {
  doc: ThalyxDoc;
  ids: Map<string, string>; // nodeId → mermaid id
  idAssignments: Record<string, string>;
  used: Set<string>;
  /** nodes included in this export (selection scope) */
  include: Set<string>;
}

function deriveId(node: ThalyxNode, used: Set<string>): string {
  const base = (node.label ?? '')
    .split(/[^A-Za-z0-9_]+/)
    .filter(Boolean)
    .map((w, i) => (i === 0 ? w : w[0]!.toUpperCase() + w.slice(1)))
    .join('');
  let candidate = ID_RE.test(base) && !MERMAID_ID_BLOCKLIST.includes(base) ? base : '';
  if (!candidate) {
    // numbered fallback
    let n = 1;
    while (!candidate) {
      const probe = `n${n}`;
      if (ID_RE.test(probe) && !MERMAID_ID_BLOCKLIST.includes(probe) && !used.has(probe)) {
        candidate = probe;
      }
      n += 1;
    }
  }
  if (used.has(candidate)) {
    let n = 2;
    while (used.has(`${candidate}_${n}`)) n += 1;
    candidate = `${candidate}_${n}`;
  }
  used.add(candidate);
  return candidate;
}

function idFor(ctx: ExportCtx, node: ThalyxNode): string {
  const existing = ctx.ids.get(node.id);
  if (existing) return existing;
  // §9.4 step 1: prefer stored meta.mermaid.id
  const stored = node.meta?.mermaid?.id;
  let id: string;
  if (
    stored &&
    ID_RE.test(stored) &&
    !MERMAID_ID_BLOCKLIST.includes(stored) &&
    !ctx.used.has(stored)
  ) {
    id = stored;
    ctx.used.add(stored);
  } else {
    id = deriveId(node, ctx.used);
    ctx.idAssignments[node.id] = id; // derived — caller persists untracked
  }
  ctx.ids.set(node.id, id);
  return id;
}

function emitLabel(node: ThalyxNode, id: string): string | null {
  if (node.kind !== 'shape') {
    // text/mermaid nodes are never skip-eligible — they need declarations
    // (mermaid islands are handled by the caller's notice, not here)
    return node.kind === 'text' ? (node.label ?? '') : null;
  }
  const label = node.label ?? '';
  // Skip condition: label == id, plain rect, and appears in an edge — the
  // caller checks edge membership; we signal plainness here.
  if (label === id && (node.shape ?? 'rect') === 'rect') return null;
  return label;
}

function nodeLine(node: ThalyxNode, id: string, label: string | null): string | null {
  if (node.kind === 'container') return null; // containers emit as blocks
  if (node.kind === 'mermaid') return null; // islands: caller handles the notice
  if (label === null) return null; // skip-eligible — no declaration line
  // mermaid rejects A[""] — empty labels emit a single space (verified)
  const safe = label.length === 0 ? ' ' : label;
  if (node.kind === 'text') return `  ${id}[${encodeLabel(safe)}]`; // text → plain bracket node
  const rawShape = node.meta?.mermaid?.shape; // unmapped original name
  if (rawShape && !SHAPE_TO_BRACKETS[node.shape ?? 'rect']) {
    return `  ${id}@{ shape: ${rawShape}, label: ${encodeLabel(safe)} }`;
  }
  const [open, close] = SHAPE_TO_BRACKETS[node.shape ?? 'rect'] ?? ['[', ']'];
  return `  ${id}${open}${encodeLabel(safe)}${close}`;
}

function edgeBody(edge: ThalyxEdge): string {
  if (edge.hidden) return extendBody(HIDDEN_BODY, edge.meta?.mermaid?.minlen ?? 1);
  const [start, end] = canonicalizeHeads(edge.arrowStart, edge.arrowEnd);
  const base = EMIT_TABLE[edge.style.line]?.[`${start}|${end}`] ?? '-->';
  return extendBody(base, edge.meta?.mermaid?.minlen ?? 1);
}

function edgeLine(edge: ThalyxEdge, srcId: string, tgtId: string): string {
  const userId = edge.meta?.mermaid?.id;
  const body = edgeBody(edge);
  const label = edge.label ? `|${encodeLabel(edge.label)}|` : '';
  const idPrefix = userId ? `${userId}@` : '';
  return `  ${srcId} ${idPrefix}${body}${label} ${tgtId}`;
}

export function exportMermaid(
  doc: ThalyxDoc,
  opts: { selection?: { nodeIds: string[]; edgeIds: string[] } } = {},
): ExportResult {
  const include = new Set<string>(
    opts.selection
      ? opts.selection.nodeIds.flatMap((id) => {
          // containers export with their descendants
          const node = doc.nodes.find((n) => n.id === id);
          if (!node) return [];
          if (node.kind === 'container') {
            return [id, ...descendants(doc, id).map((n) => n.id)];
          }
          return [id];
        })
      : doc.nodes.map((n) => n.id),
  );

  const ctx: ExportCtx = {
    doc,
    ids: new Map(),
    idAssignments: {},
    used: new Set(),
    include,
  };

  const exported = doc.nodes.filter((n) => include.has(n.id));
  // hidden edges EXPORT as ~~~ (§9.4 emit table) — not filtered out
  const edges = doc.edges.filter((e) => include.has(e.source) && include.has(e.target));

  const lines: string[] = [];
  const fm = doc.meta.mermaid?.frontmatter;
  if (fm) lines.push(fm.replace(/\n$/, ''), '');
  lines.push(`flowchart ${doc.meta.mermaid?.direction ?? 'TB'}`);

  const idsInEdges = new Set<string>();
  for (const e of edges) {
    idsInEdges.add(e.source);
    idsInEdges.add(e.target);
  }

  // Node declarations in z-order, grouped with containers
  const emitNodes = (nodes: ThalyxNode[], indent: string): void => {
    for (const node of nodes) {
      const id = idFor(ctx, node);
      if (node.kind === 'container') {
        // same empty-label rule as nodes: A[""] is a parse error — emit a space
        const rawTitle = node.label ?? '';
        const title = encodeLabel(rawTitle.length === 0 ? ' ' : rawTitle);
        lines.push(`${indent}subgraph ${id}[${title}]`);
        if (node.meta?.mermaid?.dir) {
          lines.push(`${indent}  direction ${node.meta.mermaid.dir}`);
        }
        const children = exported.filter((n) => n.parentId === node.id);
        emitNodes(children, `${indent}  `);
        lines.push(`${indent}end`);
        continue;
      }
      const appearsInEdge = idsInEdges.has(node.id);
      // skip-eligible only when the node appears in an edge; edge-less nodes
      // always emit a standalone line (or they vanish from the export)
      const label = appearsInEdge ? emitLabel(node, id) : node.label;
      const line = nodeLine(node, id, label);
      if (line) {
        lines.push(indent + line.slice(2));
      }
      // skip-eligible (label==id, rect, in an edge) — no declaration line
    }
  };
  emitNodes(
    exported.filter((n) => n.parentId === undefined),
    '  ',
  );

  for (const e of edges) {
    const src = doc.nodes.find((n) => n.id === e.source)!;
    const tgt = doc.nodes.find((n) => n.id === e.target)!;
    lines.push(edgeLine(e, idFor(ctx, src), idFor(ctx, tgt)));
  }

  // style tail
  const classDefs = doc.meta.mermaid?.classDefs ?? {};
  for (const [name, styles] of Object.entries(classDefs)) {
    lines.push(`  classDef ${name} ${styles.join(',')}`);
  }
  for (const node of exported) {
    const meta = node.meta?.mermaid;
    if (!meta) continue;
    if (meta.classes && meta.classes.length > 0) {
      lines.push(`  class ${idFor(ctx, node)} ${meta.classes.join(',')}`);
    }
    if (meta.styles && meta.styles.length > 0) {
      lines.push(`  style ${idFor(ctx, node)} ${meta.styles.join(',')}`);
    }
    if (meta.link) {
      const tooltip = meta.tooltip ? ` "${meta.tooltip}"` : '';
      lines.push(`  click ${idFor(ctx, node)} href "${meta.link}"${tooltip}`);
    }
  }

  return { text: lines.join('\n') + '\n', idAssignments: ctx.idAssignments };
}

function descendants(doc: ThalyxDoc, id: string): ThalyxNode[] {
  const out: ThalyxNode[] = [];
  const walk = (pid: string) => {
    for (const n of doc.nodes) {
      if (n.parentId === pid) {
        out.push(n);
        if (n.kind === 'container') walk(n.id);
      }
    }
  };
  walk(id);
  return out;
}
