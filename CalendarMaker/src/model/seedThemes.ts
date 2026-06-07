// The 10 built-in themes. Each maps the six item types to a font + color and
// defines the overall calendar palette. Built-ins are non-deletable; "Duplicate"
// makes an editable copy. Font keys come from src/data/fonts-registry.ts.

import type { ItemType, Theme } from './types';

interface Spec {
  id: string;
  name: string;
  // calendar chrome
  title: [string, string]; // [fontKey, color]
  header: [string, string];
  headerBg: string;
  gridLine: string;
  dayNumber: string;
  bg: string;
  holiday: [string, string];
  filler: [string, string];
  overflow: string;
  // per item type: [fontKey, color]
  prayer: [string, string];
  praise: [string, string];
  birthday: [string, string];
  lifeEvent: [string, string];
  churchEvent: [string, string];
  reminder: [string, string];
}

function build(s: Spec): Theme {
  const style = ([font, color]: [string, string]) => ({ font, color });
  const itemStyles: Record<ItemType, { font: string; color: string }> = {
    prayer: style(s.prayer),
    praise: style(s.praise),
    birthday: style(s.birthday),
    lifeEvent: style(s.lifeEvent),
    churchEvent: style(s.churchEvent),
    reminder: style(s.reminder),
  };
  return {
    id: s.id,
    name: s.name,
    builtin: true,
    itemStyles,
    calendar: {
      titleFont: s.title[0],
      titleColor: s.title[1],
      headerFont: s.header[0],
      headerColor: s.header[1],
      headerBackground: s.headerBg,
      gridLineColor: s.gridLine,
      dayNumberColor: s.dayNumber,
      backgroundColor: s.bg,
      fillerFont: s.filler[0],
      fillerColor: s.filler[1],
      holidayFont: s.holiday[0],
      holidayColor: s.holiday[1],
    },
    overflowColor: s.overflow,
  };
}

