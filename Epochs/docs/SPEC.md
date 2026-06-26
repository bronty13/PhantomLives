# Epochs — Game Design & Data Specification

> **Epochs** is an original digital recreation of the *system* of the 1990s
> Avalon Hill board game *History of the World* (designed by the Ragnar
> Brothers), built for single-player play against AI opponents. This document
> is the canonical, implementable spec for the rules engine and the data model.
>
> **Status:** v0.1 — rules engine fully specified from the official manual;
> content data (board adjacency, empire roster, event texts) enumerated as
> data-entry tasks (§14). This is a living document; update it as data lands.

---

## 0. Provenance, scope & legal posture

- **What this is based on.** The 7-epoch ruleset of the Avalon Hill / Hasbro
  edition (the same Ragnar Brothers design as the 1993 Avalon Hill North
  American edition). The primary source is the official 12-page rulebook,
  product `40196`, preserved on the Internet Archive Wayback Machine:
  `https://web.archive.org/web/20160304100157id_/http://www.wizards.com/avalonhill/rules/hotw.pdf`
  All "Manual §" citations below refer to that document's chapters/pages.
- **Behavioral oracle.** The official 1997 PC adaptation (Colorado Computer
  Creations / Avalon Hill, AI with 9 settings) is preserved and browser-playable
  at `https://archive.org/details/win3_Historyo`. Use it to resolve ambiguous
  rules interactions by *observation* — not by extracting its code or assets.
- **Reference implementation (do not fork).** GamesByEmail "Empires"
  (`http://gamesbyemail.com/Games/Empires`) is a complete, faithful, closed-source
  browser clone — useful to confirm correct rules behavior.
- **Legal stance (we are reimplementing a *system*, which is not copyrightable):**
  - Re-implement **mechanics** freely (17 U.S.C. §102(b); *Baker v. Selden*;
    *DaVinci Editrice v. Ziko*).
  - **Do NOT** copy the original rulebook *text*, board/card *artwork*, or the
    *name* "History of the World" (trademark). Use **our own** map geometry,
    iconography, card layouts, and reworded rules text.
  - This build is **private and non-distributed**. That keeps practical risk
    near-zero; the design rule "reproduce nothing protected" keeps doctrinal
    risk near-zero too (*Tetris v. Xio*: distinctive look/feel *is* protected).
  - Card/territory **values are facts** (uncopyrightable) — transcribing the
    numeric data model is fine; copying the art that displays it is not.

The in-app name is **Epochs**. Never surface "History of the World" or "Avalon
Hill" in shipped UI.

---

## 1. Game overview

Epochs is a turn-based, area-control "rise and fall of empires" game played over
**7 epochs** (rounds) spanning ~3000 BC to ~1914 AD, for **3–6 players** (here:
1 human + 2–5 AI). Each epoch, every player commands **one empire** drawn from
that period, expands it across a world map, fights for territory, builds
structures, and **scores points** for area control and structures. Empires die
off between epochs; players persist and accumulate Victory Points (VP). After
Epoch VII, **most VP wins**.

The defining tension: a strong empire one epoch becomes irrelevant the next, and
a **catch-up draft** (§4) hands the leading player the *weakest* new empires — so
leads erode and the game stays close to the end.

### The seven epochs (representative figure set per epoch)

| Epoch | Era theme | Figure set |
|------:|-----------|------------|
| I   | ~3000 BC  | Egyptian |
| II  |           | Persian |
| III |           | Roman |
| IV  |           | Byzantine |
| V   |           | Mongols |
| VI  |           | Spanish |
| VII | ~1914 AD  | British |

(Per epoch, **all** players use that epoch's figure color/set regardless of
which empire they hold — see Manual §III.)

---

## 2. Data model (entities)

TypeScript-flavored schemas; final types live in `src/shared/types.ts`.

