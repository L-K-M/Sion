/**
 * Smart-guide engine (PLAN.md §11.4). Pure.
 *
 * computeSnap(draggedBounds, staticBounds, zoom, opts) → { dx, dy, guides }.
 *
 * - Candidates: edges + centers of static nodes (x: L/C/R, y: T/C/B), capped
 *   at the nearest 40 by distance for perf.
 * - Threshold: 6/zoom canvas px (6 screen px); nearest candidate wins per axis.
 * - Equal spacing: aligned neighbor pairs with gap g; a dragged gap within
 *   threshold of g snaps and emits two gap chips (labeled with the px value).
 * - Grid: 8 px lattice when enabled; smart guides win over grid.
 * - `disableAll` (Mod held during drag) turns everything off.
 */

export interface GuideLine {
  kind: 'align' | 'gap';
  axis: 'x' | 'y';
  position: number;
  start: number;
  end: number;
  label?: string;
}

export interface Bounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface SnapOptions {
  grid: boolean;
  disableAll?: boolean;
  zoom: number;
}

export interface SnapResult {
  dx: number;
  dy: number;
  guides: GuideLine[];
}

export const SNAP_THRESHOLD_PX = 6;
export const GRID_SIZE = 8;
const MAX_CANDIDATES = 40;

interface Candidate {
  value: number;
  bounds: Bounds;
}

function edgeCandidates(bounds: Bounds[]): { x: Candidate[]; y: Candidate[] } {
  const x: Candidate[] = [];
  const y: Candidate[] = [];
  for (const b of bounds) {
    const cx = b.x + b.width / 2;
    const cy = b.y + b.height / 2;
    for (const value of [b.x, cx, b.x + b.width]) x.push({ value, bounds: b });
    for (const value of [b.y, cy, b.y + b.height]) y.push({ value, bounds: b });
  }
  return { x, y };
}

function nearestAlign(
  draggedValues: number[],
  candidates: Candidate[],
  threshold: number,
): { delta: number; guide: GuideLine } | null {
  let best: { delta: number; guide: GuideLine } | null = null;
  for (const dv of draggedValues) {
    for (const c of candidates) {
      const delta = c.value - dv;
      if (Math.abs(delta) > threshold) continue;
      if (!best || Math.abs(delta) < Math.abs(best.delta)) {
        best = {
          delta,
          guide: { kind: 'align', axis: 'x', position: c.value, start: 0, end: 0 },
        };
      }
    }
  }
  return best;
}

/** Equal-spacing: find pairs of static bounds aligned on `axis` and check the dragged gap. */
function equalSpacing(
  dragged: Bounds,
  statics: Bounds[],
  axis: 'x' | 'y',
  threshold: number,
): { delta: number; guides: GuideLine[] } | null {
  const other = axis === 'x' ? 'y' : 'x';
  const dStart = axis === 'x' ? dragged.x : dragged.y;
  const dEnd = dStart + (axis === 'x' ? dragged.width : dragged.height);

  // Static pairs: [a][gap g][b] aligned on the OTHER axis (their spans overlap).
  const pairs: Array<{ a: Bounds; b: Bounds; gap: number }> = [];
  for (let i = 0; i < statics.length; i++) {
    for (let j = 0; j < statics.length; j++) {
      if (i === j) continue;
      const a = statics[i]!;
      const b = statics[j]!;
      const aStart = axis === 'x' ? a.x : a.y;
      const aEnd = aStart + (axis === 'x' ? a.width : a.height);
      const bStart = axis === 'x' ? b.x : b.y;
      // b to the right/below a, with the aligned-span overlap
      const aOtherStart = other === 'x' ? a.x : a.y;
      const aOtherEnd = aOtherStart + (other === 'x' ? a.width : a.height);
      const bOtherStart = other === 'x' ? b.x : b.y;
      const bOtherEnd = bOtherStart + (other === 'x' ? b.width : b.height);
      const overlap = Math.min(aOtherEnd, bOtherEnd) - Math.max(aOtherStart, bOtherStart);
      if (overlap <= 0) continue;
      if (bStart >= aEnd) pairs.push({ a, b, gap: bStart - aEnd });
    }
  }

  for (const { a, b, gap } of pairs) {
    // dragged placed after b (gap between b and dragged ≈ g)
    const gapAfter = dStart - (axis === 'x' ? b.x + b.width : b.y + b.height);
    if (Math.abs(gapAfter - gap) <= threshold) {
      const delta = gap - gapAfter;
      return {
        delta,
        guides: [
          gapGuide(a, b, axis, gap),
          gapGuide(b, draggedShifted(dragged, axis, delta), axis, gap),
        ],
      };
    }
    // dragged placed before a (gap between dragged and a ≈ g)
    const gapBefore = (axis === 'x' ? a.x : a.y) - dEnd;
    if (Math.abs(gapBefore - gap) <= threshold) {
      const delta = gap - gapBefore;
      return {
        delta,
        guides: [
          gapGuide(b, a, axis, gap),
          gapGuide(draggedShifted(dragged, axis, delta), a, axis, gap),
        ],
      };
    }
  }
  return null;
}

