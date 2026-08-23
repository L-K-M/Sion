/**
 * Curated palette (PLAN.md §10.4).
 *
 * 12 fill tokens: surface, gray, blue, cyan, teal, green, yellow, orange,
 * red, pink, violet, transparent. Each token maps to a light-theme and
 * dark-theme pair (fill + auto stroke + label text color) exposed as CSS
 * variables. Values derive from the Open Color palette (MIT — values, not
 * code; see THIRD_PARTY_LICENSES.md).
 *
 * Every label/token pair must reach ≥ 4.5:1 contrast in BOTH themes —
 * enforced by tests/unit/theme/palette.test.ts (§15.1).
 */

export type PaletteToken =
  | 'surface'
  | 'gray'
  | 'blue'
  | 'cyan'
  | 'teal'
  | 'green'
  | 'yellow'
  | 'orange'
  | 'red'
  | 'pink'
  | 'violet'
  | 'transparent';

export const PALETTE_TOKENS: readonly PaletteToken[] = [
  'surface',
  'gray',
  'blue',
  'cyan',
  'teal',
  'green',
  'yellow',
  'orange',
  'red',
  'pink',
  'violet',
  'transparent',
];

export interface ThemePair {
  /** node fill */
  fill: string;
  /** auto-derived stroke (a darkened fill in light, lightened in dark) */
  stroke: string;
  /** label text color over the fill */
  text: string;
}

export interface TokenTheme {
  surface: string;
  ink: string;
  canvas: string;
  grid: string;
  panel: string;
  border: string;
  accent: string;
  tokens: Record<Exclude<PaletteToken, never>, ThemePair>;
}

export const LIGHT: TokenTheme = {
  surface: '#ffffff',
  ink: '#1f2328',
  canvas: '#fbfbfc',
  grid: '#d8dade',
  panel: '#ffffff',
  border: '#d9dce1',
  accent: '#1c7ed6',
  tokens: {
    surface: { fill: '#ffffff', stroke: '#343a40', text: '#1f2328' },
    gray: { fill: '#f1f3f5', stroke: '#495057', text: '#212529' },
    blue: { fill: '#d0ebff', stroke: '#1971c2', text: '#0b3a5d' },
    cyan: { fill: '#c5f6fa', stroke: '#0c8599', text: '#083c45' },
    teal: { fill: '#c3fae8', stroke: '#097b74', text: '#053b37' },
    green: { fill: '#d3f9d8', stroke: '#2b8a3e', text: '#12401d' },
    yellow: { fill: '#fff3bf', stroke: '#b8860b', text: '#4d3a00' },
    orange: { fill: '#ffe8cc', stroke: '#d9480f', text: '#5c2205' },
    red: { fill: '#ffe3e3', stroke: '#c92a2a', text: '#5c1010' },
    pink: { fill: '#ffdeeb', stroke: '#c2255c', text: '#571027' },
    violet: { fill: '#e5dbff', stroke: '#6741d9', text: '#2e1f66' },
    transparent: { fill: 'transparent', stroke: '#495057', text: '#1f2328' },
  },
};

export const DARK: TokenTheme = {
  surface: '#1e2126',
  ink: '#e9ebee',
  canvas: '#14161a',
  grid: '#31353c',
  panel: '#1e2126',
  border: '#33373e',
  accent: '#74c0fc',
  tokens: {
    surface: { fill: '#262a31', stroke: '#adb5bd', text: '#f1f3f5' },
    gray: { fill: '#343a40', stroke: '#ced4da', text: '#f1f3f5' },
    blue: { fill: '#0b3f66', stroke: '#74c0fc', text: '#d8efff' },
    cyan: { fill: '#08505c', stroke: '#66d9e8', text: '#d9fbff' },
    teal: { fill: '#075049', stroke: '#63e6be', text: '#d7fff2' },
    green: { fill: '#14532d', stroke: '#8ce99a', text: '#e3fce8' },
    yellow: { fill: '#614a00', stroke: '#ffe066', text: '#fff9db' },
    orange: { fill: '#6b2f0d', stroke: '#ffa94d', text: '#ffeee0' },
    red: { fill: '#611616', stroke: '#ffa8a8', text: '#ffe3e3' },
    pink: { fill: '#5f1a33', stroke: '#faa2c1', text: '#ffdeeb' },
    violet: { fill: '#3b2c78', stroke: '#b197fc', text: '#ece5ff' },
    transparent: { fill: 'transparent', stroke: '#ced4da', text: '#e9ebee' },
  },
};

/**
 * WCAG 2.x relative-luminance contrast ratio between two hex colors.
 * Used by the palette unit test (§15.1) and available for UI hints.
 */
export function contrastRatio(a: string, b: string): number {
  const lum = (hex: string): number => {
    const h = hex.replace('#', '');
    const full =
      h.length === 3
        ? h
            .split('')
            .map((c) => c + c)
            .join('')
        : h;
    const [r, g, bl] = [0, 2, 4].map((i) => parseInt(full.slice(i, i + 2), 16) / 255) as [
      number,
      number,
      number,
    ];
    const lin = (c: number) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(bl);
  };
  if (a === 'transparent') a = '#ffffff';
  if (b === 'transparent') b = '#ffffff';
  const l1 = lum(a);
  const l2 = lum(b);
  const [hi, lo] = l1 > l2 ? [l1, l2] : [l2, l1];
  return (hi + 0.05) / (lo + 0.05);
}

/** Resolve a style color value (token | hex | 'surface') for a theme. */
export function resolveColor(
  value: string,
  theme: 'light' | 'dark',
  role: 'fill' | 'stroke' | 'text' = 'fill',
): string {
  const t = theme === 'light' ? LIGHT : DARK;
  if (value === 'ink') return t.ink;
  if (value === 'surface') return t.tokens.surface[role];
  if ((PALETTE_TOKENS as readonly string[]).includes(value) && value in t.tokens) {
    return t.tokens[value as PaletteToken][role];
  }
  return value; // raw hex renders as-is in both themes (§7.1)
}
