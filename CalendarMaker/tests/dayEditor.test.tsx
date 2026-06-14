// Regression test for the "picked verse/saying doesn't appear until another item
// is added" bug: selecting from the picker must commit the item to the day at once.

import { describe, it, expect, vi, beforeAll } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { DayEditorPanel } from '../src/app/screens/DayEditorPanel';
import { SEED_THEMES } from '../src/model/seedThemes';
import { makeBundle } from '../src/model/factory';
import type { Day } from '../src/model/types';

beforeAll(() => {
  (globalThis as unknown as { ResizeObserver: unknown }).ResizeObserver = class {
    observe() {} unobserve() {} disconnect() {}
  };
});

function setup(onChange: (d: Day) => void) {
  const bundle = makeBundle({ title: 'T', year: 2026, month: 6, themeId: 'theme-classic', weekStartsOn: 0 });
  const day: Day = { date: '2026-06-10', items: [], holidayIds: [] };
  render(
    <DayEditorPanel
      date="2026-06-10"
      day={day}
      theme={SEED_THEMES[0]}
      cap={5}
      bundle={bundle}
      customSayings={[]}
      onChange={onChange}
      onClose={() => {}}
    />,
  );
}

describe('DayEditorPanel — verse/saying commit on pick', () => {
  it('picking a Bible verse adds it to the day immediately (single onChange with the item)', () => {
    const onChange = vi.fn();
    setup(onChange);

    // Choose the Bible Verse type → picker opens.
    fireEvent.change(screen.getByDisplayValue('Reminder'), { target: { value: 'bibleVerse' } });
    // Type a full reference and commit with Enter.
    const input = screen.getByPlaceholderText(/Type a reference/i);
    fireEvent.change(input, { target: { value: 'John 3:16' } });
    fireEvent.keyDown(input, { key: 'Enter' });

    expect(onChange).toHaveBeenCalled();
    const calls = onChange.mock.calls;
    const updatedDay = calls[calls.length - 1][0] as Day;
    expect(updatedDay.items).toHaveLength(1);
    expect(updatedDay.items[0].type).toBe('bibleVerse');
    expect(updatedDay.items[0].reference).toBe('John 3:16');
    expect(updatedDay.items[0].text.length).toBeGreaterThan(0);
  });

  it('picking a saying adds it to the day immediately with its attribution', () => {
    const onChange = vi.fn();
    setup(onChange);

    fireEvent.change(screen.getByDisplayValue('Reminder'), { target: { value: 'saying' } });
    fireEvent.change(screen.getByPlaceholderText(/Search sayings/i), { target: { value: 'Jesus is first' } });
    fireEvent.click(screen.getByText(/Jesus is first in my life/));

    const calls = onChange.mock.calls;
    const updatedDay = calls[calls.length - 1][0] as Day;
    expect(updatedDay.items).toHaveLength(1);
    expect(updatedDay.items[0].type).toBe('saying');
    expect(updatedDay.items[0].reference).toBe('Morning Affirmation');
  });
});
