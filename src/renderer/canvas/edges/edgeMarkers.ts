export type MarkerEnd = 'start' | 'end';

export function markerId(edgeId: string, end: MarkerEnd): string {
  return `marker-${edgeId}-${end}`;
}

export function markerReference(edgeId: string, end: MarkerEnd): string {
  return `url(#${markerId(edgeId, end)})`;
}
