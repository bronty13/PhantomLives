// Constructors for model objects.

import { nanoid } from 'nanoid';
import type { CalendarBundle, Item, ItemType, Theme } from './types';

export function newId(prefix = ''): string {
  return prefix ? `${prefix}-${nanoid(10)}` : nanoid(12);
}

export function makeItem(type: ItemType, order: number, text = ''): Item {
  return { id: newId('item'), type, text, showOnMonth: true, pinned: false, order };
}

export function makeBundle(opts: {
  title: string;
  year: number;
  month: number;
  themeId: string;
  weekStartsOn: 0 | 1;
}): CalendarBundle {
  const now = Date.now();
  return {
    id: newId('cal'),
    title: opts.title,
    year: opts.year,
    month: opts.month,
    themeId: opts.themeId,
    weekStartsOn: opts.weekStartsOn,
    days: {},
    fillers: [],
    createdAt: now,
    updatedAt: now,
  };
}

/** A deep, editable copy of a theme (used by "Duplicate" in the Theme Manager). */
export function duplicateTheme(theme: Theme, name?: string): Theme {
  return {
    ...theme,
    id: newId('theme'),
    name: name ?? `${theme.name} (copy)`,
    builtin: false,
    itemStyles: { ...theme.itemStyles },
    calendar: { ...theme.calendar },
  };
}
