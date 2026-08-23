import { describe, expect, it } from 'vitest';
import { newDoc, newEdge, newNode } from '../../../src/shared/model/create';
import { parseDoc, serializeDoc } from '../../../src/shared/files/thalyxFile';

function healthyDoc() {
  const doc = newDoc();
  doc.nodes.push(
    newNode({ id: 'a', x: 0, y: 0, label: 'A\nB' }),
    newNode({ id: 'g', kind: 'container', x: 100, y: 0, label: 'G' }),
    newNode({ id: 'b', x: 10, y: 10, label: 'B', parentId: 'g' }),
  );
  doc.edges.push(newEdge({ id: 'e', source: 'a', target: 'b', label: 'lbl' }));
  return doc;
}

describe('thalyxFile', () => {
  it('serializes pretty 2-space with trailing newline', () => {
    const text = serializeDoc(healthyDoc());
    expect(text.endsWith('\n')).toBe(true);
    expect(text).toContain('\n  "type": "thalyx"');
    expect(text.split('\n')[1]).toBe('  "type": "thalyx",');
  });

  it('round-trips a healthy doc with full fidelity', () => {
    const doc = healthyDoc();
    const back = parseDoc(serializeDoc(doc));
    expect(back.nodes.map((n) => n.id)).toEqual(['a', 'g', 'b']);
    expect(back.nodes.find((n) => n.id === 'a')?.label).toBe('A\nB');
    expect(back.nodes.find((n) => n.id === 'b')?.parentId).toBe('g');
    expect(back.edges[0]?.label).toBe('lbl');
    expect(back).toEqual(doc);
  });

  it('parseDoc throws SyntaxError on invalid JSON (not a document)', () => {
    expect(() => parseDoc('this is not json')).toThrow(SyntaxError);
    expect(() => parseDoc('')).toThrow(SyntaxError);
  });

  it('parseDoc normalizes weird-but-JSON data', () => {
    const doc = parseDoc('{"nodes":[{"id":"a","width":2}],"edges":[{"source":"a","target":"zz"}]}');
    expect(doc.nodes[0]?.width).toBe(8);
    expect(doc.edges.length).toBe(0); // dangling target dropped
  });

  it('serialize → parse is a fixpoint', () => {
    const doc = healthyDoc();
    const t1 = serializeDoc(parseDoc(serializeDoc(doc)));
    expect(t1).toBe(serializeDoc(doc));
  });
});
