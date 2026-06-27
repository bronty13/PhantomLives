# Authentic Rules Reference — History of the World (Avalon Hill, 1993)

The implementation bible for making Epochs faithful. Transcribed from the owner's
**physical-game scans** (`~/Downloads/HOTW`: rules, board, all 7 epoch cards, the
event cards, the sample game, the Sumeria card) + period digital-adaptation
screenshots, via OCR (workflow `wf_a6c66c81-7f2`, 2026-06-27) and a direct read of
the board's Victory-Point Table.

These are **game mechanics and data (facts)**, organized in our own words for
implementation — not a reproduction of the rulebook prose. The in-app rulebook is
also written in our own voice.

> **EDITION MATTERS.** This is the **Avalon Hill 1993** edition (32×22″ board,
> **5 dice = 3 white + 2 coloured**, 48 Empire cards, 64 Event cards). It has **NO
> coins and NO pre-eminence markers** — those belong to the later **Z-Man** edition.
> Epochs' v0.1–v0.9 build implemented coins + pre-eminence (wrong edition) and an
> original empire roster. The fidelity rebuild removes those and matches this edition.

Confidence is flagged. `⚠ RE-VERIFY` = the scan was folded/illegible; re-photograph
flat before locking.

---

## 1. Components & setup

- 5 dice: **3 white + 2 coloured**. 48 Empire cards, 64 Event cards. No coins, no
  pre-eminence markers.
- Each player picks a faction **symbol** (`+`, dot, square, diamond, star, triangle),
  takes that colour's pieces, places a round **VP marker** and a square **Strength
  marker** on `0` of the Victory-Point Track.
- The white **Sumeria** card sits face-up in the board centre.
- The other **63 Event cards** sort into **9 colour piles of 7**; shuffle each;
  **each player draws ONE card from each pile → a fixed 9-card hand** (one of every
  colour) for the whole game. Leftovers to the box.
- The 48 Empire cards sort into **7 Epoch piles (I–VII)**, each shuffled, stacked in
  Epoch order.

## 2. Game flow

7 Epochs. Each Epoch: **draft empires → every player takes one empire-turn in
Empire-card-number order → next Epoch.** Game ends after Epoch VII; **most VP wins**
(tie-break: highest Empire-Card-Number held in the last Epoch).

Eras: I 3000–1400 BC · II 1400–450 BC · III 450 BC–300 AD · IV 300–750 AD ·
V 750–1300 AD · VI 1300–1550 AD · VII 1550–1914 AD.

## 3. Draft

- **Sumeria seed (once, before Epoch I):** the lowest dice-roller places a white army
  + Capital in **Lower Tigris**, builds 3 more Sumerian armies, may expand normally.
  Thereafter that player only rolls to **defend** Sumeria — it is **never scored** and
  never grants Automatic Victory. (Sumeria is **not** a draftable empire.)
- **Draw order:** Epoch I = lowest dice total first. Later Epochs = **ascending
  Strength-marker rank (weakest drafts first)**; tie → most VP; still tied → lowest
  Empire-Card-Number held in the preceding Epoch. (The catch-up rubber band.)
- **Keep-or-pass:** in draw order each player draws one Empire card, inspects it
  **secretly**, and either **keeps** it (if not already holding one this turn) or
  **passes** it to a player who has none. A passed card isn't inspected by its
  recipient until distribution ends. The last drawer must keep. Undrawn empires → box.

## 4. A player's turn (in order)

1. **Event declaration** — reveal Events to play this turn (≤2). "Play before turn"
   resolve before claiming the Start Land; "play during turn" any time.
2. **Build** — take units = the Empire's **Strength Number**; advance the square
   Strength marker that many spaces.
3. **Placement** — place one army in the highlighted **Start Land** (any army there
   must retreat); if the card's top star names a city, also place a **Capital** there.
4. **Expansion** — place remaining units one at a time into Lands/Seas/Oceans adjacent
   to an already-occupied space, fighting where required.
