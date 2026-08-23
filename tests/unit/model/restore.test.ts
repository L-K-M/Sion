import { describe, expect, it } from 'vitest';
import { restoreDocument, DocTooNewError } from '../../../src/shared/model/restore';
import { newDoc, newNode, newEdge } from '../../../src/shared/model/create';
import type { ThalyxDoc } from '../../../src/shared/model/types';

/** A representative "weird but real" doc for idempotence checks. */
function weirdDoc(): Record<string, unknown> {
  return {
    type: 'thalyx',
    version: 1,
    source: 42,
    nodes: [
      // child appears BEFORE its parent (z-order violation to be fixed)
      {
        id: 'child',
        parentId: 'cont',
        kind: 'shape',
        x: 5,
        y: 6,
        width: 50,
        height: 40,
        label: 'c',
      },
      { id: 'cont', kind: 'container', x: 100, y: 100, width: 300, height: 200, label: 'G' },
      {
        id: 'shape1',
        kind: 'shape',
        shape: 'diamond',
        x: 1,
        y: 2,
        width: 10,
        height: 10,
        label: 'x'.repeat(5000),
      },
      { id: 'shape1', kind: 'shape', x: 0, y: 0 }, // duplicate id → dropped
      { id: 'bad-parent', parentId: 'shape1', x: 0, y: 0 }, // parent not a container → detached
      { id: 'island', kind: 'mermaid', mermaidSource: 'sequenceDiagram' },
      { kind: 'shape', x: 'NaN', width: -5 }, // no id → generated; width clamped
    ],
    edges: [
      { id: 'e1', source: 'shape1', target: 'child' },
      { id: 'e2', source: 'ghost', target: 'shape1' }, // dangling → dropped
      { id: 'e3', source: 'island', target: 'shape1' }, // island endpoint → dropped
      { id: 'e4', source: 'cont', target: 'shape1', kind: 'bogus', labelT: 9 }, // coerced
      { source: 'child', target: 'cont' }, // no id → generated
    ],
    canvas: { background: 7, grid: 'yes' },
    meta: { mermaid: { direction: 'SIDEWAYS' } },
  };
}