export const SEED_THEMES: Theme[] = [
  build({
    id: 'theme-classic', name: 'Classic',
    title: ['playfair', '#1f2d4d'], header: ['lora', '#ffffff'], headerBg: '#1f2d4d',
    gridLine: '#c7ccd6', dayNumber: '#1f2d4d', bg: '#fbfaf6', holiday: ['lora', '#9a1b2f'],
    filler: ['lora', '#4a4a4a'], overflow: '#9aa0ad',
    prayer: ['lora', '#3a5a78'], praise: ['lora', '#0f7a4a'], birthday: ['lora', '#c0397a'],
    lifeEvent: ['inter', '#2b2b2b'], churchEvent: ['playfair', '#6b2d8a'], reminder: ['inter', '#8a6d1f'],
  }),
  build({
    id: 'theme-springtime', name: 'Springtime',
    title: ['caveat', '#3f7d4f'], header: ['nunito', '#ffffff'], headerBg: '#7bbf7e',
    gridLine: '#cfe8cf', dayNumber: '#3f7d4f', bg: '#f6fbf3', holiday: ['nunito', '#d2497a'],
    filler: ['caveat', '#5a7a4a'], overflow: '#a9c0a3',
    prayer: ['nunito', '#3f7d8f'], praise: ['nunito', '#2f9d5b'], birthday: ['caveat', '#e0568f'],
    lifeEvent: ['nunito', '#4a4a4a'], churchEvent: ['nunito', '#7a5db0'], reminder: ['nunito', '#b07d2f'],
  }),
  build({
    id: 'theme-advent', name: 'Advent',
    title: ['playfair', '#4b1d6b'], header: ['playfair', '#f3e7c9'], headerBg: '#4b1d6b',
    gridLine: '#d8cbe6', dayNumber: '#4b1d6b', bg: '#faf6ef', holiday: ['lora', '#b8860b'],
    filler: ['playfair', '#6b3f8a'], overflow: '#b3a7c2',
    prayer: ['lora', '#4b1d6b'], praise: ['lora', '#b8860b'], birthday: ['lora', '#9a1b6b'],
    lifeEvent: ['lora', '#3a3a3a'], churchEvent: ['playfair', '#7a1d2f'], reminder: ['lora', '#6b5b2f'],
  }),
  build({
    id: 'theme-autumn', name: 'Autumn',
    title: ['merriweather', '#7a3b14'], header: ['merriweather', '#fff4e6'], headerBg: '#9a4f1e',
    gridLine: '#e7cfb5', dayNumber: '#7a3b14', bg: '#fdf8f1', holiday: ['merriweather', '#9a1b1b'],
    filler: ['merriweather', '#6b4a2f'], overflow: '#c2ab92',
    prayer: ['merriweather', '#6b4a2f'], praise: ['merriweather', '#b5651d'], birthday: ['merriweather', '#a8326e'],
    lifeEvent: ['inter', '#3a3a3a'], churchEvent: ['merriweather', '#7a3b14'], reminder: ['inter', '#8a5a1f'],
  }),
  build({
    id: 'theme-ocean', name: 'Ocean',
    title: ['montserrat', '#0d4d63'], header: ['montserrat', '#ffffff'], headerBg: '#1186a3',
    gridLine: '#bfe0e8', dayNumber: '#0d4d63', bg: '#f3fafc', holiday: ['montserrat', '#c0392b'],
    filler: ['inter', '#2f6b7a'], overflow: '#9fc2cc',
    prayer: ['inter', '#1186a3'], praise: ['inter', '#0f9d8a'], birthday: ['montserrat', '#d4498f'],
    lifeEvent: ['inter', '#2b2b2b'], churchEvent: ['montserrat', '#3a5db0'], reminder: ['inter', '#7a6d2f'],
  }),
  build({
    id: 'theme-sunshine', name: 'Sunshine',
    title: ['pacifico', '#e07b1a'], header: ['nunito', '#5a3a00'], headerBg: '#ffd24a',
    gridLine: '#f3e2b0', dayNumber: '#a6611a', bg: '#fffdf2', holiday: ['nunito', '#d63a3a'],
    filler: ['pacifico', '#e07b1a'], overflow: '#cdbb8a',
    prayer: ['nunito', '#2f7da0'], praise: ['nunito', '#e07b1a'], birthday: ['nunito', '#e0568f'],
    lifeEvent: ['nunito', '#4a4a4a'], churchEvent: ['nunito', '#8a5db0'], reminder: ['nunito', '#b07d2f'],
  }),
  build({
    id: 'theme-midnight', name: 'Midnight',
    title: ['montserrat', '#e8ecf5'], header: ['montserrat', '#c9d2e6'], headerBg: '#1b2238',
    gridLine: '#39405a', dayNumber: '#c9d2e6', bg: '#11162a', holiday: ['inter', '#ff8a8a'],
    filler: ['inter', '#aeb6cc'], overflow: '#5a6280',
    prayer: ['inter', '#7fb0ff'], praise: ['inter', '#5fd6a0'], birthday: ['montserrat', '#ff8ac0'],
    lifeEvent: ['inter', '#dfe4f0'], churchEvent: ['montserrat', '#c08aff'], reminder: ['inter', '#e0c878'],
  }),
  build({
    id: 'theme-blossom', name: 'Blossom',
    title: ['dancing', '#b03a6e'], header: ['playfair', '#ffffff'], headerBg: '#d98aa8',
    gridLine: '#f2d6e0', dayNumber: '#b03a6e', bg: '#fdf5f8', holiday: ['playfair', '#9a1b4f'],
    filler: ['dancing', '#b03a6e'], overflow: '#d9b3c2',
    prayer: ['playfair', '#7a4a8a'], praise: ['dancing', '#d4498f'], birthday: ['dancing', '#e0568f'],
    lifeEvent: ['lora', '#4a3a3a'], churchEvent: ['playfair', '#8a2d6b'], reminder: ['lora', '#9a6d4f'],
  }),
  build({
    id: 'theme-forest', name: 'Forest',
    title: ['lora', '#22432b'], header: ['lora', '#eef3e6'], headerBg: '#2f5d3a',
    gridLine: '#cdddc4', dayNumber: '#22432b', bg: '#f5f9f1', holiday: ['lora', '#8a3b1b'],
    filler: ['lora', '#3f5d3a'], overflow: '#aebfa3',
    prayer: ['lora', '#2f5d6b'], praise: ['lora', '#2f7d4a'], birthday: ['lora', '#a8326e'],
    lifeEvent: ['inter', '#3a3a3a'], churchEvent: ['lora', '#5a3b8a'], reminder: ['inter', '#7a5d2f'],
  }),
  build({
    id: 'theme-berry', name: 'Berry',
    title: ['montserrat', '#6b1b4f'], header: ['montserrat', '#ffffff'], headerBg: '#9a2d6b',
    gridLine: '#e6c4da', dayNumber: '#6b1b4f', bg: '#fcf4f9', holiday: ['caveat', '#b8336a'],
    filler: ['caveat', '#8a2d6b'], overflow: '#cba7bf',
    prayer: ['inter', '#5a3b8a'], praise: ['caveat', '#b8336a'], birthday: ['caveat', '#d4498f'],
    lifeEvent: ['inter', '#3a3a3a'], churchEvent: ['montserrat', '#7a1d6b'], reminder: ['inter', '#8a5d2f'],
  }),
];
