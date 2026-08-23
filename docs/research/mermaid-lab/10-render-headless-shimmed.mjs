// Test 10: mermaid.render() headless with extra shims (CSSStyleSheet, getBBox, getComputedTextLength).
import { JSDOM } from 'jsdom';
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', { url: 'https://localhost/' });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.CSSStyleSheet = dom.window.CSSStyleSheet;
globalThis.SVGElement = dom.window.SVGElement;
// jsdom SVG elements lack layout: stub geometry APIs.
const svgProto = dom.window.SVGElement.prototype;
svgProto.getBBox = svgProto.getBBox ?? function () { return { x: 0, y: 0, width: 100, height: 20 }; };
svgProto.getComputedTextLength = svgProto.getComputedTextLength ?? function () { return 100; };
dom.window.Element.prototype.getBoundingClientRect =
  dom.window.Element.prototype.getBoundingClientRect ?? (() => ({ x:0, y:0, width:100, height:20, top:0, left:0, right:100, bottom:20 }));

const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false });
try {
  const { svg } = await mermaid.render('g1', 'flowchart TD\n A[Start] --> B[End]');
  console.log('RENDER OK, svg length:', svg.length);
  console.log(svg.slice(0, 600));
} catch (e) {
  console.log('RENDER FAILED:', e.constructor.name);
  console.log('MESSAGE:', e.message);
  console.log(e.stack.split('\n').slice(0, 8).join('\n'));
}