```ts
type EpochId = 1 | 2 | 3 | 4 | 5 | 6 | 7;
type PlayerId = string;              // stable per game
type LandId = string;                // e.g. "libya", "greece"
type AreaId = string;                // the 13 colored scoring regions
type SeaId  = string;                // seas + oceans (fleet-navigable bodies)

interface Land {
  id: LandId;
  name: string;
  area: AreaId | null;               // null === Barren Land (impassable)
  barren: boolean;                   // 8 barren lands; cannot enter/cross
  difficultTerrain: TerrainKind[];   // forest | mountain | strait | great_wall
  hasResource: boolean;              // 18 lands carry a resource symbol
  borders: LandId[];                 // land adjacency (graph edge list)
  seaBorders: SeaId[];               // which seas/oceans this land touches
}

interface Area {                     // a colored scoring region
  id: AreaId;
  name: string;                      // e.g. "Middle East"
  lands: LandId[];
  // base (presence) value per epoch; 0 means the area scores nothing that epoch
  valueByEpoch: Record<EpochId, number>;   // see §9 VP table
}

type Navigation =                    // which water an empire's fleets may use
  | { all: true }                    // full navigation = every sea/ocean
  | { seas: SeaId[] };

interface EmpireCard {
  id: string;
  name: string;                      // OUR descriptive label (not original art)
  epoch: EpochId;
  order: number;                     // 1..7 intra-epoch draw order (1 drawn first)
  strength: number;                  // # of armies the empire deploys
  startLand: LandId;
  navigation: Navigation;            // fleets placed in these seas at setup
  hasCapital: boolean;               // false => Marauder (+1 VP per structure razed)
  // optional printed power/leader; modeled as event-like effects later
  ability?: EmpireAbilityId;
}

type EventClass = "greater" | "lesser";
type GreaterEventKind = "leader" | "weaponry" | "reallocation" | "minor_empire";

interface EventCard {
  id: string;
  class: EventClass;
  kind?: GreaterEventKind;           // greater only
  name: string;                      // OUR label
  // structured effect — see §11; exact per-card effects are a data-entry task
  effect: EventEffect;
}

type StructureKind = "capital" | "city" | "monument" | "fort";

interface BoardPiece {
  land: LandId;
  kind: "army" | StructureKind;
  owner: PlayerId | null;            // structures are owned by whoever holds them
  epochColor: EpochId;               // armies are colored by the epoch placed
}

interface PlayerState {
  id: PlayerId;
  isHuman: boolean;
  vp: number;
  hand: { greater: EventCard[]; lesser: EventCard[] };  // fixed for whole game
  preeminenceMarkers: number[];      // hidden until game end
}

interface GameState {
  epoch: EpochId;
  turnOrder: PlayerId[];             // order empires act THIS epoch (draw order)
  activePlayer: PlayerId | null;
  board: Map<LandId, BoardPiece[]>;  // ≤1 army per land; structures coexist
  players: Record<PlayerId, PlayerState>;
  preeminencePool: number[];         // remaining markers
  rng: RngState;                     // seeded, deterministic (replay/test)
}
```

**Component counts** (Avalon Hill edition, from Manual §I and box manifest — to
be reconciled during data entry, see §16):
- Board: 102 Lands, grouped into 13 Areas, plus 8 Barren Lands; resource symbols
  on 18 Lands.
- 48 Empire Cards (7 epochs × 7 empires = 49 slots; reconcile the 48/49 count).
- 64 Event Cards (manifest discrepancy with "22 Greater + 49 Lesser" — see §16).
- 30 Capitals/Cities (double-sided), 32 Forts, 36 Monuments.
- 8 Pre-eminence Markers, 5 dice, Coins/Fleet markers, Score Charts.

---

## 3. Turn & epoch structure (the game loop)

```
for epoch in 1..7:
  1. DRAW PHASE   — deal empires to players in catch-up order (§4)
  2. for each player, in this-epoch turn order (lowest VP first, §4):
       a. (optional) play up to 2 Event cards (max 1 Greater + 1 Lesser) (§11)
       b. SETUP the active empire on the board (§5)
       c. EXPAND armies one land at a time; resolve combat (§6, §7)
       d. BUILD monuments from resource symbols (§8)
       e. SCORE the active empire: area control + structures (§9)
  3. PRE-EMINENCE — highest-VP player draws a hidden marker (§10)
end
4. GAME END — reveal pre-eminence markers, add to VP; most VP wins (§12)
```

