// Test 1a: bare import of mermaid in Node, NO jsdom shims at all.
try {
  const mermaid = (await import('mermaid')).default;
  console.log('IMPORT OK, typeof mermaid:', typeof mermaid);
  const r = await mermaid.parse('flowchart TD\n A --> B');
  console.log('PARSE OK:', JSON.stringify(r));
} catch (e) {
  console.log('FAILED AT:', e.constructor.name);
  console.log('MESSAGE:', e.message);
  console.log('STACK (top 5):');
  console.log(e.stack.split('\n').slice(0, 6).join('\n'));
}
