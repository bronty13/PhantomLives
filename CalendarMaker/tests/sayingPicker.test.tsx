// Confirms the saying picker surfaces the seeded Morning Affirmations and that
// the search box filters the pool (built-in sayings + affirmations + custom).

import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { SayingPicker } from '../src/app/screens/SayingPicker';

describe('SayingPicker', () => {
  it('search filters the pool down to matching affirmations', () => {
    render(<SayingPicker sayings={[]} onSelect={vi.fn()} />);

    // Unfiltered: a TLC quote is visible.
    expect(screen.getByText(/He's where the joy is\./)).toBeTruthy();

    // Search for a word unique to an affirmation.
    fireEvent.change(screen.getByPlaceholderText(/Search sayings/i), { target: { value: 'disciplined' } });

    // The matching affirmation shows; the non-matching TLC quote is gone.
    expect(screen.getByText(/I am disciplined/)).toBeTruthy();
    expect(screen.queryByText(/He's where the joy is\./)).toBeNull();
  });

  it('selecting an affirmation returns its text + "Morning Affirmation" reference', () => {
    const onSelect = vi.fn();
    render(<SayingPicker sayings={[]} onSelect={onSelect} />);

    fireEvent.change(screen.getByPlaceholderText(/Search sayings/i), { target: { value: 'Jesus is first' } });
    fireEvent.click(screen.getByText(/Jesus is first in my life/));

    expect(onSelect).toHaveBeenCalledTimes(1);
    const [text, ref] = onSelect.mock.calls[0];
    expect(text).toMatch(/Jesus is first in my life/);
    expect(ref).toBe('Morning Affirmation');
  });
});
