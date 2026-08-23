// Task 3: encodeLabel round-trip reality with htmlLabels:false.
await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', htmlLabels: false, flowchart: { htmlLabels: false } });

const decodePlaceholders = (t) => t.replace(/ﬂ°°/g, '&#').replace(/ﬂ°/g, '&').replace(/¶ß/g, ';');

async function dumpVertex(label, line) {
  const text = 'flowchart TD\n  ' + line + '\n';
  let res;
  try { res = await mermaid.parse(text, { suppressErrors: true }); } catch (e) { res = 'THROWN:' + e.message; }
  if (res === false || typeof res === 'string') {
    let msg = '';
    try { await mermaid.parse(text); } catch (e) { msg = String(e.message).split('\n').slice(0, 3).join(' | '); }
    console.log(JSON.stringify({ case: label, line, result: 'PARSE_ERROR', message: msg.slice(0, 140) }));
    return;
  }
  const d = await mermaid.mermaidAPI.getDiagramFromText(text);
  const v = d.db.getVertices().get('A');
  const e = d.db.getEdges()[0];
  console.log(JSON.stringify({
    case: label, line, result: 'OK',
    rawText: v ? v.text : undefined,
    decoded: v ? decodePlaceholders(v.text) : undefined,
    labelType: v ? v.labelType : undefined,
    edgeRawText: e ? e.text : undefined,
    edgeDecoded: e ? decodePlaceholders(e.text) : undefined,
  }));
}

// 1. <br> inside quoted label (what exporter emits for '\n')
await dumpVertex('br-in-quotes', 'A["line1<br>line2"]');
await dumpVertex('br-selfclose', 'A["line1<br/>line2"]');
// 2. & inside quotes
await dumpVertex('amp-in-quotes', 'A["a & b"]');
// 3. literal &amp; typed by a user (exporter emits it verbatim — does it survive?)
await dumpVertex('literal-amp-entity', 'A["AT&amp;T"]');
await dumpVertex('literal-lt-entity', 'A["5 &lt; 6"]');
// 4. #quot; and #35;
await dumpVertex('quot-escape', 'A["say #quot;hi#quot;"]');
await dumpVertex('hash-35', 'A["100#35; done"]');
// 5. raw # inside quotes (does it need escaping at all?)
await dumpVertex('raw-hash', 'A["#1 item"]');
// 6. angle brackets / html-ish text
await dumpVertex('raw-lt', 'A["x < y"]');
await dumpVertex('bold-tag', 'A["a <b>bold</b> claim"]');
// 7. edge label quoted in pipes (exporter ALWAYS quotes)
await dumpVertex('edge-label-quoted', 'A -->|"a & b"| B');
await dumpVertex('edge-label-quot-esc', 'A -->|"say #quot;hi#quot;"| B');
await dumpVertex('edge-label-br', 'A -->|"l1<br>l2"| B');
// 8. subgraph quoted title
{
  const text = 'flowchart TD\n  subgraph SG1["Group #quot;One#quot; & Co"]\n    A\n  end\n';
  const ok = await mermaid.parse(text, { suppressErrors: true });
  if (ok === false) {
    let msg = ''; try { await mermaid.parse(text); } catch (e) { msg = String(e.message).split('\n').slice(0,3).join(' | '); }
    console.log(JSON.stringify({ case: 'subgraph-quoted-title', result: 'PARSE_ERROR', message: msg }));
  } else {
    const d = await mermaid.mermaidAPI.getDiagramFromText(text);
    const sg = d.db.getSubGraphs()[0];
    console.log(JSON.stringify({ case: 'subgraph-quoted-title', result: 'OK', title: sg.title, decoded: decodePlaceholders(sg.title), labelType: sg.labelType }));
  }
}
// 9. newline literal inside quotes (why <br> is needed)
await dumpVertex('literal-newline', 'A["line1\nline2"]');
