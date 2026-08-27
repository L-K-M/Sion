import type { ThalyxEdge } from '../../shared/model/types';

const PINNED_ANCHORS = new Set<ThalyxEdge['sourceAnchor']>(['n', 's', 'e', 'w']);

export function connectionAnchor(handleId: string | null): ThalyxEdge['sourceAnchor'] {
  if (handleId && PINNED_ANCHORS.has(handleId as ThalyxEdge['sourceAnchor'])) {
    return handleId as ThalyxEdge['sourceAnchor'];
  }

  return 'auto';
}
