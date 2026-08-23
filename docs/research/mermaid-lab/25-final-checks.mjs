await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', htmlLabels: false, flowchart: { htmlLabels: false } });

// A. flowchart-elk keyword → what diagram type?
for (const head of ['flowchart-elk TD']) {
  const text = head + '\n  A --> B\n';
  const ok = await mermaid.parse(text, { suppressErrors: true });
  if (ok === false) { console.log('A.', head, '→ PARSE_ERROR'); continue; }
  const d = await mermaid.mermaidAPI.getDiagramFromText(text);
  console.log('A.', head, '→ type:', d.type);
}

// B. subgraph direction emit form (what exporter would need to emit to preserve dir)
{
  const text = 'flowchart TD\n  subgraph SG1["T"]\n    direction LR\n    A --> B\n  end\n';
  const ok = await mermaid.parse(text, { suppressErrors: true });
  if (ok === false) { console.log('B. PARSE_ERROR'); }
  else {
    const d = await mermaid.mermaidAPI.getDiagramFromText(text);
    console.log('B. subgraph w/ direction stmt:', JSON.stringify(d.db.getSubGraphs()));
  }
}

// C. CamelCase-ish safe variants of reserved words (uppercase first letter parses fine?)
for (const id of ['Style', 'Class', 'Graph', 'End', 'Subgraph']) {
  const text = 'flowchart TD\n  ' + id + '[Label]\n  Z --> ' + id + '\n';
  const ok = await mermaid.parse(text, { suppressErrors: true });
  console.log('C. id=' + id, ok === false ? 'PARSE_ERROR' : 'OK');
}
