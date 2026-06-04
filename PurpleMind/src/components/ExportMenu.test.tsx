// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { ExportMenu } from './ExportMenu';

afterEach(cleanup);

function setup(busy = false) {
  const props = {
    busy,
    onExport: vi.fn(),
    onImport: vi.fn(),
    onCopy: vi.fn(),
  };
  render(<ExportMenu {...props} />);
  return props;
}

describe('ExportMenu', () => {
  it('is collapsed until clicked', () => {
    setup();
    expect(screen.queryByText('Image (PNG)')).toBeNull();
    fireEvent.click(screen.getByText(/Export \/ Import/));
    expect(screen.getByText('Image (PNG)')).toBeTruthy();
  });

  it('exports the chosen format', () => {
    const props = setup();
    fireEvent.click(screen.getByText(/Export \/ Import/));
    fireEvent.click(screen.getByText('Document (PDF)'));
    expect(props.onExport).toHaveBeenCalledWith('pdf');
  });

  it('exports the Mermaid mindmap diagram', () => {
    const props = setup();
    fireEvent.click(screen.getByText(/Export \/ Import/));
    fireEvent.click(screen.getByText(/Mindmap diagram/));
    expect(props.onExport).toHaveBeenCalledWith('mermaid');
  });

  it('copies the mindmap as Mermaid', () => {
    const props = setup();
    fireEvent.click(screen.getByText(/Export \/ Import/));
    fireEvent.click(screen.getByText('Mindmap as Mermaid'));
    expect(props.onCopy).toHaveBeenCalledWith('mermaid');
  });

  it('copies the outline as Markdown', () => {
    const props = setup();
    fireEvent.click(screen.getByText(/Export \/ Import/));
    fireEvent.click(screen.getByText('Outline as Markdown'));
    expect(props.onCopy).toHaveBeenCalledWith('outline');
  });

  it('imports a JSON map', () => {
    const props = setup();
    fireEvent.click(screen.getByText(/Export \/ Import/));
    fireEvent.click(screen.getByText(/PurpleMind map \(JSON\)…/));
    expect(props.onImport).toHaveBeenCalledWith('json');
  });

  it('is disabled while busy', () => {
    setup(true);
    const btn = screen.getByText(/Working/).closest('button') as HTMLButtonElement;
    expect(btn.disabled).toBe(true);
  });
});
