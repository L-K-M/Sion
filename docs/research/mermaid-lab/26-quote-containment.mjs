await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', htmlLabels: false, flowchart: { htmlLabels: false } });
async function t(name, text, dump) {
  let ok; try { ok = await mermaid.parse(text, { suppressErrors: true }); } catch (e) { console.log(name, 'THROWN', e.message.slice(0,100)); return; }
  if (ok === false) { let m=''; try { await mermaid.parse(text); } catch (e) { m = String(e.message).split('\n').slice(0,3).join(' | '); } console.log(name, 'PARSE_ERROR', m.slice(0,120)); return; }
  const d = await mermaid.mermaidAPI.getDiagramFromText(text);
  console.log(name, 'OK', JSON.stringify(dump(d.db)));
}
await t('pipe-in-edge-label', 'flowchart TD\n  A -->|"a | b"| B\n', db => db.getEdges()[0].text);
await t('pipe-in-node-label', 'flowchart TD\n  A["a | b"]\n', db => db.getVertices().get('A').text);
await t('bracket-in-node-label', 'flowchart TD\n  A["a ] b"]\n', db => db.getVertices().get('A').text);
await t('paren-in-quoted', 'flowchart TD\n  A["f(x)"]\n', db => db.getVertices().get('A').text);
await t('backslash', 'flowchart TD\n  A["c:\\temp\\x"]\n', db => db.getVertices().get('A').text);
