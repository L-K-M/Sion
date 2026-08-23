/**
 * Zod schemas for the document model (PLAN.md §7, bounds per §14.6).
 *
 * The schema is the final assertion inside `restoreDocument` — restore coerces
 * first, so a schema failure here indicates a restore bug, not bad user data.
 */
import { z } from 'zod';
import { ARROW_HEADS, MERMAID_DIRECTIONS, NODE_KINDS, SHAPE_KINDS } from './types';

/** Labels are plain text and bounded (§14.6: labels ≤ 4 kB). */
export const LABEL_MAX = 4096;
/** §14.6: ≤ 20 k nodes. */
export const NODES_MAX = 20_000;
/** Edge ceiling proportional to nodes. */
export const EDGES_MAX = 60_000;
/** Geometry bounds: finite numbers within a sane canvas range. */
export const COORD_MIN = -1_000_000;
export const COORD_MAX = 1_000_000;
export const SIZE_MIN = 8;
export const SIZE_MAX = 1_000_000;

export const nodeIdSchema = z.string().min(1).max(64);
export const edgeIdSchema = z.string().min(1).max(64);
export const colorTokenSchema = z.string().min(1).max(64);

export const nodeStyleSchema = z.object({
  fill: colorTokenSchema,
  stroke: colorTokenSchema,
  strokeWidth: z.union([z.literal(1), z.literal(2), z.literal(4)]),
  fontSize: z.union([z.literal(12), z.literal(14), z.literal(18), z.literal(24)]),
  textAlign: z.literal('center'),
});

export const anchorSchema = z.enum(['auto', 'n', 's', 'e', 'w']);

export const nodeMetaSchema = z.object({
  mermaid: z
    .object({
      id: z.string().max(512).optional(),
      shape: z.string().max(128).optional(),
      classes: z.array(z.string().max(512)).max(64).optional(),
      styles: z.array(z.string().max(2048)).max(64).optional(),
      link: z.string().max(2048).optional(),
      tooltip: z.string().max(2048).optional(),
      labelType: z.enum(['text', 'string', 'markdown']).optional(),
      dir: z.enum(['TB', 'BT', 'LR', 'RL']).optional(),
    })
    .optional(),
});

export const thalyxNodeSchema = z.object({
  id: nodeIdSchema,
  kind: z.enum(NODE_KINDS as unknown as [string, ...string[]]),
  shape: z.enum(SHAPE_KINDS as unknown as [string, ...string[]]).optional(),
  x: z.number().finite().min(COORD_MIN).max(COORD_MAX),
  y: z.number().finite().min(COORD_MIN).max(COORD_MAX),
  width: z.number().finite().min(SIZE_MIN).max(SIZE_MAX),
  height: z.number().finite().min(SIZE_MIN).max(SIZE_MAX),
  label: z.string().max(LABEL_MAX),
  parentId: nodeIdSchema.optional(),
  locked: z.boolean().optional(),
  hidden: z.boolean().optional(),
  style: nodeStyleSchema,
  mermaidSource: z.string().max(1_000_000).optional(),
  meta: nodeMetaSchema.optional(),
});

export const edgeStyleSchema = z.object({
  line: z.enum(['solid', 'dashed', 'thick']),
  stroke: colorTokenSchema,
  rounded: z.boolean(),
});

export const thalyxEdgeSchema = z.object({
  id: edgeIdSchema,
  source: nodeIdSchema,
  target: nodeIdSchema,
  sourceAnchor: anchorSchema,
  targetAnchor: anchorSchema,
  kind: z.enum(['elbow', 'straight', 'curved']),
  label: z.string().max(LABEL_MAX).optional(),
  labelT: z.number().finite().min(0).max(1).optional(),
  arrowStart: z.enum(ARROW_HEADS as unknown as [string, ...string[]]),
  arrowEnd: z.enum(ARROW_HEADS as unknown as [string, ...string[]]),
  hidden: z.boolean().optional(),
  waypoints: z
    .array(
      z.object({
        x: z.number().finite().min(COORD_MIN).max(COORD_MAX),
        y: z.number().finite().min(COORD_MIN).max(COORD_MAX),
      }),
    )
    .max(64)
    .optional(),
  style: edgeStyleSchema,
  meta: z
    .object({
      mermaid: z
        .object({
          id: z.string().max(512).optional(),
          minlen: z.number().int().min(1).max(64).optional(),
          styles: z.array(z.string().max(2048)).max(64).optional(),
        })
        .optional(),
    })
    .optional(),
});

export const thalyxDocSchema = z.object({
  type: z.literal('thalyx'),
  version: z.literal(1),
  source: z.string().max(128),
  nodes: z.array(thalyxNodeSchema).max(NODES_MAX),
  edges: z.array(thalyxEdgeSchema).max(EDGES_MAX),
  canvas: z.object({
    background: z.string().max(128),
    grid: z.boolean(),
  }),
  meta: z.object({
    mermaid: z
      .object({
        direction: z.enum(MERMAID_DIRECTIONS as unknown as [string, ...string[]]),
        frontmatter: z.string().max(65_536).optional(),
        classDefs: z.record(z.string().max(512), z.array(z.string().max(2048)).max(64)).optional(),
        sourceText: z.string().max(1_000_000).optional(),
      })
      .optional(),
  }),
});

/** Parse, narrowing the zod inference to the authoritative types. */
export function parseDocSchema(doc: unknown): asserts doc is import('./types').ThalyxDoc {
  thalyxDocSchema.parse(doc);
}
