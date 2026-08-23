import { ReactFlowProvider } from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import './theme/theme.css';
import './styles.css';
import { Canvas } from './canvas/Canvas';
import { Toolbar } from './panels/Toolbar';
import { useKeymap } from './canvas/hooks/useKeymap';
import { useEffectiveTheme } from './theme/useEffectiveTheme';
import { useEffect } from 'react';

function Shell() {
  useKeymap();
  const theme = useEffectiveTheme();

  useEffect(() => {
    document.documentElement.dataset['theme'] = theme;
  }, [theme]);

  return (
    <div className="thalyx-root" data-theme={theme}>
      <Toolbar />
      <Canvas />
    </div>
  );
}

export function App() {
  return (
    <ReactFlowProvider>
      <Shell />
    </ReactFlowProvider>
  );
}
