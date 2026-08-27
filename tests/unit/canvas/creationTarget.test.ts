// @vitest-environment jsdom
import { describe, expect, it } from 'vitest';
import { creationTarget } from '../../../src/renderer/canvas/creationTarget';
import { newDoc, newNode } from '../../../src/shared/model/create';

describe('creation gesture targets', () => {
  it('accepts the pane as a top-level placement target', () => {
    const pane = document.createElement('div');
    pane.className = 'react-flow__pane';

    expect(creationTarget(pane, newDoc())).toEqual({ containerId: null });
  });

  it('accepts a container even though React Flow renders it outside the pane', () => {
    const doc = newDoc();
    doc.nodes.push(newNode({ id: 'frame', kind: 'container' }));
    const node = document.createElement('div');
    node.className = 'react-flow__node';
    node.dataset.id = 'frame';
    const content = document.createElement('div');
    node.appendChild(content);

    expect(creationTarget(content, doc)).toEqual({ containerId: 'frame' });
  });

  it('accepts object bodies while preserving a child container', () => {
    const doc = newDoc();
    doc.nodes.push(
      newNode({ id: 'frame', kind: 'container' }),
      newNode({ id: 'shape', parentId: 'frame' }),
    );
    const node = document.createElement('div');
    node.className = 'react-flow__node';
    node.dataset.id = 'shape';

    expect(creationTarget(node, doc)).toEqual({ containerId: 'frame' });

    const edge = document.createElement('path');
    edge.classList.add('react-flow__edge');
    expect(creationTarget(edge, doc)).toEqual({ containerId: null });
  });

  it('rejects interactive controls', () => {
    const doc = newDoc();
    const pane = document.createElement('div');
    pane.className = 'react-flow__pane';
    const button = document.createElement('button');
    pane.appendChild(button);
    expect(creationTarget(button, doc)).toBeNull();
  });
});
