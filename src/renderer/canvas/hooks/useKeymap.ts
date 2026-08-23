/**
 * Minimal keymap for M2 (full §10.2 keymap lands in M4): tool keys,
 * delete, undo/redo, zoom-to-fit/selection. Ignores keys while typing in an
 * input/textarea/contentEditable or while composing (§10.2 matching rules).
 */
import { useEffect } from 'react';
import { useReactFlow } from '@xyflow/react';
import { useStore } from '../../store/store';
import * as A from '../../store/actions';
import type { ShapeKind, Tool } from '../../../shared/model/types';

function isTypingTarget(e: KeyboardEvent): boolean {
  const t = e.target as HTMLElement | null;
  if (!t) return false;
  const tag = t.tagName;
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || t.isContentEditable;
}

export function useKeymap(): void {
  const rf = useReactFlow();

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.isComposing) return;
      const mod = e.metaKey || e.ctrlKey;

      if (isTypingTarget(e)) {
        // Only Esc / Mod+Enter-style escapes are honored while typing (none in M2).
        return;
      }

      if (mod && !e.altKey && e.code === 'KeyZ') {
        e.preventDefault();
        if (e.shiftKey) A.redo();
        else A.undo();
        return;
      }
      if (mod && !e.altKey && e.code === 'KeyY') {
        e.preventDefault();
        A.redo();
        return;
      }
      if ((e.code === 'Delete' || e.code === 'Backspace') && !mod) {
        e.preventDefault();
        A.deleteSelection();
        return;
      }

      // Zoom-to-fit / zoom-to-selection (Shift+digit chords match on e.code —
      // Shift+1 produces e.key '!' everywhere).
      if (e.shiftKey && !mod && !e.altKey && e.code === 'Digit1') {
        e.preventDefault();
        void rf.fitView({ padding: 0.2, maxZoom: 1.25, duration: 200 });
        return;
      }
      if (e.shiftKey && !mod && !e.altKey && e.code === 'Digit2') {
        e.preventDefault();
        const { nodeIds } = useStore.getState().session.selection;
        if (nodeIds.length > 0) {
          void rf.fitView({ nodes: [{ id: nodeIds[0]! }], padding: 2, duration: 200 });
        } else {
          void rf.fitView({ padding: 0.2, duration: 200 });
        }
        return;
      }

      if (mod || e.altKey) return; // tool keys are bare letters

      const toolKeys: Record<string, () => void> = {
        KeyV: () => A.setTool('select' as Tool),
        KeyR: () => {
          A.setPendingShape('rect' as ShapeKind);
          A.setTool('shape' as Tool);
        },
        KeyO: () => {
          A.setPendingShape('ellipse' as ShapeKind);
          A.setTool('shape' as Tool);
        },
        KeyD: () => {
          A.setPendingShape('diamond' as ShapeKind);
          A.setTool('shape' as Tool);
        },
        KeyH: () => A.setTool('hand' as Tool),
        KeyT: () => A.setTool('text' as Tool),
      };
      const action = toolKeys[e.code];
      if (action) {
        e.preventDefault();
        action();
      }
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [rf]);
}