describe('restoreDocument', () => {
  it('garbage in → valid doc out (never throws on weird data)', () => {
    for (const garbage of [null, undefined, 0, 42, '', 'doc', [], [1, 2], true, {}, Number.NaN]) {
      const doc = restoreDocument(garbage);
      expect(doc.type).toBe('thalyx');
      expect(doc.version).toBe(1);
      expect(Array.isArray(doc.nodes)).toBe(true);
      expect(Array.isArray(doc.edges)).toBe(true);
      expect(doc.meta.mermaid?.direction).toBe('TB');
    }
  });

  it('throws DocTooNewError only for version > 1', () => {
    expect(() => restoreDocument({ version: 2 })).toThrow(DocTooNewError);
    expect(() => restoreDocument({ version: 99, nodes: [] })).toThrow(/newer Thalyx/);
    expect(() => restoreDocument({ version: 1 })).not.toThrow();
    expect(() => restoreDocument({ version: 'x' })).not.toThrow(); // non-number → coerce
  });

  it('drops edges whose endpoints do not resolve (invariant 1)', () => {
    const doc = restoreDocument(weirdDoc());
    const ids = new Set(doc.nodes.map((n) => n.id));
    for (const e of doc.edges) {
      expect(ids.has(e.source)).toBe(true);
      expect(ids.has(e.target)).toBe(true);
    }
    expect(doc.edges.some((e) => e.id === 'e2')).toBe(false);
  });

  it('drops edges that touch mermaid islands (invariant 5)', () => {
    const doc = restoreDocument(weirdDoc());
    expect(doc.edges.some((e) => e.id === 'e3')).toBe(false);
  });

  it('only containers may parent; non-container parents detach (invariant 2)', () => {
    const doc = restoreDocument(weirdDoc());
    const byId = new Map(doc.nodes.map((n) => [n.id, n]));
    for (const n of doc.nodes) {
      if (n.parentId !== undefined) {
        expect(byId.get(n.parentId)?.kind).toBe('container');
      }
    }
    expect(doc.nodes.find((n) => n.id === 'bad-parent')?.parentId).toBeUndefined();
  });

  it('breaks parentId cycles', () => {
    const doc = restoreDocument({
      nodes: [
        { id: 'a', kind: 'container', parentId: 'b' },
        { id: 'b', kind: 'container', parentId: 'a' },
        { id: 'c', kind: 'shape', parentId: 'a', x: 0, y: 0 },
      ],
    });
    const a = doc.nodes.find((n) => n.id === 'a');
    const b = doc.nodes.find((n) => n.id === 'b');
    // at most one of the two keeps its parent; c stays under a container
    const parentsKept = [a?.parentId, b?.parentId].filter((p) => p !== undefined).length;
    expect(parentsKept).toBeLessThanOrEqual(1);
    expect(doc.nodes.find((n) => n.id === 'c')?.parentId).toBeDefined();
  });

  it('fixes z-order: containers strictly before children (invariant 3)', () => {
    const doc = restoreDocument(weirdDoc());
    const idx = new Map(doc.nodes.map((n, i) => [n.id, i]));
    for (const n of doc.nodes) {
      if (n.parentId !== undefined) {
        expect(idx.get(n.parentId)!).toBeLessThan(idx.get(n.id)!);
      }
    }
    // the child that appeared before its container in the raw input is now after it
    expect(idx.get('cont')!).toBeLessThan(idx.get('child')!);
  });

  it('clamps numbers: NaN→0, width/height ≥ 8 (invariant 6)', () => {
    const doc = restoreDocument(weirdDoc());
    for (const n of doc.nodes) {
      expect(Number.isFinite(n.x)).toBe(true);
      expect(Number.isFinite(n.y)).toBe(true);
      expect(n.width).toBeGreaterThanOrEqual(8);
      expect(n.height).toBeGreaterThanOrEqual(8);
    }
  });

  it('truncates labels at 4 kB and generates missing ids', () => {
    const doc = restoreDocument(weirdDoc());
    expect(doc.nodes.find((n) => n.id === 'shape1')?.label.length).toBe(4096);
    const generated = doc.nodes.filter(
      (n) => !['child', 'cont', 'shape1', 'bad-parent', 'island'].includes(n.id),
    );
    expect(generated.length).toBe(1);
    expect(generated[0]!.id).toMatch(/^[A-Za-z0-9_-]{12}$/);
  });

  it('drops duplicate node ids (first wins)', () => {
    const doc = restoreDocument(weirdDoc());
    expect(doc.nodes.filter((n) => n.id === 'shape1').length).toBe(1);
  });

  it('coerces enums, labelT, canvas, direction', () => {
    const doc = restoreDocument(weirdDoc());
    const e4 = doc.edges.find((e) => e.id === 'e4');
    expect(e4?.kind).toBe('elbow');
    expect(e4?.labelT).toBe(1);
    expect(doc.canvas).toEqual({ background: 'default', grid: false });
    expect(doc.meta.mermaid?.direction).toBe('TB');
  });

  it('restore(restore(x)) === restore(x) — idempotence (§15.1)', () => {
    const fixtures: unknown[] = [
      weirdDoc(),
      null,
      42,
      {},
      { nodes: [{ id: 'a', parentId: 'a', kind: 'container' }] }, // self-parent cycle
      { nodes: 'nope', edges: 7, canvas: [], meta: 'x' },
    ];
    for (const x of fixtures) {
      const once = restoreDocument(x);
      const twice = restoreDocument(JSON.parse(JSON.stringify(once)));
      expect(twice).toEqual(once);
    }
  });

  it('preserves a healthy doc untouched (round-trip identity)', () => {
    const doc: ThalyxDoc = newDoc();
    const a = newNode({ id: 'a', x: 0, y: 0, label: 'A' });
    const g = newNode({
      id: 'g',
      kind: 'container',
      x: -10,
      y: -10,
      width: 400,
      height: 300,
      label: 'G',
    });
    const b = newNode({ id: 'b', x: 20, y: 20, label: 'B', parentId: 'g' });
    doc.nodes.push(g, a, b);
    doc.edges.push(newEdge({ id: 'e', source: 'a', target: 'b', label: 'yes' }));
    const restored = restoreDocument(JSON.parse(JSON.stringify(doc)));
    expect(restored.nodes.map((n) => n.id)).toEqual(['g', 'a', 'b']);
    expect(restored.edges[0]?.label).toBe('yes');
    expect(restored.nodes.find((n) => n.id === 'b')?.parentId).toBe('g');
  });

  it('z-order pass preserves unrelated interleavings (topological fidelity)', () => {
    // valid doc: A, child-of-A, B — B must NOT jump before child under the
    // topological pass (depth-grouping would reorder it)
    const doc = restoreDocument({
      nodes: [
        { id: 'A', kind: 'container', x: 0, y: 0, width: 300, height: 200 },
        { id: 'child', kind: 'shape', parentId: 'A', x: 1, y: 1 },
        { id: 'B', kind: 'shape', x: 500, y: 500 },
      ],
    });
    expect(doc.nodes.map((n) => n.id)).toEqual(['A', 'child', 'B']);
  });

  it('caps runaway node/edge arrays (§14.6 bounds)', () => {
    const many = Array.from({ length: 25_000 }, (_, i) => ({
      id: `n${i}`,
      kind: 'shape',
      x: 0,
      y: 0,
    }));
    const doc = restoreDocument({ nodes: many });
    expect(doc.nodes.length).toBeLessThanOrEqual(20_000);
  });
});