Each player takes **exactly one empire-turn per epoch**. A player's armies from
*past* epochs remain on the board (as older-color pieces) and still count toward
that player's area control in later scoring (§9), but only the **active** empire
expands, fights, and builds on its turn.

---

## 4. Empire draw & the catch-up "rubber band"

At the start of each epoch, empires are drawn in **reverse standing order**:

- The player with the **lowest VP draws first**, then second-lowest, … the
  **leader draws last** (Manual §VII).
- **Tie-break:** the player who held the lower-`order` (earlier-drawn) empire in
  the *previous* epoch draws first. (Epoch I has no prior; use seeded random or
  seating order — decide in §16.)
- A drawer may **keep** the drawn Empire Card or **pass** it to the next drawer
  (then draw again). [Confirm exact keep/pass mechanics against the manual during
  data entry — §16.]

Each epoch has **7 empires** with a fixed intra-epoch `order` (1..7). Empires with
higher `order` enter a more-developed board (more existing armies/structures to
fight through). Because stronger empires are generally better, first-pick-to-the-
loser is the core balancer.

> **Engine note.** "This-epoch turn order" (who acts first) follows the **same
> lowest-VP-first** ordering as the draw. The leader acts last, into the most
> contested board.

---

## 5. Empire setup (start of an empire-turn)

On the active player's turn, after optional events (§11):

1. Take **armies equal to `strength`** into hand.
2. If `hasCapital`, take the empire's capital piece.
3. Place **one fleet marker in each sea** in `navigation` (full navigation =
   every sea/ocean).
4. Place the **capital (if any) + first army** on `startLand`, **removing any
   army or fort already there** (monuments remain; a capital/city there is
   handled by sack/pillage rules, §8).
5. Remaining armies are placed during Expansion (§6).

A **Marauder** (`hasCapital === false`) gains **+1 VP each time it razes an
opponent structure** (reduces a capital or sacks a city) — its compensation for
having no capital of its own.

---

## 6. Expansion & movement

- Expansion proceeds **one Land at a time** outward from the empire's controlled
  Lands (starting at `startLand`/capital), into **adjacent** Lands.
- **One army per Land** (no stacking).
- **Barren Lands** cannot be entered or crossed.
- **Expanding into a Land that already holds your *own* past-epoch army:** no
  combat — replace it (return the old army to your pool, place the new-color
  army).
- **Expanding into an empty Land:** place an army, no combat.
- **Expanding into an enemy-held Land:** resolve **combat** (§7).
- **Fleets / sea movement.** Fleets in seas act as **stepping stones**: an active
  empire may expand over a sea/ocean into **any Land adjacent to that body of
  water**, and may **chain** through multiple connected fleets to reach distant
  Lands. (Landing from the sea triggers the amphibious defender bonus — §7.)

Expansion ends when the player has no armies left to place or chooses to stop
(placement is a player/AI decision — see AI notes §15).

---

## 7. Combat resolution (the core dice system)

> This is the most important engine routine. It is **closed-form** — no
> simulation needed — which is what makes strong AI tractable (§15).

### 7.1 Base resolution

- **Attacker** rolls `attackerDice` dice, **keeps the single highest**.
- **Defender** rolls `defenderDice` dice, **keeps the single highest**, then adds
  any **fort bonus**.
- **Higher value wins**; the loser's army is removed.
- **Tie ⇒ BOTH armies removed**, and the Land is left **vacant** (attacker does
  *not* occupy it; any capital/city there stays in its current state).

### 7.2 Dice counts

`attackerDice`:
- Base **2**.
- **3** if the attacker has a qualifying bonus (Leader, Weaponry, or certain
  Events). (Bonuses do not stack beyond 3 — confirm in §16.)

