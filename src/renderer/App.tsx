import { useEffect, useState } from 'react';
import { platform } from './platform/api';
import { DOC_SCHEMA_ID } from '../shared/model/version';

export function App() {
  const [version, setVersion] = useState<string>('…');

  useEffect(() => {
    let alive = true;
    void platform.version().then((v) => {
      if (alive) setVersion(v);
    });
    return () => {
      alive = false;
    };
  }, []);

  return (
    <main className="splash">
      <h1>Thalyx</h1>
      <p className="splash-sub">The canvas is coming. (Milestone M0 scaffold.)</p>
      <p className="splash-meta">
        app <code>{version}</code> · doc schema <code>{DOC_SCHEMA_ID}</code>
      </p>
    </main>
  );
}
