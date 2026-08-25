/**
 * Mermaid ground-truth mapping tables (PLAN.md §9.2), embedded as constants.
 * Every table verified against mermaid 11.17.0 (docs/research/mermaid-lab).
 */

// ---------------------------------------------------------------------------
// FlowDB vertex.type → ShapeKind (§7.3 table)
// ---------------------------------------------------------------------------

export const VERTEX_TYPE_TO_SHAPE: Record<string, string> = {
  '': 'rect', // absent / bare node
  square: 'rect',
  round: 'rounded',
  stadium: 'stadium',
  circle: 'circle',
  doublecircle: 'doublecircle',
  ellipse: 'ellipse',
  diamond: 'diamond',
  hexagon: 'hexagon',
  cylinder: 'cylinder',
  subroutine: 'subroutine',
  lean_right: 'parallelogram',
  lean_left: 'parallelogram-alt',
  trapezoid: 'trapezoid',
  inv_trapezoid: 'trapezoid-alt',
  odd: 'asymmetric',
};

/** '@{shape: …}' names (mermaid ≥11.3) → ShapeKind; unmapped names keep the raw
 * string in meta.mermaid.shape and map to the nearest shape. */
export const ALT_SHAPE_NAMES: Record<string, string> = {
  rect: 'rect',
  rounded: 'rounded',
  stadium: 'stadium',
  circle: 'circle',
  doublecircle: 'doublecircle',
  ellipse: 'ellipse',
  diamond: 'diamond',
  hexagon: 'hexagon',
  cyl: 'cylinder',
  cylinder: 'cylinder',
  subroutine: 'subroutine',
  leanright: 'parallelogram',
  lean_right: 'parallelogram',
  leftright: 'parallelogram-alt',
  lean_left: 'parallelogram-alt',
  trapezoid: 'trapezoid',
  inv_trapezoid: 'trapezoid-alt',
  odd: 'asymmetric',
  diam: 'diamond',
  'rounded-diamond': 'diamond',
};

/** ShapeKind → mermaid bracket syntax (export side; §9.4 inverts this). */
export const SHAPE_TO_BRACKETS: Record<string, [string, string]> = {
  rect: ['[', ']'],
  rounded: ['(', ')'],
  stadium: ['([', '])'],
  circle: ['((', '))'],
  doublecircle: ['(((', ')))'],
  ellipse: ['(-', '-)'],
  diamond: ['{', '}'],
  hexagon: ['{{', '}}'],
  cylinder: ['[(', ')]'],
  subroutine: ['[[', ']]'],
  parallelogram: ['[/', '/]'],
  'parallelogram-alt': ['[\\', '\\]'],
  trapezoid: ['[/', '\\]'],
  'trapezoid-alt': ['[\\', '/]'],
  asymmetric: ['>', ']'],
};

// ---------------------------------------------------------------------------
// Arrows — two orthogonal import lookups (§9.2)
// ---------------------------------------------------------------------------

export type ArrowHeads = [start: string, end: string];

/** db edge.type → (arrowStart, arrowEnd). */
export const EDGE_TYPE_TO_HEADS: Record<string, ArrowHeads> = {
  arrow_point: ['none', 'arrow'],
  arrow_open: ['none', 'none'],
  arrow_circle: ['none', 'circle'],
  arrow_cross: ['none', 'cross'],
  double_arrow_point: ['arrow', 'arrow'],
  double_arrow_circle: ['circle', 'circle'],
  double_arrow_cross: ['cross', 'cross'],
};

/** db edge.stroke → (line, hidden). */
export const EDGE_STROKE_TO_LINE: Record<string, [line: string, hidden: boolean]> = {
  normal: ['solid', false],
  dotted: ['dashed', false],
  thick: ['thick', false],
  invisible: ['solid', true],
};

// ---------------------------------------------------------------------------
// Export emit table — the ONLY 21+1 arrow bodies the exporter may emit
// ---------------------------------------------------------------------------

export type ArrowBody = string;

/** (line, arrowStart, arrowEnd) → syntax. Asymmetric head pairs with
 * arrowStart ≠ 'none' and ≠ arrowEnd degrade to (none, arrowEnd) BEFORE this
 * lookup (canonicalizeHeads). */
