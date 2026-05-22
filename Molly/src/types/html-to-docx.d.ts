// html-to-docx ships no types. Minimal shim sufficient for our use:
// render an HTML string into a DOCX Blob.
declare module 'html-to-docx' {
  interface DocumentOptions {
    margins?: { top: number; right: number; bottom: number; left: number };
    title?: string;
    creator?: string;
    font?: string;
    [key: string]: unknown;
  }
  function htmlToDocx(
    html: string,
    headerHTMLString?: string,
    options?: DocumentOptions,
  ): Promise<Blob>;
  export default htmlToDocx;
}
