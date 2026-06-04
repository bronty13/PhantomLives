// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { Sidebar } from './Sidebar';
import type { MapRow } from '../data/maps';

afterEach(cleanup);

const maps: MapRow[] = [
  { id: 'm1', title: 'Alpha', created_at: 't', updated_at: 't', viewport_x: 0, viewport_y: 0, viewport_zoom: 1 },
  { id: 'm2', title: 'Beta', created_at: 't', updated_at: 't', viewport_x: 0, viewport_y: 0, viewport_zoom: 1 },
];

function setup(overrides: Partial<Parameters<typeof Sidebar>[0]> = {}) {
  const props = {
    maps,
    activeMapId: 'm1',
    view: 'editor' as const,
    themePref: 'auto' as const,
    onSelectMap: vi.fn(),
    onNewMap: vi.fn(),
    onRenameMap: vi.fn(),
    onDeleteMap: vi.fn(),
    onOpenSettings: vi.fn(),
    onCycleTheme: vi.fn(),
    ...overrides,
  };
  render(<Sidebar {...props} />);
  return props;
}

describe('Sidebar', () => {
  it('lists every map title', () => {
    setup();
    expect(screen.getByText('Alpha')).toBeTruthy();
    expect(screen.getByText('Beta')).toBeTruthy();
    expect(screen.getByText(/Maps \(2\)/)).toBeTruthy();
  });

  it('selects a map when its title is clicked', () => {
    const props = setup();
    fireEvent.click(screen.getByText('Beta'));
    expect(props.onSelectMap).toHaveBeenCalledWith('m2');
  });

  it('creates a new map', () => {
    const props = setup();
    fireEvent.click(screen.getByText('＋ New map'));
    expect(props.onNewMap).toHaveBeenCalled();
  });

  it('opens settings', () => {
    const props = setup();
    fireEvent.click(screen.getByText(/Settings/));
    expect(props.onOpenSettings).toHaveBeenCalled();
  });

  it('renames a map via the inline editor', () => {
    const props = setup();
    fireEvent.doubleClick(screen.getByText('Alpha'));
    const input = screen.getByDisplayValue('Alpha') as HTMLInputElement;
    fireEvent.change(input, { target: { value: 'Renamed' } });
    fireEvent.keyDown(input, { key: 'Enter' });
    expect(props.onRenameMap).toHaveBeenCalledWith('m1', 'Renamed');
  });

  it('shows an empty state with no maps', () => {
    setup({ maps: [] });
    expect(screen.getByText(/No maps yet/)).toBeTruthy();
  });
});
