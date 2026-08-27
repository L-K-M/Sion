import type { Tool } from '../../../shared/model/types';

/** Edge labels and rails stay inert while a navigation or creation tool owns the pointer. */
export function canEditEdge(tool: Tool): boolean {
  return tool === 'select';
}
