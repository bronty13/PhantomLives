import { useState } from 'react';
import type { Persona } from '../../state/personas';
import { ExpenseListView } from './ExpenseListView';
import { RecurringExpensesView } from './RecurringExpensesView';

interface Props {
  active: Persona;
  onChanged: () => void | Promise<void>;
}

type Tab = 'list' | 'recurring';

export function ExpensesView({ active, onChanged }: Props) {
  const [tab, setTab] = useState<Tab>('list');

  return (
    <div>
      <div className="px-8 pt-6 flex items-center gap-2">
        {(['list', 'recurring'] as Tab[]).map((t) => {
          const isOn = tab === t;
          return (
            <button
              key={t}
              type="button"
              onClick={() => setTab(t)}
              className="px-3.5 py-1.5 rounded-full text-sm font-semibold"
              style={{
                background: isOn ? 'rgb(var(--persona-accent))' : 'rgba(255,255,255,0.55)',
                color: isOn ? 'white' : 'rgb(var(--persona-text))',
                border: '1px solid rgb(var(--persona-primary) / 0.45)',
              }}
            >
              {t === 'list' ? '🧾 All expenses' : '🔁 Recurring'}
            </button>
          );
        })}
      </div>
      {tab === 'list' ? (
        <ExpenseListView active={active} />
      ) : (
        <div className="p-8 max-w-5xl">
          <RecurringExpensesView onChanged={onChanged} />
        </div>
      )}
    </div>
  );
}
