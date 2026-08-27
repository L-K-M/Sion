export enum ToolShortcut {
  Select = 'select',
  Rectangle = 'rectangle',
  Ellipse = 'ellipse',
  Diamond = 'diamond',
  Arrow = 'arrow',
  Line = 'line',
  Text = 'text',
  Container = 'container',
  Hand = 'hand',
  Chevrons = 'chevrons',
}

const LETTER_SHORTCUTS: Record<string, ToolShortcut> = {
  v: ToolShortcut.Select,
  r: ToolShortcut.Rectangle,
  o: ToolShortcut.Ellipse,
  d: ToolShortcut.Diamond,
  a: ToolShortcut.Arrow,
  l: ToolShortcut.Line,
  t: ToolShortcut.Text,
  f: ToolShortcut.Container,
  h: ToolShortcut.Hand,
  q: ToolShortcut.Chevrons,
};

const DIGIT_SHORTCUTS: Record<string, ToolShortcut> = {
  Digit1: ToolShortcut.Select,
  Digit2: ToolShortcut.Rectangle,
  Digit3: ToolShortcut.Ellipse,
  Digit4: ToolShortcut.Diamond,
  Digit5: ToolShortcut.Arrow,
  Digit6: ToolShortcut.Line,
  Digit7: ToolShortcut.Text,
  Digit8: ToolShortcut.Container,
};

export function toolShortcut(key: string, code: string): ToolShortcut | null {
  return LETTER_SHORTCUTS[key.toLowerCase()] ?? DIGIT_SHORTCUTS[code] ?? null;
}
