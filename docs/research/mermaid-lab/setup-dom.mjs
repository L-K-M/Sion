// Must be imported BEFORE mermaid: dompurify captures globalThis.window at module-eval time.
import { JSDOM } from 'jsdom';
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', { url: 'https://localhost/' });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
export default dom;
