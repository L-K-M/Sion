/**
 * jsdom shim (PLAN.md §9.1): install globals BEFORE dynamically importing
 * mermaid — a static import hoists above this and fails (dompurify captures
 * globalThis.window at module-eval time).
 */
import { JSDOM } from 'jsdom';

let installed = false;

export async function importMermaidModule(): Promise<typeof import('mermaid').default> {
  if (!installed) {
    const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
      url: 'https://localhost/',
    });
    globalThis.window = dom.window as unknown as Window & typeof globalThis;
    globalThis.document = dom.window.document;
    installed = true;
  }
  return (await import('mermaid')).default;
}

export interface ShimParse {
  ok: true;
  diagramType: string;
  db: unknown;
}

/** parseMermaid equivalent for tests — D9 sequence over the shimmed module. */
export async function shimParse(
  text: string,
): Promise<
  | ShimParse
  | { ok: false; error: { message: string; line?: number; col?: number; expected?: string[] } }
> {
  const mermaid = await importMermaidModule();
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    htmlLabels: false,
    flowchart: { htmlLabels: false },
    theme: 'neutral',
  });
  try {
    await mermaid.parse(text); // throws with hash.loc on invalid input
    const diagram = await mermaid.mermaidAPI.getDiagramFromText(text);
    return { ok: true, diagramType: diagram.type, db: diagram.db };
  } catch (e: unknown) {
    const err = e as {
      message?: string;
      hash?: { loc?: { first_line?: number; first_column?: number }; expected?: string[] };
    };
    return {
      ok: false,
      error: {
        message: String(err.message ?? e),
        line: err.hash?.loc?.first_line,
        col: err.hash?.loc?.first_column,
        expected: err.hash?.expected,
      },
    };
  }
}
