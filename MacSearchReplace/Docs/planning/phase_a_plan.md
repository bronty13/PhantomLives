# Phase A — Funduc Engine: Concrete Implementation Plan

**Phase goal:** Replace the PCRE-based regex/replace path with a Funduc-syntax engine and Funduc-token replacement evaluator. After Phase A, the toggle "Funduc Regex" routes through the new code; the old PCRE path stays as a fallback during the transition. Acceptance gate is the catalog-derived test corpus.

**Dependencies on user decisions:**
- D1 = B (translator → ICU), with custom evaluators for `!`, `+n`, `^^`, `$$`
- D5 = A (Funduc replacement tokens replace `\#path`/`\#{counter}`)

**Author of plan:** Claude, 2026-04-27. Sources: `sr_feature_catalog.md` and the original CHM HTML at `~/Downloads/SR/html/`.

---

## A.0 — Findings from current codebase that constrain the design

From reading `Searcher.swift`, `Replacer.swift`, `SearchSpec.swift`, `ReplaceSpec.swift`, `Job.swift`:

1. `SearchSpec.PatternKind` is `.literal | .regex`. We will add `.funducRegex`.
2. `Searcher.stream(spec:)` switches on backend (ripgrep vs native fallback). **Ripgrep cannot be used for Funduc-syntax** because ripgrep speaks PCRE/Oniguruma. The Funduc path must always go through a Swift in-process matcher (similar in shape to existing `nativeStream`, but with a Funduc engine instead of `NSRegularExpression`).
3. `Replacer.rewriteText` builds an `NSRegularExpression`, runs `regex.replacementString(for:in:offset:template:)`, with a manual pre-pass for `\#{counter}` and `%FILE%`/`%PATH%`/`%BASENAME%` interpolation. We will replace this with a per-match Funduc token evaluator that **returns the final string** for each match, bypassing NSRegex's own template substitution.
4. The current `CounterToken` struct is hardcoded to `\#{start,step,format}` syntax. It will be deprecated; counters become first-class Funduc replacement tokens (`%n>>`, `%n>start>` etc.).
5. `Job` already manages search → preview → commit. No structural change needed; only the underlying `Searcher`/`Replacer` get new code paths.

### Funduc `*` semantics (verified against original docs)

From `~/Downloads/SR/html/HIDD_REGEXP_SEARCH_OP.htm`:
> `*` — Zero or More: Matches zero or more expressions enclosed in `()` or `[]`. `*` may be used by itself; if entered alone it will match all characters from start of line to end of line.

So:
- `*[0-9]` → zero-or-more digits. We translate to `[0-9]*` in ICU.
- Bare `*` → "all characters from start of line to end of line" → translate to `^.*$` (or equivalent).
- The "does NOT match characters under ASCII 32" caveat applies: bare `*` excludes control chars. Translator should emit `[\x20-\x{10FFFF}]*` for bare `*` to model this faithfully.
- Empty matches: at the search level we drop hits with `byteStart == byteEnd` so zero-length matches don't pollute results.

---

## A.1 — Module layout

Add two new SPM targets, both inside the existing `Packages/SnRCore/Sources/`:

```
Packages/SnRCore/Sources/SnRFunducRegex/
  ├── FunducPattern.swift       — public entry point + result types
  ├── FunducSyntaxError.swift   — typed error
  ├── AST.swift                 — node enum
  ├── Parser.swift              — recursive-descent parser (string → AST)
  ├── ICUTranslator.swift       — AST → (ICU pattern, backref map)
  ├── BackrefIndex.swift        — operator → numbered group mapping
  ├── PostFilter.swift          — applies `!` (NOT), drops empty matches, applies `+n` column constraint
  ├── FileAnchorMatcher.swift   — applies `^^` and `$$` at file level
  └── FunducMatcher.swift       — orchestrator: parse → translate → run NSRegex → post-filter

Packages/SnRCore/Sources/SnRFunducReplace/
  ├── FunducReplacement.swift   — public entry point
  ├── ReplacementToken.swift    — token enum
  ├── ReplacementParser.swift   — string → [ReplacementToken]
  ├── ReplacementContext.swift  — per-match context (file, captures, system clock, counter state)
  ├── ReplacementEvaluator.swift — tokens + context → output string
  ├── MathExpr.swift            — small expression parser/evaluator (E1..E31, + - * / %, printf format)
  └── EnvVarResolver.swift      — wraps Foundation environment reads (testable)

Packages/SnRCore/Tests/SnRFunducRegexTests/
  ├── ParserTests.swift
  ├── TranslatorTests.swift
  ├── EndToEndTests.swift       — every catalog example
  └── EdgeCaseTests.swift

Packages/SnRCore/Tests/SnRFunducReplaceTests/
  ├── ParserTests.swift
  ├── EvaluatorTests.swift
  ├── CounterTests.swift
  ├── MathTests.swift
  └── EndToEndTests.swift
```