`defenderDice` (take the **maximum** applicable, base 1):
- Base **1**.
- **2** if attacking *into* a Land whose border/terrain is **Difficult Terrain**
  (forest, mountain, Great Wall). Difficult terrain on the *attacker's* own Land
  gives no bonus.
- **3** if attacking **across a Strait** or **landing from the Sea**
  (amphibious). (Strait/sea override the terrain-2 bonus.)

`fortBonus`: **+1** to the defender's kept value if a **fort** is present (§7.4).

### 7.3 Combat odds (engine must reproduce these — test fixture)

For d6, `P(max of k dice = x) = (x^k − (x−1)^k)/6^k`. Standard combat
(attacker max-of-2 vs defender max-of-1):

| Outcome | Probability | ≈ |
|---|---:|---:|
| Attacker wins (defender removed, attacker occupies) | 125/216 | 57.9% |
| Tie (both removed, land vacant) | 36/216 | 16.7% |
| Defender wins (attacker army removed) | 55/216 | 25.5% |

Other matchups (engine computes generically; included as regression anchors):

| Attacker × Defender | Atk win | Tie | Def win | Exact (atk/tie/def) |
|---|---:|---:|---:|---|
| 2 × 1 (standard) | 57.9% | 16.7% | 25.5% | 125 / 36 / 55 over 216 |
| 2 × 2 (difficult terrain) | 39.0% | 22.1% | 39.0% | 505 / 286 / 505 over 1296 |
| 3 × 1 (attacker bonus) | 66.0% | 16.7% | 17.4% | 855 / 216 / 225 over 1296 |
| 2 × 3 (strait / amphibious) | 28.1% | 24.8% | 47.2% | 2183 / 1926 / 3667 over 7776 |

> The engine derives the full table from the max-of-k distribution
> (`combat.ts::combatOdds`); `tests/combat.test.ts` asserts every row above
> against its exact rational fraction. Fort `+1` shifts the defender's
> distribution up by one and is modeled in 7.4. (These exact values supersede
> any hand-estimate — they were corrected after the test pinned them down.)

### 7.4 Forts (multi-round)

- A fort gives the defender **+1** and is **destroyed before the army**: if the
  defender **loses or ties**, the **fort** is removed first (not the army), and
  if the attacker still has its army, combat **continues another round** against
  the now-unforted defender.
- Max **one fort per Land**; a fort may sit on a Land that also has a capital or
  city. A fort costs one unplaced army (or a Coin) to build.
- Forts are worth **0 VP**.

### 7.5 Outcome → board effects

| Result | Board effect |
|---|---|
| Attacker wins | Defender army removed; attacker army occupies the Land; apply sack/pillage to any structure (§8). |
| Tie | Both armies removed; Land vacant; structures unchanged. |
| Defender wins | Attacker army removed; defender stays; structures unchanged. |

---

## 8. Structures & building

### 8.1 Sack & pillage (on capturing a Land)

- Capture a Land containing a **capital** → the capital is **flipped to a city**
  (downgraded).
- Capture a Land containing a **city** → the city is **sacked and removed**.
- **Monuments** are never destroyed — they remain and transfer to whoever
  controls the Land.
- If a Land is left **vacant** (tie), structures stay in their current state.
- A **Marauder** scores **+1 VP** each time it razes a structure this way (§5).

### 8.2 Monuments (built from resources)

- 18 Lands carry a **resource symbol**.
- After expansion, count the resource-Lands the active empire controls: for
  **every 2** such Lands, **build 1 monument**.
- **Placement priority:** on a capital you control → else a city you control →
  else any Land with your army. If unplaceable (or all 36 monuments are already
  on the board), it isn't built.
- Only the **active empire** builds monuments (not past empires or minor empires).

### 8.3 Structure VP values

| Structure | VP |
|---|---:|
| Capital | 2 |
| City | 1 |
| Monument | 1 |
| Fort | 0 |

---

