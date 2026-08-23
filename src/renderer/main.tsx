import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';
import { installTestHooks } from './canvas/hooks/testHooks';

const container = document.getElementById('root');
if (!container) throw new Error('missing #root element');

installTestHooks();

createRoot(container).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
