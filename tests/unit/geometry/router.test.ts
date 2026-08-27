import { describe, expect, it } from 'vitest';
import {
  STUB,
  collapseCollinear,
  pointAtT,
  polylineLength,
  route,
} from '../../../src/shared/geometry/elbow';
import { edgeEndpoints, facingSide } from '../../../src/shared/geometry/anchors';
import { newNode } from '../../../src/shared/model/create';
import type { Rect } from '../../../src/shared/geometry/anchors';

const S = (x: number, y: number, w = 100, h = 60): Rect => ({ x, y, width: w, height: h });
const sidePoint = (rect: Rect, side: 'n' | 's' | 'e' | 'w') => {
  if (side === 'n') return { x: rect.x + rect.width / 2, y: rect.y };
  if (side === 's') return { x: rect.x + rect.width / 2, y: rect.y + rect.height };
  if (side === 'e') return { x: rect.x + rect.width, y: rect.y + rect.height / 2 };
  return { x: rect.x, y: rect.y + rect.height / 2 };
};

describe('elbow router side-case matrix (§11.3)', () => {
  it('opposite horizontal sides (e→w): Z through the midline', () => {
    const src = S(0, 0);
    const tgt = S(400, 200);
    const pts = route({ x: 100, y: 30 }, { x: 400, y: 230 }, src, tgt, 'e', 'w');
    // start → (rail, sy) → (rail, ty) → end
    expect(pts.length).toBe(4);
    const railX = pts[1]!.x;
    expect(railX).toBe(pts[2]!.x);
    // the vertical rail clears both shapes by a full stub
    expect(railX).toBeGreaterThanOrEqual(100 + STUB);
    expect(railX).toBeLessThanOrEqual(400 - STUB);
    expect(pts[0]!.y).toBe(30);
    expect(pts[3]!.y).toBe(230);
    // axis-aligned throughout
    for (let i = 1; i < pts.length; i++) {
      const a = pts[i - 1]!;
      const b = pts[i]!;
      expect(a.x === b.x || a.y === b.y).toBe(true);
    }
  });

  it('opposite vertical sides (s→n): Z through the horizontal midline', () => {
    const src = S(0, 0);
    const tgt = S(200, 400);
    const pts = route({ x: 50, y: 60 }, { x: 250, y: 400 }, src, tgt, 's', 'n');
    expect(pts.length).toBe(4);
    expect(pts[1]!.y).toBe(pts[2]!.y); // shared rail y
  });

  it('orthogonal sides (e→n): uses both outward stubs', () => {
    const src = S(0, 0);
    const tgt = S(300, -200);
    const pts = route({ x: 100, y: 30 }, { x: 350, y: -200 }, src, tgt, 'e', 'n');
    expect(pts.length).toBe(5);
    expect(pts[1]).toEqual({ x: 116, y: 30 });
    expect(pts.at(-2)).toEqual({ x: 350, y: -216 });
  });

  it('orthogonal sides (s→e): uses both outward stubs', () => {
    const src = S(0, 0);
    const tgt = S(300, 200);
    const pts = route({ x: 50, y: 60 }, { x: 400, y: 230 }, src, tgt, 's', 'e');
    expect(pts.length).toBe(5);
    expect(pts[1]).toEqual({ x: 50, y: 76 });
    expect(pts.at(-2)).toEqual({ x: 416, y: 230 });
  });

  it('same side (e→e): U via a rail beyond the outermost bound', () => {
    const src = S(0, 0);
    const tgt = S(200, 200);
    const pts = route({ x: 100, y: 30 }, { x: 300, y: 230 }, src, tgt, 'e', 'e');
    expect(pts.length).toBe(4);
    const railX = pts[1]!.x;
    expect(railX).toBe(pts[2]!.x);
    expect(railX).toBeGreaterThanOrEqual(300 + STUB);
  });

  it('same side (w→w): U rail left of the outermost bound', () => {
    const src = S(100, 0);
    const tgt = S(300, 200);
    const pts = route({ x: 100, y: 30 }, { x: 300, y: 230 }, src, tgt, 'w', 'w');
    const railX = pts[1]!.x;
    expect(railX).toBeLessThanOrEqual(100 - STUB);
  });

  it('same side (n→n): U rail above the outermost bound', () => {
    const src = S(0, 100);
    const tgt = S(200, 300);
    const pts = route({ x: 50, y: 100 }, { x: 250, y: 300 }, src, tgt, 'n', 'n');
    expect(pts[1]!.y).toBeLessThanOrEqual(100 - STUB);
  });

  it('all outputs stay axis-aligned and finite', () => {
    const rects: Array<[Rect, Rect, 'n' | 's' | 'e' | 'w', 'n' | 's' | 'e' | 'w']> = [
      [S(0, 0), S(400, 10), 'e', 'w'],
      [S(0, 0), S(400, 10), 'e', 'n'],
      [S(0, 0), S(400, 10), 'e', 's'],
      [S(0, 0), S(10, 400), 's', 'n'],
      [S(0, 0), S(10, 400), 's', 'e'],
      [S(0, 0), S(10, 400), 's', 'w'],
      [S(0, 0), S(-200, 10), 'w', 'e'],
      [S(0, 0), S(50, 50), 'e', 'e'],
      [S(0, 0), S(50, 50), 'n', 'n'],
      [S(0, 0), S(50, 50), 's', 's'],
      [S(0, 0), S(50, 50), 'w', 'w'],
      [S(0, 0), S(0, 0), 'n', 's'], // overlapping rects — degenerate but finite
    ];
    for (const [src, tgt, ss, ts] of rects) {
      const pts = route(sidePoint(src, ss), sidePoint(tgt, ts), src, tgt, ss, ts);
      expect(pts.length).toBeGreaterThanOrEqual(2);
      for (const p of pts) {
        expect(Number.isFinite(p.x)).toBe(true);
        expect(Number.isFinite(p.y)).toBe(true);
      }
      for (let i = 1; i < pts.length; i++) {
        const a = pts[i - 1]!;
        const b = pts[i]!;
        expect(a.x === b.x || a.y === b.y).toBe(true);
      }
    }
  });

  it('collapseCollinear merges straight runs', () => {
    expect(
      collapseCollinear([
        { x: 0, y: 0 },
        { x: 10, y: 0 },
        { x: 20, y: 0 },
        { x: 20, y: 5 },
      ]),
    ).toEqual([
      { x: 0, y: 0 },
      { x: 20, y: 0 },
      { x: 20, y: 5 },
    ]);
  });

  it('pointAtT walks by arc length', () => {
    const pts = [
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 10 },
    ];
    expect(pointAtT(pts, 0)).toEqual({ x: 0, y: 0 });
    expect(pointAtT(pts, 0.25)).toEqual({ x: 5, y: 0 });
    expect(pointAtT(pts, 0.5)).toEqual({ x: 10, y: 0 });
    expect(pointAtT(pts, 0.75)).toEqual({ x: 10, y: 5 });
    expect(pointAtT(pts, 1)).toEqual({ x: 10, y: 10 });
    expect(polylineLength(pts)).toBe(20);
  });
});

