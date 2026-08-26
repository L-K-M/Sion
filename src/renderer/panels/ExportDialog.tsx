/**
 * Export dialog (PLAN.md §13): SVG / PNG (1x/2x) / PDF / Mermaid; background
 * choice; PNG font inlining handled by the pipeline (§13.2). Mod+Shift+E.
 */
import { useState } from 'react';
import { useStore } from '../store/store';
import * as A from '../store/actions';
import { platform } from '../platform/api';
import { mermaidText, pdfBlob, pngBlob, svgString } from '../export/pipeline';

export function ExportDialog() {
  const open = useStore((s) => s.session.exportDialogOpen);
  const doc = useStore((s) => s.doc);
  const [format, setFormat] = useState<'svg' | 'png' | 'pdf' | 'mmd'>('svg');
  const [scale, setScale] = useState<1 | 2>(2);
  const [background, setBackground] = useState<'light' | 'dark' | 'transparent'>('light');
  const [busy, setBusy] = useState(false);

  if (!open) return null;

  const doExport = async (): Promise<void> => {
    setBusy(true);
    try {
      if (format === 'mmd') {
        const text = mermaidText(doc);
        await platform.dialog.saveFile('diagram.mmd', text, [
          { name: 'Mermaid', extensions: ['mmd'] },
        ]);
      } else if (format === 'svg') {
        const svg = await svgString(doc, { background });
        await platform.dialog.saveFile('diagram.svg', svg, [{ name: 'SVG', extensions: ['svg'] }]);
      } else if (format === 'png') {
        const blob = await pngBlob(doc, scale, background);
        // Electron save dialogs only accept text via this bridge — PNGs use
        // the platform clip.writePng path for clipboard or the browser
        // download anchor (both available everywhere); a native binary
        // save-file IPC lands with M8 polish if needed.
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = 'diagram.png';
        a.click();
      } else {
        const blob = await pdfBlob(doc, background === 'transparent' ? 'light' : background);
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = 'diagram.pdf';
        a.click();
      }
      A.setExportDialogOpen(false);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="thalyx-help-backdrop" onClick={() => A.setExportDialogOpen(false)}>
      <div
        className="thalyx-export-dialog"
        role="dialog"
        aria-label="Export"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="thalyx-panel-title">Export</div>
        <div className="thalyx-panel-row">
          <span className="thalyx-panel-label">Format</span>
          <div className="thalyx-seg-group" role="group" aria-label="Format">
            {(['svg', 'png', 'pdf', 'mmd'] as const).map((f) => (
              <button
                key={f}
                className="thalyx-seg"
                aria-pressed={format === f}
                onClick={() => setFormat(f)}
              >
                {f.toUpperCase()}
              </button>
            ))}
          </div>
        </div>
        {format === 'png' ? (
          <div className="thalyx-panel-row">
            <span className="thalyx-panel-label">Scale</span>
            <div className="thalyx-seg-group" role="group" aria-label="Scale">
              {([1, 2] as const).map((s) => (
                <button
                  key={s}
                  className="thalyx-seg"
                  aria-pressed={scale === s}
                  onClick={() => setScale(s)}
                >
                  {s}×
                </button>
              ))}
            </div>
          </div>
        ) : null}
        {format !== 'mmd' ? (
          <div className="thalyx-panel-row">
            <span className="thalyx-panel-label">Background</span>
            <div className="thalyx-seg-group" role="group" aria-label="Background">
              {(['light', 'dark', 'transparent'] as const).map((b) => (
                <button
                  key={b}
                  className="thalyx-seg"
                  aria-pressed={background === b}
                  onClick={() => setBackground(b)}
                >
                  {b}
                </button>
              ))}
            </div>
          </div>
        ) : null}
        <div className="thalyx-island-editor-actions">
          <button onClick={() => A.setExportDialogOpen(false)}>Cancel</button>
          <button disabled={busy} onClick={() => void doExport()}>
            {busy ? 'Exporting…' : 'Export'}
          </button>
        </div>
      </div>
    </div>
  );
}
