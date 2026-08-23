import { describe, expect, it } from 'vitest';
import { shapeBoundaryIntersection, shapePath } from '../../../src/shared/geometry/shapes';
import { SHAPE_KINDS } from '../../../src/shared/model/types';

describe('shapePath (§7.3)', () => {
  it('produces non-empty path data for every ShapeKind', () => {
    for (const kind of SHAPE_KINDS) {
      const d = shapePath(kind, 160, 64);
      expect(d.length).toBeGreaterThan(10);
      expect(d.startsWith('M')).toBe(true);
    }
  });

  it('rect path covers the box', () => {
    expect(shapePath('rect', 100, 50)).toBe('M 0 0 H 100 V 50 H 0 Z');
  });

  it('rounded path uses arcs and stays within bounds', () => {
    const d = shapePath('rounded', 100, 50);
    expect(d).toContain('A');
    const nums = d.match(/-?\d+(?:\.\d+)?/g)!.map(Number);
    expect(Math.max(...nums)).toBeLessThanOrEqual(100 + 1e-9);
  });

  it('diamond hits the four extreme points', () => {
    const d = shapePath('diamond', 100, 50);
    expect(d).toContain('M 50 0');
    expect(d).toContain('L 100 25');
    expect(d).toContain('L 50 50');
    expect(d).toContain('L 0 25');
  });

  it('doublecircle emits two subpaths', () => {
    const d = shapePath('doublecircle', 80, 80);
    expect((d.match(/Z/g) ?? []).length).toBe(2);
  });

  it('parallelogram skew is 0.2·w', () => {
    const d = shapePath('parallelogram', 100, 40);
    expect(d).toContain('M 20 0');
    expect(d).toContain('L 80 40');
  });

  it('stable output (golden snippets)', () => {
    expect(shapePath('ellipse', 80, 40)).toBe('M 0 20 A 40 20 0 1 0 80 20 A 40 20 0 1 0 0 20 Z');
    expect(shapePath('cylinder', 80, 60)).toBe(
      'M 0 7.5 A 40 7.5 0 0 1 80 7.5 L 80 52.5 A 40 7.5 0 0 1 0 52.5 Z',
    );
  });

  it('stadium is a closed pill with two semicircular caps', () => {
    const d = shapePath('stadium', 100, 40);
    expect(d).toBe('M 20 0 H 80 A 20 20 0 0 1 80 40 H 20 A 20 20 0 0 1 20 0 Z');
    // starts where it ends — closed outline
    expect(d.startsWith('M 20 0')).toBe(true);
    expect(d.endsWith('20 0 Z')).toBe(true);
    expect(d).not.toContain('V '); // no stray connector line
  });

  it('degenerates safely at zero size', () => {
    expect(() => shapePath('rect', 0, 0)).not.toThrow();
    expect(shapePath('rect', 0, 0)).toBe('M 0 0 H 0 V 0 H 0 Z');
  });
});

describe('shapeBoundaryIntersection (§11.2)', () => {
  it('rect: right-edge hit from the east', () => {
    const p = shapeBoundaryIntersection('rect', 100, 50, { x: 200, y: 25 });
    expect(p.x).toBeCloseTo(100, 5);
    expect(p.y).toBeCloseTo(25, 5);
  });

  it('ellipse: radial scaling onto the boundary', () => {
    const p = shapeBoundaryIntersection('ellipse', 100, 50, { x: 50 + 200, y: 25 });
    expect(p.x).toBeCloseTo(100, 5);
    const q = shapeBoundaryIntersection('ellipse', 100, 50, { x: 50, y: 25 + 200 });
    expect(q.y).toBeCloseTo(50, 5);
    // corner direction hits the ellipse, inside the rect corner
    const r = shapeBoundaryIntersection('ellipse', 100, 100, { x: 50 + 50, y: 50 + 50 });
    expect(r.x).toBeCloseTo(50 + 50 / Math.SQRT2, 4);
  });

  it('aim-at-center returns a stable point instead of NaN', () => {
    for (const kind of ['rect', 'ellipse', 'diamond'] as const) {
      const p = shapeBoundaryIntersection(kind, 100, 50, { x: 50, y: 25 });
      expect(Number.isFinite(p.x)).toBe(true);
      expect(Number.isFinite(p.y)).toBe(true);
      expect(p).toEqual({ x: 50, y: 0 });
    }
  });

  it('diamond: diagonal hits the vertex midpoint edge', () => {
    const p = shapeBoundaryIntersection('diamond', 100, 100, { x: 50 + 50, y: 50 });
    expect(p.x).toBeCloseTo(100, 5);
    const q = shapeBoundaryIntersection('diamond', 100, 100, { x: 50 + 50, y: 50 + 50 });
    expect(q.x).toBeCloseTo(75, 5);
    expect(q.y).toBeCloseTo(75, 5);
  });
});
