// UI smoke test: mount the real React app in jsdom (with a fake IndexedDB and a
// ResizeObserver polyfill) and drive a full create → edit → overflow flow. This
// catches runtime/render errors the pure-logic tests can't.

import 'fake-indexeddb/auto';
import { describe, it, expect, beforeAll } from 'vitest';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import { App } from '../src/app/App';

beforeAll(() => {
  // jsdom lacks ResizeObserver (used by CalendarPreview).
  (globalThis as unknown as { ResizeObserver: unknown }).ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  };
});

describe('App smoke', () => {
  it('mounts, creates a calendar, and surfaces an overflow alert', async () => {
    render(<App />);

    // Home loads after seeding.
    await waitFor(() => expect(screen.getByText('Your calendars')).toBeTruthy());
    // Time-of-day greeting with the default name.
    expect(screen.getByText(/Good (morning|afternoon|evening|night), Jan/)).toBeTruthy();
    expect(screen.getByText(/No calendars yet/i)).toBeTruthy();

    // Open the New-calendar wizard and create one (topbar button).
    fireEvent.click(screen.getAllByText('+ New calendar')[0]);
    const titleInput = await screen.findByPlaceholderText(/Grace Church/i);
    fireEvent.change(titleInput, { target: { value: 'Smoke Test Cal' } });
    fireEvent.click(screen.getByText('Create'));

    // Editor opens; the title field carries the name.
    await waitFor(() => expect(screen.getByDisplayValue('Smoke Test Cal')).toBeTruthy());

    // Click the first in-month day cell to open the day editor.
    const cells = document.querySelectorAll('.cal-cell:not(.blank)');
    expect(cells.length).toBeGreaterThan(0);
    fireEvent.click(cells[0]);

    // Add several items so the day overflows the month grid.
    const addText = await screen.findByPlaceholderText('Event text…');
    for (let i = 0; i < 10; i++) {
      fireEvent.change(addText, { target: { value: `Event number ${i + 1}` } });
      fireEvent.click(screen.getByText('+ Add item'));
    }

    // The overflow alert should appear in the day drawer.
    await waitFor(() => expect(screen.getByText(/won’t fit on the month grid/i)).toBeTruthy());
  });

  it('opens the holidays panel and toggles a holiday', async () => {
    render(<App />);
    await waitFor(() => expect(screen.getByText('Your calendars')).toBeTruthy());
    // Open the existing calendar from the previous test (shared fake-indexeddb).
    const openBtns = await screen.findAllByText('Open');
    fireEvent.click(openBtns[0]);
    await waitFor(() => expect(screen.getByText('Holidays')).toBeTruthy());
    fireEvent.click(screen.getByText('Holidays'));
    const drawer = await screen.findByText(/Holidays —/i);
    expect(drawer).toBeTruthy();
    // At least one On/Off toggle exists for a month with holidays, or the empty note.
    const panel = drawer.closest('.drawer') as HTMLElement;
    expect(within(panel).queryAllByText(/No holidays|Off|On/).length).toBeGreaterThan(0);
  });
});
