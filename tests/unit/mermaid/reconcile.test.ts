import { describe, expect, it } from 'vitest';
import { reconcileDocument } from '../../../src/shared/mermaid/reconcile';
import { importMermaid } from '../../../src/shared/mermaid/import';
import { newDoc, newEdge, newNode } from '../../../src/shared/model/create';
import type { ThalyxDoc, ThalyxNode } from '../../../src/shared/model/types';
import { shimParse } from '../../corpus/shim';

function docWithIds(): ThalyxDoc {
  const doc = newDoc();
  const a: ThalyxNode = {
    ...newNode({ id: 'nA', label: 'Alpha', x: 100, y: 100 }),
    meta: { mermaid: { id: 'A' } },
  };
  const b: ThalyxNode = {
    ...newNode({ id: 'nB', label: 'Beta', x: 400, y: 100 }),
    meta: { mermaid: { id: 'B' } },
  };
  doc.nodes.push(a, b);
  doc.edges.push(newEdge({ id: 'e1', source: 'nA', target: 'nB', label: 'yes' }));
  return doc;
}

async function importText(text: string) {
  const r = await importMermaid(text, shimParse);
  if (r.kind !== 'flowchart') throw new Error('not a flowchart: ' + text);
  return r;
}

describe('reconcileDocument (§9.6)', () => {
  it('rename: matched node keeps identity (id) and position; label follows the text', async () => {
    const cur = docWithIds();
    const imp = await importText('flowchart TB\n  A[Alpha2] --> B[Beta]');
    const { doc } = reconcileDocument(cur, imp);
    const alpha = doc.nodes.find((n) => n.meta?.mermaid?.id === 'A')!;
    expect(alpha.id).toBe('nA'); // matched identity survives
    expect(alpha.label).toBe('Alpha2');
    expect(alpha.x).toBe(100);
    expect(alpha.y).toBe(100);
    expect(doc.nodes).toHaveLength(2);
  });

  it('add an edge: matched by endpoints; label follows the text (import is authoritative)', async () => {
    const cur = docWithIds();
    const imp = await importText('flowchart TB\n  A --> B\n  B --> A');
    const { doc } = reconcileDocument(cur, imp);
    expect(doc.edges).toHaveLength(2);
    // text is the source of truth: the old label is REPLACED (import has none)
    expect(doc.edges.every((e) => e.label === undefined)).toBe(true);
  });

  it('delete a node: absent id removed with its edges', async () => {
    const cur = docWithIds();
    const imp = await importText('flowchart TB\n  A[Alpha2]');
    const { doc, removed } = reconcileDocument(cur, imp);
    expect(removed).toBe(1);
    expect(doc.nodes).toHaveLength(1);
    expect(doc.edges).toHaveLength(0);
  });

  it('new node placed near its placed neighbor', async () => {
    const cur = docWithIds();
    const imp = await importText('flowchart TB\n  A --> B\n  B --> C[Gamma]');
    const { doc, added } = reconcileDocument(cur, imp);
    expect(added).toBe(1);
    const gamma = doc.nodes.find((n) => n.meta?.mermaid?.id === 'C')!;
    // within ~grid gap of Beta's position (which is at 400,100)
    expect(Math.abs(gamma.x - (400 + 48))).toBeLessThanOrEqual(64);
    expect(Math.abs(gamma.y - (100 + 48))).toBeLessThanOrEqual(64);
  });

  it('parentId change converts coordinates (absolute position preserved)', async () => {
    const cur = docWithIds();
    // wrap A in a container in the new text
    const imp = await importText(
      'flowchart TB\n  subgraph SG [G]\n    A[Alpha2]\n  end\n  B[Beta]\n  A --> B',
    );
    const { doc } = reconcileDocument(cur, imp);
    const a = doc.nodes.find((n) => n.meta?.mermaid?.id === 'A')!;
    const sg = doc.nodes.find((n) => n.kind === 'container')!;
    expect(a.parentId).toBe(sg.id);
    // stored x/y are now parent-relative
    const sgAbs = absoluteOf(doc, sg);
    expect(a.x + sgAbs.x).toBeCloseTo(100, 0);
    expect(a.y + sgAbs.y).toBeCloseTo(100, 0);
  });

  it('unmatched old nodes (no mermaid id) are kept untouched', async () => {
    const cur = docWithIds();
    cur.nodes.push(newNode({ id: 'hand', label: 'Hand drawn', x: 900, y: 500 }));
    const imp = await importText('flowchart TB\n  A[Alpha2] --> B[Beta]');
    const { doc } = reconcileDocument(cur, imp);
    const hand = doc.nodes.find((n) => n.id === 'hand')!;
    expect(hand).toBeTruthy();
    expect(hand.x).toBe(900); // truly untouched
    expect(hand.y).toBe(500);
  });

  it('one-way semantic check: reconcile(doc, import(export(doc))) is a fixpoint twice', async () => {
    const cur = docWithIds();
    const { exportMermaid } = await import('../../../src/shared/mermaid/export');
    // assign ids as exportMermaid would
    const out = exportMermaid(cur);
    for (const n of cur.nodes) {
      const mid = out.idAssignments[n.id];
      if (mid) {
        n.meta ??= {};
        n.meta.mermaid ??= {};
        n.meta.mermaid.id = mid;
      }
    }
    const out2 = exportMermaid(cur);
    const imp = await importText(out2.text);
    const { doc } = reconcileDocument(cur, imp);
    const a = doc.nodes.find((n) => n.meta?.mermaid?.id === 'A')!;
    expect(a.x).toBe(100);
    expect(a.label).toBe('Alpha');

    // fixpoint: reconcile(reconcile(...)) with the same text changes nothing
    const imp2 = await importText(out2.text);
    const again = reconcileDocument(doc, imp2);
    const a2 = again.doc.nodes.find((n) => n.meta?.mermaid?.id === 'A')!;
    expect(a2.x).toBe(a.x);
    expect(again.doc.nodes.map((n) => n.id).sort()).toEqual(doc.nodes.map((n) => n.id).sort());
  });
});

function absoluteOf(doc: ThalyxDoc, node: ThalyxNode): { x: number; y: number } {
  let x = node.x;
  let y = node.y;
  let cursor = node.parentId;
  while (cursor !== undefined) {
    const p = doc.nodes.find((n) => n.id === cursor);
    if (!p) break;
    x += p.x;
    y += p.y;
    cursor = p.parentId;
  }
  return { x, y };
}
