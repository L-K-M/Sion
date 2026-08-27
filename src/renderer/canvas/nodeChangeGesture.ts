import type { NodeChange } from '@xyflow/react';

/** Start history before React Flow applies the first drag or resize delta. */
export function startsNodeGesture(changes: NodeChange[]): boolean {
  return changes.some(
    (change) =>
      (change.type === 'position' && change.dragging === true) ||
      (change.type === 'dimensions' && change.resizing === true),
  );
}