Both new modules become dependencies of `SnRCore`. `SnRSearch` and `SnRReplace` get a *runtime* dependency (call into them when `useFunducSyntax` is true) — but to avoid circular deps, the wiring lives in a new orchestrator inside `SnRSearch` that imports `SnRFunducRegex`.

Updated `Package.swift` deps:
- `SnRFunducRegex` — depends on nothing (pure parsing + Foundation NSRegex).
- `SnRFunducReplace` — depends on `SnRFunducRegex` (shares `BackrefIndex` for `%n` resolution).
- `SnRSearch` — adds dep on `SnRFunducRegex`.
- `SnRReplace` — adds dep on `SnRFunducRegex` and `SnRFunducReplace`.
- `SnRCore` — adds both new modules to its `dependencies:` and re-exports.

---

## A.2 — `SnRFunducRegex` — detailed design

### A.2.1 — AST

```swift
public indirect enum FunducNode: Sendable, Equatable {
    case literal(String)                 // run of plain characters
    case anyChar                         // `?`  (one of any non-control char)
    case charClass(CharSet, negated: Bool)  // `[a-z]`, `[!abc]`
    case group([FunducNode])             // `( ... )`
    case alternation([[FunducNode]])     // `a|b|c`
    case zeroOrMore(FunducNode)          // `*X`
    case oneOrMore(FunducNode)           // `+X`
    case exactlyOne(FunducNode)          // `?X`
    case not(FunducNode)                 // `!X`
    case startOfLine                     // `^`
    case endOfLine                       // `$`
    case startOfFile                     // `^^`
    case endOfFile                       // `$$`
    case columnSpec(Int, FunducNode)     // `+n X`  e.g. `+5[a-z]`
    case columnRange(Int, Int, FunducNode)  // `+n-m X` e.g. `+5-15[0-9]`
}

public struct CharSet: Sendable, Equatable {
    public var ranges: [ClosedRange<Unicode.Scalar>]
    public var explicit: Set<Unicode.Scalar>
    /// Empty `[]` is special: it means "any non-control character".
    public var isEmpty: Bool
}
```

### A.2.2 — Parser

Hand-rolled recursive descent. Top-level produces `[FunducNode]`. Strict about Funduc's positional rules:

