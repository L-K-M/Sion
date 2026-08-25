/**
 * Keymap (PLAN.md §10.2, M4a scope; chevrons/grow/layout chords land in M4c).
 *
 * Matching rules (§10.2):
 *  - plain single letters match on e.code (layout-safe enough for tools here);
 *  - chords containing Alt, and Shift+digit/punctuation chords, match on
 *    e.code (macOS Option composes characters; Shift+1 → '!' everywhere);
 *  - ignored while composing or while an input/textarea/contentEditable has
 *    focus (except Esc);
 *  - type-to-edit precedence: printable key with a single NODE selected
 *    starts label editing with that character and suppresses tool bindings;
 *    Shift+digit (zoom) and Shift+/ (help) win via e.code first.
 */
import { useEffect } from 'react';
import { useReactFlow } from '@xyflow/react';
import { useStore } from '../../store/store';
import * as A from '../../store/actions';
import { beginEditingWithChar } from './useLabelEditing';
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

      if (isTypingTarget(e)) return; // the label editor handles its own keys

      // --- Mod chords -----------------------------------------------------
      if (mod && !e.altKey) {
        switch (e.code) {
          case 'KeyZ':
            e.preventDefault();
            if (e.shiftKey) A.redo();
            else A.undo();
            return;
          case 'KeyY':
            e.preventDefault();
            A.redo();
            return;
          case 'KeyD':
            e.preventDefault();
            A.duplicateSelection();
            return;
          case 'KeyG':
            e.preventDefault();
            if (e.shiftKey) A.dissolveContainer();
            else A.groupIntoContainer();
            return;
          case 'BracketLeft':
            e.preventDefault();
            A.reorderZ(e.shiftKey ? 'back' : 'backward');
            return;
          case 'BracketRight':
            e.preventDefault();
            A.reorderZ(e.shiftKey ? 'front' : 'forward');
            return;
          case 'KeyA':
            e.preventDefault();
            A.selectAll();
            return;
        }
        // Other Mod chords fall through (e.g. Mod+Arrow grow below); the
        // bare-tool section re-guards on `mod`.
      }

      // --- Delete ----------------------------------------------------------
      if ((e.code === 'Delete' || e.code === 'Backspace') && !mod && !e.altKey) {
        e.preventDefault();
        A.deleteSelection();
        return;
      }

      // --- Shift+digit / Shift+punctuation chords (match on e.code) --------
      if (e.shiftKey && !e.altKey) {
        if (e.code === 'Digit1') {
          e.preventDefault();
          void rf.fitView({ padding: 0.2, maxZoom: 1.25, duration: 200 });
          return;
        }
        if (e.code === 'Digit2') {
          e.preventDefault();
          const { nodeIds } = useStore.getState().session.selection;
          if (nodeIds.length > 0) {
            void rf.fitView({ nodes: nodeIds.map((id) => ({ id })), padding: 0.2, duration: 200 });
          } else {
            void rf.fitView({ padding: 0.2, duration: 200 });
          }
          return;
        }
        if (e.code === 'Slash') {
          e.preventDefault();
          A.setHelpOpen(!useStore.getState().session.helpOpen);
          return;
        }
        if (e.code.startsWith('Digit')) {
          // other digits: tool aliases below
        } else if (e.key.length === 1) {
          // Shift+letter: capitals — type-to-edit, not tools
          const sel = useStore.getState().session.selection;
          if (!mod && sel.nodeIds.length === 1 && sel.edgeIds.length === 0) {
            e.preventDefault();
            beginEditingWithChar('node', sel.nodeIds[0]!, e.key);
          }
          return;
        }
      }

      // --- Mod+Arrow: grow (§11.6) — gated while a label editor is open so
      // macOS caret navigation stays intact (§10.1 delta 1)
      if (
        mod &&
        !e.altKey &&
        ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)
      ) {
        const sel = useStore.getState().session;
        if (sel.editingLabel === null && sel.selection.nodeIds.length === 1) {
          e.preventDefault();
          const dir =
            e.code === 'ArrowUp'
              ? 'n'
              : e.code === 'ArrowDown'
                ? 's'
                : e.code === 'ArrowRight'
                  ? 'e'
                  : 'w';
          A.growConnectedNode(sel.selection.nodeIds[0]!, dir, {
            grid: useStore.getState().doc.canvas.grid,
          });
          return;
        }
        return;
      }

      // --- Alt+Shift chords for layout (§10.2: Alt chords match on e.code) ---
      if (e.altKey && e.shiftKey && !mod && e.code === 'KeyT') {
        e.preventDefault();
        A.tidyUpSelection();
        return;
      }
      if (e.altKey && e.shiftKey && !mod && e.code === 'KeyL') {
        e.preventDefault();
        A.autoLayout();
        return;
      }

      // --- Arrow keys: nudge ---
      if (
        e.code === 'ArrowUp' ||
        e.code === 'ArrowDown' ||
        e.code === 'ArrowLeft' ||
        e.code === 'ArrowRight'
      ) {
        if (
          e.key === 'ArrowUp' ||
          e.key === 'ArrowDown' ||
          e.key === 'ArrowLeft' ||
          e.key === 'ArrowRight'
        ) {
          const step = e.shiftKey ? 8 : 1;
          e.preventDefault();
          const map: Record<string, [number, number]> = {
            ArrowUp: [0, -step],
            ArrowDown: [0, step],
            ArrowLeft: [-step, 0],
            ArrowRight: [step, 0],
          };
          const [dx, dy] = map[e.key]!;
          A.nudgeSelection(dx, dy);
          return;
        }
      }

      // --- Enter: edit the single selection --------------------------------
      if (e.code === 'Enter' && !e.shiftKey) {
        const sel = useStore.getState().session.selection;
        if (sel.nodeIds.length === 1 && sel.edgeIds.length === 0) {
          e.preventDefault();
          A.setEditingLabel({ kind: 'node', id: sel.nodeIds[0]! });
          return;
        }
        return;
      }

      // --- Esc: commit + deselect -------------------------------------------
      if (e.code === 'Escape') {
        A.setEditingLabel(null);
        A.clearSelection();
        if (
          useStore.getState().session.tool !== 'select' &&
          !useStore.getState().session.toolLocked
        ) {
          A.setTool('select');
        }
        return;
      }

      // Shift+Alt+D: cycle theme (Alt chord → e.code matching, §10.2)
      if (e.altKey && e.shiftKey && !mod && e.code === 'KeyD') {
        e.preventDefault();
        const cycle = ['system', 'light', 'dark'] as const;
        const current = useStore.getState().session.theme;
        const next = cycle[(cycle.indexOf(current) + 1) % cycle.length]!;
        A.setTheme(next);
        return;
      }

      if (mod || e.altKey || e.shiftKey) return;

      // --- Type-to-edit precedence (printable char, single node selected) ---
      if (e.key.length === 1) {
        const sel = useStore.getState().session.selection;
        if (sel.nodeIds.length === 1 && sel.edgeIds.length === 0) {
          e.preventDefault();
          beginEditingWithChar('node', sel.nodeIds[0]!, e.key);
          return;
        }
      }

      // --- Tool keys (bare letters / digits) ---------------------------------
      const toolKeys: Record<string, () => void> = {
        KeyV: () => A.setTool('select' as Tool),
        Digit1: () => A.setTool('select' as Tool),
        KeyR: () => {
          A.setPendingShape('rect' as ShapeKind);
          A.setTool('shape' as Tool);
        },
        Digit2: () => {
          A.setPendingShape('rect' as ShapeKind);
          A.setTool('shape' as Tool);
        },
        KeyO: () => {
          A.setPendingShape('ellipse' as ShapeKind);
          A.setTool('shape' as Tool);
        },
        Digit3: () => {
          A.setPendingShape('ellipse' as ShapeKind);
          A.setTool('shape' as Tool);
        },
        KeyD: () => {
          A.setPendingShape('diamond' as ShapeKind);
          A.setTool('shape' as Tool);
        },
        Digit4: () => {
          A.setPendingShape('diamond' as ShapeKind);
          A.setTool('shape' as Tool);
        },
        KeyA: () => A.setTool('arrow' as Tool),
        Digit5: () => A.setTool('arrow' as Tool),
        KeyL: () => A.setTool('line' as Tool),
        Digit6: () => A.setTool('line' as Tool),
        KeyT: () => A.setTool('text' as Tool),
        Digit7: () => A.setTool('text' as Tool),
        KeyF: () => A.setTool('container' as Tool),
        Digit8: () => A.setTool('container' as Tool),
        KeyH: () => A.setTool('hand' as Tool),
        KeyQ: () => A.toggleChevrons(),
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
