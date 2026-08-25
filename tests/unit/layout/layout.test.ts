import { describe, expect, it } from 'vitest';
import { dagreLayout } from '../../../src/shared/layout/dagreLayout';
import { tidyUp } from '../../../src/shared/layout/tidy';
import { newDoc, newEdge, newNode } from '../../../src/shared/model/create';
import type { ThalyxDoc } from '../../../src/shared/model/types';

function doc(): ThalyxDoc {
  const d = newDoc();
  const a = newNode({ id: 'a', x: 0, y: 0, label: 'A' });
  const b = newNode({ id: 'b', x: 500, y: 0, label: 'B' });
  const c = newNode({ id: 'c', x: 250, y: 500, label: 'C' });
  d.nodes.push(a, b, c);
  d.edges.push(newEdge({ source: 'a', target: 'b' }), newEdge({ source: 'b', target: 'c' }));
  return d;
}

const W = 160;
const H = 64;
const RANKSEP = 60;
const EPS = 1;

describe('dagreLayout (§11.5)', () => {
  it('handles a parentId cycle without throwing (defensive)', () => {
    const d = newDoc();
    d.nodes.push(
      newNode({ id: 'p', kind: 'container', x: 0, y: 0, width: 300, height: 200 }),
      newNode({ id: 'q', kind: 'container', x: 0, y: 0, width: 300, height: 200 }),
    );
    const p = d.nodes.find((n) => n.id === 'p')!;
    const q = d.nodes.find((n) => n.id === 'q')!;
    p.parentId = 'q';
    q.parentId = 'p';
    expect(() => dagreLayout(d, null, { rankdir: 'TB' })).not.toThrow();
  });

  it('lays out a chain top-down with rank separation', () => {
    const d = doc();
    const positions = dagreLayout(d, null, { rankdir: 'TB', ranksep: RANKSEP });
    expect(positions.size).toBe(3);
    const a = positions.get('a')!;
    const b = positions.get('b')!;
    const c = positions.get('c')!;
    // all finite integers
    for (const p of [a, b, c]) {
      expect(Number.isFinite(p.x)).toBe(true);
      expect(Number.isFinite(p.y)).toBe(true);
    }
    // a → b are on consecutive ranks (b below a by ≥ ranksep)
    expect(b.y).toBeGreaterThanOrEqual(a.y + RANKSEP - EPS);
    expect(c.y).toBeGreaterThanOrEqual(b.y + 60 - 1);
  });

  it('LR direction goes left to right', () => {
    const d = doc();
    const positions = dagreLayout(d, null, { rankdir: 'LR', ranksep: RANKSEP });
    const a = positions.get('a')!;
    const b = positions.get('b')!;
    expect(b.x).toBeGreaterThanOrEqual(a.x + 60 - 1);
  });

  it('containered doc: children stay inside their container (acceptance)', () => {
    const d = newDoc();
    const g = newNode({
      id: 'g',
      kind: 'container',
      x: 100,
      y: 100,
      width: 600,
      height: 400,
      label: 'G',
    });
    const x1 = newNode({ id: 'x1', x: 150, y: 150, label: 'X1', parentId: 'g' });
    const x2 = newNode({ id: 'x2', x: 400, y: 300, label: 'X2', parentId: 'g' });
    const outer = newNode({ id: 'out', x: 900, y: 100, label: 'Out' });
    d.nodes.push(g, x1, x2, outer);
    d.edges.push(newEdge({ source: 'x1', target: 'x2' }), newEdge({ source: 'g', target: 'out' }));
    // must not throw (container edge skipped; setParent on compound graph)
    const positions = dagreLayout(d, null, { rankdir: 'TB' });
    expect(positions.size).toBe(4);
    // children relative to their container: g's own frame keeps them in-bounds
    const gp = positions.get('g')!;
    const x1p = positions.get('x1')!;
    const x2p = positions.get('x2')!;
    expect(x1p.x).toBeGreaterThanOrEqual(0);
    expect(x1p.y).toBeGreaterThanOrEqual(0);
    expect(x2p.x + W).toBeLessThanOrEqual(600 + EPS);
    expect(x2p.y + H).toBeLessThanOrEqual(400 + EPS);
    // the container is placed by dagre too (finite, on-canvas)
    expect(Number.isFinite(gp.x)).toBe(true);
    expect(Number.isFinite(gp.y)).toBe(true);
  });

  it('subset layout only moves the selection', () => {
    const d = doc();
    const positions = dagreLayout(d, new Set(['a']), { rankdir: 'TB' });
    expect(positions.has('a')).toBe(true);
    expect(positions.has('b')).toBe(false);
    expect(positions.has('c')).toBe(false);
  });

  it('minlen edges space ranks further apart', () => {
    const d = newDoc();
    d.nodes.push(newNode({ id: 'a', x: 0, y: 0 }), newNode({ id: 'b', x: 0, y: 500 }));
    d.edges.push({ ...newEdge({ source: 'a', target: 'b' }), meta: { mermaid: { minlen: 2 } } });
    const positions = dagreLayout(d, null, { rankdir: 'TB', ranksep: 60 });
    const a = positions.get('a')!;
    const b = positions.get('b')!;
    expect(b.y).toBeGreaterThanOrEqual(a.y + RANKSEP * 2 - 2);
  });
});

