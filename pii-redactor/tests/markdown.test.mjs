// Markdown renderer tests (powers the in-app User Manual).
import { test } from "node:test";
import assert from "node:assert/strict";
import { renderMarkdown, slugify } from "../src/markdown.js";

test("slugify produces anchor-safe ids", () => {
  assert.equal(slugify("Quick Start"), "quick-start");
  assert.equal(slugify("What gets detected?"), "what-gets-detected");
});

test("headings render with ids and populate the TOC (h2/h3 only)", () => {
  const { html, toc } = renderMarkdown("# Title\n\n## Section A\n\n### Sub\n\n#### Deep");
  assert.match(html, /<h1 id="title">Title<\/h1>/);
  assert.match(html, /<h2 id="section-a">Section A<\/h2>/);
  assert.deepEqual(toc.map((t) => t.id), ["section-a", "sub"]);
  assert.deepEqual(toc.map((t) => t.level), [2, 3]);
});

test("inline formatting: bold, italic, code", () => {
  const { html } = renderMarkdown("This is **bold**, *italic*, and `code`.");
  assert.match(html, /<strong>bold<\/strong>/);
  assert.match(html, /<em>italic<\/em>/);
  assert.match(html, /<code>code<\/code>/);
});

test("fenced code block is escaped, not interpreted", () => {
  const { html } = renderMarkdown("```\n<script>alert(1)</script>\n```");
  assert.match(html, /<pre><code>&lt;script&gt;/);
  assert.ok(!html.includes("<script>alert"));
});

test("GFM table renders thead + tbody", () => {
  const { html } = renderMarkdown("| A | B |\n| --- | --- |\n| 1 | 2 |");
  assert.match(html, /<table><thead><tr><th>A<\/th><th>B<\/th>/);
  assert.match(html, /<tbody><tr><td>1<\/td><td>2<\/td>/);
});

test("lists and blockquotes", () => {
  const ul = renderMarkdown("- one\n- two").html;
  assert.match(ul, /<ul><li>one<\/li><li>two<\/li><\/ul>/);
  const ol = renderMarkdown("1. a\n2. b").html;
  assert.match(ol, /<ol><li>a<\/li><li>b<\/li><\/ol>/);
  assert.match(renderMarkdown("> quoted").html, /<blockquote>quoted<\/blockquote>/);
});

test("html in prose is escaped", () => {
  assert.match(renderMarkdown("a < b & c > d").html, /a &lt; b &amp; c &gt; d/);
});