describe('floating anchors (§11.2)', () => {
  it('auto endpoints sit on the center-to-center line at the shape boundary', () => {
    const a = newNode({ id: 'a', shape: 'rect', x: 0, y: 0, width: 100, height: 60 });
    const b = newNode({ id: 'b', shape: 'rect', x: 400, y: 220, width: 100, height: 60 });
    const { source, target, sourceSide, targetSide } = edgeEndpoints(
      a,
      { x: 0, y: 0 },
      b,
      { x: 400, y: 220 },
      'auto',
      'auto',
    );
    // centers (50,30) → (450,250): dx=400 dominates dy=220 → east/west
    expect(sourceSide).toBe('e');
    expect(targetSide).toBe('w');
    // endpoints on the facing edges, on the center line
    expect(source.x).toBeCloseTo(100, 5);
    expect(source.y).toBeCloseTo(30 + 220 * (50 / 400), 5);
    expect(target.x).toBeCloseTo(400, 5);
    expect(target.y).toBeCloseTo(30 + 220 * (350 / 400), 5);
  });

  it('ellipse boundary intersections are radial', () => {
    const a = newNode({ id: 'a', shape: 'ellipse', x: 0, y: 0, width: 100, height: 100 });
    const b = newNode({ id: 'b', shape: 'ellipse', x: 300, y: 0, width: 100, height: 100 });
    const { source, target } = edgeEndpoints(
      a,
      { x: 0, y: 0 },
      b,
      { x: 300, y: 0 },
      'auto',
      'auto',
    );
    expect(source.x).toBeCloseTo(100, 5);
    expect(source.y).toBeCloseTo(50, 5);
    expect(target.x).toBeCloseTo(300, 5);
    expect(target.y).toBeCloseTo(50, 5);
  });

  it('pinned sides use side midpoints', () => {
    const a = newNode({ id: 'a', shape: 'rect', x: 0, y: 0, width: 100, height: 60 });
    const b = newNode({ id: 'b', shape: 'rect', x: 400, y: 0, width: 100, height: 60 });
    const { source, target } = edgeEndpoints(a, { x: 0, y: 0 }, b, { x: 400, y: 0 }, 'n', 'e');
    expect(source).toEqual({ x: 50, y: 0 });
    expect(target).toEqual({ x: 500, y: 30 });
  });

  it('facingSide picks the dominant axis', () => {
    const r = S(0, 0);
    expect(facingSide('auto', r, { x: 500, y: 10 })).toBe('e');
    expect(facingSide('auto', r, { x: -500, y: 10 })).toBe('w');
    expect(facingSide('auto', r, { x: 10, y: 500 })).toBe('s');
    expect(facingSide('auto', r, { x: 10, y: -500 })).toBe('n');
    expect(facingSide('w', r, { x: 500, y: 10 })).toBe('w'); // pinned wins
  });
});
