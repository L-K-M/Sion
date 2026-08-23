// Test 9: can mermaid.render() produce SVG headless under jsdom?
await import('./setup-dom.mjs');
const mermaid = (await import('mermaid')).default;

mermaid.initialize({ startOnLoad: false });
try {
  const { svg } = await mermaid.render('g1', 'flowchart TD\n A[Start] --> B[End]');
  console.log('RENDER OK, svg length:', svg.length);
  console.log(svg.slice(0, 400));
} catch (e) {
  console.log('RENDER FAILED:', e.constructor.name);
  console.log('MESSAGE:', e.message);
  console.log(e.stack.split('\n').slice(0, 8).join('\n'));
}
