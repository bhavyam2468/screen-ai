import { createContext, createElement, useCallback, useContext, type ReactNode } from "react";

/**
 * theme.conf's `[motion] speed` multiplier (1.0 is the default, 2.0 twice as
 * slow, 0.5 twice as fast).
 *
 * Most of the UI animates through Framer Motion, whose durations live in JS, so
 * the `--motion-scale` CSS variable alone cannot reach them. App reads the token
 * once and publishes it here; every animated component scales its own base
 * durations with `useSeconds`. CSS transitions multiply the variable directly.
 */
const MotionScaleContext = createContext(1);

export function MotionScaleProvider({ scale, children }: { scale: number; children: ReactNode }) {
  const value = Number.isFinite(scale) && scale > 0 ? scale : 1;
  return createElement(MotionScaleContext.Provider, { value }, children);
}

export function useMotionScale(): number {
  return useContext(MotionScaleContext);
}

/** Scales a base duration in seconds, honouring the configured motion speed. */
export function useSeconds(): (base: number) => number {
  const scale = useMotionScale();
  return useCallback((base: number) => base * scale, [scale]);
}

/**
 * Time-scales a spring: stiffness/s² with damping/s stretches it by `s` while
 * keeping the same damping ratio, so a slower setting does not also get bouncier.
 */
export function scaleSpring<T extends { stiffness: number; damping: number }>(spring: T, scale: number): T {
  const factor = scale > 0 ? scale : 1;
  return { ...spring, stiffness: spring.stiffness / (factor * factor), damping: spring.damping / factor };
}
