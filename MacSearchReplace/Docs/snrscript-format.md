# `.snrscript` File Format (v1)

Saved search/replace pipelines. JSON, human-readable, diff-friendly.

## Schema

```json
{
  "version": 1,
  "name": "Rename oldName → newName",
  "roots": ["/Users/me/code"],
  "include": ["*.swift", "*.m"],
  "exclude": ["Pods/**", ".build/**"],
  "honorGitignore": true,
  "followSymlinks": false,
  "maxFileBytes": 5242880,
  "modifiedAfter": "2025-01-01T00:00:00Z",
  "steps": [
    {
      "type": "regex",
      "search": "\\boldName\\b",
      "replace": "newName",
      "caseInsensitive": false,
      "multiline": false,
      "counter": false,
      "interpolatePathTokens": false
    },
    {
      "type": "literal",
      "search": "TODO(old)",
      "replace": "TODO(new)"
    },
    {
      "type": "literal",
      "search": "ID-XXX",
      "replace": "ID-#{1000,1,%04d}",
      "counter": true
    }
  ]
}
```

## Step types

| Type      | Meaning                                                                        |
|-----------|--------------------------------------------------------------------------------|
| `literal` | Plain string match. Search backend uses `rg -F`.                                |
| `regex`   | ICU regex via `NSRegularExpression`; replacement supports `$1`…`$9` backrefs.   |
| `binary`  | Hex bytes (e.g. `CAFE BABE`). Length-changing edits require explicit opt-in.    |

## Replacement tokens

| Token                     | Replaced with                       |
|---------------------------|-------------------------------------|
| `$1`…`$9`                 | regex capture groups                |
| `#{start,step,format}`    | per-match counter (printf format)   |
| `%FILE%`                  | filename                            |
| `%PATH%`                  | full path                           |
| `%BASENAME%`              | filename without extension          |

Counter and path tokens require their corresponding flags (`counter: true`,
`interpolatePathTokens: true`) on the step.
