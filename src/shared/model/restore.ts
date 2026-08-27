/**
 * restoreDocument(): normalize-on-load (PLAN.md §7.5).
 *
 * Strategy (Excalidraw's restore()): coerce whatever arrives into a valid v1
 * doc — fill defaults, drop unknown fields, drop edges whose endpoints don't
 * resolve, fix z-order/parent ordering, clamp numbers. Never throw on
 * merely-weird data. The only hard error is `version > 1` (DocTooNewError).
 */
import { DEFAULT_NODE_HEIGHT, DEFAULT_NODE_WIDTH, newEdge, newId, newNode } from './create';
import {
  parseDocSchema,
  COORD_MAX,
  COORD_MIN,
  EDGES_MAX,
  LABEL_MAX,
  NODES_MAX,
  SIZE_MAX,
  SIZE_MIN,
} from './schema';
import { ARROW_HEADS, MERMAID_DIRECTIONS, NODE_KINDS, SHAPE_KINDS } from './types';
import type {
  MermaidDirection,
  NodeKind,
  NodeStyle,
  ThalyxDoc,
  ThalyxEdge,
  ThalyxNode,
} from './types';

/** The document was made with a newer Thalyx (§7.5 step 1). */
export class DocTooNewError extends Error {
  constructor(public readonly foundVersion: number) {
    super(`Document was made with a newer Thalyx (schema v${foundVersion} > v1)`);
    this.name = 'DocTooNewError';
  }
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function coerceString(v: unknown, fallback = ''): string {
  return typeof v === 'string' ? v : fallback;
}

function coerceLabel(v: unknown): string {
  return typeof v === 'string' ? v.slice(0, LABEL_MAX) : '';
}

function coerceFinite(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}

function clamp(v: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, v));
}

function coerceCoord(v: unknown, fallback = 0): number {
  return clamp(coerceFinite(v, fallback), COORD_MIN, COORD_MAX);
}

function coerceSize(v: unknown, fallback: number): number {
  return clamp(coerceFinite(v, fallback), SIZE_MIN, SIZE_MAX);
}

function coerceBool(v: unknown): boolean | undefined {
  return typeof v === 'boolean' ? v : undefined;
}

function coerceEnum<T extends string>(v: unknown, allowed: readonly T[], fallback: T): T {
  return typeof v === 'string' && (allowed as readonly string[]).includes(v) ? (v as T) : fallback;
}

function coerceStrokeWidth(v: unknown): NodeStyle['strokeWidth'] {
  return v === 1 || v === 4 ? v : 2;
}

function coerceFontSize(v: unknown): NodeStyle['fontSize'] {
  return v === 12 || v === 18 || v === 24 ? v : 14;
}

function coerceNodeStyle(v: unknown): NodeStyle {
  const raw = isRecord(v) ? v : {};
  return {
    fill: coerceString(raw['fill'], 'surface').slice(0, 64) || 'surface',
    stroke: coerceString(raw['stroke'], 'ink').slice(0, 64) || 'ink',
    strokeWidth: coerceStrokeWidth(raw['strokeWidth']),
    fontSize: coerceFontSize(raw['fontSize']),
    textAlign: 'center',
  };
}

function coerceStringArray(v: unknown, cap = 64, entryMax = 2048): string[] | undefined {
  if (!Array.isArray(v)) return undefined;
  return v
    .filter((s): s is string => typeof s === 'string')
    .slice(0, cap)
    .map((s) => s.slice(0, entryMax));
}

function coerceNodeMeta(v: unknown): ThalyxNode['meta'] {
  if (!isRecord(v) || !isRecord(v['mermaid'])) return undefined;
  const m = v['mermaid'] as Record<string, unknown>;
  const classes = coerceStringArray(m['classes'], 64, 512);
  const styles = coerceStringArray(m['styles'], 64);
  const labelType = coerceEnum(m['labelType'], ['text', 'string', 'markdown'] as const, 'text');
  const dir = MERMAID_DIRECTIONS.includes(m['dir'] as MermaidDirection)
    ? (m['dir'] as MermaidDirection)
    : undefined;
  return {
    mermaid: {
      ...(typeof m['id'] === 'string' ? { id: m['id'].slice(0, 512) } : {}),
      ...(typeof m['shape'] === 'string' ? { shape: m['shape'].slice(0, 128) } : {}),
      ...(classes ? { classes } : {}),
      ...(styles ? { styles } : {}),
      ...(typeof m['link'] === 'string' ? { link: m['link'].slice(0, 2048) } : {}),
      ...(typeof m['tooltip'] === 'string' ? { tooltip: m['tooltip'].slice(0, 2048) } : {}),
      ...(m['labelType'] !== undefined ? { labelType } : {}),
      ...(dir ? { dir } : {}),
    },
  };
}

