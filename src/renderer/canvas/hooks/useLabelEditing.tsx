/**
 * Inline label editor (PLAN.md §10 I10): textarea-in-node on double-click /
 * Enter / type-to-edit. IME-safe: `isComposing` presses never commit; Esc
 * commits and deselects; blur commits. Multi-line labels join with '\n'.
 */
import { useEffect, useRef } from 'react';

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
