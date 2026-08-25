/**
 * MermaidPanel (§9.5): right-side collapsible panel — live read-only export
 * (debounced 300 ms), copy, island notice, direction dropdown.
 * Edit mode + Apply/reconcile land with M8 per the milestone sequence.
 */
import { memo, useEffect, useMemo, useRef, useState } from 'react';
import { useStore } from '../store/store';
import * as A from '../store/actions';
import { exportMermaid } from '../../shared/mermaid/export';

export const MermaidPanel = memo(function MermaidPanel() {
  const open = useStore((s) => s.session.mermaidPanelOpen);
  const doc = useStore((s) => s.doc);
  const [text, setText] = useState('');
  const [islandNotice, setIslandNotice] = useState<number | null>(null);
  const timer = useRef<number | null>(null);

  useEffect(() => {
    if (!open) return;
    if (timer.current !== null) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      const out = exportMermaid(doc);
      setText(out.text);
      // untracked id assignments (§8.3/§9.4) — never a history entry
      A.ensureMermaidIds(out.idAssignments);
      const islands = doc.nodes.filter((n) => n.kind === 'mermaid');
      setIslandNotice(islands.length > 0 ? islands.length : null);
    }, 300);
    return () => {
      if (timer.current !== null) window.clearTimeout(timer.current);
    };
  }, [open, doc]);

  const headline = useMemo(() => {
    // single-island doc: the island's own source (§9.4)
    if (doc.nodes.length === 1 && doc.nodes[0]!.kind === 'mermaid') {
      return doc.nodes[0]!.mermaidSource ?? '';
    }
    return text;
  }, [doc, text]);

  if (!open) return null;

  return (
    <aside className="thalyx-mermaid-panel" aria-label="Mermaid source">
      <div className="thalyx-mermaid-head">
        <span>Mermaid</span>
        <div className="thalyx-mermaid-head-actions">
          <select
            className="thalyx-panel-select"
            value={doc.meta.mermaid?.direction ?? 'TB'}
            onChange={(e) => A.setDirection(e.target.value as 'TB' | 'BT' | 'LR' | 'RL')}
            aria-label="Flow direction"
            title="Direction — an action, not a mode (§9.5)"
          >
            <option value="TB">TB ↓</option>
            <option value="BT">BT ↑</option>
            <option value="LR">LR →</option>
            <option value="RL">RL ←</option>
          </select>
          <button onClick={() => void A.copyAsMermaid()} title="Copy as Mermaid (Mod+Shift+C)">
            Copy
          </button>
          <button onClick={() => A.setMermaidPanelOpen(false)} title="Close (Mod+Shift+M)">
            ✕
          </button>
        </div>
      </div>
      {islandNotice !== null ? (
        <div className="thalyx-mermaid-notice" role="status">
          {islandNotice} mermaid island{islandNotice > 1 ? 's' : ''} not included
        </div>
      ) : null}
      <pre className="thalyx-mermaid-text" aria-readonly="true">
        {headline}
      </pre>
    </aside>
  );
});
