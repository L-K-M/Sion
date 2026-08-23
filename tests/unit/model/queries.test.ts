import { describe, expect, it } from 'vitest';
import { newDoc, newEdge, newNode } from '../../../src/shared/model/create';
import type { ThalyxDoc } from '../../../src/shared/model/types';
import {
  absolutePosition,
  boundsOfNodes,
  childrenOf,
  depthOfNode,
  descendantsOf,
  edgesAmong,
  edgesOfNode,
  isAncestorOf,
  positionUnderParent,
} from '../../../src/shared/model/queries';

function fixture(): ThalyxDoc {
  const doc = newDoc();
  const outer = newNode({
    id: 'outer',
    kind: 'container',
    x: 100,
    y: 100,
    width: 500,
    height: 400,
    label: 'outer',
  });
  const inner = newNode({
    id: 'inner',
    kind: 'container',
    x: 50,
    y: 50,
    width: 300,
    height: 200,
    label: 'inner',
    parentId: 'outer',
  });
  const a = newNode({ id: 'a', x: 10, y: 10, label: 'A', parentId: 'inner' });
  const b = newNode({ id: 'b', x: 400, y: 300, label: 'B' }); // top level
  const c = newNode({ id: 'c', x: 20, y: 20, label: 'C', parentId: 'outer' });
  doc.nodes.push(outer, inner, a, b, c);
  doc.edges.push(
    newEdge({ id: 'e-ab', source: 'a', target: 'b' }),
    newEdge({ id: 'e-bc', source: 'b', target: 'c' }),
  );
  return doc;
}

describe('queries', () => {
  it('absolutePosition sums ancestor offsets', () => {
    const doc = fixture();
    // inner abs = (100+50, 100+50) = (150,150); a abs = inner + (10,10) = (160,160)
    expect(
      absolutePosition(
        doc,
        doc.nodes.find((n) => n.id === 'a')!,
      ),
    ).toEqual({ x: 160, y: 160 });
    expect(
      absolutePosition(
        doc,
        doc.nodes.find((n) => n.id === 'c')!,
      ),
    ).toEqual({ x: 120, y: 120 });
    expect(
      absolutePosition(
        doc,
        doc.nodes.find((n) => n.id === 'b')!,
      ),
    ).toEqual({ x: 400, y: 300 });
  });

  it('childrenOf / descendantsOf', () => {
    const doc = fixture();
    expect(childrenOf(doc, 'outer').map((n) => n.id)).toEqual(['inner', 'c']);
    expect(descendantsOf(doc, 'outer').map((n) => n.id)).toEqual(['inner', 'a', 'c']);
    expect(descendantsOf(doc, 'inner').map((n) => n.id)).toEqual(['a']);
  });

  it('depthOfNode', () => {
    const doc = fixture();
    expect(depthOfNode(doc, 'b')).toBe(0);
    expect(depthOfNode(doc, 'c')).toBe(1);
    expect(depthOfNode(doc, 'inner')).toBe(1);
    expect(depthOfNode(doc, 'a')).toBe(2);
  });

  it('isAncestorOf', () => {
    const doc = fixture();
    expect(isAncestorOf(doc, 'outer', 'a')).toBe(true);
    expect(isAncestorOf(doc, 'inner', 'a')).toBe(true);
    expect(isAncestorOf(doc, 'outer', 'inner')).toBe(true);
    expect(isAncestorOf(doc, 'a', 'outer')).toBe(false);
    expect(isAncestorOf(doc, 'b', 'a')).toBe(false);
  });

  it('edgesOfNode / edgesAmong', () => {
    const doc = fixture();
    expect(
      edgesOfNode(doc, 'b')
        .map((e) => e.id)
        .sort(),
    ).toEqual(['e-ab', 'e-bc']);
    expect(edgesAmong(doc, new Set(['a', 'b'])).map((e) => e.id)).toEqual(['e-ab']);
    expect(edgesAmong(doc, new Set(['a', 'c'])).length).toBe(0);
  });

  it('boundsOfNodes uses absolute coords', () => {
    const doc = fixture();
    const a = doc.nodes.find((n) => n.id === 'a')!;
    const c = doc.nodes.find((n) => n.id === 'c')!;
    const bounds = boundsOfNodes(doc, [a, c]);
    // a abs (160,160) size 160x64; c abs (120,120) size 160x64
    expect(bounds).toEqual({ x: 120, y: 120, width: 200, height: 104 });
    expect(boundsOfNodes(doc, [])).toBeNull();
  });

  it('positionUnderParent converts preserving absolute position (§7.2.7)', () => {
    const doc = fixture();
    const a = doc.nodes.find((n) => n.id === 'a')!; // abs (160,160)
    // move a to top level:
    expect(positionUnderParent(doc, a, undefined)).toEqual({ x: 160, y: 160 });
    // move a under outer (abs 100,100):
    expect(positionUnderParent(doc, a, 'outer')).toEqual({ x: 60, y: 60 });
    // move a under c (abs 120,120):
    expect(positionUnderParent(doc, a, 'c')).toEqual({ x: 40, y: 40 });
  });
});
