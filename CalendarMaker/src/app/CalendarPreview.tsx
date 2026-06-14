import { useLayoutEffect, useRef, useState } from 'react';
import type { CalendarBundle, Theme } from '../model/types';
import { MONTH_NAMES, WEEKDAY_ABBR } from '../model/types';
import { computeWeeks, largestBlankRun, weekdayOrder } from '../calendar/grid';
import { classifyDay, type FitContext } from '../calendar/fit';
import { CELL, monthGeometry } from '../pdf/geometry';
import { cssFontFamily } from '../data/fonts';
import { holidayNamesFor } from '../pdf/holidayNames';

interface Props {
  bundle: CalendarBundle;
  theme: Theme;
  cap: number;
  onSelectDay?: (date: string) => void;
  selectedDate?: string | null;
}

/** A scaled, WYSIWYG HTML render of the month page (matches the PDF geometry). */
export function CalendarPreview({ bundle, theme, cap, onSelectDay, selectedDate }: Props) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);

  const grid = computeWeeks(bundle.year, bundle.month, bundle.weekStartsOn);
  const footerFiller = bundle.fillers.find((f) => f.slot === 'footer');
  const gridFiller = bundle.fillers.find((f) => f.slot === 'grid');
  const geo = monthGeometry(grid.weeks, !!footerFiller);
  const ctx: FitContext = { geo, theme, cap };
  const order = weekdayOrder(bundle.weekStartsOn);

  useLayoutEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const apply = () => setScale(Math.min(1.15, el.clientWidth / geo.pageW));
    apply();
    const ro = new ResizeObserver(apply);
    ro.observe(el);
    return () => ro.disconnect();
  }, [geo.pageW]);

  const run = gridFiller ? largestBlankRun(grid) : null;
  let fillerRect: { x: number; y: number; w: number; h: number } | null = null;
  if (gridFiller && run && run.count >= 1) {
    const startR = Math.floor(run.start / 7);
    const startC = run.start % 7;
    const sameRowCount = Math.min(run.count, 7 - startC);
    fillerRect = {
      x: geo.gridX + startC * geo.colW + 6,
      y: geo.gridY + startR * geo.rowH + 4,
      w: sameRowCount * geo.colW - 12,
      h: geo.rowH - 8,
    };
  }

  return (
    <div className="preview-wrap" ref={wrapRef}>
      <div
        className="cal-page"
        style={{
          width: geo.pageW,
          height: geo.pageH,
          transform: `scale(${scale})`,
          marginBottom: geo.pageH * (scale - 1),
          background: theme.calendar.backgroundColor,
        }}
      >
        {/* Title */}
        <div
          style={{
            position: 'absolute', left: geo.titleBand.x, top: geo.titleBand.y, width: geo.titleBand.w, height: geo.titleBand.h,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontFamily: cssFontFamily(theme.calendar.titleFont), fontWeight: 700, fontSize: 30, color: theme.calendar.titleColor,
          }}
        >
          {MONTH_NAMES[bundle.month - 1]} {bundle.year}
        </div>

        {/* Weekday header */}
        <div
          style={{
            position: 'absolute', left: geo.weekdayHeader.x, top: geo.weekdayHeader.y, width: geo.weekdayHeader.w, height: geo.weekdayHeader.h,
            background: theme.calendar.headerBackground, display: 'flex',
          }}
        >
          {order.map((wd, c) => (
            <div
              key={c}
              style={{
                width: geo.colW, textAlign: 'center', alignSelf: 'center',
                fontFamily: cssFontFamily(theme.calendar.headerFont), fontWeight: 700, fontSize: 11, color: theme.calendar.headerColor,
              }}
            >
              {WEEKDAY_ABBR[wd]}
            </div>
          ))}
        </div>

        {/* Cells */}
        {grid.cells.map((cell, i) => {
          const r = Math.floor(i / 7);
          const c = i % 7;
          const x = geo.gridX + c * geo.colW;
          const y = geo.gridY + r * geo.rowH;
          const day = cell.date ? bundle.days[cell.date] : undefined;
          const holidayNames = holidayNamesFor(day);
          const verseMode = bundle.verseMode ?? 'force';
          const cls = classifyDay(day ?? { date: cell.date ?? '', items: [], holidayIds: [] }, ctx, holidayNames.length, verseMode);
          const nonForceItems = cls.monthItems.filter((i) => !cls.forceItems.includes(i));
          return (
            <div
              key={i}
              className={`cal-cell${cell.inMonth ? '' : ' blank'}`}
              style={{
                left: x, top: y, width: geo.colW, height: geo.rowH,
                border: `0.75px solid ${theme.calendar.gridLineColor}`,
                outline: selectedDate && cell.date === selectedDate ? `2px solid ${theme.calendar.headerBackground}` : undefined,
                outlineOffset: -2,
              }}
              onClick={() => cell.inMonth && cell.date && onSelectDay?.(cell.date)}
            >
              {cell.inMonth && (
                <>
                  <div style={{ position: 'absolute', left: CELL.PAD, top: CELL.PAD - 1, fontFamily: cssFontFamily(theme.calendar.titleFont), fontWeight: 700, fontSize: 11, color: theme.calendar.dayNumberColor }}>
                    {cell.day}
                  </div>
                  <div style={{ position: 'absolute', left: CELL.PAD, right: CELL.PAD, top: CELL.PAD + CELL.DATE_LINE_H }}>
                    {holidayNames.map((name, hi) => (
                      <div key={hi} style={{ fontFamily: cssFontFamily(theme.calendar.holidayFont), fontSize: CELL.HOLIDAY_FONT, lineHeight: `${CELL.HOLIDAY_LINE_H}px`, color: theme.calendar.holidayColor, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                        {name}
                      </div>
                    ))}
                    {verseMode === 'force' && cls.forceItems.map((item) => {
                      const st = theme.itemStyles[item.type];
                      return (
                        <div key={item.id} style={{ marginBottom: CELL.CHIP_GAP, fontFamily: cssFontFamily(st.font), fontSize: CELL.CHIP_FONT - 0.5, lineHeight: `${CELL.CHIP_LINE_H}px`, color: st.color, overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 1, WebkitBoxOrient: 'vertical', fontStyle: 'italic' }}>
                          {item.text}
                          {item.reference && <> — {item.reference}</>}
                        </div>
                      );
                    })}
                    {nonForceItems.map((item) => {
                      const st = theme.itemStyles[item.type];
                      const suppressDot = verseMode === 'force' && cls.forceItems.length > 0;
                      return (
                        <div key={item.id} className="cal-chip" style={{ marginBottom: CELL.CHIP_GAP }}>
                          {!suppressDot && <span className="dot" style={{ background: st.color }} />}
                          <span style={{ fontFamily: cssFontFamily(st.font), fontSize: CELL.CHIP_FONT, lineHeight: `${CELL.CHIP_LINE_H}px`, color: st.color, overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: CELL.CHIP_MAX_LINES, WebkitBoxOrient: 'vertical' }}>
                            {item.text}
                          </span>
                        </div>
                      );
                    })}
                    {cls.detailOnly.length > 0 && (
                      <div style={{ fontSize: CELL.MORE_FONT, color: theme.overflowColor, fontFamily: cssFontFamily(theme.calendar.headerFont) }}>
                        +{cls.detailOnly.length} more (detail)
                      </div>
                    )}
                  </div>
                </>
              )}
            </div>
          );
        })}

        {/* Grid free-space filler */}
        {gridFiller && fillerRect && (
          <FillerBox theme={theme} text={gridFiller.entry.text} reference={gridFiller.entry.reference} rect={fillerRect} />
        )}

        {/* Footer filler */}
        {footerFiller && geo.footerBand && (
          <FillerBox
            theme={theme}
            text={footerFiller.entry.text}
            reference={footerFiller.entry.reference}
            rect={{ x: geo.footerBand.x + 12, y: geo.footerBand.y + 2, w: geo.footerBand.w - 24, h: geo.footerBand.h - 4 }}
          />
        )}
      </div>
    </div>
  );
}

function FillerBox({ theme, text, reference, rect }: { theme: Theme; text: string; reference?: string; rect: { x: number; y: number; w: number; h: number } }) {
  return (
    <div
      style={{
        position: 'absolute', left: rect.x, top: rect.y, width: rect.w, height: rect.h,
        display: 'flex', alignItems: 'center', justifyContent: 'center', textAlign: 'center',
        fontFamily: cssFontFamily(theme.calendar.fillerFont), color: theme.calendar.fillerColor,
        fontSize: 12, lineHeight: 1.25, overflow: 'hidden', padding: '0 4px',
      }}
    >
      <span>{text}{reference ? `  — ${reference}` : ''}</span>
    </div>
  );
}