function draggedShifted(dragged: Bounds, axis: 'x' | 'y', delta: number): Bounds {
  return axis === 'x' ? { ...dragged, x: dragged.x + delta } : { ...dragged, y: dragged.y + delta };
}

function gapGuide(a: Bounds, b: Bounds, axis: 'x' | 'y', gap?: number): GuideLine {
  const aStart = axis === 'x' ? a.x : a.y;
  const aEnd = aStart + (axis === 'x' ? a.width : a.height);
  const bStart = axis === 'x' ? b.x : b.y;
  const mid = (aEnd + bStart) / 2;
  const aOtherStart = axis === 'x' ? a.y : a.x;
  const aOtherEnd = aOtherStart + (axis === 'x' ? a.height : a.width);
  const bOtherStart = axis === 'x' ? b.y : b.x;
  const bOtherEnd = bOtherStart + (axis === 'x' ? b.height : b.width);
  return {
    kind: 'gap',
    axis,
    position: mid,
    start: Math.min(aOtherStart, bOtherStart),
    end: Math.max(aOtherEnd, bOtherEnd),
    ...(gap !== undefined ? { label: String(Math.round(gap)) } : {}),
  };
}

function capCandidates(candidates: Candidate[], draggedValues: number[]): Candidate[] {
  // Keep the MAX_CANDIDATES nearest to the dragged values by distance.
  const scored = candidates.map((c) => ({
    c,
    dist: Math.min(...draggedValues.map((v) => Math.abs(c.value - v))),
  }));
  scored.sort((a, b) => a.dist - b.dist);
  return scored.slice(0, MAX_CANDIDATES).map((s) => s.c);
}

export function computeSnap(dragged: Bounds, statics: Bounds[], options: SnapOptions): SnapResult {
  const result: SnapResult = { dx: 0, dy: 0, guides: [] };
  if (options.disableAll || statics.length === 0) return applyGridOnly(dragged, options, result);

  const threshold = SNAP_THRESHOLD_PX / options.zoom;
  const { x, y } = edgeCandidates(statics);
  const draggedX = [dragged.x, dragged.x + dragged.width / 2, dragged.x + dragged.width];
  const draggedY = [dragged.y, dragged.y + dragged.height / 2, dragged.y + dragged.height];

  const bestX = nearestAlign(draggedX, capCandidates(x, draggedX), threshold);
  const bestY = nearestAlign(draggedY, capCandidates(y, draggedY), threshold);

  if (bestX) {
    result.dx = bestX.delta;
    const staticB = x.find((c) => c.value === bestX.guide.position)?.bounds;
    if (staticB) {
      result.guides.push({
        kind: 'align',
        axis: 'x',
        position: bestX.guide.position,
        start: Math.min(staticB.y, dragged.y),
        end: Math.max(staticB.y + staticB.height, dragged.y + dragged.height),
      });
    }
  }
  if (bestY) {
    result.dy = bestY.delta;
    const staticB = y.find((c) => c.value === bestY.guide.position)?.bounds;
    if (staticB) {
      result.guides.push({
        kind: 'align',
        axis: 'y',
        position: bestY.guide.position,
        start: Math.min(staticB.x, dragged.x),
        end: Math.max(staticB.x + staticB.width, dragged.x + dragged.width),
      });
    }
  }

  // Equal spacing (only when not already align-snapped on that axis)
  if (!bestX) {
    const eq = equalSpacing(dragged, statics, 'x', threshold);
    if (eq) {
      result.dx = eq.delta;
      result.guides.push(...eq.guides);
    }
  }
  if (!bestY) {
    const eq = equalSpacing(dragged, statics, 'y', threshold);
    if (eq) {
      result.dy = eq.delta;
      result.guides.push(...eq.guides);
    }
  }

  // Grid fills any axis still free (smart guides win)
  if (options.grid) {
    if (result.dx === 0) result.dx = snapToLattice(dragged.x, dragged.width);
    if (result.dy === 0) result.dy = snapToLattice(dragged.y, dragged.height);
  }
  return result;
}

function snapToLattice(start: number, size: number): number {
  // snap the CENTER to the lattice (more predictable than the edge)
  const center = start + size / 2;
  const target = Math.round(center / GRID_SIZE) * GRID_SIZE;
  return target - center;
}

function applyGridOnly(dragged: Bounds, options: SnapOptions, result: SnapResult): SnapResult {
  if (!options.grid || options.disableAll) return result;
  result.dx = snapToLattice(dragged.x, dragged.width);
  result.dy = snapToLattice(dragged.y, dragged.height);
  return result;
}
