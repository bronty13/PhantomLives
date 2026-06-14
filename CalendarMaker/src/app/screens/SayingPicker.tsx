import { useState, useMemo } from 'react';
import { sayingPool, getRandomSaying } from '../../data/sayings';
import type { FillerEntry } from '../../model/types';

interface SayingPickerProps {
  sayings: FillerEntry[];
  onSelect: (text: string, reference: string) => void;
  onClose?: () => void;
}

export function SayingPicker({ sayings, onSelect, onClose }: SayingPickerProps) {
  const pool = useMemo(() => sayingPool(sayings), [sayings]);
  const [search, setSearch] = useState<string>('');

  const filtered = useMemo(() => {
    if (!search) return pool;
    const q = search.toLowerCase();
    return pool.filter((s) => s.text.toLowerCase().includes(q) || s.reference?.toLowerCase().includes(q));
  }, [pool, search]);

  const handleRandom = () => {
    const saying = getRandomSaying(pool);
    if (saying) {
      onSelect(saying.text, saying.reference || '');
      onClose?.();
    }
  };

  const handleSelect = (entry: FillerEntry) => {
    onSelect(entry.text, entry.reference || '');
    onClose?.();
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <input
        type="text"
        placeholder="Search sayings..."
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        style={{ padding: '6px 8px', borderRadius: 4, border: '1px solid var(--border)' }}
      />

      <button className="secondary" onClick={handleRandom}>
        ↻ Random
      </button>

      <div style={{ maxHeight: 240, overflowY: 'auto', border: '1px solid var(--border)', borderRadius: 4 }}>
        {filtered.map((saying) => (
          <div
            key={saying.id}
            onClick={() => handleSelect(saying)}
            style={{
              padding: '8px 12px',
              borderBottom: '1px solid var(--border)',
              cursor: 'pointer',
              transition: 'background 0.2s',
            }}
            onMouseOver={(e) => (e.currentTarget.style.background = 'var(--hover-bg)')}
            onMouseOut={(e) => (e.currentTarget.style.background = 'transparent')}
          >
            <div style={{ fontWeight: 500, fontSize: 14, marginBottom: 2 }}>{saying.text}</div>
            {saying.reference && <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>— {saying.reference}</div>}
          </div>
        ))}
        {filtered.length === 0 && (
          <div style={{ padding: 16, textAlign: 'center', color: 'var(--text-muted)' }}>No sayings found</div>
        )}
      </div>
    </div>
  );
}
