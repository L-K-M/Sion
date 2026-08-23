// Test 7: (a) state getData() nesting/parentId; (b) parse error shape + suppressErrors.
await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;

const text = `stateDiagram-v2
  [*] --> Still
  state Composite {
    [*] --> Inner1
    Inner1 --> Inner2
  }
`;
await mermaid.parse(text);
const diagram = await mermaid.mermaidAPI.getDiagramFromText(text);
const data = diagram.db.getData();
console.log('=== state getData().nodes (id, parentId, isGroup, shape) ===');
console.log(JSON.stringify(data.nodes.map(n => ({ id: n.id, parentId: n.parentId, isGroup: n.isGroup, shape: n.shape, label: n.label })), null, 2));

// (b) error shapes
console.log('\n=== mermaid.parse of invalid text (suppressErrors: true) ===');
const r1 = await mermaid.parse('flowchart TD\n A --> --> B', { suppressErrors: true });
console.log('result:', JSON.stringify(r1));

console.log('\n=== mermaid.parse of invalid text (throws) ===');
try {
  await mermaid.parse('flowchart TD\n A --> --> B');
} catch (e) {
  console.log('error name:', e.name);
  console.log('error message first line:', e.message.split('\n')[0]);
  console.log('error.hash:', JSON.stringify(e.hash, null, 2));
}
