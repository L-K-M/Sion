import { realpath } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';

/** Resolve physical ownership for existing files and new Save As targets. */
export async function canonicalDocumentPath(path: string): Promise<string> {
  const absolute = resolve(path);
  try {
    return await realpath(absolute);
  } catch {
    try {
      return join(await realpath(dirname(absolute)), basename(absolute));
    } catch {
      return absolute;
    }
  }
}
