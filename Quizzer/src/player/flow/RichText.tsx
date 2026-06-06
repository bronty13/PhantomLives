import { sanitizeHtml } from '../../shared/sanitize';

/** Render author-provided WYSIWYG HTML, sanitized at render time. */
export function RichText({ html, className }: { html: string; className?: string }) {
  if (!html || !html.trim()) return null;
  return (
    <div
      className={`rich ${className ?? ''}`}
      dangerouslySetInnerHTML={{ __html: sanitizeHtml(html) }}
    />
  );
}
