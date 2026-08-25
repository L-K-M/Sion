/**
 * Factories: newDoc/newNode/newEdge with defaults (PLAN.md §6, §10.4).
 *
 * Defaults (§10.4): surface fill, ink stroke, medium width, font M.
 */
import { nanoid } from 'nanoid';
import type {
  EdgeKind,
  NodeKind,
  NodeStyle,
  ShapeKind,
  ThalyxDoc,
  ThalyxEdge,
  ThalyxNode,
} from './types';
import pkg from '../../../package.json' with { type: 'json' };

export function appVersion(): string {
  return pkg.version;
}

export function newId(): string {
  return nanoid(12);
}

export const DEFAULT_NODE_STYLE: NodeStyle = {
  fill: 'surface',
  stroke: 'ink',
  strokeWidth: 2,
  fontSize: 14,
  textAlign: 'center',
};

/** Default factory size — enough for a short label at font M. */
export const DEFAULT_NODE_WIDTH = 160;
export const DEFAULT_NODE_HEIGHT = 64;

/** §10.4: the default pendingShape is 'rounded' (soft-cornered reads friendlier). */
export const DEFAULT_SHAPE: ShapeKind = 'rounded';

export interface NewNodeInit {
  id?: string;
  kind?: NodeKind;
  shape?: ShapeKind;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  label?: string;
  parentId?: string;
  style?: Partial<NodeStyle>;
  locked?: boolean;
  hidden?: boolean;
  mermaidSource?: string;
  meta?: ThalyxNode['meta'];
}

export function newNode(init: NewNodeInit = {}): ThalyxNode {
  const kind: NodeKind = init.kind ?? 'shape';
  const node: ThalyxNode = {
    id: init.id ?? newId(),
    kind,
    x: init.x ?? 0,
    y: init.y ?? 0,
    width: init.width ?? DEFAULT_NODE_WIDTH,
    height: init.height ?? DEFAULT_NODE_HEIGHT,
    label: init.label ?? '',
    style: { ...DEFAULT_NODE_STYLE, ...init.style },
    ...(init.parentId !== undefined ? { parentId: init.parentId } : {}),
    ...(init.locked !== undefined ? { locked: init.locked } : {}),
    ...(init.hidden !== undefined ? { hidden: init.hidden } : {}),
    ...(init.mermaidSource !== undefined ? { mermaidSource: init.mermaidSource } : {}),
    ...(init.meta !== undefined ? { meta: JSON.parse(JSON.stringify(init.meta)) } : {}),
  };
  if (kind === 'shape') {
    node.shape = init.shape ?? DEFAULT_SHAPE;
  } else if (kind !== 'container' && init.shape) {
    // text/mermaid nodes may still carry a shape (e.g. future use); containers never do.
    node.shape = init.shape;
  }
  return node;
}

export interface NewEdgeInit {
  id?: string;
  source: string;
  target: string;
  kind?: EdgeKind;
  label?: string;
  labelT?: number;
  arrowStart?: ThalyxEdge['arrowStart'];
  arrowEnd?: ThalyxEdge['arrowEnd'];
  sourceAnchor?: ThalyxEdge['sourceAnchor'];
  targetAnchor?: ThalyxEdge['targetAnchor'];
  hidden?: boolean;
  waypoints?: { x: number; y: number }[];
  style?: Partial<ThalyxEdge['style']>;
  meta?: ThalyxEdge['meta'];
}

export function newEdge(init: NewEdgeInit): ThalyxEdge {
  return {
    id: init.id ?? newId(),
    source: init.source,
    target: init.target,
    sourceAnchor: init.sourceAnchor ?? 'auto',
    targetAnchor: init.targetAnchor ?? 'auto',
    kind: init.kind ?? 'elbow',
    ...(init.label !== undefined ? { label: init.label } : {}),
    ...(init.labelT !== undefined ? { labelT: init.labelT } : {}),
    arrowStart: init.arrowStart ?? 'none',
    arrowEnd: init.arrowEnd ?? 'arrow',
    ...(init.hidden !== undefined ? { hidden: init.hidden } : {}),
    ...(init.waypoints !== undefined ? { waypoints: init.waypoints } : {}),
    style: { line: 'solid', stroke: 'ink', rounded: true, ...init.style },
    ...(init.meta !== undefined ? { meta: JSON.parse(JSON.stringify(init.meta)) } : {}),
  };
}

export function newDoc(): ThalyxDoc {
  return {
    type: 'thalyx',
    version: 1,
    source: `thalyx@${appVersion()}`,
    nodes: [],
    edges: [],
    canvas: { background: 'default', grid: false },
    meta: { mermaid: { direction: 'TB' } },
  };
}
