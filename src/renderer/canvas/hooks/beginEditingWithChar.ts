import * as A from '../../store/actions';

/** Start editing with an initial character after the editor mounts. */
export function beginEditingWithChar(kind: 'node' | 'edge', id: string, character: string): void {
  A.setEditingLabel({ kind, id });

  requestAnimationFrame(() => {
    const editor = document.activeElement as HTMLTextAreaElement | null;
    if (!editor?.classList.contains('thalyx-label-editor')) return;

    editor.value = character;
    editor.setSelectionRange(character.length, character.length);
  });
}