export const EMIT_TABLE: Record<string, Record<string, ArrowBody>> = {
  solid: {
    'none|none': '---',
    'none|arrow': '-->',
    'none|circle': '--o',
    'none|cross': '--x',
    'arrow|arrow': '<-->',
    'circle|circle': 'o--o',
    'cross|cross': 'x--x',
  },
  dashed: {
    'none|none': '-.-',
    'none|arrow': '-.->',
    'none|circle': '-.-o',
    'none|cross': '-.-x',
    'arrow|arrow': '<-.->',
    'circle|circle': 'o-.-o',
    'cross|cross': 'x-.-x',
  },
  thick: {
    'none|none': '===',
    'none|arrow': '==>',
    'none|circle': '==o',
    'none|cross': '==x',
    'arrow|arrow': '<==>',
    'circle|circle': 'o==o',
    'cross|cross': 'x==x',
  },
};

export const HIDDEN_BODY = '~~~';

/** §9.2 degrade rule — the canonicalization for round-trip tests. */
export function canonicalizeHeads(start: string, end: string): ArrowHeads {
  if (start !== 'none' && start !== end) return ['none', end];
  return [start, end];
}

/** minlen extension: repeat the line's MIDDLE character (minlen − 1) times. */
export function extendBody(body: string, minlen: number): string {
  if (minlen <= 1) return body;
  if (body === HIDDEN_BODY) return HIDDEN_BODY.repeat(minlen);
  // body like '-->' / '-.->' / '<==>' / '---': middle char is
  // '-' for solid, '.' for dashed, '=' for thick.
  const middle = body.includes('.')
    ? '.'
    : body.includes('=') && !body.startsWith('x') && !body.startsWith('o')
      ? '='
      : '-';
  // insert (minlen-1) middle chars after the first run start
  const extra = middle.repeat(minlen - 1);
  // '->' style: insert before the head arrow segment. Simplest robust rule:
  // bodies end with optional head chars; insert after the leading run.
  const m = body.match(/^([<xo-]*)([-.=])(.*)$/);
  if (!m) return body + extra;
  const [, head = '', firstChar = '-'] = m;
  // find the leading run of the SAME char from the body start (after head chars)
  const runMatch = body
    .slice(head.length)
    .match(new RegExp(`\\${firstChar === '.' ? '.' : firstChar}+`));
  const runStart = head.length;
  const runEnd = runStart + (runMatch ? runMatch[0].length : 0);
  return body.slice(0, runEnd) + extra + body.slice(runEnd);
}

// ---------------------------------------------------------------------------
// Mermaid-safe ids (§9.2)
// ---------------------------------------------------------------------------

/** Node-id keywords that are parse errors when used bare. */
export const MERMAID_ID_BLOCKLIST = [
  'end',
  'style',
  'class',
  'classDef',
  'click',
  'subgraph',
  'graph',
  'flowchart',
  'linkStyle',
];

/** Full sequence LINETYPE table (§9.2; the abbreviated one is missing 26–34). */
export const LINETYPE: Record<string, number> = {
  SOLID: 0,
  DOTTED: 1,
  NOTE: 2,
  SOLID_CROSS: 3,
  DOTTED_CROSS: 4,
  SOLID_OPEN: 5,
  DOTTED_OPEN: 6,
  LOOP_START: 10,
  LOOP_END: 11,
  ALT_START: 12,
  ALT_ELSE: 13,
  ALT_END: 14,
  OPT_START: 15,
  OPT_END: 16,
  ACTIVE_START: 17,
  ACTIVE_END: 18,
  PAR_START: 19,
  PAR_AND: 20,
  PAR_END: 21,
  RECT_START: 22,
  RECT_END: 23,
  SOLID_POINT: 24,
  DOTTED_POINT: 25,
  AUTONUMBER: 26,
  CRITICAL_START: 27,
  CRITICAL_OPTION: 28,
  CRITICAL_END: 29,
  BREAK_START: 30,
  BREAK_END: 31,
  PAR_OVER_START: 32,
  BIDIRECTIONAL_SOLID: 33,
  BIDIRECTIONAL_DOTTED: 34,
};

export const PLACEMENT: Record<string, number> = {
  LEFTOF: 0,
  RIGHTOF: 1,
  OVER: 2,
};
