import type { ThalyxDoc } from '../../shared/model/types';

const BLOCKED_TARGETS =
  'button, input, textarea, select, .react-flow__handle, .react-flow__resize-control';

export interface CreationTarget {
  containerId: string | null;
}

/** Resolve only blank canvas or frame content; existing objects keep their native interaction. */
export function creationTarget(target: Element, doc: ThalyxDoc): CreationTarget | null {
  if (target.closest(BLOCKED_TARGETS)) return null;

  const nodeElement = target.closest('.react-flow__node');
  const nodeId = nodeElement?.getAttribute('data-id');
  if (nodeId) {
    const node = doc.nodes.find((candidate) => candidate.id === nodeId);
    if (!node) return null;

    return { containerId: node.kind === 'container' ? node.id : (node.parentId ?? null) };
  }

  if (target.closest('.react-flow__edge')) return { containerId: null };
  if (!target.closest('.react-flow__pane')) return null;

  return { containerId: null };
}
