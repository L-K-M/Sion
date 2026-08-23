// Test 8: @mermaid-js/parser (langium AST) — NO DOM shims needed at all.
import { parse } from '@mermaid-js/parser';

// Langium AST nodes carry circular refs in $-prefixed props ($container, $cstNode, $document).
// Keep $type (the node kind), drop the rest.
const replacer = (k, v) => (k.startsWith('$') && k !== '$type') ? undefined : v;

const pieAst = await parse('pie', `pie title Pets
  "Dogs" : 386
  "Cats" : 85
`);
console.log('=== pie AST ===');
console.log(JSON.stringify(pieAst, replacer, 2));

const gitAst = await parse('gitGraph', `gitGraph
  commit id: "one"
  branch develop
  commit
  checkout main
  merge develop
`);
console.log('\n=== gitGraph AST (statements) ===');
console.log(JSON.stringify(gitAst.statements, replacer, 2));

// Prove flowchart is unsupported:
try {
  await parse('flowchart', 'flowchart TD\n A-->B');
} catch (e) {
  console.log('\nflowchart via @mermaid-js/parser →', e.constructor.name + ':', e.message);
}
