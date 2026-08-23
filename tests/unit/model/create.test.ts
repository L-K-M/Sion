import { describe, expect, it } from 'vitest';
import { DEFAULT_SHAPE, newDoc, newEdge, newNode } from '../../../src/shared/model/create';

describe('factories', () => {
  it('newDoc produces a valid empty v1 doc', () => {
    const doc = newDoc();
    expect(doc.type).toBe('thalyx');
    expect(doc.version).toBe(1);
    expect(doc.source).toMatch(/^thalyx@/);
    expect(doc.nodes).toEqual([]);
    expect(doc.edges).toEqual([]);
    expect(doc.meta.mermaid?.direction).toBe('TB');
    expect(doc.canvas).toEqual({ background: 'default', grid: false });
  });

  it('newNode gets a 12-char nanoid and defaults', () => {
    const n = newNode({ x: 10, y: 20 });
    expect(n.id).toMatch(/^[A-Za-z0-9_-]{12}$/);
    expect(n.kind).toBe('shape');
    expect(n.shape).toBe(DEFAULT_SHAPE);
    expect(n.shape).toBe('rounded');
    expect(n.width).toBe(160);
    expect(n.height).toBe(64);
    expect(n.style).toEqual({
      fill: 'surface',
      stroke: 'ink',
      strokeWidth: 2,
      fontSize: 14,
      textAlign: 'center',
    });
  });

  it('newNode respects overrides and does not leak defaults', () => {
    const n = newNode({ kind: 'container', label: 'Auth', style: { fill: 'blue' } });
    expect(n.kind).toBe('container');
    expect(n.shape).toBeUndefined();
    expect(n.style.fill).toBe('blue');
    expect(n.style.strokeWidth).toBe(2);
  });

  it('newEdge defaults: elbow, auto anchors, arrow end, solid ink', () => {
    const e = newEdge({ source: 'a', target: 'b' });
    expect(e.id).toMatch(/^[A-Za-z0-9_-]{12}$/);
    expect(e.kind).toBe('elbow');
    expect(e.sourceAnchor).toBe('auto');
    expect(e.targetAnchor).toBe('auto');
    expect(e.arrowStart).toBe('none');
    expect(e.arrowEnd).toBe('arrow');
    expect(e.style).toEqual({ line: 'solid', stroke: 'ink', rounded: true });
    expect(e.label).toBeUndefined();
  });

  it('two newNodes never share ids', () => {
    const ids = new Set(Array.from({ length: 200 }, () => newNode().id));
    expect(ids.size).toBe(200);
  });
});
