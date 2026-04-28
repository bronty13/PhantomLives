# Regex Cheatsheet

MacSearchReplace uses ICU regex via `NSRegularExpression` for the in-app and
CLI replace engine, and ripgrep's regex (Rust `regex` crate) for the search
backend. The two are highly compatible; differences flagged below.

## Common syntax

| Pattern        | Meaning                                |
|----------------|----------------------------------------|
| `.`            | Any character (not newline by default) |
| `\d` `\D`      | Digit / non-digit                      |
| `\w` `\W`      | Word char / non-word char              |
| `\s` `\S`      | Whitespace / non-whitespace            |
| `\b`           | Word boundary                          |
| `^` `$`        | Start / end of line (with multiline)   |
| `[abc]` `[^a]` | Character class / negated              |
| `a*` `a+` `a?` | Quantifiers                            |
| `a{2,5}`       | Range quantifier                       |
| `(abc)`        | Capture group                          |
| `(?:abc)`      | Non-capturing group                    |
| `(?i)abc`      | Inline case-insensitive flag           |
| `\1` / `$1`    | Backref / replacement reference        |

## Multi-line

Enable the **¶ Multi-line** toggle (or `multiline: true` in scripts). This
sets `--multiline --multiline-dotall` for ripgrep search, and
`.dotMatchesLineSeparators` for the replace engine, so `.` matches `\n`.

## Counters in replacement

```
ID-#{1000,1,%04d}
```

Expands to `ID-1000`, `ID-1001`, … one per match in the file.
Format string is printf-style.

## File / path tokens

```
// header for: %FILE%
```

Requires `interpolatePathTokens: true` on the step.

## Notable differences from PCRE

- No lookbehind in ripgrep search (Rust `regex` crate). The replace engine
  (NSRegularExpression / ICU) **does** support lookbehind.
- Atomic groups `(?>…)` not supported.
- For very advanced PCRE features, switch the backend to ripgrep's PCRE2 mode
  (planned: `--pcre2` flag passthrough).
