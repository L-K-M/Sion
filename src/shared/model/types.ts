/**
 * Thalyx document model — authoritative types (PLAN.md §7.1).
 *
 * This module is pure TypeScript: no React, no Electron, no DOM.
 */

export type NodeId = string; // nanoid(12)
export type EdgeId = string;

export type ShapeKind =
  // toolbar set (MVP visible)
  | 'rect'
  | 'rounded'
  | 'ellipse'
  | 'diamond'
  | 'cylinder'
  // full mermaid flowchart set (renderable, reachable via import & shape popup)
  | 'stadium'
  | 'circle'
  | 'doublecircle'
  | 'subroutine'
  | 'hexagon'
  | 'parallelogram'
  | 'parallelogram-alt'
  | 'trapezoid'
  | 'trapezoid-alt'
  | 'asymmetric';

export const SHAPE_KINDS: readonly ShapeKind[] = [
  'rect',
  'rounded',
  'ellipse',
  'diamond',
  'cylinder',
  'stadium',
  'circle',
  'doublecircle',
  'subroutine',
  'hexagon',
  'parallelogram',
  'parallelogram-alt',
  'trapezoid',
  'trapezoid-alt',
  'asymmetric',
] as const;

export type NodeKind = 'shape' | 'text' | 'container' | 'mermaid';
export const NODE_KINDS: readonly NodeKind[] = ['shape', 'text', 'container', 'mermaid'] as const;

export interface NodeStyle {
  /** token like 'surface' | palette key like 'blue' | '#rrggbb' */
  fill: string;
  stroke: string;
  strokeWidth: 1 | 2 | 4; // thin | medium | bold
  fontSize: 12 | 14 | 18 | 24; // S | M | L | XL
  textAlign: 'center'; // reserved; only center in MVP
}

// NOTE: there is deliberately NO corner-radius style property. Sharp vs rounded rectangles are
// two ShapeKinds ('rect' vs 'rounded') — one representation only, so Mermaid export ([x] vs (x))
// can never disagree with what the canvas shows. The context panel's sharp/round toggle swaps
// the ShapeKind between 'rect' and 'rounded' (shown only for those two kinds).

export interface ThalyxNode {
  id: NodeId;
  kind: NodeKind;
  shape?: ShapeKind; // kind === 'shape'
  /**
   * Top-left, absolute canvas coords — but for children of a container:
   * RELATIVE to the parent (React Flow parentId convention — keep it).
   */
  x: number;
  y: number;
  width: number;
  height: number;
  /** plain text; '\n' allowed */
  label: string;
  parentId?: NodeId; // containment (container nodes only as parents)
  locked?: boolean;
  hidden?: boolean; // e.g. mermaid '~~~' phantom targets
  style: NodeStyle;
  /** kind === 'mermaid' (island): */
  mermaidSource?: string;
  meta?: NodeMeta;
}

export interface NodeMeta {
  mermaid?: {
    /** mermaid node id, e.g. 'A' — round-trip anchor */
    id?: string;
    /** original mermaid vertex.type if it differs from our mapping (e.g. new '@{shape: …}' names) */
    shape?: string;
    /** mermaid class assignments */
    classes?: string[];
    /** raw 'fill:#f9f' strings from `style`/classDef we didn't map */
    styles?: string[];
    /** click href */
    link?: string;
    tooltip?: string;
    labelType?: 'text' | 'string' | 'markdown';
    /** containers only: subgraph-local `direction` (round-tripped) */
    dir?: 'TB' | 'BT' | 'LR' | 'RL';
  };
}

export type ArrowHead = 'none' | 'arrow' | 'circle' | 'cross';
export const ARROW_HEADS: readonly ArrowHead[] = ['none', 'arrow', 'circle', 'cross'] as const;

export interface EdgeStyle {
  line: 'solid' | 'dashed' | 'thick';
  stroke: string;
  /** rounded elbow corners */
  rounded: boolean;
}

export type EdgeKind = 'elbow' | 'straight' | 'curved';

export interface ThalyxEdge {
  id: EdgeId;
  source: NodeId;
  target: NodeId;
  /** 'auto' floats; cardinal anchors pin the originating handle. */
  sourceAnchor: 'auto' | 'n' | 's' | 'e' | 'w';
  targetAnchor: 'auto' | 'n' | 's' | 'e' | 'w';
  kind: EdgeKind;
  label?: string;
  /** 0..1 position of label along route (default 0.5) */
  labelT?: number;
  arrowStart: ArrowHead; // default 'none'
  arrowEnd: ArrowHead; // default 'arrow'
  hidden?: boolean; // mermaid '~~~'
  /** manual route override; cleared on endpoint move (D12) */
  waypoints?: { x: number; y: number }[];
  style: EdgeStyle;
  meta?: {
    mermaid?: {
      /** only when isUserDefinedId */
      id?: string;
      /** mermaid edge.length > 1 */
      minlen?: number;
      /** raw linkStyle strings */
      styles?: string[];
    };
  };
}

export type MermaidDirection = 'TB' | 'BT' | 'LR' | 'RL';
export const MERMAID_DIRECTIONS: readonly MermaidDirection[] = ['TB', 'BT', 'LR', 'RL'] as const;

export interface ThalyxDoc {
  type: 'thalyx';
  version: 1;
  /** 'thalyx@<appVersion>' */
  source: string;
  /** z-order = array order (first = back) */
  nodes: ThalyxNode[];
  edges: ThalyxEdge[];
  canvas: { background: 'default' | string; grid: boolean };
  meta: {
    mermaid?: {
      direction: MermaidDirection; // default 'TB'
      /** verbatim '---\n…\n---\n' block, re-emitted on export */
      frontmatter?: string;
      /** classDef name -> raw style strings */
      classDefs?: Record<string, string[]>;
      /** last imported/applied mermaid text (for the panel diff) */
      sourceText?: string;
    };
  };
}

/** Tool ids (session slice, §8.1). */
export type Tool = 'select' | 'shape' | 'arrow' | 'line' | 'text' | 'container' | 'hand';
