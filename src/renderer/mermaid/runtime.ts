/**
 * Mermaid runtime for the RENDERER (PLAN.md §9.1). D10: htmlLabels always off.
 * D9: parse-first init sequence (parse registers lazy detectors, then
 * getDiagramFromText yields {type, db}).
 */
import mermaid, { type MermaidConfig } from 'mermaid';

mermaid.initialize({
  startOnLoad: false,
  securityLevel: 'strict',
  htmlLabels: false,
  flowchart: { htmlLabels: false },
  theme: 'neutral',
});

export interface ParsedMermaid {
  ok: true;
  diagramType: string;
  config: MermaidConfig;
  db: unknown;
}

export interface MermaidParseError {
  ok: false;
  error: { message: string; line?: number; col?: number; expected?: string[] };
}

export type ParseResult = ParsedMermaid | MermaidParseError;

export async function parseMermaid(text: string): Promise<ParseResult> {
  const res = await mermaid.parse(text, { suppressErrors: true });
  if (res === false) {
    try {
      await mermaid.parse(text);
    } catch (e: unknown) {
      const err = e as {
        message?: string;
        hash?: { loc?: { first_line?: number; first_column?: number }; expected?: string[] };
      };
      const loc = err.hash?.loc;
      return {
        ok: false,
        error: {
          message: String(err.message ?? e),
          line: loc?.first_line,
          col: loc?.first_column,
          expected: err.hash?.expected,
        },
      };
    }
    return { ok: false, error: { message: 'Invalid mermaid text' } };
  }
  try {
    const diagram = await mermaid.mermaidAPI.getDiagramFromText(text);
    return {
      ok: true,
      diagramType: diagram.type,
      config: res.config ?? {},
      db: diagram.db,
    };
  } catch (e) {
    // parse() accepted it but lazy diagram init failed — same error contract
    const err = e as {
      message?: string;
      hash?: { loc?: { first_line?: number; first_column?: number }; expected?: string[] };
    };
    const loc = err.hash?.loc;
    return {
      ok: false,
      error: {
        message: String(err.message ?? e),
        line: loc?.first_line,
        col: loc?.first_column,
        expected: err.hash?.expected,
      },
    };
  }
}

export default mermaid;
