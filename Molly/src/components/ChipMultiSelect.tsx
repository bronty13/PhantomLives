interface ChipOption {
  id: number;
  label: string;
  color: string;
}

interface Props {
  options: ChipOption[];
  selected: number[];
  onChange: (ids: number[]) => void;
  emptyMessage?: string;
}

export function ChipMultiSelect({ options, selected, onChange, emptyMessage }: Props) {
  const set = new Set(selected);
  const toggle = (id: number) => {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    onChange(Array.from(next));
  };

  if (options.length === 0) {
    return <div className="text-xs opacity-60 italic">{emptyMessage ?? 'No options — add some in Settings.'}</div>;
  }

  return (
    <div className="flex flex-wrap gap-1.5">
      {options.map((o) => {
        const isOn = set.has(o.id);
        return (
          <button
            key={o.id}
            type="button"
            onClick={() => toggle(o.id)}
            className="px-2.5 py-1 rounded-full text-sm transition"
            style={{
              background: isOn ? o.color : 'transparent',
              color: isOn ? 'white' : 'rgb(var(--persona-text))',
              border: `1px solid ${o.color}`,
              fontWeight: isOn ? 600 : 500,
              boxShadow: isOn ? `0 3px 8px -4px ${o.color}88` : undefined,
            }}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}
