import { describe, expect, it } from 'vitest';
import { WindowDocuments, resolveWindowBootstrap } from '../../../src/main/windowDocuments';
import type { WindowBootstrap } from '../../../src/shared/windowBootstrap';

const blank = (scratchId: string): WindowBootstrap => ({
  scratchId,
  openPath: null,
  recovery: null,
  updateReady: false,
});

describe('window document ownership', () => {
  it('rejects a second owner for the same native document', () => {
    const documents = new WindowDocuments<number>(
      () => 'fresh',
      (path) => `id:${path}`,
    );
    documents.add(1, blank('one'));
    documents.add(2, blank('two'));

    expect(documents.associate(1, '/tmp/doc.thalyx', false).kind).toBe('associated');
    expect(documents.associate(2, '/tmp/doc.thalyx', false)).toEqual({
      kind: 'conflict',
      owner: 1,
    });
  });

  it('keeps the scratch identity when an untitled document is saved', () => {
    const documents = new WindowDocuments<number>(
      () => 'fresh',
      (path) => `id:${path}`,
    );
    documents.add(1, blank('untitled-recovery'));

    const result = documents.associate(1, '/tmp/doc.thalyx', false);

    expect(result.kind === 'associated' ? result.bootstrap.scratchId : null).toBe(
      'untitled-recovery',
    );
  });

  it('gives imported or detached documents unique scratch identities', () => {
    let next = 0;
    const documents = new WindowDocuments<number>(
      () => `scratch-${(next += 1)}`,
      (path) => `id:${path}`,
    );
    documents.add(1, blank('one'));
    documents.add(2, blank('two'));

    const first = documents.associate(1, null, false);
    const second = documents.associate(2, null, false);

    expect(first.kind === 'associated' ? first.bootstrap.scratchId : null).toBe('scratch-1');
    expect(second.kind === 'associated' ? second.bootstrap.scratchId : null).toBe('scratch-2');
  });

  it('reserves a save target before an asynchronous write', () => {
    const documents = new WindowDocuments<number>(
      () => 'fresh',
      (path) => `id:${path}`,
    );
    documents.add(1, blank('one'));
    documents.add(2, blank('two'));

    const reservation = documents.reserve(1, '/tmp/doc.thalyx', false);

    expect(reservation.kind).toBe('reserved');
    expect(documents.associate(2, '/tmp/doc.thalyx', false)).toEqual({
      kind: 'conflict',
      owner: 1,
    });
    if (reservation.kind !== 'reserved') return;

    reservation.rollback();
    expect(documents.associate(2, '/tmp/doc.thalyx', false).kind).toBe('associated');
  });
});

describe('window bootstrap recovery', () => {
  it('loads the latest scratch contents on every request', async () => {
    let contents = 'first';
    const bootstrap = blank('scratch');

    const first = await resolveWindowBootstrap(bootstrap, async () => contents);
    contents = 'second';
    const second = await resolveWindowBootstrap(bootstrap, async () => contents);

    expect(first.recovery?.contents).toBe('first');
    expect(second.recovery?.contents).toBe('second');
  });

  it('does not treat associated files as scratch recovery', async () => {
    const bootstrap = { ...blank('file-id'), openPath: '/tmp/doc.thalyx' };
    const resolved = await resolveWindowBootstrap(bootstrap, async () => 'stale');

    expect(resolved.recovery).toBeNull();
  });
});
