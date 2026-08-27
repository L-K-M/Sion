import { describe, expect, it } from 'vitest';
import {
  validateContentSize,
  validateRecoveryWrite,
  validateSavePath,
} from '../../../src/main/ipcValidation';
import { SaveDialogPurpose } from '../../../src/shared/saveDialog';

describe('validateRecoveryWrite', () => {
  it.each(['../escape', 'a/b', '', 'x'.repeat(65), 'doc.1', 'a b'])(
    'rejects invalid doc id %j',
    (docId) => {
      expect(() => validateRecoveryWrite(docId, 'ok')).toThrow();
    },
  );

  it('rejects content over the limit and accepts the exact boundary', () => {
    expect(() => validateContentSize('x'.repeat(11), 10)).toThrow('content too large');
    expect(() => validateContentSize('x'.repeat(10), 10)).not.toThrow();
  });

  it('accepts a bounded recovery payload', () => {
    expect(() => validateRecoveryWrite('valid_id-1', 'contents')).not.toThrow();
  });
});

describe('validateSavePath', () => {
  it('requires the native document extension for document saves', () => {
    expect(() => validateSavePath('/tmp/diagram.thalyx', SaveDialogPurpose.Document)).not.toThrow();

    for (const extension of ['mmd', 'svg', 'png', 'pdf']) {
      expect(() =>
        validateSavePath(`/tmp/diagram.${extension}`, SaveDialogPurpose.Document),
      ).toThrow('Thalyx');
    }
  });

  it('allows supported export extensions for exports', () => {
    expect(() => validateSavePath('/tmp/diagram.svg', SaveDialogPurpose.Export)).not.toThrow();
  });
});
