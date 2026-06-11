/**
 * @file icons.tsx — tiny inline SVG icon set (16px grid, stroke style).
 */
import React from 'react';

interface IconProps {
  size?: number;
}

function svg(path: React.ReactNode, size = 16, viewBox = '0 0 16 16'): React.JSX.Element {
  return (
    <svg
      width={size}
      height={size}
      viewBox={viewBox}
      fill="none"
      stroke="currentColor"
      strokeWidth="1.4"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {path}
    </svg>
  );
}

export const ChevronRight = ({ size = 12 }: IconProps): React.JSX.Element =>
  svg(<path d="M6 3.5 10.5 8 6 12.5" />, size);

export const Plus = ({ size = 14 }: IconProps): React.JSX.Element =>
  svg(<path d="M8 3v10M3 8h10" />, size);

export const Dots = ({ size = 14 }: IconProps): React.JSX.Element =>
  svg(
    <>
      <circle cx="3.2" cy="8" r="1.1" fill="currentColor" stroke="none" />
      <circle cx="8" cy="8" r="1.1" fill="currentColor" stroke="none" />
      <circle cx="12.8" cy="8" r="1.1" fill="currentColor" stroke="none" />
    </>,
    size
  );

export const PageGlyph = ({ size = 14 }: IconProps): React.JSX.Element =>
  svg(
    <>
      <path d="M4 1.8h5.2L12 4.6v9.6H4z" />
      <path d="M9 2v3h3M6 8h4M6 10.5h4" />
    </>,
    size
  );

export const DatabaseGlyph = ({ size = 14 }: IconProps): React.JSX.Element =>
  svg(
    <>
      <rect x="2.2" y="3" width="11.6" height="10" rx="1.2" />
      <path d="M2.2 6.4h11.6M6.2 6.4V13" />
    </>,
    size
  );

export const Star = ({ size = 14, filled = false }: IconProps & { filled?: boolean }): React.JSX.Element =>
  svg(
    <path
      d="M8 1.8l1.9 3.9 4.3.6-3.1 3 .7 4.3L8 11.6l-3.8 2 .7-4.3-3.1-3 4.3-.6z"
      fill={filled ? 'currentColor' : 'none'}
    />,
    size
  );

export const TrashGlyph = ({ size = 14 }: IconProps): React.JSX.Element =>
  svg(
    <>
      <path d="M2.5 4h11M5.5 4V2.6h5V4M3.8 4l.7 9.4h7l.7-9.4" />
      <path d="M6.4 6.5v4.5M9.6 6.5v4.5" />
    </>,
    size
  );

export const SearchGlyph = ({ size = 14 }: IconProps): React.JSX.Element =>
  svg(
    <>
      <circle cx="7" cy="7" r="4.4" />
      <path d="M10.4 10.4 14 14" />
    </>,
    size
  );

export const GearGlyph = ({ size = 14 }: IconProps): React.JSX.Element =>
  svg(
    <>
      <circle cx="8" cy="8" r="2.2" />
      <path d="M8 1.8v2M8 12.2v2M1.8 8h2M12.2 8h2M3.6 3.6l1.4 1.4M11 11l1.4 1.4M12.4 3.6 11 5M5 11l-1.4 1.4" />
    </>,
    size
  );

export const ArrowUpDown = ({ size = 13 }: IconProps): React.JSX.Element =>
  svg(<path d="M5 2.8v10.4M5 2.8 2.6 5.2M5 2.8 7.4 5.2M11 13.2V2.8M11 13.2l-2.4-2.4M11 13.2l2.4-2.4" />, size);

export const FilterGlyph = ({ size = 13 }: IconProps): React.JSX.Element =>
  svg(<path d="M2 3.5h12M4.5 8h7M6.8 12.5h2.4" />, size);

export const RestoreGlyph = ({ size = 14 }: IconProps): React.JSX.Element =>
  svg(<path d="M3 7a5 5 0 1 1 1.5 3.5M3 7V3.5M3 7h3.5" />, size);

export const ExportGlyph = ({ size = 14 }: IconProps): React.JSX.Element =>
  svg(
    <>
      <path d="M8 2.5v7.5M8 2.5 5.2 5.3M8 2.5l2.8 2.8" />
      <path d="M3 10.5V13a.8.8 0 0 0 .8.8h8.4a.8.8 0 0 0 .8-.8v-2.5" />
    </>,
    size
  );

export const DuplicateGlyph = ({ size = 14 }: IconProps): React.JSX.Element =>
  svg(
    <>
      <rect x="5" y="5" width="8.5" height="8.5" rx="1.2" />
      <path d="M11 2.8H3.8A1.3 1.3 0 0 0 2.5 4v7.2" />
    </>,
    size
  );

export const RenameGlyph = ({ size = 14 }: IconProps): React.JSX.Element =>
  svg(<path d="m9.6 3 3.4 3.4-7.4 7.4-3.9.5.5-3.9zM8.3 4.3l3.4 3.4" />, size);

export const SidebarToggle = ({ size = 15 }: IconProps): React.JSX.Element =>
  svg(
    <>
      <rect x="1.8" y="2.5" width="12.4" height="11" rx="1.4" />
      <path d="M6 2.5v11" />
    </>,
    size
  );

export const TYPE_GLYPHS: Record<string, string> = {
  title: 'Aa',
  text: 'Aa',
  number: '#',
  select: '◦',
  multiSelect: '≔',
  date: '📅',
  checkbox: '☑',
  url: '🔗'
};
