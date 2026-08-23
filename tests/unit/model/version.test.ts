import { describe, expect, it } from 'vitest';
import { DOC_SCHEMA_ID, DOC_TYPE, DOC_VERSION } from '../../../src/shared/model/version';

describe('shared/model/version (M0 smoke)', () => {
  it('declares the thalyx v1 document schema', () => {
    expect(DOC_TYPE).toBe('thalyx');
    expect(DOC_VERSION).toBe(1);
    expect(DOC_SCHEMA_ID).toBe('thalyx@v1');
  });
});
