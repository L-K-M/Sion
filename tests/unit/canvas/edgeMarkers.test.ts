import { describe, expect, it } from 'vitest';
import { markerId, markerReference } from '../../../src/renderer/canvas/edges/edgeMarkers';

describe('SVG edge markers', () => {
  it('uses a URL fragment reference for SVG marker attributes', () => {
    expect(markerId('edge-1', 'end')).toBe('marker-edge-1-end');
    expect(markerReference('edge-1', 'end')).toBe('url(#marker-edge-1-end)');
  });
});