function coerceNode(raw: unknown): ThalyxNode | null {
  if (!isRecord(raw)) return null;
  const kind: NodeKind = coerceEnum(raw['kind'], NODE_KINDS, 'shape');
  const node = newNode({
    id: typeof raw['id'] === 'string' && raw['id'].length > 0 ? raw['id'].slice(0, 64) : newId(),
    kind,
    x: coerceCoord(raw['x']),
    y: coerceCoord(raw['y']),
    width: coerceSize(raw['width'], DEFAULT_NODE_WIDTH),
    height: coerceSize(raw['height'], DEFAULT_NODE_HEIGHT),
    label: coerceLabel(raw['label']),
    parentId: typeof raw['parentId'] === 'string' ? raw['parentId'] : undefined,
    style: coerceNodeStyle(raw['style']),
    locked: coerceBool(raw['locked']),
    hidden: coerceBool(raw['hidden']),
    mermaidSource:
      kind === 'mermaid' && typeof raw['mermaidSource'] === 'string'
        ? raw['mermaidSource'].slice(0, 1_000_000)
        : undefined,
  });
  if (kind === 'shape') {
    node.shape = coerceEnum(raw['shape'], SHAPE_KINDS, 'rect');
  }
  const meta = coerceNodeMeta(raw['meta']);
  if (meta) node.meta = meta;
  return node;
}

function coerceWaypoints(v: unknown): { x: number; y: number }[] | undefined {
  if (!Array.isArray(v) || v.length === 0) return undefined;
  const pts = v
    .filter(isRecord)
    .map((p) => ({
      x: clamp(coerceFinite(p['x'], 0), COORD_MIN, COORD_MAX),
      y: clamp(coerceFinite(p['y'], 0), COORD_MIN, COORD_MAX),
    }))
    .slice(0, 64);
  return pts.length > 0 ? pts : undefined;
}

function coerceEdge(raw: unknown): ThalyxEdge | null {
  if (!isRecord(raw)) return null;
  const source = coerceString(raw['source']);
  const target = coerceString(raw['target']);
  if (!source || !target) return null;
  const rawLabelT = raw['labelT'];
  const edge = newEdge({
    id: typeof raw['id'] === 'string' && raw['id'].length > 0 ? raw['id'].slice(0, 64) : newId(),
    source,
    target,
    kind: coerceEnum(raw['kind'], ['elbow', 'straight', 'curved'] as const, 'elbow'),
    label: typeof raw['label'] === 'string' ? raw['label'].slice(0, LABEL_MAX) : undefined,
    ...(typeof rawLabelT === 'number' && Number.isFinite(rawLabelT)
      ? { labelT: clamp(rawLabelT, 0, 1) }
      : {}),
    arrowStart: coerceEnum(raw['arrowStart'], ARROW_HEADS, 'none'),
    arrowEnd: coerceEnum(raw['arrowEnd'], ARROW_HEADS, 'arrow'),
    sourceAnchor: coerceEnum(raw['sourceAnchor'], ['auto', 'n', 's', 'e', 'w'] as const, 'auto'),
    targetAnchor: coerceEnum(raw['targetAnchor'], ['auto', 'n', 's', 'e', 'w'] as const, 'auto'),
    hidden: coerceBool(raw['hidden']),
    waypoints: coerceWaypoints(raw['waypoints']),
  });
  const rawStyle = isRecord(raw['style']) ? (raw['style'] as Record<string, unknown>) : {};
  edge.style = {
    line: coerceEnum(rawStyle['line'], ['solid', 'dashed', 'thick'] as const, 'solid'),
    stroke: coerceString(rawStyle['stroke'], 'ink').slice(0, 64) || 'ink',
    rounded: rawStyle['rounded'] !== false,
  };
  if (isRecord(raw['meta']) && isRecord(raw['meta']['mermaid'])) {
    const m = raw['meta']['mermaid'] as Record<string, unknown>;
    const styles = coerceStringArray(m['styles'], 64);
    const rawMinlen = m['minlen'];
    edge.meta = {
      mermaid: {
        ...(typeof m['id'] === 'string' ? { id: m['id'].slice(0, 512) } : {}),
        ...(typeof rawMinlen === 'number' && Number.isFinite(rawMinlen)
          ? { minlen: clamp(Math.round(rawMinlen), 1, 64) }
          : {}),
        ...(styles ? { styles } : {}),
      },
    };
  }
  return edge;
}

function coerceCanvas(raw: unknown): ThalyxDoc['canvas'] {
  const r = isRecord(raw) ? raw : {};
  return {
    background: coerceString(r['background'], 'default').slice(0, 128) || 'default',
    grid: r['grid'] === true,
  };
}

