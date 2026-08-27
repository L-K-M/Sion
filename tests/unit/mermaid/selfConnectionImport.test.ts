import { describe, expect, it } from 'vitest';
import { importMermaid } from '../../../src/shared/mermaid/import';
import { shimParse } from '../../corpus/shim';

describe('self-connection Mermaid import', () => {
  it('drops imported self-loops', async () => {
    const result = await importMermaid('flowchart TB\n  A --> A', shimParse);

    expect(result.kind).toBe('flowchart');
    if (result.kind === 'flowchart') expect(result.edges).toEqual([]);
  });
});
