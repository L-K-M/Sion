import { describe, expect, it } from 'vitest';
import {
  DARK,
  LIGHT,
  PALETTE_TOKENS,
  contrastRatio,
  resolveColor,
} from '../../../src/renderer/theme/palette';

describe('palette contrast (§10.4 / §15.1)', () => {
  it('every token reaches ≥ 4.5:1 label contrast in BOTH themes', () => {
    for (const theme of [LIGHT, DARK]) {
      for (const token of PALETTE_TOKENS) {
        const pair = theme.tokens[token];
        // 'transparent' fills show labels over the canvas itself.
        const fill = pair.fill === 'transparent' ? theme.canvas : pair.fill;
        const ratio = contrastRatio(fill, pair.text);
        expect(
          ratio,
          `${token} text/fill in ${theme === LIGHT ? 'light' : 'dark'}: ${ratio}`,
        ).toBeGreaterThanOrEqual(4.5);
      }
    }
  });

  it('surface ink contrast ≥ 4.5:1 in both themes', () => {
    expect(contrastRatio(LIGHT.surface, LIGHT.ink)).toBeGreaterThanOrEqual(4.5);
    expect(contrastRatio(DARK.surface, DARK.ink)).toBeGreaterThanOrEqual(4.5);
  });

  it('contrastRatio computes the WCAG reference value', () => {
    // black on white = 21
    expect(contrastRatio('#000000', '#ffffff')).toBeCloseTo(21, 1);
    // equal colors = 1
    expect(contrastRatio('#808080', '#808080')).toBe(1);
  });

  it('resolveColor maps tokens, ink, surface, and passes hex through', () => {
    expect(resolveColor('blue', 'light', 'fill')).toBe(LIGHT.tokens.blue.fill);
    expect(resolveColor('blue', 'dark', 'fill')).toBe(DARK.tokens.blue.fill);
    expect(resolveColor('ink', 'light')).toBe(LIGHT.ink);
    expect(resolveColor('#123456', 'dark')).toBe('#123456');
  });
});
