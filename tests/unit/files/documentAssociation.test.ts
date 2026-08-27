import { describe, expect, it } from 'vitest';
import { associatedPathForOpen } from '../../../src/renderer/files/documentAssociation';

describe('opened document association', () => {
  it('keeps native documents associated with their source', () => {
    expect(associatedPathForOpen('/tmp/diagram.thalyx', '{"type":"thalyx"}')).toBe(
      '/tmp/diagram.thalyx',
    );
  });

  it.each(['/tmp/diagram.mmd', '/tmp/diagram.mermaid'])(
    'imports %s without making the source writable',
    (path) => {
      expect(associatedPathForOpen(path, 'flowchart LR\n  A --> B')).toBeNull();
    },
  );

  it('does not associate Mermaid text with a misleading extension', () => {
    expect(associatedPathForOpen('/tmp/diagram.txt', 'flowchart LR\n  A --> B')).toBeNull();
  });
});
