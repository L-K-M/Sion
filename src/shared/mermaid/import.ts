/**
 * importMermaid (PLAN.md §9.3): mermaid text → nodes/edges/meta (or an
 * island marker, or an error). Runs in the renderer (real DOM) or tests
 * (jsdom-shimmed mermaid). Pure data in/out — no store access here.
 */
import { newEdge, newNode } from '../model/create';
import type { MermaidDirection, ThalyxEdge, ThalyxNode } from '../model/types';
import {
  ALT_SHAPE_NAMES,
  EDGE_STROKE_TO_LINE,
  EDGE_TYPE_TO_HEADS,
  VERTEX_TYPE_TO_SHAPE,
} from './tables';
import { decodeMermaidLabel } from './entities';
import { positionUnderParent } from '../model/queries';

export interface FlowchartImport {
  kind: 'flowchart';
  nodes: ThalyxNode[];
  edges: ThalyxEdge[];
  meta: {
    direction: MermaidDirection;
    frontmatter?: string;
    classDefs?: Record<string, string[]>;
    sourceText: string;
  };
}

export interface IslandImport {
  kind: 'island';
  diagramType: string;
  source: string;
}

export interface ErrorImport {
  kind: 'error';
  error: { message: string; line?: number; col?: number; expected?: string[] };
}

export type ImportResult = FlowchartImport | IslandImport | ErrorImport;

interface FlowDb {
  getVertices(): Map<string, Vertex>;
  getEdges(): EdgeRecord[];
  getSubGraphs(): SubGraph[];
  getDirection(): string;
  getClasses(): Map<string, { styles?: string[] }>;
  getTooltip(id: string): string | undefined;
}

interface Vertex {
  id: string;
  text: string;
  labelType?: 'text' | 'string' | 'markdown';
  type?: string;
  styles?: string[];
  classes?: string[];
  link?: string;
}

interface EdgeRecord {
  start: string;
  end: string;
  type: string;
  stroke: string;
  length?: number;
  text: string;
  labelType?: string;
  id?: string;
  isUserDefinedId?: boolean;
}

interface SubGraph {
  id: string;
  nodes: string[];
  title: string;
  dir?: string;
  labelType?: string;
}

const FLOWCHART_TYPES = new Set(['flowchart-v2', 'flowchart-elk']);

/** Strip and return the frontmatter block if present ('---\n…\n---\n'). */
function splitFrontmatter(text: string): { frontmatter?: string; body: string } {
  if (!text.startsWith('---\n')) return { body: text };
  const end = text.indexOf('\n---\n', 4);
  if (end === -1) return { body: text };
  return {
    frontmatter: text.slice(0, end + 5), // keep trailing newline of the block
    body: text.slice(end + 5),
  };
}

function mapStyleStrings(styles: string[] | undefined): {
  fill?: string;
  stroke?: string;
  strokeWidth?: 1 | 2 | 4;
} {
  const out: { fill?: string; stroke?: string; strokeWidth?: 1 | 2 | 4 } = {};
  if (!styles) return out;
  for (const raw of styles) {
    const s = raw.trim();
    const m = s.match(/^(fill|stroke|stroke-width)\s*:\s*([^;]+)/);
    if (!m) continue;
    const [, prop, value] = m;
    const v = value!.trim();
    if (prop === 'fill') out.fill = v;
    if (prop === 'stroke') out.stroke = v;
    if (prop === 'stroke-width') {
      const n = Number.parseFloat(v);
      out.strokeWidth = n <= 1 ? 1 : n >= 4 ? 4 : 2;
    }
  }
  return out;
}

