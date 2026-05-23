import { useState } from 'react';
import {
  createRewardMilestone,
  deleteRewardMilestone,
  listRewardMilestones,
  updateRewardMilestone,
  type RewardMilestone,
} from '../../data/hours';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

export function RewardsSettings() {
  const [items, setItems] = useState<RewardMilestone[]>([]);
  const [draftHours, setDraftHours] = useState('');
  const [draftLabel, setDraftLabel] = useState('');
  const [editing, setEditing] = useState<{ id: number; hours: string; label: string } | null>(null);
  const [status, setStatus] = useState('');
  const [busy, setBusy] = useState(false);

  const { refresh } = useAsyncRefresh(async (alive) => {
    const all = await listRewardMilestones();
    if (!alive()) return;
    setItems(all);
  }, []);

  async function add() {
    const h = parseFloat(draftHours);
    const label = draftLabel.trim();
    if (!Number.isFinite(h) || h <= 0 || !label) return;
    setBusy(true);
    try {
      await createRewardMilestone({ hoursGoal: h, label });
      setStatus(`Added "${label}" at ${h}h.`);
      setDraftHours('');
      setDraftLabel('');
      await refresh();
    } catch (e) {
      setStatus(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function saveEdit() {
    if (!editing) return;
    const h = parseFloat(editing.hours);
    const label = editing.label.trim();
    if (!Number.isFinite(h) || h <= 0 || !label) return;
    setBusy(true);
    try {
      await updateRewardMilestone(editing.id, { hoursGoal: h, label });
      setStatus(`Saved "${label}".`);
      setEditing(null);
      await refresh();
    } catch (e) {
      setStatus(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function remove(m: RewardMilestone) {
    if (!confirm(`Delete the "${m.label}" milestone?`)) return;
    setBusy(true);
    try {
      await deleteRewardMilestone(m.id);
      setStatus(`Removed "${m.label}".`);
      await refresh();
    } catch (e) {
      setStatus(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <h3 className="display-font text-xl font-semibold persona-accent mb-1">🎁 Reward milestones</h3>
        <p className="text-sm opacity-70 mb-3">
          Hour-based goals tied to rewards. Global — all hours across personas count toward each goal.
          Add as many as you like (100h, 150h, 250h…) — let the goals be goals.
          Progress bars render in <strong>Reddit → Hours</strong>.
        </p>

        <div className="flex gap-2 flex-wrap mb-4">
          <input
            className="pretty-input w-32"
            type="number"
            min="1"
            step="1"
            placeholder="Hours goal"
            value={draftHours}
            onChange={(e) => setDraftHours(e.target.value)}
            disabled={busy}
          />
          <input
            className="pretty-input flex-1 min-w-[200px]"
            placeholder="Reward (e.g. spa day, new lens, weekend off…)"
            value={draftLabel}
            onChange={(e) => setDraftLabel(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') add(); }}
            disabled={busy}
          />
          <button
            type="button"
            className="pretty-button"
            onClick={add}
            disabled={busy || !draftLabel.trim() || !parseFloat(draftHours)}
          >
            ＋ Add milestone
          </button>
        </div>

        {items.length === 0 ? (
          <div className="text-sm opacity-60 italic">No milestones yet. Add one above.</div>
        ) : (
          <ul className="space-y-1.5">
            {items.map((m) => {
              const isEdit = editing?.id === m.id;
              if (isEdit) {
                return (
                  <li
                    key={m.id}
                    className="flex items-center gap-2 rounded-xl px-3 py-2 border"
                    style={{ borderColor: 'rgb(var(--persona-primary) / 0.45)', background: 'rgb(var(--persona-tint))' }}
                  >
                    <input
                      className="pretty-input w-24"
                      type="number"
                      min="1"
                      step="1"
                      value={editing.hours}
                      onChange={(e) => setEditing({ ...editing, hours: e.target.value })}
                    />
                    <input
                      className="pretty-input flex-1"
                      value={editing.label}
                      onChange={(e) => setEditing({ ...editing, label: e.target.value })}
                      onKeyDown={(e) => { if (e.key === 'Enter') saveEdit(); }}
                    />
                    <button type="button" className="pretty-button secondary text-xs" onClick={() => setEditing(null)} disabled={busy}>Cancel</button>
                    <button type="button" className="pretty-button text-xs" onClick={saveEdit} disabled={busy}>Save</button>
                  </li>
                );
              }
              return (
                <li
                  key={m.id}
                  className="flex items-center gap-3 rounded-xl px-3 py-2 border"
                  style={{ borderColor: 'rgb(var(--persona-primary) / 0.25)' }}
                >
                  <span className="text-lg">🎁</span>
                  <span className="font-bold persona-accent text-sm w-16">{m.hoursGoal}h</span>
                  <span className="flex-1 text-sm">{m.label}</span>
                  <button
                    type="button"
                    className="pretty-button secondary text-xs"
                    onClick={() => setEditing({ id: m.id, hours: String(m.hoursGoal), label: m.label })}
                    disabled={busy}
                  >
                    Edit
                  </button>
                  <button
                    type="button"
                    className="pretty-button danger text-xs"
                    onClick={() => remove(m)}
                    disabled={busy}
                  >
                    Delete
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
