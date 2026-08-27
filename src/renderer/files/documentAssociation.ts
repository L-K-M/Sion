import { isProbablyMermaid } from '../../shared/mermaid/detect';

export function associatedPathForOpen(path: string, contents: string): string | null {
  if (/\.mmd$|\.mermaid$/i.test(path) || isProbablyMermaid(contents)) return null;

  return path;
}
