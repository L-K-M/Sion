import { describe, expect, it } from 'vitest';
import { DOCUMENT_OPEN_FILTERS } from '../../../src/shared/documentOpenFilters';

describe('document Open filters', () => {
  it('offers JSON documents and an unrestricted picker', () => {
    const extensions = DOCUMENT_OPEN_FILTERS.flatMap((filter) => filter.extensions);

    expect(extensions).toContain('json');
    expect(extensions).toContain('*');
  });
});
