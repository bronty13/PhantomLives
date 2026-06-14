import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { Markdown } from '../src/app/components/Markdown';
import { USER_MANUAL_MD } from '../src/data/manual';

describe('Markdown renderer', () => {
  it('renders headings, lists, bold, code, and links', () => {
    const md = [
      '# Title',
      '',
      'A paragraph with **bold** and `code` and a [link](https://example.com).',
      '',
      '- one',
      '- two',
      '',
      '1. first',
      '2. second',
    ].join('\n');
    const { container } = render(<Markdown md={md} />);

    expect(screen.getByText('Title')).toBeTruthy();
    expect(container.querySelector('strong')?.textContent).toBe('bold');
    expect(container.querySelector('code')?.textContent).toBe('code');
    // Bold (**) must win over italic (*) — no stray <em> inside bold.
    const boldOnly = render(<Markdown md={'**hi** and *there*'} />);
    expect(boldOnly.container.querySelector('strong')?.textContent).toBe('hi');
    expect(boldOnly.container.querySelector('em')?.textContent).toBe('there');
    const link = container.querySelector('a');
    expect(link?.getAttribute('href')).toBe('https://example.com');
    expect(container.querySelectorAll('ul li')).toHaveLength(2);
    expect(container.querySelectorAll('ol li')).toHaveLength(2);
  });

  it('groups consecutive bullet lines into a single list', () => {
    const { container } = render(<Markdown md={'- a\n- b\n- c'} />);
    expect(container.querySelectorAll('ul')).toHaveLength(1);
    expect(container.querySelectorAll('ul li')).toHaveLength(3);
  });
});

describe('in-app User Manual content', () => {
  it('inlines the real USER_MANUAL.md and renders its title + key sections', () => {
    expect(USER_MANUAL_MD).toContain('# CalendarMaker — User Manual');
    const { container } = render(<Markdown md={USER_MANUAL_MD} />);
    const text = container.textContent ?? '';
    // A few sections every user needs.
    expect(text).toContain('Making a new calendar');
    expect(text).toContain('Printing your calendar');
    expect(text).toContain('Getting updates');
  });
});
