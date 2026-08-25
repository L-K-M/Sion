/**
 * MermaidIslandNode (§9.8): renders mermaidSource via mermaid.render,
 * sanitizes with DOMPurify (SVG profile, foreignObject forbidden), injects,
 * sizes from the SVG viewBox. Double-click opens the modal editor (M5 stub:
 * a plain prompt-less dialog lands with the panel work in M6 — the dialog
 * itself is part of this milestone).
 */
import { memo, useEffect, useRef, useState } from 'react';
import DOMPurify from 'dompurify';
import mermaid from '../../mermaid/runtime';
import type { ThalyxNode } from '../../../shared/model/types';
import type { ThalyxNodeData } from '../rfSelectors';
import { useStore } from '../../store/store';
import * as A from '../../store/actions';

export const MermaidIslandNode = memo(function MermaidIslandNode({ data }: { data?: unknown }) {
  const node = (data as ThalyxNodeData | undefined)?.node as ThalyxNode | undefined;
  const editing = useStore((s) => s.session.editingLabel);
  const [rendered, setRendered] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const idRef = useRef(`island-${node?.id ?? 'x'}`);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!node?.mermaidSource) return;
      setRendered(null); // stale SVG must not linger during re-render
      setError(null);
      try {
        const { svg } = await mermaid.render(idRef.current, node.mermaidSource);
        const clean = DOMPurify.sanitize(svg, {
          USE_PROFILES: { svg: true },
          FORBID_TAGS: ['foreignObject'],
        });
        if (!cancelled) {
          setRendered(clean);
          setError(null);
        }
      } catch (e) {
        if (!cancelled) setError(String((e as Error).message ?? e));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [node?.mermaidSource]);

  if (!node) return null;
  return (
    <div className="thalyx-island" style={{ width: '100%', height: '100%', position: 'relative' }}>
      {rendered ? (
        <div
          className="thalyx-island-svg"
          // DOMPurify-sanitized SVG (§14.3) after mermaid's own strict mode
          dangerouslySetInnerHTML={{ __html: rendered }}
        />
      ) : (
        <div className="thalyx-island-placeholder">
          {error ? `Parse error: ${error.slice(0, 120)}` : 'Rendering…'}
        </div>
      )}
      {editing?.kind === 'node' && editing.id === node.id ? <IslandEditor node={node} /> : null}
    </div>
  );
});

function IslandEditor({ node }: { node: ThalyxNode }) {
  const [text, setText] = useState(node.mermaidSource ?? '');
  return (
    <div
      className="thalyx-island-editor"
      role="dialog"
      aria-label="Edit Mermaid source"
      onPointerDown={(e) => e.stopPropagation()}
    >
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        spellCheck={false}
        aria-label="Mermaid source"
      />
      <div className="thalyx-island-editor-actions">
        <button
          onClick={() => {
            A.updateNodeMermaidSource(node.id, text);
            A.setEditingLabel(null);
          }}
        >
          Apply
        </button>
        <button onClick={() => A.setEditingLabel(null)}>Cancel</button>
      </div>
    </div>
  );
}
