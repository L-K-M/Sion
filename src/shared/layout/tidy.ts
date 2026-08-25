/**
 * Tidy Up (PLAN.md §11.5): unconnected-shape selection → infer row/column/grid
 * from the current arrangement, distribute evenly with 24 px gaps, align to
 * the dominant axis. Pure.
 */
import type { ThalyxDoc, ThalyxNode } from '../model/types';
import { absolutePosition } from '../model/queries';

export const TIDY_GAP = 24;

export interface TidyResult {
  positions: Map<string, { x: number; y: number }>;
}

/**
 * Infer the arrangement: cluster by y (rows) with a tolerance of half the max
 * height, then lay each row out left-to-right with even gaps; align rows on
 * the dominant (first) row's top. If a single row → treat as one row; if
 * every node is its own row (a column) → distribute vertically.
 */
export function tidyUp(doc: ThalyxDoc, nodes: ThalyxNode[]): TidyResult {
  const positions = new Map<string, { x: number; y: number }>();
  if (nodes.length < 2) return { positions };

  const items = nodes.map((n) => ({ n, abs: absolutePosition(doc, n) }));
  const maxH = Math.max(...items.map((i) => i.n.height));
  const tol = maxH / 2;

  // sort by y then x; cluster rows by y within tolerance
  items.sort((a, b) => a.abs.y - b.abs.y || a.abs.x - b.abs.x);
  const rows: Array<Array<{ n: ThalyxNode; abs: { x: number; y: number } }>> = [];
  for (const item of items) {
    const row = rows[rows.length - 1];
    if (row && Math.abs(item.abs.y - row[0]!.abs.y) <= tol) {
      row.push(item);
    } else {
      rows.push([item]);
    }
  }

  // A single cluster: decide row vs column by the bbox aspect ratio
  if (rows.length === 1 && rows[0]!.length >= 2) {
    const row = rows[0]!;
    const widthSum = row.reduce((acc, i) => acc + i.n.width, 0);
    const span = row[row.length - 1]!.abs.x + row[row.length - 1]!.n.width - row[0]!.abs.x;
    // already wider than tall → row; else column
    if (
      span >= maxH ||
      widthSum / Math.max(1, row.reduce((a, i) => a + i.n.height, 0) / row.length) > 1
    ) {
      layoutRow(row, positions);
      return { positions };
    }
    layoutColumn(row, positions);
    return { positions };
  }

  // One node per row → a column
  if (rows.every((r) => r.length === 1)) {
    layoutColumn(rows.flat(), positions);
    return { positions };
  }

  // Grid: distribute each row, rows stacked top to bottom
  let y = Math.min(...items.map((i) => i.abs.y));
  const rowHeight = Math.max(...items.map((i) => i.n.height));
  for (const row of rows) {
    row.sort((a, b) => a.abs.x - b.abs.x);
    let x = Math.min(...items.map((i) => i.abs.x));
    for (const item of row) {
      positions.set(item.n.id, { x, y });
      x += item.n.width + TIDY_GAP;
    }
    y += rowHeight + TIDY_GAP;
  }
  return { positions };
}

function layoutRow(
  row: Array<{ n: ThalyxNode; abs: { x: number; y: number } }>,
  out: Map<string, { x: number; y: number }>,
): void {
  row.sort((a, b) => a.abs.x - b.abs.x);
  let x = Math.min(...row.map((i) => i.abs.x));
  const y = row[0]!.abs.y;
  for (const item of row) {
    out.set(item.n.id, { x, y });
    x += item.n.width + TIDY_GAP;
  }
}

function layoutColumn(
  col: Array<{ n: ThalyxNode; abs: { x: number; y: number } }>,
  out: Map<string, { x: number; y: number }>,
): void {
  col.sort((a, b) => a.abs.y - b.abs.y);
  let y = Math.min(...col.map((i) => i.abs.y));
  const x = col[0]!.abs.x;
  for (const item of col) {
    out.set(item.n.id, { x, y });
    y += item.n.height + TIDY_GAP;
  }
}
