import { useCallback, useEffect, useState, type RefObject } from 'react';

export interface StageBox {
  left: number;
  top: number;
  width: number;
  height: number;
}

/** Measure a <video>'s actual rendered box within its (relative) offset
 * parent. The crop overlay must match the *video* pixels exactly — not a
 * wrapper that can be wider (which made "whole frame" / edge drags only
 * cover part of the video). Re-measures on resize and when `dep` changes
 * (e.g. a new source); a ResizeObserver catches the size jump when the
 * video's metadata loads and it lays out at its real aspect. */
export function useVideoStage(
  videoRef: RefObject<HTMLVideoElement | null>,
  dep: unknown,
): StageBox | null {
  const [box, setBox] = useState<StageBox | null>(null);

  const measure = useCallback(() => {
    const v = videoRef.current;
    if (!v) return;
    setBox({ left: v.offsetLeft, top: v.offsetTop, width: v.offsetWidth, height: v.offsetHeight });
  }, [videoRef]);

  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    measure();
    const ro = new ResizeObserver(() => measure());
    ro.observe(v);
    window.addEventListener('resize', measure);
    return () => { ro.disconnect(); window.removeEventListener('resize', measure); };
  }, [measure, dep]);

  return box;
}
