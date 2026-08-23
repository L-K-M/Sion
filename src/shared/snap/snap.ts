/**
 * Smart-guide engine (PLAN.md §11.4).
 *
 * M1: only the `GuideLine` type exists (the session slice holds these, §8.1).
 * The computeSnap engine (thresholds, candidates, equal-spacing) lands in M4.
 */

export interface GuideLine {
  kind: 'align' | 'gap';
  axis: 'x' | 'y'; // the axis the guide constrains
  position: number; // canvas coord of the guide line (align) / gap midline (gap)
  start: number; // extent along the other axis, spanning the aligned bounds
  end: number;
  label?: string; // gap chips: the px value, e.g. '24'
}