## 9. Scoring (end of each empire-turn)

A player scores their **active empire** immediately after building. Two
components: **area control** + **structures**.

### 9.1 Area control tiers

For each **Area**, determine the active player's tier (count **all** the player's
pieces of the **current epoch's color**, wherever placed):

| Tier | Condition | Multiplier |
|---|---|---:|
| **Presence** | ≥ 1 army in the Area | **× base** (1×) |
| **Dominance** | ≥ 2 armies **and** more than any other player in the Area | **× 2** |
| **Control** | ≥ 3 armies **and** no other player has any army in the Area | **× 3** |

`base` = that Area's `valueByEpoch[currentEpoch]` (§9.3). Score the **highest
tier** achieved for each Area, summed across all Areas.

### 9.2 Structure points

Add VP for every structure the player controls (§8.3): capitals ×2, cities ×1,
monuments ×1.

### 9.3 Victory Point Table (base / presence value per Area per Epoch)

Transcribed from Manual §VI / back-page VP Table. Columns are Epochs I–VII; a
dash (—) means the Area scores **0** that epoch.

| Area | I | II | III | IV | V | VI | VII |
|---|--:|--:|--:|--:|--:|--:|--:|
| Middle East     | 2 | 3 | 3 | 3 | 3 | 2 | 1 |
| North Africa    | 1 | 2 | 2 | 2 | 2 | 2 | 1 |
| China           | 1 | 2 | 3 | 3 | 3 | 3 | 3 |
| India           | 1 | 2 | 3 | 3 | 3 | 3 | 3 |
| Southern Europe | 1 | 2 | 3 | 3 | 3 | 3 | 2 |
| Northern Europe | — | — | 1 | 2 | 2 | 3 | 4 |
| Southeast Asia  | — | — | 1 | 2 | 2 | 2 | 2 |
| Eurasia         | — | — | — | — | 1 | 1 | 2 |
| North America   | — | — | — | — | 1 | 1 | 3 |
| South America   | — | — | — | — | 1 | 2 | 2 |
| Nippon          | — | — | — | — | 1 | 1 | 2 |
| Africa          | — | — | — | — | — | 1 | 2 |
| Australia       | — | — | — | — | — | — | 2 |

> Dominance doubles and Control triples these base values. This table is the
> heart of the AI value function (§15) — a placement's worth is largely "what
> does it do to my tier in each Area this epoch, weighted by survival into future
> epochs."

---

## 10. Pre-eminence markers (hidden endgame swing)

- At the **end of each epoch**, the player with the **most VP** takes **one**
  Pre-eminence Marker from the pool, **face down** (may not look until game end).
- If **two or more players tie** for most VP, **no** marker is drawn that epoch.
- There are **8 markers**: values **two 3s, three 4s, two 5s, one 6**.
- At game end, all held markers are revealed and **added to VP**.

This injects hidden information: the visible leaderboard during play is not the
true score.

---

## 11. Event cards

- Each player is dealt a **fixed hand at game start**: **3 Greater + 7 Lesser**
  Events. **No new event cards are ever gained** — managing this hand across all
  7 epochs is a core strategic layer.
- Before an empire-turn, a player may play **up to 2 events**: at most **one
  Greater + one Lesser** (never two of the same type; never two "Disasters"
  together — confirm full restriction list in §16).

**Greater Events (4 kinds):**
- **Leader** — combat bonus (attacker rolls 3 dice); cannot combine with a Minor
  Empire on the same turn.
- **Weaponry** — combat bonus (attacker rolls 3 dice).
- **Reallocation** — diverts naval resources to extra ground armies.
- **Minor Empire** — plays a small extra empire at turn start (epoch-specific);
  not scored until the active empire finishes.

**Lesser Events** — grant **Coins** (do not carry between turns), spent to return
a combat-lost army to your pool or to buy a fort. ("22 types" per manual text.)

> The rulebook gives kinds/counts but **not** every card's exact effect — those
> are a data-entry task (§14). Model each event as a structured `EventEffect`
> the engine can apply; start with the kinds above and fill specific cards as
> transcribed.

