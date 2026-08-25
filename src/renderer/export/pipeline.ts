/**
 * Export pipeline (PLAN.md §13.2/13.3): SVG / PNG (1x/2x, font inlined) /
 * PDF (svg2pdf + bundled Inter) / clipboard flavors. Runs in the renderer.
 */
import { renderDocToSvg, type RenderSvgOptions } from '../../shared/export/svg';
import { serializeDoc } from '../../shared/files/thalyxFile';
import { exportMermaid } from '../../shared/mermaid/export';
import type { ThalyxDoc } from '../../shared/model/types';

export interface ExportRequest {
  format: 'svg' | 'png' | 'pdf' | 'mmd';
  scale?: 1 | 2;
  background: 'light' | 'dark' | 'transparent';
}

export interface IslandSvgProvider {
  /** cached, DOMPurify-sanitized SVG per island node id (§13.1) */
  (nodeId: string): string | undefined;
}

async function inlineInterFont(svg: string): Promise<string> {
  // PNG rasterization path only (§13.2): inject the bundled Inter woff2 as a
  // data: URI — the isolated SVG-in-<img> context cannot see document fonts.
  try {
    const url = new URL('../theme/fonts/inter-regular.woff2', import.meta.url);
    const res = await fetch(url);
    const buf = await res.arrayBuffer();
    const b64 = btoa(String.fromCharCode(...new Uint8Array(buf)));
    return svg.replace(
      /(<svg[^>]*>)/,
      `$1<defs><style>@font-face{font-family:'Inter';src:url(data:font/woff2;base64,${b64}) format('woff2');}</style></defs>`,
    );
  } catch {
    return svg; // font unavailable → rasterizer falls back; acceptable dev path
  }
}

export async function svgString(
  doc: ThalyxDoc,
  opts: RenderSvgOptions & { islandSvgsProvider?: IslandSvgProvider },
): Promise<string> {
  const islandSvgs: Record<string, string> = {};
  for (const n of doc.nodes) {
    if (n.kind === 'mermaid' && opts.islandSvgsProvider) {
      const cached = opts.islandSvgsProvider(n.id);
      if (cached) islandSvgs[n.id] = cached;
    }
  }
  return renderDocToSvg(doc, { ...opts, islandSvgs });
}

export async function pngBlob(
  doc: ThalyxDoc,
  scale: 1 | 2,
  background: 'light' | 'dark' | 'transparent',
  islandSvgsProvider?: IslandSvgProvider,
): Promise<Blob> {
  let svg = await svgString(doc, { background, islandSvgsProvider });
  svg = await inlineInterFont(svg);
  const blob = new Blob([svg], { type: 'image/svg+xml' });
  const url = URL.createObjectURL(blob);
  try {
    const img = new Image();
    img.decoding = 'sync';
    await new Promise<void>((resolve, reject) => {
      img.onload = () => resolve();
      img.onerror = () => reject(new Error('SVG rasterization failed'));
      img.src = url;
    });
    const vb = svg.match(/viewBox="([-\d.]+) ([-\d.]+) ([\d.]+) ([\d.]+)"/);
    const nums = vb ? vb.map(Number) : [0, 0, 640, 480];
    const vw = nums[2] ?? 640;
    const vh = nums[3] ?? 480;
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(vw * scale);
    canvas.height = Math.round(vh * scale);
    const ctx = canvas.getContext('2d')!;
    ctx.scale(scale, scale);
    ctx.drawImage(img, 0, 0, vw!, vh!);
    return await new Promise<Blob>((resolve, reject) =>
      canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('toBlob failed'))), 'image/png'),
    );
  } finally {
    URL.revokeObjectURL(url);
  }
}

export async function pdfBlob(
  doc: ThalyxDoc,
  background: 'light' | 'dark',
  islandSvgsProvider?: IslandSvgProvider,
): Promise<Blob> {
  const { default: jsPDF } = await import('jspdf');
  await import('svg2pdf.js'); // registers jsPDF.API.svg
  const svg = await svgString(doc, { background, islandSvgsProvider });
  const vb = svg.match(/viewBox="([-\d.]+) ([-\d.]+) ([\d.]+) ([\d.]+)"/);
  const nums = vb ? vb.map(Number) : [0, 0, 640, 480];
  const vw = nums[2] ?? 640;
  const vh = nums[3] ?? 480;
  const pdf = new jsPDF({
    unit: 'pt',
    format: [vw, vh],
    orientation: vw > vh ? 'landscape' : 'portrait',
  });
  // register the bundled Inter TTF (D19) — best-effort; built-ins otherwise
  try {
    const url = new URL('../theme/fonts/inter-regular.ttf', import.meta.url);
    const res = await fetch(url);
    const buf = new Uint8Array(await res.arrayBuffer());
    pdf.addFileToVFS('inter-regular.ttf', btoa(String.fromCharCode(...buf)));
    pdf.addFont('inter-regular.ttf', 'Inter', 'normal');
  } catch {
    // fall back to helvetica (documented §13 limitation)
  }
  const el = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  el.innerHTML = svg.replace(/^<svg[^>]*>/, '').replace(/<\/svg>$/, '');
  el.setAttribute('width', String(vw));
  el.setAttribute('height', String(vh));
  document.body.appendChild(el);
  try {
    await (
      pdf as unknown as { svg(el: Element, o: { width: number; height: number }): Promise<void> }
    ).svg(el, { width: vw, height: vh });
  } finally {
    el.remove();
  }
  return pdf.output('blob');
}

export function mermaidText(doc: ThalyxDoc): string {
  return exportMermaid(doc).text;
}

/** Internal clipboard flavor (§13.3): text/plain carries BOTH thalyx JSON and
 *  falls back to mermaid for foreign pastes. PNG via ClipboardItem. */
export async function writeInternalClipboard(
  doc: ThalyxDoc,
  nodeIds: string[],
  edgeIds: string[],
): Promise<void> {
  const include = new Set(nodeIds);
  const nodes = doc.nodes.filter((n) => include.has(n.id));
  const nodeIdsSet = new Set(nodes.map((n) => n.id));
  const edges = doc.edges.filter(
    (e) => nodeIdsSet.has(e.source) && nodeIdsSet.has(e.target) && edgeIds.includes(e.id),
  );
  const payload = JSON.stringify({ type: 'thalyx/clipboard', version: 1, nodes, edges });
  try {
    const png = await pngBlob(doc, 1, 'light');
    await navigator.clipboard.write([
      new ClipboardItem({
        'text/plain': new Blob([payload], { type: 'text/plain' }),
        'image/png': png,
      }),
    ]);
  } catch {
    await navigator.clipboard.writeText(payload).catch(() => undefined);
  }
}

export function thalyxClipboardDocFile(doc: ThalyxDoc): string {
  return serializeDoc(doc);
}
