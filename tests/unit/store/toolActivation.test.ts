import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { resetStore, getStore } from '../../../src/renderer/store/store';
import * as A from '../../../src/renderer/store/actions';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('placement tool activation', () => {
  it('locks a repeated placement tool and resets lock when switching tools', () => {
    const activate = Reflect.get(A, 'activateTool') as (tool: string) => void;

    activate('shape');
    expect(getStore().session.toolLocked).toBe(false);
    activate('shape');
    expect(getStore().session.toolLocked).toBe(true);
    activate('text');
    expect(getStore().session.toolLocked).toBe(false);
  });
});