---

## 12. End game & victory

After Epoch VII scoring and the final pre-eminence draw:
1. Reveal all Pre-eminence Markers; add their values to each holder's VP.
2. **Highest total VP wins.** (Tie-break: confirm in §16 — likely most
   pre-eminence markers, then a shared win.)

---

## 13. Determinism & RNG

All randomness (dice, any shuffles/draws) flows through a **single seeded RNG**
in `GameState.rng`. Given the same seed + same inputs, a game replays identically.
This is required for: reproducible tests, save/replay, and AI self-play. Never
call `Math.random()` in the engine.

---

## 14. Data-entry tasks (the real remaining work)

The **rules engine** is fully specified above. The **content data** must be
transcribed (facts, not protected expression) from the rulebook scan, a
high-resolution board image, and/or the 1997 game as oracle. Each becomes a JSON
(or TS) data file under `src/shared/data/`:

1. **`board.ts` — the map graph.** All 102 Lands: `id`, `name`, `area`,
   `barren`, `borders[]` (full adjacency), `seaBorders[]`, `difficultTerrain[]`,
   `hasResource`. Plus the 13 Areas → Lands membership and the 8 Barren Lands.
   *Source:* high-res board scan (BGG / Google Arts & Culture / The Strong);
   cross-check adjacencies in the 1997 game.
