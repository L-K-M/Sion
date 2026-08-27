import { afterEach, describe, expect, it } from 'vitest';
import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { canonicalDocumentPath } from '../../../src/main/canonicalPath';

let scratch: string | null = null;

afterEach(() => {
  if (scratch) rmSync(scratch, { recursive: true, force: true });
  scratch = null;
});

describe('canonicalDocumentPath', () => {
  it('collapses symlink aliases for existing documents', async () => {
    scratch = mkdtempSync(join(tmpdir(), 'thalyx-canonical-'));
    const documentPath = join(scratch, 'diagram.thalyx');
    const aliasPath = join(scratch, 'alias.thalyx');
    writeFileSync(documentPath, '{}');
    symlinkSync(documentPath, aliasPath);

    expect(await canonicalDocumentPath(aliasPath)).toBe(await canonicalDocumentPath(documentPath));
  });

  it('canonicalizes the parent of a new Save As target', async () => {
    scratch = mkdtempSync(join(tmpdir(), 'thalyx-canonical-'));
    const aliasDirectory = join(scratch, 'alias');
    symlinkSync(scratch, aliasDirectory);

    expect(await canonicalDocumentPath(join(aliasDirectory, 'new.thalyx'))).toBe(
      join(scratch, 'new.thalyx'),
    );
  });
});
