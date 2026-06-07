// Resolve a day's toggled-on holiday IDs to display names.

import type { Day } from '../model/types';
import { HOLIDAYS } from '../data/holidays';

const NAME_BY_ID = new Map(HOLIDAYS.map((h) => [h.id, h.name]));

export function holidayNamesFor(day: Day | undefined): string[] {
  if (!day || !day.holidayIds.length) return [];
  return day.holidayIds.map((id) => NAME_BY_ID.get(id) ?? id);
}