5. **Build forts** (remove one unused army → one fort; max one per Land).
6. **Monuments** — one free Monument per **pair of controlled Resource symbols**.
7. **Score** — total VP from all your still-in-play forces; advance the VP marker.

## 5. Combat

- **Dice:** attacker rolls **2 white dice (keep highest)**; defender rolls **1 coloured
  die**. Highest single die wins; loser removes one army. Attacker may keep placing &
  re-attacking until the Land is taken or he declines.
- **Ties: REROLLED** ✅ confirmed from the worked example ("the +1 modification for his
  fort makes it a '6'. **The battle must be rerolled**"). Highest single die wins; an
  exact tie is rerolled until decisive. *Fanaticism* (attacker) and *Fortress*
  (defender) override this to auto-win ties for their side. **NOT "both removed"** — the
  old engine's tie rule was wrong, and the combat-odds renormalize to
  `P(att>def) / (P(att>def)+P(def>att))`.
- **Difficult terrain** ✅ (Mountain / Forest-Jungle / Wall on the defender's border, OR
  an overseas/amphibious attack): the **defender rolls BOTH coloured dice, keeps the
  highest** ("a defender who rolls two dice instead of one. Both players choose the
  highest die roll"). Caps the defender at 2 dice — **no defender-rolls-3**; amphibious
  = the same defender-2 as terrain. The Great Wall is in effect all game.
- **Forts:** **+1** to the defending die. Do **not** absorb losses; eliminated with the
  last defending army.
- **Naval combat:** fleets fight like armies but get **no** fort/terrain benefit;
  Leader/Weaponry/Naval-Supremacy bonuses **do** apply.
- **Automatic Victory:** you may not expand from (or build Monuments using) Lands held
  by **another empire of your own colour**, so you may be forced to attack your own
  former Lands — those attacks are **won automatically**. (Not when forced via
  Barbarians.)
- **Conquest:** taking a Land eliminates any fort/City there and **flips a Capital to
  its City side**; a **Monument is unaffected** (it scores for whoever controls it).

## 6. Scoring

- **Structures (each, end of your turn):** Capital **2**, City **1**, Monument **1**,
  each **Sea controlled 1**, fort **0**, Ocean **0**. All still-in-play forces count
  (including past-Epoch survivors).
- **Areas (13 coloured regions):** counts **LANDS**, not armies.
  - **Presence** ≥1 Land in the Area → base ×1
  - **Domination** ≥3 Lands **and more than any other player** → base ×2
  - **Control** **every** Land in the Area → base ×3
  - Each Area scores **once per player per Epoch** (highest tier only). A player may
    **combine the Lands of his different same-colour empires** to reach Dom/Control.

## 7. Victory-Point Table (base / presence value per Area per Epoch)

**AUTHENTIC — read directly off the board** (high confidence; `—` = scores 0).
Domination doubles, Control triples.

| Area | I | II | III | IV | V | VI | VII |
|---|--:|--:|--:|--:|--:|--:|--:|
| Middle East        | 2 | 3 | 3 | 3 | 2 | 2 | 1 |
| North Africa       | 1 | 2 | 2 | 2 | 2 | 2 | 1 |
| China              | 1 | 2 | 3 | 3 | 3 | 3 | 3 |
| India              | 1 | 2 | 3 | 3 | 3 | 3 | 3 |
| Southern Europe    | — | 2 | 3 | 3 | 3 | 2 | 2 |
| Northern Europe    | — | — | 1 | 2 | 2 | 2 | 4 |
| South-East Asia    | — | — | 1 | 2 | 2 | 2 | 2 |
| Eurasia            | — | — | — | — | 1 | 1 | 2 |
| North America      | — | — | — | — | 1 | 1 | 3 |
| South America      | — | — | — | — | — | 2 | 2 |
| Sub-Saharan Africa | — | — | — | — | — | 1 | 2 |
| Nippon             | — | — | — | — | — | 1 | 2 |
| Australasia        | — | — | — | — | — | — | 1 |

## 8. Water bodies

- **Oceans (3, score 0, movement-only, unlimited fleets, combat optional):**
  **Atlantic, Pacific, Indian.**
- **Seas (10, score 1 VP each when controlled; max 2 fleets; one player's fleets at
  end of Expansion):** North Sea, Caribbean, Black Sea, **Caspian**, Red Sea, South
  China Sea, Sea of Japan, **Eastern Mediterranean, Western Mediterranean, Bay of
  Bengal**. (The last three lack the literal word "Sea" but are enclosed scoring seas.)
- **Caspian special case:** a scoring Sea by type, but **fleets may never enter it**
  (rule 7.3) → effectively never scores. Model as a Sea with no fleet placement.
- **Do NOT invent** (not on this board): Arabian Sea, Yellow Sea, East China Sea,
  Baltic, Adriatic, Aegean, Persian Gulf, Arctic Ocean. Epochs' current data references
  several of these — reconcile: the water west of India is open **Indian Ocean**; the
  Mediterranean splits only into **Eastern/Western Med**; Scandinavia's water is the
  **North Sea**.

## 9. Barren Lands (impassable — 8 grey Lands armies may never enter or cross)

Northern Lakes, Amazonia, Alps, Sahara Desert, Syrian Desert, Plateau of Tibet,
The Outback, Siberia.

## 10. Monuments

End of Expansion: one free Monument per **pair of controlled Resource symbols** (not
already used for a Minor-Empire Monument). Site priority: **A.** your Capital → **B.**
a City site → **C.** a Resource site — controlled by you, holding no other Monument.
Monuments are not destroyed by Conquest; only Events remove them; they score for
whoever **controls** them; may be rebuilt.

## 11. Empire roster (authentic 48 cards / 49 empires)

Distribution **I=6, II=7, III=7, IV=7, V=7, VI=7-cards/8-empires, VII=7** (+ neutral
Sumeria seed). Strength is much higher/wider than Epochs' old 3–9 band. Marauder =
**no Capital** (no special VP bonus). Navigation `+` = open-ocean extension.

**Sumeria (neutral seed, pre-Epoch-I):** str 4, Lower Tigris, Capital Ur, nav none.

**Epoch I (6):** Egypt 5 (Nile Delta, Red Sea + E.Med, Cap Memphis) · Minoans 4 (Crete,
E.Med) · Indus Valley 4 (Lower Indus) · Babylonia 4 (Middle Tigris) · Shang Dynasty 4
(Yellow River) · **Aryans 5 (Turanian Plain, marauder)**.

**Epoch II (7):** Assyria 8 · Chou 6 · Vedic City States 6 · Greek City States 9 ·
**Scythians 7 (marauder)** · Carthaginia 8 · **Persia 15**.

**Epoch III (7):** **Celts 8 (marauder)** · Macedonia 15 · Maurya 10 · Han 12 ·
**Hsiung-Nu 7 (marauder)** · **Romans 25** · Sassanids 9.

**Epoch IV (7):** Guptas 8 (Eastern Deccan, Bay of Bengal) · **Goths 10 (Danubia,
marauder)** · **Huns 14 (Western Steppe, marauder)** · Byzantines 12 (Balkans, Black
Sea + E.&W.Med) · T'ang Dynasty 11 (Yangtze Kiang, Sea of Japan + S.China Sea) ·
Arabs 18 (Arabian Peninsula, Red Sea) · Khmers 5 (Mekong, S.China Sea).

**Epoch V (7):** Franks 10 (Northern Gaul, W.Med) · **Vikings 9 (Scandinavia, marauder
— but navigates North Sea + W.Med + Atlantic)** · Holy Roman Empire 10 (Central Europe)
· Chola 8 (Eastern Ghats, Bay of Bengal) · Sung Dynasty 9 (Szechuan, S.China Sea) ·
**Seljuk Turks 12 (Turanian Plain, marauder)** · **Mongols 20 (Mongolia, marauder —
navigates Sea of Japan)**. ← Mongols are **Epoch V** here, not VI.

**Epoch VI (7 cards / 8 empires):** Ming Dynasty 10 (Chekiang, Sea of Japan + S.China
Sea) · Timurid Emirate 8 (Turanian Plain) · **Incas 2 + Aztecs 2 (SHARED card** —
Incas start Northern Andes, Aztecs Mexican Valley; build **two** Capitals; play 0/1/2
Events; Strength marker advances 4; one Monument if they control 2 Resources between
them) · Ottoman Turks 15 (Western Anatolia, Red Sea + Black Sea + E.Med) · Portugal 10
(Western Iberia, Atlantic+ Indian+) · Spain 15 (Pyrenees, Atlantic+ Indian+) ·
Mughals 12 (Ganges Valley, Bay of Bengal).

**Epoch VII (7):** Russia 12 (North European Plain, North Sea + Black Sea + Sea of
Japan) · Manchu Dynasty 12 (Manchurian Plain, Sea of Japan + S.China Sea) · Netherlands
8 (Lower Rhine, Atlantic+ Indian+ Pacific+) · France 15 (Western Gaul, Atlantic+ Indian+
Pacific+) · **Britain 20 (Albion, Atlantic+ Indian+ Pacific+)** · United States 10
(Appalachia, Caribbean) · Germany 10 (Baltic Seaboard, Atlantic+ Indian+ Pacific+).

> Start Lands use the **board's own territory names** (Nile Delta, Lower Tigris,
> Turanian Plain, Albion, Appalachia, Baltic Seaboard, Manchurian Plain…) — reconcile
> Land ids to the authentic territory list when the map data is rebuilt.

## 12. Event system (9 colour piles of 7 = 63 + 1 white Sumeria = 64)

Each player draws **one card per pile** → a fixed **9-card hand**; plays **≤2 per turn**;
each card valid only in its printed Epoch band; "before turn" vs "during turn" timing.
An Event may not modify another Event played the **same** turn, but may modify a
**previous** one. **No "two-of-a-kind" restriction in this edition.**

**Pile composition:** (1) Lime-Green = 7 **Minor Empires** ✅ (one per Epoch — see table
below). (2) Dark-Blue = 3 Leaders, 2 Weaponry, 2 Fanaticism. (3) Orange =
2 Elite Troops, 2 Civil Wars, 1 Jihad, 1 Crusade, 1 Jewish Revolt. (4) Purple = 2
Migrants, 5 Kingdoms. (5) Brown = 7 Disasters (1 Flood + 2 Volcano + 3 Fire + 1 Storm).
(6) Blue = 2 Rebellions, 3 Treachery, 1 Empires Fortify, 1 Empires Revive. (7) Red = 3
Barbarians, 1 Plague, 1 Pestilence, 1 Black Death, 1 Famine. (8) Dark-Green = 2 Allies,
1 Population Explosion, 1 Trade Bonus, 1 Ship Building, 1 Civil Service, 1 Engineering.
(9) Pink = 2 Surprise Attacks, 1 Naval Supremacy, 1 Pirates, 1 Siegecraft, 1 Empire
Revives, 1 Empire Fortifies. ⚠ pile assignment of Treachery / Revive / Siegecraft is
inferred — verify.

**Effects (~30 distinct):**
- **Leader** (during): attack with **3 dice until you roll triples**; triples kills the
  Leader → back to 2 dice.
- **Weaponry** (during): **+1 to each** attacking die.
- **Fanaticism** (during): **win all tied** die rolls while attacking.
- **Elite Troops** (during): 3 dice attacking until you lose an army/fleet, then 2.
- **Jihad** (during): 3 dice until first loss (then 2); **and** win all ties until your
  second loss of the turn.
- **Treachery** (during, ×3): once per card, **auto-win all attacks in ONE Land** this
  turn; declare before rolling; can't void battles already lost.
- **Surprise Attack** (during): void fort **and** Difficult-Terrain advantages in one
  Land this turn.
- **Siegecraft** (during, III–VII): forts have **no effect** vs your attacks this turn.
- **Naval Supremacy** (during): your fleets attack with **3 dice +1 each**.
- **Pirates** (during): one free fleet in any one Sea (ignoring Navigation) or adjacent
  friendly Land; eliminated if it has no adjacent friendly Land at end of turn.
- **Ship Building** (during): 2 free fleets for builds **if you have Navigation**.
- **Engineering** (during): 2 free forts for builds **if you have a Capital** (may
  upgrade a fort to Fortress under optional rules).
- **Allies** (during, ×2): 2 extra armies, **only into vacant Lands adjacent** to you
  (one per Land, no attacking).
- **Civil Service** (before): if you have a Capital, buy **2 extra units**.
- **Population Explosion** (before): buy **2 extra armies** (no Capital needed).
- **Trade Bonus** (during): offer to trade; each accepting player gains 1 army in an
  occupied Land and you gain 1 extra build per partner.
- **Kingdom** (before, ×5, one per named Land): place an army (past-empire type) + City
  + fort in the named Land (any army there retreats). Lands/bands: Upper Nile (II–VII),
  Southern Iberia (III–VII), Gold Coast (IV–VII), Malay Peninsula (IV–VII), Highlands
  (IV–VII).
- **Sub-Saharan Migrants** (before, II–VII) / **N. American Migrants** (before, II–VII):
  place **2 armies** (past-empire type) in that Area's vacant Lands; no Monuments, no
  attacking.
- **Minor Empires** (×7, lime-green, **play before turn**): build & expand like a normal
  empire with a **different-type marker**; not part of your main empire for
  Monuments/Expansion; resolves fully before your main empire places; **does** add to
  your end-of-turn score. ✅ The 7 cards (one per Epoch):

  | Epoch | Minor Empire | Str | Capital | Leader | Navigation | Start Land |
  |--|--|--:|--|--|--|--|
  | I | Hittites | 3 | Hattusas | Hattusilis I | — | Eastern Anatolia |
  | II | Phoenicia | 3 | Byblos | Hiram I (969–936 BC) | E.Med + W.Med | Levant |
  | III | Mayans | 2 | Uucil-Abnal | Unknown | — | Mexican Valley |
  | IV | Anglo-Saxons | 3 | — (marauder) | Hengist (c. 550 AD) | North Sea | Baltic Seaboard ⚠ confirm |
  | V | Fujiwara | 3 | Kyoto | Fujiwara Motoisune (836–891 AD) | Sea of Japan | Honshu |
  | VI | Safavids | 3 | Isfahan | Shah Ismail I (1501–1524 AD) | — | Persian Plateau |
  | VII | Japan | 5 | Tokyo | Mutsuhito (1867–1912 AD) | Sea of Japan | Honshu |
- **Disasters** (before unless noted): **Flood** destroy a Monument in a Land adjacent
  to a Sea/Ocean (City/fort destroyed, Capital→City); **Volcano** ×2 same in a Mountain
  Land; **Fire** ×3 same in **any** Land; **Storm at Sea** (during) destroy **all fleets
  in one Sea**.
- **Barbarians** (before, ×3): one army attacks **out of a Barren Land** into adjacent
  Lands, continuing until destroyed (or it conquers all adjacent Lands, then dies).
  Normal conquest effects; no Automatic Victory.
- **Plague** (before): one Land rolls **4 dice per army**; each `1` kills that army.
- **Pestilence** (before): chosen Land **3 dice/army**, each adjacent Land **2
  dice/army**; each `1` kills.
- **Black Death** (before, **Epoch VI only**): two adjacent Areas roll **1 die/army**;
  each `1` kills.
- **Famine** (before): one Area eliminates **all armies in excess of one per Land**.
  (Plague/Pestilence/Black Death/Famine leave structures intact; vacated Land claimable
  without Conquest.)
- **Rebellion** (before, II–VII, ×2): one army (past-empire type) appears in an enemy
  Land and attacks with **2 dice**, no Difficult-Terrain (fort still helps); no retreat.
- **Civil War** (before, II–VII, ×2): one army appears in **each of 3 Lands** of one
  enemy empire; no Difficult Terrain; each attacks in its Land; no retreat.
- **Jewish Revolt** (before, II–VII): one army attacks **Palestine** with **3 dice**;
  if conquered place a City + fort; no Difficult Terrain; no retreat.
- **Crusade** (before, **V–VI only**): 3 armies attack from the **E. Med.** with +1
  dice; if Palestine captured place City + fort; E.Med need not be friendly-controlled.
- **Empire Revives** (before, III–VII): 3 free armies in Lands of **one** past empire;
  no attacking/expanding. **Empires Revive** (plural): 4 armies across **two** past
  empires (≥1 each). **Empire Fortifies**: 2 free forts in **one** past empire's Lands.
  **Empires Fortify** (IV–VII): 3 forts across **two** past empires (≥1 each).

## 13. Optional rules

- **2–3 players:** each runs **two colours** (separate scores/strength/hands); may keep
  an empire by passing to his own other colour; wins on combined score.
- **Preservation of Culture:** own-colour Monuments only — worth 2 VP to you, 1 to
  others. Sumerians build no Monuments.
- **Fortresses:** built for **2 Strength** by flipping a fort; **+1 to defender AND
  wins all ties**; Engineering / Empires-Fortify can upgrade a fort to a fortress.

## 14. What Epochs must change (prioritized)

- **P0 Remove non-edition mechanics:** coins (Lesser=coins deck, `spendCoinsOnForts`),
  pre-eminence (markers, pool, end-of-epoch draw, reveal scoring), the "no two
  Disasters / two-of-a-kind" rule. (SPEC §10/§11, `data/events.ts`, `game.ts`,
  `scoring.ts`.)
