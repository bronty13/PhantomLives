// CalendarMaker data model. One file, all interfaces, plus the schema version
// stamped into exported bundle files.

export const SCHEMA_VERSION = 1;
export const APP_VERSION = '0.2.1';
export const APP_NAME = 'CalendarMaker';

// ---- Items ----------------------------------------------------------------

export type ItemType =
  | 'prayer'
  | 'praise'
  | 'birthday'
  | 'lifeEvent'
  | 'churchEvent'
  | 'reminder';

export const ITEM_TYPES: ItemType[] = [
  'prayer',
  'praise',
  'birthday',
  'lifeEvent',
  'churchEvent',
  'reminder',
];

export const ITEM_TYPE_LABELS: Record<ItemType, string> = {
  prayer: 'Prayer',
  praise: 'Praise',
  birthday: 'Birthday',
  lifeEvent: 'Life Event',
  churchEvent: 'Church Event',
  reminder: 'Reminder',
};

export interface Item {
  id: string;
  type: ItemType;
  text: string;
  /** Derived + persisted by fit.ts. false → renders detail-view-only (⊘ marker). */
  showOnMonth: boolean;
  /** User pinned this to a month slot during overflow arbitration. */
  pinned: boolean;
  /** Per-day ordering within its cell. */
  order: number;
}

// ---- A single day ---------------------------------------------------------

export interface Day {
  /** ISO date key 'YYYY-MM-DD'. */
  date: string;
  items: Item[];
  /** Holiday IDs (from the catalog) the user toggled ON for this date. */
  holidayIds: string[];
}

// ---- Free-space filler (sayings / verses) ---------------------------------

export type FillerKind = 'saying' | 'verse';

export interface FillerEntry {
  id: string;
  kind: FillerKind;
  text: string;
  /** Verse: 'John 3:16'. Saying: the author/attribution. */
  reference?: string;
}

export type FillerSlot = 'footer' | 'grid';

/** A filler the user placed into the calendar (resolved from a catalog or ad-hoc). */
export interface FillerPlacement {
  slot: FillerSlot;
  entry: FillerEntry;
}

// ---- Holidays -------------------------------------------------------------

export type HolidayCategory = 'federal' | 'observance' | 'christian';

export type HolidayRule =
  | { kind: 'fixed'; month: number; day: number } // month 1-12
  | { kind: 'nthWeekday'; month: number; weekday: number; n: number } // weekday 0=Sun; n=-1 → last
  | { kind: 'easterOffset'; days: number }; // days relative to Easter Sunday

export interface HolidayDef {
  id: string;
  name: string;
  rule: HolidayRule;
  category: HolidayCategory;
  /** If it lands on a weekend, also surface the observed (shifted) weekday. */
  observed: boolean;
}

/** A holiday resolved to a concrete date within a given month/year. */
export interface ResolvedHoliday {
  def: HolidayDef;
  date: string; // 'YYYY-MM-DD'
  observed?: boolean; // true when this is the shifted observance, not the actual day
}

// ---- Themes ---------------------------------------------------------------

/** A font reference: a key into the embedded-font registry (data/fonts). */
export type FontKey = string;

export interface ItemStyle {
  font: FontKey;
  color: string; // hex
}

export interface Theme {
  id: string;
  name: string;
  builtin: boolean;
  /** Per-item-type styling. */
  itemStyles: Record<ItemType, ItemStyle>;
  /** Overall calendar styling. */
  calendar: {
    titleFont: FontKey;
    titleColor: string;
    headerFont: FontKey; // weekday header row
    headerColor: string;
    headerBackground: string;
    gridLineColor: string;
    dayNumberColor: string;
    backgroundColor: string;
    fillerFont: FontKey; // sayings / verses
    fillerColor: string;
    holidayFont: FontKey;
    holidayColor: string;
  };
  /** Distinct color for ⊘-marked (detail-only) items. */
  overflowColor: string;
}

// ---- The bundle (one saved calendar) --------------------------------------

export interface CalendarBundle {
  id: string;
  title: string; // = the save name
  year: number;
  month: number; // 1-12
  themeId: string;
  weekStartsOn: 0 | 1; // 0=Sun, 1=Mon
  days: Record<string, Day>; // keyed 'YYYY-MM-DD'
  fillers: FillerPlacement[];
  createdAt: number;
  updatedAt: number;
}

/** Portable export unit — opens identically on another machine. */
export interface BundleFile {
  schemaVersion: number;
  app: string;
  bundle: CalendarBundle;
  theme: Theme;
}

// ---- App settings ---------------------------------------------------------

export type ExportMode = 'month' | 'detail' | 'both';

export interface AppSettings {
  /** Name used in the home-screen greeting ("Good morning, Jan"). */
  userName: string;
  defaultThemeId: string;
  defaultWeekStartsOn: 0 | 1;
  /** Hard safety cap on items shown per month cell (fit math may allow fewer). */
  maxItemsPerMonthCell: number;
  defaultExportMode: ExportMode;
  showVerseOnHome: boolean;
  showSayingOnHome: boolean;
}

export const DEFAULT_APP_SETTINGS: AppSettings = {
  userName: 'Jan',
  defaultThemeId: 'theme-classic',
  defaultWeekStartsOn: 0,
  maxItemsPerMonthCell: 5,
  defaultExportMode: 'both',
  showVerseOnHome: true,
  showSayingOnHome: true,
};

export const MONTH_NAMES = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

export const WEEKDAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
export const WEEKDAY_ABBR = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
