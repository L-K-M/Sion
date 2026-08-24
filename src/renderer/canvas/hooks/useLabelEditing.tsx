/**
 * Inline label editor (PLAN.md §10 I10): textarea-in-node on double-click /
 * Enter / type-to-edit. IME-safe: `isComposing` presses never commit; Esc
 * commits and deselects; blur commits. Multi-line labels join with '\n'.
 */
import { useEffect, useRef } from 'react';
import * as A from '../../store/actions';

/**
 * The textarea itself — rendered inside the node component.
 */
export function LabelTextarea({
  value,
  onCommit,
  fontSize,
  onCancel,
}: {
  value: string;
  onCommit: (next: string) => void;
  onCancel: () => void;
  fontSize: number;
}) {
  const ref = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    el.focus();
    el.select();
  }, []);

  return (
    <textarea
      ref={ref}
      className="thalyx-label-editor nodrag nopan"
      defaultValue={value}
      style={{ fontSize }}
      spellCheck={false}
      onPointerDown={(e) => e.stopPropagation()}
      onKeyDown={(e) => {
        if (e.nativeEvent.isComposing) return; // IME safety (I10)
        e.stopPropagation();
        if (e.code === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          onCommit((e.target as HTMLTextAreaElement).value);
        } else if (e.code === 'Escape') {
          e.preventDefault();
          onCommit((e.target as HTMLTextAreaElement).value);
          onCancel();
        }
      }}
      onBlur={(e) => onCommit(e.target.value)}
    />
  );
}

/** Start editing with an initial character (type-to-edit precedence, §10.2). */
export function beginEditingWithChar(kind: 'node' | 'edge', id: string, ch: string): void {
  A.setEditingLabel({ kind, id });
  void kind;
  // The char lands after the textarea mounts (focus + setRangeText).
  requestAnimationFrame(() => {
    const el = document.activeElement as HTMLTextAreaElement | null;
    if (el && el.classList.contains('thalyx-label-editor')) {
      el.value = ch;
      el.setSelectionRange(ch.length, ch.length);
    }
  });
}