describe('tidyUp (§11.5)', () => {
  it('distributes a row of nodes with 24px gaps and aligns tops', () => {
    const d = newDoc();
    const n1 = newNode({ id: 'n1', x: 0, y: 5, label: '1' });
    const n2 = newNode({ id: 'n2', x: 100, y: 7, label: '2' });
    const n3 = newNode({ id: 'n3', x: 190, y: 3, label: '3' });
    d.nodes.push(n1, n2, n3);
    const { positions } = tidyUp(d, [n1, n2, n3]);
    expect(positions.size).toBe(3);
    const p1 = positions.get('n1')!;
    const p2 = positions.get('n2')!;
    const p3 = positions.get('n3')!;
    expect(p1.y).toBe(p2.y);
    expect(p2.y).toBe(p3.y);
    expect(p2.x).toBe(p1.x + 160 + 24);
    expect(p3.x).toBe(p2.x + 160 + 24);
  });

  it('stacks a column with 24px gaps', () => {
    const d = newDoc();
    const n1 = newNode({ id: 'n1', x: 5, y: 0, label: '1' });
    const n2 = newNode({ id: 'n2', x: 7, y: 100, label: '2' });
    d.nodes.push(n1, n2);
    const { positions } = tidyUp(d, [n1, n2]);
    const p1 = positions.get('n1')!;
    const p2 = positions.get('n2')!;
    expect(p1.x).toBe(p2.x);
    expect(p2.y).toBe(p1.y + 64 + 24);
  });

  it('grid arrangement: rows distributed evenly', () => {
    const d = newDoc();
    const nodes = [
      newNode({ id: 'a', x: 0, y: 0, label: 'a' }),
      newNode({ id: 'b', x: 200, y: 4, label: 'b' }),
      newNode({ id: 'c', x: 2, y: 200, label: 'c' }),
      newNode({ id: 'd', x: 205, y: 196, label: 'd' }),
    ];
    d.nodes.push(...nodes);
    const { positions } = tidyUp(d, nodes);
    expect(positions.size).toBe(4);
    const a = positions.get('a')!;
    const b = positions.get('b')!;
    const c = positions.get('c')!;
    const d4 = positions.get('d')!;
    // two rows, aligned columns
    expect(a.y).toBe(b.y);
    expect(c.y).toBe(d4.y);
    expect(c.y).toBeGreaterThan(a.y);
    expect(b.x - a.x).toBe(d4.x - c.x);
  });
});