- **P0 Replace the event system** with the 9-pile / 9-card-hand / ≤2-per-turn model and
  the ~30 effects above (before/during timing, Epoch bands).
- **P0 Fix combat**: ties are **rerolled** (renormalize odds to
  `P(att>def)/(P(att>def)+P(def>att))`), and the dice model (attacker 2 white keep-high;
  defender 1, or 2-keep-high in Difficult Terrain/overseas; **no defender-rolls-3**;
  fort = +1 defender die). Re-derive the combat-odds fixture afterward.
- **P1 Replace the empire roster** with §11 (names, Start Lands, real strengths, named-
  sea navigation + `+`, correct marauders, Epoch I = 6 + Sumeria seed, Inca/Aztec
  shared card). Regenerate `world.source.json` → `empires.ts`.
- **P1 Add the Sumeria seed**; implement the **keep-or-pass draft** and the
  **strength-rank draw order**.
- **P1 Fix area scoring** to count **Lands** (Presence ≥1 / Domination ≥3 + most /
  Control = all Lands), once per Area per Epoch, same-colour empires combine.
- **P2** Forts/fortresses, Monuments-by-resource-pairs (A/B/C priority), the **port
  rule**, **Sea = 1 VP**, Oceans = 0, optional ocean combat, **Caspian no-fleets**, the
  **8 Barren Lands**, reconcile water bodies (3 Oceans + 10 Seas; remove invented ones).
- **P2** Remove the invented Marauder "+1 VP per razed structure" bonus.
- **P3** Re-verify the full VP staircase (done — read directly) and the 7 Minor-Empire
  cards; add optional-rule toggles.

## 15. Open re-verification

- ✅ **Combat ties** — RESOLVED: **rerolled** (worked-example re-photo, 2026-06-27).
- ✅ **Difficult Terrain** — RESOLVED: **defender rolls 2, keeps highest** (re-photo).
- ✅ **The 7 Minor Empires** — RESOLVED: card re-photo (§12 table).
- ✅ **Area VP table** — read directly off the board (§7).
- ⚠ Minor remaining: exact Start Lands for a couple of Minor Empires (Anglo-Saxons);
  event-pile assignment of Treachery / Empire(s) Revive-Fortify / Siegecraft (affects
  only how many cards go undealt, not mechanics). Confirm during data entry.
