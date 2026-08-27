import { commitActiveInput } from './commitActiveInput';

const SAVE_FAILURE_SELECTOR = '[data-save-failure]';
const OWNERSHIP_CONFLICT = 'already open in another window';
const DOCUMENT_EXTENSION_ERROR = 'must use .thalyx';

function failureMessage(error: unknown): string {
  const detail = error instanceof Error ? error.message : String(error);
  if (detail.includes(OWNERSHIP_CONFLICT)) {
    return 'This destination is open in another window. Choose a different name.';
  }
  if (detail.includes(DOCUMENT_EXTENSION_ERROR)) {
    return 'Use a .thalyx filename for documents.';
  }

  return 'Could not save this document. Check the destination and try again.';
}

/** Commit uncontrolled editor drafts before the save callback reads the store. */
export async function runManualSave<T>(documentRoot: Document, save: () => Promise<T>): Promise<T> {
  commitActiveInput(documentRoot);
  return save();
}

export function clearManualSaveFailure(documentRoot: Document): void {
  documentRoot.querySelector(SAVE_FAILURE_SELECTOR)?.remove();
}

/** Keep save errors visible and actionable without blocking further editing. */
export function showManualSaveFailure(documentRoot: Document, error: unknown): void {
  clearManualSaveFailure(documentRoot);

  const toast = documentRoot.createElement('div');
  toast.className = 'thalyx-toast thalyx-toast-error';
  toast.dataset['saveFailure'] = 'true';
  toast.setAttribute('role', 'alert');
  toast.setAttribute('aria-live', 'assertive');

  const message = documentRoot.createElement('span');
  message.textContent = failureMessage(error);

  const dismiss = documentRoot.createElement('button');
  dismiss.textContent = 'Dismiss';
  dismiss.onclick = () => toast.remove();

  toast.append(message, dismiss);
  documentRoot.body.append(toast);
}
