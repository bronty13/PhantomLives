// Behavioral test for the grid + type-ahead Bible verse picker. Verifies both
// interaction paths a user has: typing a reference, and tapping book→chapter→verse.

import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { BibleVersePicker } from '../src/app/screens/BibleVersePicker';

describe('BibleVersePicker', () => {
  it('type-ahead: typing a full reference + Enter commits that verse', () => {
    const onSelect = vi.fn();
    render(<BibleVersePicker onSelect={onSelect} />);

    const input = screen.getByPlaceholderText(/Type a reference/i);
    fireEvent.change(input, { target: { value: 'John 3:16' } });
    fireEvent.keyDown(input, { key: 'Enter' });

    expect(onSelect).toHaveBeenCalledTimes(1);
    const [text, ref] = onSelect.mock.calls[0];
    expect(ref).toBe('John 3:16');
    expect(text.length).toBeGreaterThan(0);
  });

  it('type-ahead: a partial book prefix narrows the book grid', () => {
    const onSelect = vi.fn();
    render(<BibleVersePicker onSelect={onSelect} />);

    fireEvent.change(screen.getByPlaceholderText(/Type a reference/i), { target: { value: 'phil' } });
    // Philippians and Philemon both start with "Phil"; Genesis should be gone.
    expect(screen.getByRole('button', { name: 'Philippians' })).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Philemon' })).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Genesis' })).toBeNull();
  });

  it('tap drill-down: book → chapter → verse commits the chosen verse', () => {
    const onSelect = vi.fn();
    render(<BibleVersePicker onSelect={onSelect} />);

    fireEvent.click(screen.getByRole('button', { name: 'John' }));     // book
    fireEvent.click(screen.getByRole('button', { name: '3' }));        // chapter
    fireEvent.click(screen.getByRole('button', { name: '16' }));       // verse

    expect(onSelect).toHaveBeenCalledTimes(1);
    expect(onSelect.mock.calls[0][1]).toBe('John 3:16');
  });

  it('book buttons show a compact abbreviation but keep the full accessible name', () => {
    render(<BibleVersePicker onSelect={vi.fn()} />);
    const genesis = screen.getByRole('button', { name: 'Genesis' }); // accessible name via aria-label
    expect(genesis.textContent).toBe('Gen');                          // visible label is abbreviated
    const firstSamuel = screen.getByRole('button', { name: '1 Samuel' });
    expect(firstSamuel.textContent).toBe('1Sa');                      // numbered book abbreviation
  });

  it('handles numbered books (e.g. "1 Jo" → 1 John)', () => {
    const onSelect = vi.fn();
    render(<BibleVersePicker onSelect={onSelect} />);

    fireEvent.change(screen.getByPlaceholderText(/Type a reference/i), { target: { value: '1 Jo 1:9' } });
    fireEvent.keyDown(screen.getByPlaceholderText(/Type a reference/i), { key: 'Enter' });

    expect(onSelect).toHaveBeenCalledTimes(1);
    expect(onSelect.mock.calls[0][1]).toBe('1 John 1:9');
  });
});