- `*`, `+`, `?` are *prefix* operators — they bind to the immediately-following `(...)` or `[...]`. If followed by anything else, they apply to the *whole rest of expression up to a delimiter* (Funduc's "alone, matches start to end of line" rule). The parser captures bare `*`/`+`/`?` as `case zeroOrMore(.charClass(emptyAnyExceptControl, false))` etc.
- `!` requires a following `(...)` or `[...]`.
- `^^` and `$$` parsed as 2-char tokens before `^` and `$`. They cannot appear inside `()` (the parser will throw `FunducSyntaxError.fileAnchorInsideGroup`).
- `+n` column specifier: `+` followed by an integer, then `[` or `(` or another expression. `+n-m` is the column-range form.
- Escape rule: `\` escapes `+ - * ? ( ) [ ] \ | ^ $ !` to literal characters.

The parser exposes:
```swift
public struct FunducPattern: Sendable {
    public let source: String
    public let nodes: [FunducNode]
    public let backrefIndex: BackrefIndex  // %1..%N → node positions
    public init(source: String) throws
}
```

### A.2.3 — Backreference indexing

Catalog quirk: **`^`, `$`, `^^`, `$$` count as `%n` parameters**. So:

```
^+[ ][a-zA-Z]
%1 = ^      (start-of-line)
%2 = +[ ]   (one or more spaces)
%3 = [a-zA-Z]
```

`BackrefIndex` walks the AST in source order and assigns each "operator-bearing node" a 1-based index. Anchors and column specifiers contribute to numbering even though they may not produce a meaningful captured substring (we surface anchors as empty-string captures in replacement).

```swift
public struct BackrefIndex: Sendable {
    public let count: Int
    public func nodeForBackref(_ n: Int) -> FunducNode?
    public func icuGroupNumber(forBackref n: Int) -> Int?  // -1 if backref is anchor-only
}
```

### A.2.4 — ICU translator

Walks the AST, emits ICU pattern (Foundation's NSRegularExpression / ICU dialect):

| Funduc node | ICU emission |
|---|---|
| `literal("foo")` | `\Qfoo\E` (quoted block) |
| `anyChar` | `[^\x00-\x1F]` (Funduc `?` = single non-control char) |
| `charClass([a-z], neg=false)` | `[a-z]` |
| `charClass([], neg=false)` (bare `[]`) | `[^\x00-\x1F]` |
| `group(children)` | `(?: ... )` for non-capturing layout, with selective capturing groups added by index manager |
| `alternation([a,b,c])` | `(?:a|b|c)` |
| `zeroOrMore(X)` | `X*` (greedy) |
| `oneOrMore(X)` | `X+` |
| `exactlyOne(X)` | `X` (no quantifier) |
| `startOfLine` | `^` (with `.anchorsMatchLines` option) |
| `endOfLine` | `$` |
| `startOfFile` | `\A` |
| `endOfFile` | `\z` |
| `not(X)` | **untranslatable in pure ICU** — see PostFilter below |
| `columnSpec(n, X)` | translated as `X` plus a post-filter that drops matches whose start column ≠ n |
| `columnRange(a,b,X)` | translated as `X` plus a post-filter for column-in-range |

Each operator-bearing node also wraps its translation in `(...)` to create a numbered capture, with the index recorded in `BackrefIndex`. Anchors (`^`, `$`, `^^`, `$$`) get a sentinel "no-capture" entry so `%n` still numbers correctly.

### A.2.5 — `!` (NOT) operator

The Funduc `!` operator means: match when the positive part matches AND the negated part *also has a match* in the same scope. From catalog:

> `?at!((b|c)at)` matches "mat" or "sat" but not "bat" or "cat"
> `*file!(beg*file)` matches "a file" but not "beginning of file"

Reading carefully: `?at!((b|c)at)` finds 3-char strings ending in "at" — but excluding ones that *are* "bat" or "cat". So `!(X)` means: match position must NOT also satisfy X.

Implementation: parse `!(X)` as `not(X)`. The translator emits the *positive* part, runs ICU. Then for each candidate match, the post-filter re-runs the ICU translation of `X` against the same span. If it matches, drop the candidate. Detail: scope of `X` is the same matched substring, anchored.

### A.2.6 — `+n` column specifier

From catalog:
> `w+2[a-z]` matches "Wor" in "World" (one `w`, then exactly 2 lowercase letters)
> `[ ]+5-15[0-9.]` matches numbers in column range 5–15

Two forms:
- **Quantifier form `+n`** after a class: "exactly n characters of this class". Translates to `[a-z]{2}` in ICU directly.
- **Column form `+n-m`** prefix: "match must start at columns n–m of the line". Implemented as a post-filter on column number.

The parser distinguishes by context. `[a-z]+2` after a class → quantifier. `+5-15[0-9]` at the start of a sub-expression → column anchor.

### A.2.7 — `^^` / `$$`

ICU has `\A` (start of input) and `\z` (end of input). When the engine runs against a single file's full text, those map directly. But our matcher operates per-line in some flows — so the matcher signals to the file-anchor checker which lines are line 1 and which is the final line, and constraints get enforced post-hoc. Easier: always run the engine in "whole-file" mode (we have to anyway for multi-line patterns).

Constraint from docs: **`^^` and `$$` cannot appear inside `()`** — parser enforces.

### A.2.8 — Output type

```swift
public struct FunducMatch: Sendable {
    public let range: Range<String.Index>       // in the searched text
    public let line: Int                         // 1-based
    public let column: Int                       // 1-based
    public let captures: [String?]               // by Funduc %n index (1-based; index 0 unused)
}

public struct FunducMatcher: Sendable {
    public init(pattern: FunducPattern, caseInsensitive: Bool, wholeWord: Bool, multiline: Bool)
    public func matches(in text: String) -> [FunducMatch]
}
```

`captures[n]` returns the substring captured for `%n`, or `nil` if it's an anchor.

### A.2.9 — Edge cases the tests must cover

- `*` alone matches whole line (one match per non-empty line).
- `*` does not match characters below ASCII 32 (so a line containing only tabs gives no matches).
- `*[0-9]` matches "0", "12", "345" — but does not match the empty string (post-filter).
- `^` and `$` in the same pattern → parser error (catalog quirk).
- Backslash escapes for all 13 metas: `- + * ? ( ) [ ] \ | ^ $ !`.
- `[!abc]` as negated class.
- `t[]e` matches "the", "toe" (empty `[]` = any single non-control char).

---

## A.3 — `SnRFunducReplace` — detailed design

### A.3.1 — Token enum

```swift
public enum ReplacementToken: Sendable, Equatable {
    case literal(String)                                  // plain text
    case backref(n: Int, transform: CaseTransform)        // %n, %n<, %n>
    case counterUp(n: Int, startValue: Int?, padding: Int) // %n>>, %n>start>
    case counterDown(n: Int, startValue: Int?, padding: Int)
    case math(n: Int, format: String, expression: MathExpr)
    case foundText                                        // %%srfound%%
    case filePath                                         // %%srpath%%
    case fileName                                         // %%srfile%%
    case fileDate(format: DateFormat)                     // %%srfiledate%%
    case fileTime(format: DateFormat)                     // %%srfiletime%%
    case fileSize                                         // %%srfilesize%%
    case systemDate                                       // %%srdate%%
    case systemTime                                       // %%srtime%%
    case envVar(name: String)                             // %%envvar=NAME%%
    case prependMarker                                    // %%srprepend%%
    case appendMarker                                     // %%srappend%%
    case formatColumn(Int)                                // %%srformat%%=nn

    public enum CaseTransform: Sendable { case none, lower, upper }
}
```

### A.3.2 — Parser

State-machine over the replacement string. Recognizes:

- `%` escape: `\%` → literal `%`; `\\` → literal `\`; `\<` → `<`; `\>` → `>`.
- `%n` where n is `1`–`9` → `backref(n)`. Followed by `<` or `>` → case transform.
- `%n>>` / `%n<<` → counter operators (parser disambiguates from `%n>` followed by `>`).
- `%n>integer>` / `%n<integer<` → counter with start.
- `%n<%format(expression)>` → math operation. The format spec is anything between `<` and the opening `(`; the expression is between `(` and `)`.
- Extended params: `%:` through `%N` map to params 10–31 via the ASCII table from the catalog (`123456789:;<=>?@ABCDEFGHIJKLMN`).
- `%%srfound%%`, `%%srpath%%`, etc. — recognized verbatim, case-insensitive.
- `%%envvar=NAME%%` — captures NAME as the variable name.
- `%%srformat%%=nn` — captures column number.

Output: `[ReplacementToken]`.

### A.3.3 — Context

```swift
public struct ReplacementContext: Sendable {
    public let captures: [String?]              // from FunducMatch
    public let foundText: String                // matched substring
    public let fileURL: URL
    public let fileAttributes: [FileAttributeKey: any Sendable]  // pre-replace snapshot
    public let systemDate: Date                 // captured at job start
    public let counters: CounterStateRef        // mutable across matches in same file
    public let environment: EnvVarResolver
    public let dateFormatter: DateFormatter     // configurable
    public let timeFormatter: DateFormatter
}

public final class CounterStateRef: @unchecked Sendable {
    // Per-token counter state. Key: token's source-position fingerprint.
    // Allows multiple counters in same replacement string to maintain independent state.
    public func currentValue(forKey: String, defaultStart: Int, step: Int) -> Int
    public func advance(forKey: String, by step: Int)
    public func reset()  // called per file when configured
}
```

### A.3.4 — Evaluator

Walks token list, returns final string for one match. Algorithm:

```
for token in tokens:
    case literal(s): out += s
    case backref(n, transform):
        let captured = ctx.captures[n] ?? ""
        out += apply(transform, to: captured)
    case counterUp(n, startValue, padding):
        let key = "\(tokenIndex)-\(n)"
        let initial = startValue ?? (Int(ctx.captures[n] ?? "0") ?? 0) + 1
        let value = ctx.counters.currentValue(forKey: key, defaultStart: initial, step: 1)
        out += String(format: "%0\(padding)d", value)
        ctx.counters.advance(forKey: key, by: 1)
    case counterDown(...): // mirror
    case math(n, format, expression):
        let value = expression.evaluate(captures: ctx.captures.map { Double($0 ?? "0") ?? 0 })
        out += String(format: format, value)
    case foundText: out += ctx.foundText
    case filePath: out += ctx.fileURL.deletingLastPathComponent().path
    case fileName: out += ctx.fileURL.lastPathComponent
    case fileDate(fmt): out += ctx.dateFormatter.string(from: ctx.fileAttributes[.modificationDate] as? Date ?? Date())
    // ... etc
```

### A.3.5 — Math sub-evaluator

Tiny Pratt parser for: numeric literals, `E1`–`E31` variables, `+ - * / %` infix, parens. ~150 LOC. Standalone, testable. Returns `Double`. The format spec (`%d`, `%f`, `%0.2lf`) is then applied via `String(format:)`.

### A.3.6 — Padding semantics

Catalog quirk: `%1>000>` starts at 001 (3 digits); `%1>0>` starts at 1 (1 digit). The number of zeros in the start value determines the padding. Parser captures this:

```swift
case counterUp(n: 1, startValue: 0, padding: 3)   // for %1>000>
case counterUp(n: 1, startValue: 0, padding: 1)   // for %1>0>
```

### A.3.7 — Prepend/append

`%%srprepend%%` and `%%srappend%%` are *markers*, not values. The replacer recognizes a replacement that starts/ends with one of these markers and routes to the prepend/append code path instead of substituting matches in place. Phase B will implement the actual prepend/append routine; Phase A leaves `prependMarker`/`appendMarker` as token types but evaluator returns empty string with a warning.

---

## A.4 — Wiring into `SnRSearch` / `SnRReplace`

### A.4.1 — `SearchSpec` change

Add to `SearchSpec.PatternKind`:
```swift
public enum PatternKind: String, Sendable, Codable, Hashable {
    case literal
    case regex          // existing PCRE path (kept temporarily for non-Funduc fallback)
    case funducRegex    // NEW
}
```

### A.4.2 — `Searcher.stream` routing

Add a third branch:
```swift
public func stream(spec: SearchSpec) -> Stream {
    if spec.kind == .funducRegex {
        return funducStream(spec: spec)
    }
    switch backend { ... existing ... }
}
```

`funducStream` reuses the existing native enumerator (file walker + glob matching + encoding detection) but applies `FunducMatcher` instead of `NSRegularExpression`. This bypasses ripgrep entirely — slower but unavoidable since ripgrep can't speak Funduc syntax.

### A.4.3 — `ReplaceSpec` change

Add a new mode:
```swift
public enum Mode: String, Sendable, Codable, Hashable {
    case literal
    case regex            // legacy
    case funducRegex      // NEW — Funduc syntax + Funduc replacement tokens
    case binary
}
```

Counter/path-token flags become unused under `funducRegex` mode (the replacement evaluator handles those tokens natively). Leave them on the struct for back-compat for now.

### A.4.4 — `Replacer.rewriteText` branching

```swift
case .funducRegex:
    newData = try rewriteFunducText(spec: spec, fileURL: fileURL, data: data, acceptedHits: acceptedHits)
```

`rewriteFunducText` is the new path: parse pattern into `FunducPattern`, run `FunducMatcher`, parse replacement into `[ReplacementToken]`, evaluate per match, splice into source.

### A.4.5 — App ViewModel

Add `useFunducSyntax: Bool` (default `true`) to the criteria block in `SearchReplaceViewModel`. When the user toggles "Regex" ON, the kind becomes `.funducRegex` (if `useFunducSyntax`) or `.regex` (if not). Surface as a small "(Funduc syntax)" affordance next to the Regex toggle for now; later phases remove the `.regex` path entirely.

### A.4.6 — CLI

Add `--funduc` flag to `snr search` and `snr replace`. Default off in this phase (so existing scripts keep working); flip to on by default in Phase E when we add the Funduc-flag-style `sr` front-end.

---

## A.5 — Test corpus

All tests use `swift-testing` (matches existing convention).

### A.5.1 — `SnRFunducRegexTests/EndToEndTests.swift`

One test per concrete example from `sr_feature_catalog.md` §3 and §4. Approximately 50 tests:

- `*(is)` matches "is", "Miss", "Mississippi"
- `*[0-9]` matches "0", "12", "345"; doesn't match empty
- `+(is)` matches "is", "Miss"; doesn't match empty
- `w+e` matches "wide", "write"; doesn't match "we"
- `?(is)` matches only "is"
- `Win?95` matches "Win 95", "Win-95", "Win/95"
- `(01|02)+[0-9](/95|/98)` matches "01/15/95", "02/12/98"
- `?at!((b|c)at)` matches "mat", "sat"; doesn't match "bat", "cat"
- `*file!(beg*file)` matches "a file"; doesn't match "beginning of file"
- `^the` matches "the" only at line start
- `end$` matches "end" only at line end
- `^^First` matches "First" only on line 1
- `*$$` matches text on the final line
- `t[]e` matches "the", "toe"
- `[a-z]` matches lowercase letter
- `Win( 95|dows 95)` matches "Win 95" or "Windows 95"
- `w+2[a-z]` matches "Wor" in "World"
- bare `*` matches whole non-control line; not lines of pure tabs
- escape coverage: `\+ \- \* \? \( \) \[ \] \\ \| \^ \$ \!` each tested
- `^` and `$` in same pattern → parser throws

### A.5.2 — `SnRFunducRegexTests/ParserTests.swift`

~25 tests on AST structure: confirm each operator parses to the expected node shape, error cases throw the right error.

### A.5.3 — `SnRFunducRegexTests/EdgeCaseTests.swift`

The catalog's "edge cases" section becomes tests:
- Zero-length matches don't surface as hits.
- Operators count in `%n` numbering: `^+[ ][a-zA-Z]` → 3 backrefs, `%1` is empty, `%2` is the spaces, `%3` is the letter.
- `^^`/`$$` inside `()` throws.
- `*` not matching control chars.

### A.5.4 — `SnRFunducReplaceTests/EvaluatorTests.swift`

~40 tests, each from catalog §4 "Replacement Operators" and "Special Operations":

- Search `+[A-Z]`, replace `%1<` on "HELLO" → "hello"
- Search `w+[a-z]`, replace `W%1>` on "windows" → "WINDOWS"
- Search `page*[0-9].htm`, replace `page%1>>` over `["page5.htm","page2.htm","page4.htm"]` → `["page6.htm","page7.htm","page8.htm"]`
- Search `Var*[0-9]`, replace `Var%1<100<` over three matches → `Var99`, `Var98`, `Var97`
- Search `cat*[0-9] dog*[0-9]`, replace `cat%1>> dog%2>100>` — multi-counter
- `%1>000>` → 3-digit padding; `%1>0>` → 1-digit
- Math: search `page*[0-9].htm`, replace `page%1<%d(E1-1)>.htm` → decrement page numbers
- Math: search `Price: *[0-9]`, replace `Price: %1<%0.2lf(E1*1.1)>` on "Price: 100" → "Price: 110.00"
- `%%srfile%%` returns just filename
- `%%srpath%%` returns directory
- `%%srdate%%` returns formatted current date
- `%%envvar=HOME%%` returns the HOME variable
- `\%` → literal `%` in output
- `\\` → literal `\` in output

### A.5.5 — Acceptance gate

Phase A is complete when:
1. All Phase A tests pass under `swift test` (or the smoke-test wrapper if running in CLT).
2. The app builds, runs, and a hand-tested sequence works:
   - In the GUI, type `*[0-9]` in Find with Regex + Funduc syntax ON, point at a folder of test files, and verify it finds digit runs.
   - Type `page*[0-9].htm` Find / `page%1>>.htm` Replace, run in dry-run, verify the replacement preview shows incremented page numbers.
3. Smoke test (`Tests/smoke.sh`) gains 4 new cases:
   - Funduc literal with `*[0-9]` (search only).
   - Funduc replace with `%1>>` counter.
   - Funduc replace with `%%srpath%%` token.
   - Funduc replace with math `%1<%d(E1+1)>`.

---

## A.6 — Estimated work

| Step | Files | Estimate |
|---|---|---|
| A.2.1 AST | 1 | 0.5d |
| A.2.2 Parser | 1 + tests | 2d |
| A.2.3 BackrefIndex | 1 + tests | 0.5d |
| A.2.4 ICUTranslator | 1 + tests | 1.5d |
| A.2.5 NOT post-filter | 1 + tests | 0.5d |
| A.2.6/2.7 column / file anchors | 1 + tests | 1d |
| A.2.8 FunducMatcher orchestrator | 1 + tests | 1d |
| A.3.1/3.2 Replace tokens + parser | 2 + tests | 2d |
| A.3.5 Math sub-evaluator | 1 + tests | 1d |
| A.3.4 Evaluator | 1 + tests | 1.5d |
| A.4 Wiring | 4 | 1d |
| A.5 Catalog test corpus | 4 test files | 2d |
| Buffer for surprises | — | 2d |

**Total: ~17 working days.** Realistic calendar estimate at part-time: 4–6 weeks.

---

## A.7 — What Phase A explicitly does NOT include

These belong to later phases — flagged so we don't scope-creep:

- HTML mode, Ignore Whitespace mode, Boolean expression mode (Phase B)
- Clipboard search/replace (Phase B)
- Capitalization processing on replace (Phase B)
- Prepend/append routines (Phase B; tokens are recognized but no-op in A)
- File reformatting `%%srformat%%=nn` actual behavior (Phase B; token is parsed but no-op)
- `.srs` script format (Phase E)
- Iteration / linked / Apply Script (Phase E)
- New UI shape (Phase D)
- Funduc-flag CLI (Phase E)

---

## A.8 — Risks and mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| ICU translation can't faithfully express `*` "no control chars" semantics in all contexts | medium | Translator emits `[\x20-\x{10FFFF}]*` for bare `*` and tracks whether any class needs the control-char carve-out. Tests pin the behavior. |
| `!` (NOT) operator subtle scoping — does negative apply to span, file, or line? | medium | Catalog examples suggest "same span" — tests enforce that. If real Funduc behavior differs in actual usage, we adjust. |
| Greedy vs lazy: Funduc's `*` and `+` greedy by default; ICU is too. Verify identical greediness. | low | Tests with overlapping patterns pin behavior. |
| Performance: pure-Swift NSRegex is slower than ripgrep. Big corpora may feel sluggish. | high for huge searches; low for typical | Phase A is correctness-first. Phase F includes a performance pass. |
| Backreference numbering for anchor-only operators (`^`, `$`) — they consume a `%n` slot but have no captured text. Replacement must handle `nil` capture gracefully. | medium | Captures array is `[String?]`; evaluator treats `nil` as empty string. Tests cover `^+[ ][a-zA-Z]` → `%1` empty. |
| Math expression parsing collisions with replacement parsing (e.g. `<` and `>` are both delimiters and Funduc characters) | medium | Strict state machine in `ReplacementParser`; specific tests for nested `<` `>`. |

---

## A.9 — First commit

When we start coding, the very first commit should be:

1. Add `SnRFunducRegex/AST.swift` + `SnRFunducRegex/FunducSyntaxError.swift`
2. Add `SnRFunducRegex/FunducPattern.swift` (signature only, body throws `.notImplemented`)
3. Add target to `Package.swift`
4. Verify `swift build` passes
5. Add a single failing test in `SnRFunducRegexTests` to confirm the test target compiles

This is the "skeleton up, lights on" commit. Everything else is incremental.

---

## A.10 — Hygiene checklist (per CLAUDE.md)

Per `~/Documents/GitHub/PhantomLives/CLAUDE.md`, every change must:
1. Bump version (`SnR.version` in `SnRCore.swift`, README, etc.)
2. CHANGELOG entry
3. README/USER_MANUAL updates as features land
4. Update tests for each change
5. Update operational files (`smoke.sh`, build scripts) when relevant

Phase A specifically will need:
- Bump `SnR.version` to `0.2.0-dev` at start of phase
- New CHANGELOG section "Phase A — Funduc engine"
- Update README parity matrix to flag the Funduc-syntax mode
- Update `Docs/regex-cheatsheet.md` → split into `Docs/funduc-regex.md` (the new authoritative reference) and a deprecation note in the old file
- Smoke-test additions per A.5.5

---

## Done

When you're ready, the next concrete step is the "skeleton up" commit (A.9). I can do that as a single small edit set: new module folder, AST + error stubs, Package.swift target, one failing test. After your approval, I'll start there.
