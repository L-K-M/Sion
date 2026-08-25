import { describe, expect, it } from 'vitest';
import {
  canonicalizeHeads,
  EDGE_STROKE_TO_LINE,
  EDGE_TYPE_TO_HEADS,
  EMIT_TABLE,
  extendBody,
  MERMAID_ID_BLOCKLIST,
  SHAPE_TO_BRACKETS,
  VERTEX_TYPE_TO_SHAPE,
} from '../../../src/shared/mermaid/tables';
import { decodeMermaidLabel, encodeLabel } from '../../../src/shared/mermaid/entities';
import { isProbablyMermaid } from '../../../src/shared/mermaid/detect';

describe('mermaid tables (§9.2)', () => {
  it('vertex type table covers the §7.3 mapping', () => {
    expect(VERTEX_TYPE_TO_SHAPE['square']).toBe('rect');
    expect(VERTEX_TYPE_TO_SHAPE['round']).toBe('rounded');
    expect(VERTEX_TYPE_TO_SHAPE['lean_right']).toBe('parallelogram');
    expect(VERTEX_TYPE_TO_SHAPE['inv_trapezoid']).toBe('trapezoid-alt');
    expect(VERTEX_TYPE_TO_SHAPE['odd']).toBe('asymmetric');
  });

  it('arrow heads: two orthogonal lookups compose (-.-o)', () => {
    const heads = EDGE_TYPE_TO_HEADS['arrow_circle'];
    const dotted = EDGE_STROKE_TO_LINE['dotted']!;
    const [line, hidden] = dotted;
    expect(heads).toEqual(['none', 'circle']);
    expect(line).toBe('dashed');
    expect(hidden).toBe(false);
  });

  it('invisible edges map to solid+hidden', () => {
    expect(EDGE_STROKE_TO_LINE['invisible']).toEqual(['solid', true]);
  });

  it('emit table has exactly 21 bodies + degrade canonicalization', () => {
    const all = Object.values(EMIT_TABLE).flatMap((row) => Object.values(row));
    expect(all).toHaveLength(21);
    expect(all).toContain('-->');
    expect(all).toContain('x-.-x');
    // degrade: asymmetric pairs collapse to (none, end)
    expect(canonicalizeHeads('circle', 'arrow')).toEqual(['none', 'arrow']);
    expect(canonicalizeHeads('arrow', 'arrow')).toEqual(['arrow', 'arrow']);
    expect(canonicalizeHeads('none', 'cross')).toEqual(['none', 'cross']);
  });

  it('extendBody repeats the middle char (verified minlen-2 bodies)', () => {
    expect(extendBody('-->', 2)).toBe('--->');
    expect(extendBody('----', 2)).toBe('-----');
    expect(extendBody('-.->', 2)).toBe('-..->');
    expect(extendBody('-..-', 2)).toBe('-...-');
    expect(extendBody('==>', 2)).toBe('===>');
    expect(extendBody('====', 2)).toBe('=====');
    expect(extendBody('~~~', 2)).toBe('~~~~~~');
    // bidirectional thick/dashed bodies (regression: head chars o/x broke middle detection)
    expect(extendBody('o==o', 2)).toBe('o===o');
    expect(extendBody('x==x', 2)).toBe('x===x');
    expect(extendBody('o-.-o', 2)).toBe('o-..-o');
    expect(extendBody('x-.-x', 2)).toBe('x-..-x');
    // no extension at minlen 1
    expect(extendBody('-->', 1)).toBe('-->');
  });

  it('shape→brackets inverts the vertex table', () => {
    expect(SHAPE_TO_BRACKETS['cylinder']).toEqual(['[(', ')]']);
    expect(SHAPE_TO_BRACKETS['trapezoid']).toEqual(['[/', '\\]']);
    expect(SHAPE_TO_BRACKETS['asymmetric']).toEqual(['>', ']']);
  });

  it('id blocklist is the verified set', () => {
    expect(MERMAID_ID_BLOCKLIST).toContain('end');
    expect(MERMAID_ID_BLOCKLIST).not.toContain('End');
  });
});

describe('entity decode/encode (§9.2 gotcha)', () => {
  it('decodes #quot; placeholders (verified raw: ﬂ°quot¶ß)', () => {
    // db raw text for A["say #quot;hi#quot;"] is 'say ﬂ°quot¶ßhiﬂ°quot¶ß';
    // placeholder pass → '&quot;' → one entity pass → '"'.
    expect(decodeMermaidLabel('say ﬂ°quot¶ßhiﬂ°quot¶ß')).toBe(
      'say ' + String.fromCharCode(34) + 'hi' + String.fromCharCode(34),
    );
  });

  it('ONE entity pass — &amp;lt; does NOT double-decode', () => {
    expect(decodeMermaidLabel('5 &amp;lt; 6')).toBe('5 &lt; 6');
  });

  it('numeric entities decode', () => {
    expect(decodeMermaidLabel('&#9829;')).toBe('\u2665');
  });

  it('<br> variants become newline', () => {
    expect(decodeMermaidLabel('line1<br>line2')).toBe('line1\nline2');
    expect(decodeMermaidLabel('line1<br/>line2')).toBe('line1\nline2');
    expect(decodeMermaidLabel('line1<BR />line2')).toBe('line1\nline2');
  });

  it('encode order interaction: # escaped before & so entities stay literal', () => {
    // '#' first means an encoded '#38;' is never re-escaped by the & pass
    const encoded = encodeLabel('a & b');
    expect(encoded).not.toContain('&&');
    expect(decodeMermaidLabel('a ﬂ°°38¶ß b')).toBe('a & b');
  });

  it('encodeLabel escapes in the verified order', () => {
    expect(encodeLabel('AT&T')).toBe('"AT#38;T"');
    expect(encodeLabel('say "hi"')).toBe('"say #quot;hi#quot;"');
    expect(encodeLabel('a#b')).toBe('"a#35;b"');
    expect(encodeLabel('l1\nl2')).toBe('"l1<br>l2"');
    // round trip: encode then placeholder+entity decode returns the original
    const original = '5 &lt; 6';
    const encoded = encodeLabel(original); // '"5 #38;lt; 6"'
    // db raw would be '5 ﬂ°°38¶ßlt; 6' → decode:
    expect(decodeMermaidLabel('5 ﬂ°°38¶ßlt; 6')).toBe(original);
    expect(encoded).toBe('"5 #38;lt; 6"');
  });
});

describe('isProbablyMermaid (§9.7)', () => {
  it('accepts known headers', () => {
    expect(isProbablyMermaid('flowchart TB\n  A-->B')).toBe(true);
    expect(isProbablyMermaid('graph TD\n  A-->B')).toBe(true);
    expect(isProbablyMermaid('sequenceDiagram\n  A->>B: hi')).toBe(true);
    expect(isProbablyMermaid('stateDiagram-v2\n  [*] --> A')).toBe(true);
  });

  it('skips frontmatter and %% directives', () => {
    expect(isProbablyMermaid('---\ntitle: x\n---\nflowchart TB\n  A-->B')).toBe(true);
    expect(isProbablyMermaid('%%{init: {"theme":"dark"}}%%\nflowchart TB\n  A-->B')).toBe(true);
    expect(isProbablyMermaid('%% just a comment\ngraph LR\n  A-->B')).toBe(true);
  });

  it('rejects plain text and code', () => {
    expect(isProbablyMermaid('hello world')).toBe(false);
    expect(isProbablyMermaid('const x = 1;')).toBe(false);
    expect(isProbablyMermaid('')).toBe(false);
  });
});
