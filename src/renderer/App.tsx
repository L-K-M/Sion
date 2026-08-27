import { ReactFlowProvider } from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import './theme/theme.css';
import './styles.css';
import { Canvas } from './canvas/Canvas';
import { Toolbar } from './panels/Toolbar';
import { ContextPanel } from './panels/ContextPanel';
import { HelpOverlay } from './panels/HelpOverlay';
import { MermaidPanel } from './panels/MermaidPanel';
import { DocumentLifecyclePhase, useDocumentLifecycle } from './files/useDocumentLifecycle';
import { ExportDialog } from './panels/ExportDialog';
import { useKeymap } from './canvas/hooks/useKeymap';
import { useEffectiveTheme } from './theme/useEffectiveTheme';
import { useEffect } from 'react';

function Workspace({ theme }: { theme: string }) {
  useKeymap();

  return (
    <div className="thalyx-root" data-theme={theme}>
      <Toolbar />
      <Canvas />
      <ContextPanel />
      <MermaidPanel />
      <ExportDialog />
      <HelpOverlay />
    </div>
  );
}

function Shell() {
  const phase = useDocumentLifecycle();
  const theme = useEffectiveTheme();

  useEffect(() => {
    document.documentElement.dataset['theme'] = theme;
  }, [theme]);

  if (phase !== DocumentLifecyclePhase.Ready) {
    const message =
      phase === DocumentLifecyclePhase.Error
        ? 'Could not open this document.'
        : phase === DocumentLifecyclePhase.Closing
          ? 'Saving…'
          : 'Opening…';
    return (
      <div className="thalyx-root thalyx-lifecycle" data-theme={theme} role="status">
        {message}
      </div>
    );
  }

  return <Workspace theme={theme} />;
}

export function App() {
  return (
    <ReactFlowProvider>
      <Shell />
    </ReactFlowProvider>
  );
}
