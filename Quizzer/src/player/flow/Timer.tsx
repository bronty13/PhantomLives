import { useEffect, useRef, useState } from 'react';
import { formatDuration } from '../../shared/util';

/** Counts down from `seconds`; calls onExpire once at zero. */
export function Timer({ seconds, onExpire }: { seconds: number; onExpire: () => void }) {
  const [left, setLeft] = useState(seconds);
  const expired = useRef(false);

  useEffect(() => {
    const start = Date.now();
    const id = setInterval(() => {
      const remaining = seconds - Math.floor((Date.now() - start) / 1000);
      setLeft(remaining);
      if (remaining <= 0 && !expired.current) {
        expired.current = true;
        clearInterval(id);
        onExpire();
      }
    }, 250);
    return () => clearInterval(id);
  }, [seconds, onExpire]);

  return (
    <div className={`timer ${left <= 30 ? 'warning' : ''}`} role="timer" aria-live="off">
      ⏱ {formatDuration(left)}
    </div>
  );
}