export async function importMermaid(text: string, parse: ParseFn): Promise<ImportResult> {
  const { frontmatter, body } = splitFrontmatter(text);
  const parsed = await parse(body); // NOTE: frontmatter stripped — mermaid handles it
  // itself when present; callers pass the full text when the doc has one. We
  // parse the BODY here because our splitter already consumed it; mermaid's
  // own frontmatter handling is equivalent for the flowchart db surface.
  if (!parsed.ok) return { kind: 'error', error: parsed.error };
  if (!FLOWCHART_TYPES.has(parsed.diagramType)) {
    return { kind: 'island', diagramType: parsed.diagramType, source: text };
  }
  const db = parsed.db as FlowDb;

  const direction = normalizeDirection(db.getDirection());
  const nodes: ThalyxNode[] = [];
  const edges: ThalyxEdge[] = [];

  // --- subgraphs first (containers before children — invariant 3) ---
  const subgraphs = db.getSubGraphs();
  // inner subgraphs list BEFORE outer ones (§9.3 gotcha) — topologically
  // sort parent-first by nesting depth.
  const nodeToSubgraph = new Map<string, string>();
  const subgraphById = new Map<string, SubGraph>();
  for (const sg of subgraphs) {
    subgraphById.set(sg.id, sg);
    for (const memberId of sg.nodes) {
      // a member may itself be a subgraph id (nested); the INNERMOST container
      // wins for direct shape membership — mermaid lists members per level.
      if (!nodeToSubgraph.has(memberId)) nodeToSubgraph.set(memberId, sg.id);
    }
  }
  const subgraphDepth = (id: string): number => {
    let depth = 0;
    let cursor: string | undefined = id;
    while (cursor !== undefined) {
      const sg = subgraphById.get(cursor);
      if (!sg) break;
      const outer = sg.nodes.length > 0 ? nodeToSubgraph.get(sg.id) : undefined;
      cursor = outer && outer !== sg.id ? outer : undefined;
      depth += 1;
    }
    return depth;
  };
  const orderedSubgraphs = [...subgraphs].sort((a, b) => subgraphDepth(a.id) - subgraphDepth(b.id));
  for (const sg of orderedSubgraphs) {
    const outer = nodeToSubgraph.get(sg.id);
    nodes.push(
      newNode({
        id: sg.id,
        kind: 'container',
        label: sg.title.length > 0 ? decodeMermaidLabel(sg.title) : '',
        style: { fill: 'surface', stroke: 'ink' },
        ...(outer && outer !== sg.id ? { parentId: outer } : {}),
        meta: {
          mermaid: {
            id: sg.id,
            ...(sg.dir ? { dir: normalizeDirection(sg.dir) } : {}),
          },
        },
      }),
    );
  }

  // --- classDefs resolved BEFORE vertices (class styles compose into the
  //     vertex style map — db keeps them on the CLASS, not the vertex) ---
  const classes = db.getClasses();
  const classDefs: Record<string, string[]> = {};
  for (const [name, def] of classes) {
    if (def?.styles && def.styles.length > 0) classDefs[name] = [...def.styles];
  }

  // --- vertices (subgraph ids do NOT appear in getVertices — §9.3 gotcha) ---
  for (const [id, v] of db.getVertices()) {
    const shape: import('../model/types').ShapeKind = vertexShape(v.type);
    const mergedStyles = [...(v.styles ?? [])];
    for (const cls of v.classes ?? []) {
      if (classDefs[cls]) mergedStyles.push(...classDefs[cls]!);
    }
    const mapped = mapStyleStrings(mergedStyles);
    const label = decodeMermaidLabel(v.text);
    const parentId = nodeToSubgraph.get(id);
    nodes.push(
      newNode({
        id,
        kind: 'shape',
        shape,
        // seed size (§9.3): clamped text-width estimate; dagre refines later
        width: clamp(96, 8 + 9 * longestLine(label), 320),
        height: 40 + 20 * Math.max(0, label.split('\n').length - 1),
        label,
        ...(parentId ? { parentId } : {}),
        style: {
          ...(mapped.fill ? { fill: mapped.fill } : {}),
          ...(mapped.stroke ? { stroke: mapped.stroke } : {}),
          ...(mapped.strokeWidth ? { strokeWidth: mapped.strokeWidth } : {}),
        },
        meta: {
          mermaid: {
            id,
            ...(v.type && !VERTEX_TYPE_TO_SHAPE[v.type] && v.type !== 'square' && v.type !== ''
              ? { shape: v.type }
              : {}),
            ...(v.classes && v.classes.length > 0 ? { classes: v.classes } : {}),
            ...(v.styles && v.styles.length > 0 ? { styles: v.styles } : {}),
            ...(v.link ? { link: v.link } : {}),
            ...(db.getTooltip(id) ? { tooltip: db.getTooltip(id)! } : {}),
            ...(v.labelType ? { labelType: v.labelType } : {}),
          },
        },
      }),
    );
  }

  // --- edges ---
  for (const e of db.getEdges()) {
    const [arrowStart, arrowEnd] = (EDGE_TYPE_TO_HEADS[e.type] ?? ['none', 'arrow']) as [
      import('../model/types').ArrowHead,
      import('../model/types').ArrowHead,
    ];
    const [line, hidden] = (EDGE_STROKE_TO_LINE[e.stroke] ?? ['solid', false]) as [
      'solid' | 'dashed' | 'thick',
      boolean,
    ];
    edges.push(
      newEdge({
        source: e.start,
        target: e.end,
        kind: 'elbow',
        label: e.text ? decodeMermaidLabel(e.text) : undefined,
        arrowStart,
        arrowEnd,
        hidden,
        style: { line },
        meta: {
          mermaid: {
            ...(e.isUserDefinedId && e.id ? { id: e.id } : {}),
            ...(e.length && e.length > 1 ? { minlen: e.length } : {}),
          },
        },
      }),
    );
  }

  return {
    kind: 'flowchart',
    nodes,
    edges,
    meta: {
      direction,
      ...(frontmatter ? { frontmatter } : {}),
      ...(Object.keys(classDefs).length > 0 ? { classDefs } : {}),
      sourceText: text,
    },
  };
}

export type ParseFn = (
  text: string,
) => Promise<
  | { ok: true; diagramType: string; db: unknown }
  | { ok: false; error: { message: string; line?: number; col?: number; expected?: string[] } }
>;

function vertexShape(type: string | undefined): import('../model/types').ShapeKind {
  if (!type || type === '') return 'rect';
  const direct = VERTEX_TYPE_TO_SHAPE[type];
  if (direct) return direct as import('../model/types').ShapeKind;
  const alt = ALT_SHAPE_NAMES[type];
  return (alt ?? 'rect') as import('../model/types').ShapeKind;
}

function clamp(min: number, v: number, max: number): number {
  return Math.min(max, Math.max(min, v));
}

function longestLine(label: string): number {
  return label.split('\n').reduce((max, l) => Math.max(max, l.length), 0);
}

function normalizeDirection(d: string): MermaidDirection {
  if (d === 'BT' || d === 'LR' || d === 'RL') return d;
  return 'TB'; // includes TD
}

// Re-anchor helper used by the layout step of importMermaidAsNew (renderer).
export { positionUnderParent };
