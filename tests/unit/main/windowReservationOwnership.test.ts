import { describe, expect, it } from 'vitest';
import { WindowDocuments } from '../../../src/main/windowDocuments';
import type { WindowBootstrap } from '../../../src/shared/windowBootstrap';

const file = (path: string): WindowBootstrap => ({
  scratchId: path,
  openPath: path,
  recovery: null,
  updateReady: false,
});

describe('Save As ownership reservation', () => {
  it('keeps the old and new paths owned until rollback', () => {
    const documents = new WindowDocuments<number>(
      () => 'scratch',
      (path) => path,
    );
    documents.add(1, file('/documents/old.thalyx'));
    documents.add(2, file('/documents/other.thalyx'));

    const reservation = documents.reserve(1, '/documents/new.thalyx', false);

    expect(reservation.kind).toBe('reserved');
    expect(documents.owner('/documents/old.thalyx')).toBe(1);
    expect(documents.owner('/documents/new.thalyx')).toBe(1);
    expect(documents.associate(2, '/documents/old.thalyx', false)).toEqual({
      kind: 'conflict',
      owner: 1,
    });
    if (reservation.kind !== 'reserved') return;

    reservation.rollback();
    expect(documents.owner('/documents/old.thalyx')).toBe(1);
    expect(documents.owner('/documents/new.thalyx')).toBeNull();
  });

  it('moves ownership only when the write commits', () => {
    const documents = new WindowDocuments<number>(
      () => 'scratch',
      (path) => path,
    );
    documents.add(1, file('/documents/old.thalyx'));
    const reservation = documents.reserve(1, '/documents/new.thalyx', false);
    if (reservation.kind !== 'reserved') throw new Error('reservation failed');

    reservation.commit();

    expect(documents.owner('/documents/old.thalyx')).toBeNull();
    expect(documents.owner('/documents/new.thalyx')).toBe(1);
  });
});
