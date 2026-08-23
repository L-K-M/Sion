/**
 * Theme color resolution for inline styles (PLAN.md §10.4): palette tokens
 * resolve to CSS variables (live theme remap, no re-render); raw hex renders
 * identically in both themes (§7.1).
 */
import { PALETTE_TOKENS } from './palette';

export function colorStyle(value: string, role: 'fill' | 'stroke' | 'text'): string {
  if (value === 'ink') return 'var(--ink)';
  if (value === 'surface') return `var(--surface-${role})`;
  if ((PALETTE_TOKENS as readonly string[]).includes(value)) return `var(--${value}-${role})`;
  return value; // raw hex
}
