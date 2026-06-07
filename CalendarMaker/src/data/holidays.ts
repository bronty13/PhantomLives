// US holiday catalog — rule-based so any year resolves correctly. Categories:
// federal (the 11 US federal holidays), observance (common secular days), and
// christian (liturgical days, several derived from Easter via the computus).
//
// weekday: 0=Sun..6=Sat. nthWeekday n=-1 means "last". easterOffset is days
// relative to Easter Sunday (Good Friday = -2, Pentecost = +49, etc.).

import type { HolidayDef } from '../model/types';

export const HOLIDAYS: HolidayDef[] = [
  // ---- Federal ----
  { id: 'new-years-day', name: "New Year's Day", rule: { kind: 'fixed', month: 1, day: 1 }, category: 'federal', observed: true },
  { id: 'mlk-day', name: 'Martin Luther King Jr. Day', rule: { kind: 'nthWeekday', month: 1, weekday: 1, n: 3 }, category: 'federal', observed: false },
  { id: 'presidents-day', name: "Presidents' Day", rule: { kind: 'nthWeekday', month: 2, weekday: 1, n: 3 }, category: 'federal', observed: false },
  { id: 'memorial-day', name: 'Memorial Day', rule: { kind: 'nthWeekday', month: 5, weekday: 1, n: -1 }, category: 'federal', observed: false },
  { id: 'juneteenth', name: 'Juneteenth', rule: { kind: 'fixed', month: 6, day: 19 }, category: 'federal', observed: true },
  { id: 'independence-day', name: 'Independence Day', rule: { kind: 'fixed', month: 7, day: 4 }, category: 'federal', observed: true },
  { id: 'labor-day', name: 'Labor Day', rule: { kind: 'nthWeekday', month: 9, weekday: 1, n: 1 }, category: 'federal', observed: false },
  { id: 'columbus-day', name: 'Columbus Day', rule: { kind: 'nthWeekday', month: 10, weekday: 1, n: 2 }, category: 'federal', observed: false },
  { id: 'veterans-day', name: 'Veterans Day', rule: { kind: 'fixed', month: 11, day: 11 }, category: 'federal', observed: true },
  { id: 'thanksgiving', name: 'Thanksgiving Day', rule: { kind: 'nthWeekday', month: 11, weekday: 4, n: 4 }, category: 'federal', observed: false },
  { id: 'christmas-day', name: 'Christmas Day', rule: { kind: 'fixed', month: 12, day: 25 }, category: 'federal', observed: true },

  // ---- Observances (secular) ----
  { id: 'groundhog-day', name: 'Groundhog Day', rule: { kind: 'fixed', month: 2, day: 2 }, category: 'observance', observed: false },
  { id: 'valentines-day', name: "Valentine's Day", rule: { kind: 'fixed', month: 2, day: 14 }, category: 'observance', observed: false },
  { id: 'st-patricks-day', name: "St. Patrick's Day", rule: { kind: 'fixed', month: 3, day: 17 }, category: 'observance', observed: false },
  { id: 'earth-day', name: 'Earth Day', rule: { kind: 'fixed', month: 4, day: 22 }, category: 'observance', observed: false },
  { id: 'cinco-de-mayo', name: 'Cinco de Mayo', rule: { kind: 'fixed', month: 5, day: 5 }, category: 'observance', observed: false },
  { id: 'mothers-day', name: "Mother's Day", rule: { kind: 'nthWeekday', month: 5, weekday: 0, n: 2 }, category: 'observance', observed: false },
  { id: 'flag-day', name: 'Flag Day', rule: { kind: 'fixed', month: 6, day: 14 }, category: 'observance', observed: false },
  { id: 'fathers-day', name: "Father's Day", rule: { kind: 'nthWeekday', month: 6, weekday: 0, n: 3 }, category: 'observance', observed: false },
  { id: 'halloween', name: 'Halloween', rule: { kind: 'fixed', month: 10, day: 31 }, category: 'observance', observed: false },
  { id: 'new-years-eve', name: "New Year's Eve", rule: { kind: 'fixed', month: 12, day: 31 }, category: 'observance', observed: false },

  // ---- Christian (liturgical) ----
  { id: 'epiphany', name: 'Epiphany', rule: { kind: 'fixed', month: 1, day: 6 }, category: 'christian', observed: false },
  { id: 'ash-wednesday', name: 'Ash Wednesday', rule: { kind: 'easterOffset', days: -46 }, category: 'christian', observed: false },
  { id: 'palm-sunday', name: 'Palm Sunday', rule: { kind: 'easterOffset', days: -7 }, category: 'christian', observed: false },
  { id: 'maundy-thursday', name: 'Maundy Thursday', rule: { kind: 'easterOffset', days: -3 }, category: 'christian', observed: false },
  { id: 'good-friday', name: 'Good Friday', rule: { kind: 'easterOffset', days: -2 }, category: 'christian', observed: false },
  { id: 'easter-sunday', name: 'Easter Sunday', rule: { kind: 'easterOffset', days: 0 }, category: 'christian', observed: false },
  { id: 'ascension-day', name: 'Ascension Day', rule: { kind: 'easterOffset', days: 39 }, category: 'christian', observed: false },
  { id: 'pentecost', name: 'Pentecost', rule: { kind: 'easterOffset', days: 49 }, category: 'christian', observed: false },
  { id: 'all-saints-day', name: "All Saints' Day", rule: { kind: 'fixed', month: 11, day: 1 }, category: 'christian', observed: false },
  { id: 'christmas-eve', name: 'Christmas Eve', rule: { kind: 'fixed', month: 12, day: 24 }, category: 'christian', observed: false },
];
