import { describe, expect, it } from 'vitest';
import { newDoc, newEdge, newNode } from '../../../src/shared/model/create';
import { parseDocSchema, thalyxDocSchema } from '../../../src/shared/model/schema';

describe('zod schema', () => {
  it('accepts a factory doc', () => {
    const doc = newDoc();
    doc.nodes.push(newNode({ id: 'n1', x: 0, y: 0, label: 'A' }));
    doc.nodes.push(newNode({ id: 'n2', kind: 'container', x: 10, y: 10 }));
    doc.nodes[0]!.parentId = 'n2';
    doc.edges.push(newEdge({ id: 'e1', source: 'n1', target: 'n2' }));
    expect(() => parseDocSchema(doc)).not.toThrow();
  });

  it('rejects wrong type/version', () => {
    const doc: Record<string, unknown> = { ...newDoc(), type: 'other' };
    expect(thalyxDocSchema.safeParse(doc).success).toBe(false);
    expect(thalyxDocSchema.safeParse({ ...newDoc(), version: 2 }).success).toBe(false);
  });

  it('rejects non-finite coordinates and sub-minimum sizes', () => {
    const doc = newDoc();
    doc.nodes.push(newNode({ id: 'n1' }));
    (doc.nodes[0] as unknown as { x: number }).x = Number.POSITIVE_INFINITY;
    expect(thalyxDocSchema.safeParse(doc).success).toBe(false);

    const doc2 = newDoc();
    doc2.nodes.push(newNode({ id: 'n1', width: 3 }));
    expect(thalyxDocSchema.safeParse(doc2).success).toBe(false);
  });

  it('rejects oversized labels (4 kB bound, §14.6)', () => {
    const doc = newDoc();
    doc.nodes.push(newNode({ id: 'n1', label: 'x'.repeat(4097) }));
    expect(thalyxDocSchema.safeParse(doc).success).toBe(false);
    doc.nodes[0]!.label = 'x'.repeat(4096);
    expect(thalyxDocSchema.safeParse(doc).success).toBe(true);
  });

  it('rejects bad enum values', () => {
    const doc = newDoc();
    const n = newNode({ id: 'n1' });
    (n as unknown as { kind: string }).kind = 'bogus';
    doc.nodes.push(n);
    expect(thalyxDocSchema.safeParse(doc).success).toBe(false);
  });

  it('bounds labelT to 0..1', () => {
    const doc = newDoc();
    doc.nodes.push(newNode({ id: 'n1' }), newNode({ id: 'n2' }));
    doc.edges.push(newEdge({ id: 'e1', source: 'n1', target: 'n2', labelT: 1.5 }));
    expect(thalyxDocSchema.safeParse(doc).success).toBe(false);
  });
});
