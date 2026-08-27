export interface DocumentOpenFilter {
  name: string;
  extensions: string[];
}

export const DOCUMENT_OPEN_FILTERS: DocumentOpenFilter[] = [
  { name: 'Thalyx documents', extensions: ['thalyx'] },
  { name: 'JSON documents', extensions: ['json'] },
  { name: 'Mermaid', extensions: ['mmd', 'mermaid'] },
  { name: 'All files', extensions: ['*'] },
];
