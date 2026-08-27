import { describe, expect, it, vi } from 'vitest';
import {
  saveTargetPath,
  type DocumentPathReservation,
} from '../../../src/main/documentSaveReservation';

describe('document save reservation', () => {
  it('uses the canonical reserved path instead of a selected symlink alias', () => {
    const reservation: DocumentPathReservation = {
      path: '/documents/real.thalyx',
      commit: vi.fn(),
      rollback: vi.fn(),
    };

    expect(saveTargetPath('/documents/alias.thalyx', reservation)).toBe('/documents/real.thalyx');
  });

  it('keeps the selected path for non-document exports', () => {
    expect(saveTargetPath('/exports/diagram.svg', null)).toBe('/exports/diagram.svg');
  });
});
