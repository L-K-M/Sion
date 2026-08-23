/**
 * Snapshot history (PLAN.md §8.2, decision D4) — hand-rolled, no dependency.
 *
 * `doc` is updated immutably (immer inside actions), so snapshots structurally
 * share unchanged paths; memory cost per entry is only the changed path.
 *
 * API (see the plan's pseudocode):
 * - commit(h, prevDoc)      called by the action wrapper BEFORE a tracked mutation
 * - beginGesture(h, cur)    pending ??= current doc   (drag/resize/label-edit start)
 * - endGesture(h, cur)      if pending && changed → push pending; pending = null
 * - undo(h, cur) / redo(h, cur)
 */
import type { ThalyxDoc } from '../../shared/model/types';

export interface History {
  past: ThalyxDoc[];
  future: ThalyxDoc[];
  pending: ThalyxDoc | null;
}

export const HISTORY_LIMIT = 100;

export function emptyHistory(): History {
  return { past: [], future: [], pending: null };
}

/** Push the pre-mutation doc onto `past`, clear `future` and any pending gesture. */
export function commit(h: History, prevDoc: ThalyxDoc): History {
  const past = [...h.past, prevDoc];
  if (past.length > HISTORY_LIMIT) past.shift();
  return { past, future: [], pending: null };
}

/** Start (or continue) a gesture: remember the doc as it was before the gesture. */
export function beginGesture(h: History, currentDoc: ThalyxDoc): History {
  return h.pending ? h : { ...h, pending: currentDoc };
}

/**
 * End a gesture: if the doc actually changed since beginGesture, push the
 * pre-gesture snapshot as one history entry. No-op when nothing changed
 * (immer's structural sharing makes no-op produces reference-identical).
 */
export function endGesture(h: History, currentDoc: ThalyxDoc): History {
  if (!h.pending || h.pending === currentDoc) return { ...h, pending: null };
  const past = [...h.past, h.pending];
  if (past.length > HISTORY_LIMIT) past.shift();
  return { past, future: [], pending: null };
}

export function undo(
  h: History,
  currentDoc: ThalyxDoc,
): { history: History; doc: ThalyxDoc } | null {
  if (h.past.length === 0) return null;
  const past = [...h.past];
  const doc = past.pop() as ThalyxDoc;
  return { history: { past, future: [currentDoc, ...h.future], pending: null }, doc };
}

export function redo(
  h: History,
  currentDoc: ThalyxDoc,
): { history: History; doc: ThalyxDoc } | null {
  if (h.future.length === 0) return null;
  const [first, ...future] = h.future;
  if (!first) return null;
  const doc = first;
  return { history: { past: [...h.past, currentDoc], future, pending: null }, doc };
}

export function canUndo(h: History): boolean {
  return h.past.length > 0 || h.pending !== null;
}

export function canRedo(h: History): boolean {
  return h.future.length > 0;
}