2. **`areas.ts` — VP table.** Already specified in §9.3 — encode directly.
3. **`empires.ts` — the 49 Empire Cards.** Per card: `epoch`, `order`,
   `strength`, `startLand`, `navigation`, `hasCapital`, optional `ability`.
   *Source:* card scans / fan lists, validated against the 1997 game. (The modern
   Z-Man/Rio Grande rulebooks print full rosters but for the 5-epoch redesign —
   useful shape, different numbers; don't mix editions.)
4. **`events.ts` — the event deck.** Each Greater/Lesser card's structured
   `effect`. *Source:* card scans / transcription; the kinds in §11 are the
   scaffold.

> **Edition discipline (critical):** target the **Avalon Hill 7-epoch** edition
> throughout. The 2018 Z-Man (5 epochs) and 2024 Rio Grande editions are
> *different games*; their numbers will silently corrupt the data model if mixed
> in.

Until real data lands, the engine ships with a **small fixture map** (a handful
of Lands/Areas/empires) so the engine and tests run end-to-end (§ scaffold).

---

## 15. AI design — `HeuristicBot` (implemented v0.3)

A **tunable heuristic / weighted-scoring bot** (`src/shared/heuristicBot.ts`),
not a learned agent — justified by closed-form combat (§7.3) + a clean scoring
objective (§9). It scores each frontier placement by its **marginal, survival-
discounted, relative expected VP** and returns the argmax (null only when the
frontier is empty). Empirically it beats `GreedyStubBot` ~100% and `RandomBot`
~91% (2-player, seat-averaged); `tests/tournament.test.ts` is the evidence.

**Engine-parity value function.** The value of a move is computed as
`scoring.scoreArea(after) − scoring.scoreArea(before)`, summed over remaining
epochs `E..7` and discounted by a per-epoch **retention** `rho` — so the bot can
never value a move differently from how the engine actually scores it. Terms:

- **SelfArea** — my tier delta in the land's area (presence→dominance→control),
  over the horizon. A win also drops the defender's count (can lift my tier).
- **own_old = 0 area value** — re-occupying my own land adds no body under
  all-armies scoring; its *only* worth is refreshing a current-epoch army onto a
  **resource** land for monuments. (This is the bug `GreedyStubBot` had.)
- **Structures** (via `applyCapture` semantics): capturing an enemy capital is
  **+1/−2** (flips to a city I bank), enemy city → sacked (−1 to them), monument
  → transfers (+1/−1); Marauder gets +1 one-time per razed structure.
- **Denial** — the victim's lost VP via the same parity math from *their*
  perspective, weighted toward the leader / whoever is ahead (`wDeny`), ramped
  by epoch.
- **Risk** — enemy EV `= pw·WIN + pt·TIE − riskAversion·pl·oppCost`, where
  `oppCost = max(armyFloor, best peaceful score)` (a lost army forfeits the safe
  placement it could have made). A **tie** removes the defender without occupying
  — modeled as a possible self-upgrade + denial.

**Two count semantics** (do not mix): area tiers count **all** army colors;
monuments count only **current-epoch** armies on resource lands.

**Determinism.** All tie-break / persona jitter flows through
`hash01(seed, player, epoch, land)` — never `Math.random`, never the engine RNG
(§13). The engine rebuilds the `BotView` (with a fresh `pieces` snapshot) on
**every** placement, because `state.pieces` is reassigned on each mutation.

**Difficulty / personas** are pure weight overlays: `easy/medium/hard` trade
foresight (`rhoBase`), opponent-awareness (`denialBase`), and noise (`tieEps`).
The knob is monotonic at the extreme (medium & hard crush easy ~97%), but the
fine `hard` vs `medium` ordering does **not** hold on the tiny fixture
(long-horizon weights overfit) — **re-tune via self-play once the real board
lands** (§14). Weights in `DEFAULT_WEIGHTS` are provisional fixture placeholders.

**Future** (reuse the same primitives): bot-controlled empire **draft** and
**event** play (currently engine-controlled / unmodeled), fort building, and an
optional **MCTS** scoped to placement (ref: Szita/Chaslot/Spronck, *MCTS in
Settlers of Catan*) using this heuristic as the rollout policy.

**Known strength gaps** (correctness-clean per the AI review — improve during
self-play tuning, not bugs): (1) **denial is scoped to the attacked defender
only** — a *peaceful* placement (or a win/tie) that co-occupies an area a *third*
player controls also drops that rival's tier, but no denial credit is given for
it; extend `scoreEmpty` and the win/tie maps to value non-defender rivals.
(2) A **tie** charges no opportunity-cost on the burned army (debit is on `pl`
only) — optionally price the tie mass too. Both are magnitude/strategy tweaks
best validated by self-play on the real board.

---

## 16. Open questions / discrepancies to resolve during data entry

- **Empire count 48 vs 49** (box manifest "48 Empire cards" vs 7×7=49 slots).
- **Event count**: box "64 Event cards" vs manual "22 Greater + 49 Lesser" (=71)
  vs "4 kinds / 22 types" wording. Pin exact physical counts.
- **Keep/pass draft mechanics**: confirm the precise rule for keeping vs passing
  a drawn Empire Card, and how the deck is ordered within an epoch.
- **Epoch I draw order / overall tie-breaks** (no prior epoch).
- **Attacker bonus stacking** cap (Leader + Weaponry + Event — does it exceed 3
  dice?).
- **Full event-play restriction list** (the "no two Disasters" family).
- **Final-score tie-break** rule.
- **1993 vs 2001 rule deltas**: the 2001 reprint changed some unit counts
  (plastic figures); verify no scoring/combat wording changed.

Resolve each by re-reading the Wayback manual page images and observing the 1997
game; record the resolution inline here and bump this doc's version.

---

## 17. Sources

- Official rulebook (Avalon Hill/Hasbro, product 40196), Wayback Machine:
  `https://web.archive.org/web/20160304100157id_/http://www.wizards.com/avalonhill/rules/hotw.pdf`
- 1997 PC adaptation (behavioral oracle): `https://archive.org/details/win3_Historyo`
- Reference clone (do not fork): `http://gamesbyemail.com/Games/Empires`
- Legal: 17 U.S.C. §102(b); U.S. Copyright Office games guidance
  (`https://www.copyright.gov/register/tx-games.html`); *Tetris Holding v. Xio*;
  *DaVinci Editrice v. Ziko*.

---

*v0.1 — engine spec complete; content data pending (§14). Not legal advice.*
