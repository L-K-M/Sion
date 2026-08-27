import { extname } from 'node:path';
import { z } from 'zod';
import { SaveDialogPurpose } from '../shared/saveDialog';

export const DOCUMENT_EXTENSION = '.thalyx';

export const MAX_CONTENT_BYTES = 50 * 1024 * 1024;

const docIdSchema = z.string().regex(/^[A-Za-z0-9_-]{1,64}$/);

export function validateDocId(docId: string): void {
  docIdSchema.parse(docId);
}

export function validateContentSize(contents: string, maxBytes: number = MAX_CONTENT_BYTES): void {
  if (Buffer.byteLength(contents, 'utf8') <= maxBytes) return;

  throw new Error('content too large');
}

export function validateRecoveryWrite(docId: string, contents: string): void {
  validateDocId(docId);
  validateContentSize(contents);
}

export function validateSavePath(path: string, purpose: SaveDialogPurpose): void {
  if (purpose !== SaveDialogPurpose.Document) return;
  if (extname(path).toLowerCase() === DOCUMENT_EXTENSION) return;

  throw new Error(`Thalyx documents must use ${DOCUMENT_EXTENSION}`);
}
