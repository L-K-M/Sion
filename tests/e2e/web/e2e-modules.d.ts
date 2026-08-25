// Virtual modules served by vite.preview.config.ts for the e2e export suite.
declare module '__thalyx-svg' {
  export function renderDocToSvg(doc: unknown, opts: unknown): string;
}
declare module '__thalyx-pipeline' {
  export function pngBlob(doc: unknown, scale: 1 | 2, background: string): Promise<Blob>;
  export function pdfBlob(doc: unknown, background: string): Promise<Blob>;
  export function writeInternalClipboard(
    doc: unknown,
    nodeIds: string[],
    edgeIds: string[],
  ): Promise<void>;
}
