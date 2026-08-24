import { describe, expect, it } from 'vitest';
import {
  GRID_SIZE,
  SNAP_THRESHOLD_PX,
  computeSnap,
  type Bounds,
} from '../../../src/shared/snap/snap';

const B = (x: number, y: number, w = 100, h = 60): Bounds => ({ x, y, width: w, height: h });

describe('smart-guide engine (§11.4)', () => {
  it('snaps dragged left edge to a static right edge within threshold', () => {
    const dragged = B(160, 0);
    const res = computeSnap(dragged, [B(0, 0)], { grid: false, zoom: 1 });
    // dragged.x=160 vs static right edge 100: distance 60 > 6 → no snap
    expect(res.dx).toBe(0);
    const close = computeSnap(B(104, 0), [B(0, 0)], { grid: false, zoom: 1 });
    expect(close.dx).toBe(-4); // snap to 100
    expect(
      close.guides.some((g) => g.kind === 'align' && g.axis === 'x' && g.position === 100),
    ).toBe(true);
  });

  it('edge-to-center snap is a valid alignment; far candidates do not snap', () => {
    const res = computeSnap(B(300, 0), [B(0, 0)], { grid: false, zoom: 1 });
    expect(res.dx).toBe(0);
    // dragged left edge 53 vs static center 50 → -3 snaps
    const near = computeSnap(B(53, 0), [B(0, 0)], { grid: false, zoom: 1 });
    expect(near.dx).toBe(-3);
    const res2 = computeSnap(B(2, 0), [B(0, 0)], { grid: false, zoom: 1 });
    expect(res2.dx).toBe(-2); // left-to-left
    const xGuide = res2.guides.find((g) => g.axis === 'x')!;
    expect(xGuide.position).toBe(0);
  });

  it('vertical align: centers match', () => {
    const res = computeSnap(B(200, 3), [B(0, 0)], { grid: false, zoom: 1 });
    // dragged center y=33 vs static center y=30 → dy=-3 within threshold
    expect(res.dy).toBe(-3);
    expect(res.dx).toBe(0);
  });

  it('exactly-at-threshold deltas still snap (inclusive edge)', () => {
    const res = computeSnap(B(106, 0), [B(0, 0)], { grid: false, zoom: 1 });
    // distance exactly 6 → snaps
    expect(res.dx).toBe(-6);
    const beyond = computeSnap(B(107, 0), [B(0, 0)], { grid: false, zoom: 1 });
    // distance 7 → no snap
    expect(beyond.dx).toBe(0);
  });

  it('threshold scales with zoom', () => {
    // zoom 0.5 → threshold 12 canvas px
    const res = computeSnap(B(110, 0), [B(0, 0)], { grid: false, zoom: 0.5 });
    expect(res.dx).toBe(-10);
    // zoom 2 → threshold 3 canvas px: distance 10 no longer snaps
    const res2 = computeSnap(B(110, 0), [B(0, 0)], { grid: false, zoom: 2 });
    expect(res2.dx).toBe(0);
  });

  it('equal spacing snaps to the established gap and emits gap chips', () => {
    // two statics 24 px apart horizontally; dragged approaching from the right
    const statics = [B(0, 0), B(124, 0)]; // gap between them = 24
    const dragged = B(224 + 30, 0); // gap after second static = 30 → snap to 24
    const res = computeSnap(dragged, statics, { grid: false, zoom: 1 });
    expect(res.dx).toBe(-6);
    const gaps = res.guides.filter((g) => g.kind === 'gap');
    expect(gaps.length).toBeGreaterThanOrEqual(2);
    expect(gaps.every((g) => g.label === '24')).toBe(true);
  });

  it('grid snapping: centers snap to the 8px lattice when no smart guide matches', () => {
    // dragged center x = 5 → snaps to 8 → dx = 3
    const res = computeSnap(B(-45, -45), [], { grid: true, zoom: 1 });
    expect(res.dx).toBe(3);
    expect(res.dy).toBe(-1); // center y = -15 → lattice -16
  });

  it('smart guides win over grid', () => {
    // smart dx available (-4 to edge 100); grid would move +? — smart must win
    const res = computeSnap(B(104, 0), [B(0, 0)], { grid: true, zoom: 1 });
    expect(res.dx).toBe(-4);
  });

  it('disableAll (Mod held) turns everything off', () => {
    const res = computeSnap(B(104, 0), [B(0, 0)], { grid: true, zoom: 1, disableAll: true });
    expect(res.dx).toBe(0);
    expect(res.dy).toBe(0);
    expect(res.guides).toEqual([]);
  });

  it('threshold constant and grid size per the §10.1 deltas', () => {
    expect(SNAP_THRESHOLD_PX).toBe(6);
    expect(GRID_SIZE).toBe(8);
  });

  it('guide extents span both aligned bounds', () => {
    const res = computeSnap(B(104, 20), [B(0, 0, 100, 60)], { grid: false, zoom: 1 });
    const g = res.guides.find((x) => x.axis === 'x')!;
    expect(g.start).toBe(0);
    expect(g.end).toBe(80); // max(60, 20+60)
  });
});
