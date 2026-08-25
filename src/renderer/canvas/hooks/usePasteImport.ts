/**
 * Paste import (§9.7): on paste of mermaid-looking text onto the canvas,
 * import as a diagram (native or island) at the cursor + toast with an
 * undo escape hatch and a "paste as text instead" option. Plain text
 * becomes a text node.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { useReactFlow } from '@xyflow/react';
import { isProbablyMermaid } from '../../../shared/mermaid/detect';
import * as A from '../../store/actions';
import { parseMermaid } from '../../mermaid/runtime';

export function usePasteImport(): { toast: { message: string; onTextInstead: () => void } | null } {
  const rf = useReactFlow();
  const [toast, setToast] = useState<{ message: string; onTextInstead: () => void } | null>(null);
  const lastPasteRef = useRef<string | null>(null);

  const showToast = useCallback((message: string, onTextInstead: () => void) => {
    setToast({ message, onTextInstead });
    window.setTimeout(() => setToast(null), 6000);
  }, []);

  useEffect(() => {
    const onPaste = async (e: ClipboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (
        target &&
        (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable)
      ) {
        return; // editing contexts handle their own paste
      }
      const text = e.clipboardData?.getData('text/plain') ?? '';
      if (text.length === 0) return;

      if (isProbablyMermaid(text)) {
        e.preventDefault();
        const ok = await A.importMermaidAsNew(text, parseMermaid);
        if (ok) {
          lastPasteRef.current = text;
          void rf.fitView({ padding: 0.2, maxZoom: 1.25, duration: 200 });
          showToast('Imported Mermaid — ⌘Z to undo', () => {
            A.undo();
            A.addNode({ kind: 'text', x: 100, y: 100, label: text.slice(0, 4000) });
          });
        } else {
          // parse failed → plain text node (not mermaid after all)
          A.addNode({ kind: 'text', x: 100, y: 100, label: text.slice(0, 4000) });
        }
        return;
      }
      // plain text → text node at the viewport center
      const center = rf.screenToFlowPosition({
        x: window.innerWidth / 2,
        y: window.innerHeight / 2,
      });
      A.addNode({
        kind: 'text',
        x: Math.round(center.x - 80),
        y: Math.round(center.y - 12),
        label: text.slice(0, 4000),
      });
    };
    window.addEventListener('paste', onPaste);
    return () => window.removeEventListener('paste', onPaste);
  }, [rf, showToast]);

  return { toast };
}
