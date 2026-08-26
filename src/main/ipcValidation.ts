import { z } from 'zod';

export const MAX_CONTENT_BYTES = 50 * 1024 * 1024;

const docIdSchema = z.string().regex(/^[A-Za-z0-9_-]{1,64}$/);

export function validateDocId(docId: string): void {
  docIdSchema.parse(docId);
}

export function validateContentSize(contents: string): void {
  if (Buffer.byteLength(contents, 'utf8') <= MAX_CONTENT_BYTES) return;

  throw new Error('content too large');
}

export function validateRecoveryWrite(docId: string, contents: string): void {
  validateDocId(docId);
  validateContentSize(contents);
}
