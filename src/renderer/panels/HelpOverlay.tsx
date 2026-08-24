/**
 * HelpOverlay (PLAN.md §10.2): Shift+/ opens a searchable shortcut sheet.
 */
import { memo, useEffect, useMemo, useState } from 'react';
import { useStore } from '../store/store';
import * as A from '../store/actions';

interface Shortcut {
  keys: string;
  action: string;
  group: string;
}

const SHORTCUTS: Shortcut[] = [
  { keys: 'V / 1', action: 'Select tool', group: 'Tools' },
  { keys: 'R / 2', action: 'Rectangle', group: 'Tools' },
  { keys: 'O / 3', action: 'Ellipse', group: 'Tools' },
  { keys: 'D / 4', action: 'Diamond', group: 'Tools' },
  { keys: 'A / 5', action: 'Arrow connector', group: 'Tools' },
  { keys: 'L / 6', action: 'Line (no arrowheads)', group: 'Tools' },
  { keys: 'T / 7', action: 'Text', group: 'Tools' },
  { keys: 'F / 8', action: 'Container / frame', group: 'Tools' },
  { keys: 'H', action: 'Hand tool (hold Space for temporary)', group: 'Tools' },
  { keys: 'Q', action: 'Toggle quick-connect chevrons', group: 'Tools' },
  { keys: 'type any letter', action: 'Edit the selected node’s label', group: 'Editing' },
  { keys: 'Enter', action: 'Edit label of selection', group: 'Editing' },
  { keys: 'Esc', action: 'Commit + deselect', group: 'Editing' },
  { keys: 'Mod+Arrow', action: 'Grow: new connected node in that direction', group: 'Editing' },
  { keys: 'Tab', action: 'Cycle shape while growing', group: 'Editing' },
  { keys: 'Mod+D / Alt+drag', action: 'Duplicate', group: 'Editing' },
  { keys: 'Delete / Backspace', action: 'Delete selection', group: 'Editing' },
  { keys: 'Mod+A', action: 'Select all', group: 'Selection' },
  { keys: 'Arrow / Shift+Arrow', action: 'Nudge 1 px / 8 px', group: 'Selection' },
  { keys: 'Mod+G / Mod+Shift+G', action: 'Group into container / dissolve', group: 'Selection' },
  { keys: 'Mod+[ · Mod+]', action: 'Z-order back / forward one', group: 'Selection' },
  { keys: 'Mod+Shift+[ · Mod+Shift+]', action: 'Z-order to back / to front', group: 'Selection' },
  { keys: 'Mod+Z / Mod+Shift+Z', action: 'Undo / redo', group: 'History' },
  { keys: 'Mod+Y', action: 'Redo', group: 'History' },
  { keys: 'Shift+1 / Shift+2', action: 'Zoom to fit / to selection', group: 'View' },
  { keys: 'Mod+= · Mod+- · Mod+0', action: 'Zoom in / out / 100%', group: 'View' },
  { keys: 'Shift+Alt+D', action: 'Toggle theme', group: 'View' },
  { keys: 'Mod+scroll / pinch', action: 'Zoom at cursor', group: 'View' },
  { keys: 'Space-drag · middle/right-drag', action: 'Pan', group: 'View' },
  { keys: 'Alt+Shift+L', action: 'Auto-layout (one shot)', group: 'Layout' },
  { keys: 'Alt+Shift+T', action: 'Tidy Up selection', group: 'Layout' },
  { keys: 'Mod+Shift+M', action: 'Toggle Mermaid panel', group: 'Mermaid' },
  { keys: 'Mod+Shift+C', action: 'Copy as Mermaid', group: 'Mermaid' },
  { keys: 'Shift+/', action: 'This help', group: 'Help' },
];

export const HelpOverlay = memo(function HelpOverlay() {
  const open = useStore((s) => s.session.helpOpen);
  const [query, setQuery] = useState('');
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return SHORTCUTS;
    return SHORTCUTS.filter(
      (s) =>
        s.action.toLowerCase().includes(q) ||
        s.keys.toLowerCase().includes(q) ||
        s.group.toLowerCase().includes(q),
    );
  }, [query]);

  useEffect(() => {
    if (!open) setQuery('');
  }, [open]);

  if (!open) return null;
  return (
    <div className="thalyx-help-backdrop" onClick={() => A.setHelpOpen(false)}>
      <div
        className="thalyx-help"
        role="dialog"
        aria-label="Keyboard shortcuts"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          if (e.key === 'Escape') A.setHelpOpen(false);
        }}
      >
        <div className="thalyx-help-head">
          <input
            autoFocus
            className="thalyx-help-search"
            placeholder="Search shortcuts…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Escape') A.setHelpOpen(false);
            }}
          />
          <button
            className="thalyx-toolbtn"
            onClick={() => A.setHelpOpen(false)}
            title="Close (Esc)"
          >
            ✕
          </button>
        </div>
        <div className="thalyx-help-list">
          {filtered.map((s) => (
            <div key={s.keys + s.action} className="thalyx-help-row">
              <span className="thalyx-help-group">{s.group}</span>
              <kbd>{s.keys}</kbd>
              <span>{s.action}</span>
            </div>
          ))}
          {filtered.length === 0 ? <div className="thalyx-help-empty">No matches</div> : null}
        </div>
      </div>
    </div>
  );
});
