/**
 * Zustand store: doc + session slices (PLAN.md §8.1).
 *
 * ONLY `doc` is persisted and history-tracked. `session` is UI state.
 *
 * CONVENTION (enforced by tests/unit/store/convention.test.ts): every store
 * mutation — doc AND session — goes through named actions in `actions.ts`.
 * Nothing outside this store module and actions.ts may call setStore.
 */
import { create } from 'zustand';
import type { ShapeKind, ThalyxDoc, Tool } from '../../shared/model/types';
import type { GuideLine } from '../../shared/snap/snap';
import { newDoc } from '../../shared/model/create';
import { emptyHistory } from './history';
import type { History } from './history';

export interface SessionState {
  filePath: string | null;
  dirtySinceSave: boolean;
  selection: { nodeIds: string[]; edgeIds: string[] };
  tool: Tool;
  pendingShape: ShapeKind;
  toolLocked: boolean;
  editingLabel: { kind: 'node' | 'edge'; id: string } | null;
  viewport: { x: number; y: number; zoom: number };
  theme: 'system' | 'light' | 'dark';
  guides: GuideLine[];
  chevronsEnabled: boolean;
  mermaidPanelOpen: boolean;
  /** Last-used connector style (arrow/line + line style) — new edges inherit it (§10.1 delta 1). */
  lastEdgeStyle: { arrowEnd: 'none' | 'arrow'; line: 'solid' | 'dashed' | 'thick' };
  helpOpen: boolean;
}

export interface StoreState {
  doc: ThalyxDoc;
  session: SessionState;
  history: History;
}

export function createInitialState(doc: ThalyxDoc = newDoc()): StoreState {
  return {
    doc,
    session: {
      filePath: null,
      dirtySinceSave: false,
      selection: { nodeIds: [], edgeIds: [] },
      tool: 'select',
      pendingShape: 'rounded',
      toolLocked: false,
      editingLabel: null,
      viewport: { x: 0, y: 0, zoom: 1 },
      theme: 'system',
      guides: [],
      chevronsEnabled: true,
      mermaidPanelOpen: false,
      helpOpen: false,
      lastEdgeStyle: { arrowEnd: 'arrow', line: 'solid' },
    },
    history: emptyHistory(),
  };
}

export const useStore = create<StoreState>()(() => createInitialState());

/** For actions.ts only (see the convention above). */
export const getStore = useStore.getState;
export const setStore = useStore.setState;
export const resetStore = (doc?: ThalyxDoc): void => {
  useStore.setState(createInitialState(doc), true);
};
