import { useState } from 'react';
import type { Persona } from '../../state/personas';
import { AdhocIncomeView } from './AdhocIncomeView';
import { SiteIncomeWizard } from './SiteIncomeWizard';

interface Props {
  active: Persona;
}

type Tab = 'adhoc' | 'site';

export function IncomeView({ active }: Props) {
  const [tab, setTab] = useState<Tab>('adhoc');

  return (
    <div className="space-y-3">
      <div className="px-8 pt-6 flex items-center gap-2">
        {(['adhoc', 'site'] as Tab[]).map((t) => {
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
              {t === 'adhoc' ? '💖 Adhoc income' : '🌐 Site income wizard'}
            </button>
          );
        })}
      </div>
      {tab === 'adhoc' ? <AdhocIncomeView active={active} /> : <SiteIncomeWizard onClose={() => setTab('adhoc')} />}
    </div>
  );
}
