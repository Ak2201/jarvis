// Juno's "visor bot" silhouette — port of `enum JunoShape` in
// NotchBuddy/Sources/JarvisKit/JunoOutfitDrawing.swift.
//
// A dome on top (exponent TOP_EXP) and a squarer base below (BOTTOM_EXP). The
// engine, the outfits and every other Juno drawer use these two numbers, so
// hats and scarves keep hugging the body.

export const TOP_EXP = 2.2;
export const BOTTOM_EXP = 4.5;

/** Point on the outline in direction (ca, sa), screen coordinates (y down). */
export function shapePoint(ca: number, sa: number, rx: number, ry: number): { x: number; y: number } {
  const e = 2 / (sa < 0 ? TOP_EXP : BOTTOM_EXP);
  return {
    x: rx * (ca >= 0 ? Math.pow(ca, e) : -Math.pow(-ca, e)),
    y: ry * (sa >= 0 ? Math.pow(sa, e) : -Math.pow(-sa, e)),
  };
}

/** Radius of the horizontal ring of the head at head-local height y (y up, −1…1). */
export function shapeRingR(y: number): number {
  const a = Math.min(1, Math.abs(y));
  const e = y > 0 ? TOP_EXP : BOTTOM_EXP;
  return Math.pow(1 - Math.pow(a, e), 1 / e);
}

/** The closed outline, `n` segments. */
export function shapePath(rx: number, ry: number, n = 96): Path2D {
  const p = new Path2D();
  for (let i = 0; i <= n; i++) {
    const a = (i / n) * Math.PI * 2;
    const pt = shapePoint(Math.cos(a), Math.sin(a), rx, ry);
    if (i === 0) p.moveTo(pt.x, pt.y);
    else p.lineTo(pt.x, pt.y);
  }
  p.closePath();
  return p;
}

// ── Shared colours (JunoConst) ────────────────────────────────────────────────

export const JUNO_BASE_TOP = "#F2F4F7";
export const JUNO_BASE_BOTTOM = "#BCC3CE";
/** LED eyes. */
export const JUNO_INK = "#4FD3FF";
export const JUNO_VISOR_TOP = "#172338";
export const JUNO_VISOR_BOTTOM = "#0B1220";
export const JUNO_ANTENNA = "#C5CBD5";
