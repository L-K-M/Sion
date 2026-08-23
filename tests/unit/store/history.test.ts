import { describe, expect, it } from 'vitest';
import {
  HISTORY_LIMIT,
  beginGesture,
  commit,
  emptyHistory,
  endGesture,
  redo,
  undo,
} from '../../../src/renderer/store/history';
import { newDoc, newNode } from '../../../src/shared/model/create';
import type { ThalyxDoc } from '../../../src/shared/model/types';

function docWith(label: string): ThalyxDoc {
  const doc = newDoc();
  doc.nodes.push(newNode({ id: 'n1', label }));
  return doc;
}

const D0 = docWith('');
const D1 = docWith('one');
const D2 = docWith('two');
const D3 = docWith('three');

describe('snapshot history (§8.2)', () => {
  it('commit pushes the pre-mutation doc and clears the future', () => {
    let h = emptyHistory();
    h = commit(h, D0);
    const r = undo(h, D1);
    expect(r?.doc).toBe(D0);
    h = r ? r.history : h;
    // after undo, future holds D1; a new commit clears it
    h = commit(h, D2);
    expect(redo(h, D3)).toBeNull();
    expect(undo(h, D3)?.doc).toBe(D2);
  });

  it('undo/redo are no-ops at the ends', () => {
    expect(undo(emptyHistory(), D0)).toBeNull();
    expect(redo(emptyHistory(), D0)).toBeNull();
  });

  it('gestures coalesce: begin → many changes → end = ONE entry', () => {
    let h = emptyHistory();
    h = commit(h, D0); // earlier action
    h = beginGesture(h, D1); // drag start
    h = beginGesture(h, D2); // repeated begin is a no-op
    expect(h.pending).toBe(D1);
    h = endGesture(h, D3); // drag end (doc changed during the gesture)
    expect(h.pending).toBeNull();
    expect(h.past).toEqual([D0, D1]); // one entry for the whole gesture
    const r = undo(h, D3);
    expect(r?.doc).toBe(D1);
  });

  it('a gesture with no net change creates no entry', () => {
    let h = emptyHistory();
    h = beginGesture(h, D1);
    h = endGesture(h, D1); // same reference → nothing changed
    expect(h.past).toEqual([]);
    expect(h.future).toEqual([]);
  });

  it('endGesture without begin is a no-op', () => {
    const h = endGesture(emptyHistory(), D1);
    expect(h.past).toEqual([]);
  });

  it('caps the past at HISTORY_LIMIT (oldest dropped)', () => {
    let h = emptyHistory();
    const docs = Array.from({ length: HISTORY_LIMIT + 5 }, (_, i) => docWith(String(i)));
    for (const d of docs) h = commit(h, d);
    expect(h.past.length).toBe(HISTORY_LIMIT);
    // the oldest surviving entry is docs.length - LIMIT
    let cur = docs[docs.length - 1]!;
    for (let i = 0; i < HISTORY_LIMIT; i++) {
      const r = undo(h, cur);
      expect(r).not.toBeNull();
      cur = r!.doc;
      h = r!.history;
    }
    expect(cur).toBe(docs[docs.length - HISTORY_LIMIT]);
    expect(undo(h, cur)).toBeNull();
  });

  it('undo/redo preserve snapshot identity (structural sharing)', () => {
    let h = emptyHistory();
    h = commit(h, D0);
    const r = undo(h, D1);
    expect(r?.doc).toBe(D0); // exact same reference, not a clone
    const r2 = redo(r!.history, r!.doc);
    expect(r2?.doc).toBe(D1);
  });
});