function coerceMeta(raw: unknown): ThalyxDoc['meta'] {
  const r =
    isRecord(raw) && isRecord(raw['mermaid']) ? (raw['mermaid'] as Record<string, unknown>) : {};
  const classDefs: Record<string, string[]> = {};
  if (isRecord(r['classDefs'])) {
    for (const [k, v] of Object.entries(r['classDefs']).slice(0, 256)) {
      const styles = coerceStringArray(v, 64);
      if (styles && styles.length > 0) classDefs[k.slice(0, 512)] = styles;
    }
  }
  return {
    mermaid: {
      direction: coerceEnum(r['direction'], MERMAID_DIRECTIONS, 'TB'),
      ...(typeof r['frontmatter'] === 'string'
        ? { frontmatter: r['frontmatter'].slice(0, 65_536) }
        : {}),
      ...(Object.keys(classDefs).length > 0 ? { classDefs } : {}),
      ...(typeof r['sourceText'] === 'string'
        ? { sourceText: r['sourceText'].slice(0, 1_000_000) }
        : {}),
    },
  };
}

/**
 * Normalize-on-load. Throws DocTooNewError iff raw declares version > 1;
 * never throws otherwise. Output satisfies the zod schema.
 */
export function restoreDocument(raw: unknown): ThalyxDoc {
  if (isRecord(raw)) {
    const v = raw['version'];
    if (typeof v === 'number' && Number.isFinite(v) && v > 1) {
      throw new DocTooNewError(v);
    }
  }

  const rawNodes = Array.isArray((raw as Record<string, unknown> | null)?.['nodes'])
    ? ((raw as Record<string, unknown>)['nodes'] as unknown[])
    : [];
  const rawEdges = Array.isArray((raw as Record<string, unknown> | null)?.['edges'])
    ? ((raw as Record<string, unknown>)['edges'] as unknown[])
    : [];

  // --- nodes: coerce + dedupe ids (keep first) ---
  const seenIds = new Set<string>();
  const nodes: ThalyxNode[] = [];
  for (const rn of rawNodes.slice(0, NODES_MAX)) {
    const node = coerceNode(rn);
    if (!node || seenIds.has(node.id)) continue;
    seenIds.add(node.id);
    nodes.push(node);
  }
  const byId = new Map(nodes.map((n) => [n.id, n]));

  // --- parentId repair: only existing containers; break cycles ---
  for (const node of nodes) {
    if (node.parentId === undefined) continue;
    const parent = byId.get(node.parentId);
    if (!parent || parent.kind !== 'container') {
      node.parentId = undefined;
      continue;
    }
    // cycle check: walk up with a visited set; if we reach this node again,
    // detach it (the set terminates arbitrary-length chains — no depth cap)
    const chain = new Set<string>([node.id]);
    let cursor: string | undefined = node.parentId;
    while (cursor !== undefined && !chain.has(cursor)) {
      chain.add(cursor);
      cursor = byId.get(cursor)?.parentId;
    }
    if (cursor === node.id) node.parentId = undefined;
  }

  // --- edges: endpoints must resolve to existing, non-island nodes ---
  const edges: ThalyxEdge[] = [];
  const seenEdgeIds = new Set<string>();
  for (const re of rawEdges.slice(0, EDGES_MAX)) {
    const edge = coerceEdge(re);
    if (!edge || edge.source === edge.target) continue;
    const source = byId.get(edge.source);
    const target = byId.get(edge.target);
    if (!source || !target) continue; // invariant 1: drop dangling
    if (source.kind === 'mermaid' || target.kind === 'mermaid') continue; // invariant 5
    if (seenEdgeIds.has(edge.id)) continue;
    seenEdgeIds.add(edge.id);
    edges.push(edge);
  }

  // --- z-order: containers strictly before children (invariant 3) ---
  // Stable topological pass: emit each node as soon as its parent (if any)
  // has been emitted; defer otherwise. Preserves the ORIGINAL relative order
  // as much as possible (unlike depth-grouping, which hoists same-depth
  // nodes past unrelated ones).
  const ordered: ThalyxNode[] = [];
  const emitted = new Set<string>();
  let pending = nodes;
  while (pending.length > 0) {
    const deferred: ThalyxNode[] = [];
    let progress = false;
    for (const n of pending) {
      if (n.parentId === undefined || emitted.has(n.parentId)) {
        emitted.add(n.id);
        ordered.push(n);
        progress = true;
      } else {
        deferred.push(n);
      }
    }
    if (!progress) {
      ordered.push(...pending); // defensive: residual cycle keeps original order
      break;
    }
    pending = deferred;
  }

  const raw_ = isRecord(raw) ? raw : {};
  const doc: ThalyxDoc = {
    type: 'thalyx',
    version: 1,
    source: coerceString(raw_['source'], 'thalyx@0.0.0').slice(0, 128) || 'thalyx@0.0.0',
    nodes: ordered,
    edges,
    canvas: coerceCanvas(raw_['canvas']),
    meta: coerceMeta(raw_['meta']),
  };

  // Final assertion (§7.5 step 3): a failure here is a restore bug.
  parseDocSchema(doc);
  return doc;
}
