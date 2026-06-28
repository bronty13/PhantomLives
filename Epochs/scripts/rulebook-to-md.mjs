// Generate a Markdown copy of the in-app Rulebook (our own-words rules + original
// sample game) from src/renderer/rulebook.ts — the single source of truth, so the
// app view and the exported note can't drift. This emits OUR OWN content only.
//
// Usage:  node scripts/rulebook-to-md.mjs [output.md]
//   default output: ~/Downloads/Epochs/Epochs-Rulebook.md
// Move the result wherever you like (e.g. an Obsidian vault folder).

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { homedir } from 'node:os'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = readFileSync(join(root, 'src/renderer/rulebook.ts'), 'utf8')

// Pull each { id, title, body: `...` } section out of the source.
const sections = [...src.matchAll(/\{\s*id:\s*'([^']+)',\s*title:\s*'([^']+)',\s*body:\s*`([\s\S]*?)`,?\s*\}/g)]
if (sections.length === 0) {
  console.error('no rule sections found — did rulebook.ts change shape?')
  process.exit(1)
}

function htmlToMd(html) {
  let s = html
    // template vars + named entities the bodies use
    .replace(/\$\{RESOURCE\}/g, '◆')
    .replace(/&nbsp;/g, ' ')
    // inline marks (do before block handling so they survive whitespace collapse)
    .replace(/<\/?(?:b|strong)>/g, '**')
    .replace(/<\/?(?:i|em)>/g, '*')
    .replace(/<\/?code>/g, '`')
    // lists → bullets
    .replace(/<(ul|ol)>([\s\S]*?)<\/\1>/g, (_, _tag, inner) =>
      '\n' +
      [...inner.matchAll(/<li>([\s\S]*?)<\/li>/g)]
        .map((m) => '- ' + m[1].replace(/\s+/g, ' ').trim())
        .join('\n') +
      '\n\n',
    )
    // paragraphs → one line each
    .replace(/<p>([\s\S]*?)<\/p>/g, (_, inner) => inner.replace(/\s+/g, ' ').trim() + '\n\n')
    // strip any stragglers + decode entities
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
  // left-trim every line (kills any residual source indentation), tidy blank runs
  s = s
    .split('\n')
    .map((l) => l.replace(/^[ \t]+/, '').replace(/[ \t]+$/, ''))
    .join('\n')
  return s.replace(/\n{3,}/g, '\n\n').trim()
}

let md = `# Epochs — Rulebook\n\n`
md += `> A faithful reference to **Epochs'** actual rules, in our own words (the game diverges from the original\n`
md += `> board game in documented ways). Generated from the in-app rulebook — do not edit by hand; re-run\n`
md += `> \`node scripts/rulebook-to-md.mjs\` after changing \`src/renderer/rulebook.ts\`.\n\n`
md += sections.map(([, , title]) => `- [[#${title}]]`).join('\n') + '\n'
for (const [, , title, body] of sections) {
  md += `\n\n## ${title}\n\n${htmlToMd(body)}\n`
}

const out =
  process.argv[2] ?? join(homedir(), 'Downloads', 'Epochs', 'Epochs-Rulebook.md')
mkdirSync(dirname(out), { recursive: true })
writeFileSync(out, md)
console.log(`✓ ${sections.length} sections → ${out}`)
