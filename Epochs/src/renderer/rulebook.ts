// The in-app rulebook — Epochs' rules in OUR OWN WORDS, describing the game as this
// app actually implements it (which diverges from the original in documented ways:
// no pre-eminence/coins, simplified combat/areas, our seas + scoring). This is an
// original rendering of the mechanics, NOT a transcription of any copyrighted
// rulebook. The scanned original pages live behind the "Classic" tab as the owner's
// own nostalgic reference; see RulebookView.

export interface RuleSection {
  id: string
  title: string
  /** HTML body (trusted, authored here — no user input). */
  body: string
}

const RESOURCE = '◆'

export const RULEBOOK: RuleSection[] = [
  {
    id: 'overview',
    title: 'Overview',
    body: `
      <p><b>Epochs</b> is a march through seven ages of history. Across the game you
      command a succession of empires — each rises on its homeland, spreads across the
      map, and fades — while you accumulate <b>victory points</b> for the regions you
      hold and the works you build. The player with the most points after the
      <b>seventh epoch</b> wins.</p>
      <p>You never keep one empire for long. Each epoch you are dealt a new one, play
      its single turn, and pass on. Your <i>score</i> carries forward; your <i>armies</i>
      do not. The art is turning each empire — strong or weak, early or late — into
      lasting points.</p>`,
  },
  {
    id: 'board',
    title: 'The Board',
    body: `
      <p>The world is <b>100 lands</b> grouped into <b>13 Areas</b> (Middle East, China,
      India, Europe, the Americas, and so on), ringed by <b>29 seas and oceans</b>.</p>
      <ul>
        <li><b>Barren lands</b> (8 of them — great deserts, Siberia, Amazonia) are
        <b>impassable</b>: no army may enter or cross them.</li>
        <li><b>Resource lands</b> (marked ${RESOURCE}) let you raise <b>Monuments</b>.</li>
        <li>Each Area is worth a number of points <b>per epoch</b> — see the
        <b>Victory&nbsp;Point Table</b> (the ⊞ button). An Area worth nothing early can
        become decisive late, and vice-versa.</li>
        <li><b>Seas</b> connect coasts. An empire that can navigate a sea may sail
        across it to reach <i>any</i> land on that sea — this is how the Americas,
        Australasia and sub-Saharan Africa are reached at all.</li>
      </ul>`,
  },
  {
    id: 'epoch',
    title: 'Starting an Epoch — Roll & Draft',
    body: `
      <p>At the very start of the game, every player rolls a die; <b>highest goes
      first</b>. Thereafter, each epoch the <b>weakest player drafts first</b> (lowest
      score) — a catch-up mechanism that hands the trailing player the first pick.</p>
      <p><b>Keep or Pass.</b> When it is your turn to draft you are dealt a
      <b>random empire</b> face-down. You may <b>Keep</b> it, or <b>Pass</b> (gift) it
      to any player who has no empire yet — then you draw again. Passing a weak empire
      to a leader is a way to deny them; keeping a strong one builds your own turn.</p>`,
  },
  {
    id: 'turn',
    title: 'Your Empire-Turn',
    body: `
      <p>When your empire comes up, you take one turn, in order:</p>
      <ol>
        <li><b>Events</b> — optionally play cards from your hand (see Events).</li>
        <li><b>Minor Empire</b> — if you played one, it takes a full mini-turn first.</li>
        <li><b>Set up</b> — place your capital (if any) and first army on your homeland,
        clearing whatever army or fort stood there.</li>
        <li><b>Expand</b> — place the rest of your armies (your empire's
        <b>strength</b>), one at a time, into reachable lands, fighting where needed.</li>
        <li><b>Build</b> — raise Monuments from your resource lands.</li>
        <li><b>Score</b> — total your Areas and structures, and add it to your VP.</li>
      </ol>`,
  },
  {
    id: 'expand',
    title: 'Expansion & Movement',
    body: `
      <p>Each army you place must go into a land you can <b>reach</b> from a land you
      already hold this turn:</p>
      <ul>
        <li><b>By land</b> — into any adjacent non-barren land.</li>
        <li><b>By sea</b> — if your empire navigates a sea, you may reach any land on
        that sea (a <b>sea-borne / amphibious</b> landing).</li>
        <li><b>Straits</b> let armies cross narrow water to a named neighbour
        (Britain↔Gaul, Crete↔Greece, the Japans, and so on).</li>
      </ul>
      <p>Placing into an <b>empty</b> land simply claims it. Placing into an
      <b>enemy</b> land is an attack (see Combat). <b>Barren</b> lands can never be
      entered or crossed.</p>`,
  },
  {
    id: 'combat',
    title: 'Combat',
    body: `
      <p>To take a defended land, attacker and defender each roll a die; <b>higher wins</b>,
      and <b>ties are re-rolled</b> until broken. Lose, and your attacking army is spent
      with nothing gained.</p>
      <p>The <b>defender</b> rolls with advantages for terrain and works:</p>
      <ul>
        <li><b>Difficult terrain</b> (mountains, forest) and <b>amphibious</b> landings
        favour the defender.</li>
        <li>A <b>Fort</b> adds to the defence.</li>
      </ul>
      <p>When an army is destroyed, any <b>fort</b> with it falls too. Taking a land with
      a <b>capital</b> reduces that capital to a <b>city</b> rather than destroying it.
      Certain events negate these defences (Siegecraft voids forts; Surprise Attack and
      the naval boons void terrain / amphibious penalties).</p>`,
  },
  {
    id: 'events',
    title: 'Events',
    body: `
      <p>Each epoch you hold a small hand of <b>Greater</b> and <b>Lesser</b> cards.
      You may play <b>one of each</b> per turn. They fall into families:</p>
      <ul>
        <li><b>Combat boons</b> (Leader, Weaponry, Fanaticism, Siegecraft, Surprise
        Attack) — strengthen your attacks this turn.</li>
        <li><b>Economy boons</b> (Reallocation, Population Boom, Civil Service,
        Kingdoms) — extra armies, or a fortified city.</li>
        <li><b>Naval boons</b> (Ship Building, Naval Supremacy) — sail every sea this
        turn, reaching any coast.</li>
        <li><b>Minor Empires</b> — summon a second dynasty (see next section).</li>
        <li><b>Disasters</b> (Lesser, aimed at a foe before your turn) — Plague,
        Pestilence, Famine, Volcano/Flood/Fire, Barbarians, Pirates, Storm at Sea —
        each strikes a different kind of enemy land.</li>
      </ul>
      <p>Your hand is finite and never refills, so spend it where it counts: a strong
      empire presses the attack, a weak one bulks up or fortifies.</p>`,
  },
  {
    id: 'minor',
    title: 'Minor Empires',
    body: `
      <p>Playing a <b>Minor Empire</b> card summons that epoch's lesser dynasty —
      Hittites, Phoenicia, Mayans, Anglo-Saxons, Fujiwara, Safavids or Japan — which
      takes a <b>full second empire-turn before your main one</b>: it sets up on its own
      homeland (with a capital where it has one) and expands its own strength, fighting
      where it must. Its lands and works are <b>yours</b>, so they score for you — a
      genuine second front, often on a far continent.</p>`,
  },
  {
    id: 'build',
    title: 'Monuments & Structures',
    body: `
      <p>Four kinds of work can stand on a land:</p>
      <ul>
        <li><b>Capital</b> — your empire's seat (worth 2). Reduced to a city if taken.</li>
        <li><b>City</b> — a lesser seat (worth 1).</li>
        <li><b>Monument</b> — built in the Build step: one for every <b>two resource
        lands</b> ${RESOURCE} you hold (worth 1).</li>
        <li><b>Fort</b> — defensive only (no points); strengthens the land in combat.</li>
      </ul>
      <p>Crucially, <b>structures persist across epochs</b> while armies fade — a city or
      monument you raise keeps scoring for you in <i>every</i> later epoch, so works are
      how a good early empire pays out for the rest of the game.</p>`,
  },
  {
    id: 'scoring',
    title: 'Scoring',
    body: `
      <p>You score immediately after building. Two parts:</p>
      <p><b>1 · Area control.</b> In every Area you have armies in, you score that Area's
      value for this epoch, multiplied by your tier:</p>
      <ul>
        <li><b>Presence</b> (≥1 army) — <b>×1</b></li>
        <li><b>Dominance</b> (≥2 and more than any rival) — <b>×2</b></li>
        <li><b>Control</b> (≥3 and no rival present at all) — <b>×3</b></li>
      </ul>
      <p>Only this epoch's armies count toward tiers (older empires' armies are spent).
      The live <b>You</b> column in the VP Table shows your current tier in every Area.</p>
      <p><b>2 · Structures.</b> Add up your capitals (2), cities (1) and monuments (1),
      everywhere on the board.</p>
      <p>A <b>Marauder</b> (a capital-less empire) instead earns <b>+1 point each time it
      razes an enemy structure</b> — its compensation for having no capital of its own.</p>`,
  },
  {
    id: 'seas',
    title: 'Seas & Navigation',
    body: `
      <p>The <b>29 seas</b> are travel lanes, not scored regions. An empire's
      <b>navigation</b> lists which seas it may sail; from any coast it holds, it can
      reach <i>every</i> land on a navigable sea. This is the only way to the
      <b>overseas continents</b> — the Americas, Australasia and sub-Saharan Africa,
      which no land route touches.</p>
      <p>The naval events extend this: <b>Ship Building</b> and <b>Naval Supremacy</b>
      let you sail <i>every</i> sea for a turn, and the sea-raid disasters
      (<b>Pirates</b>, <b>Storm at Sea</b>) strike coastal foes.</p>`,
  },
  {
    id: 'winning',
    title: 'Winning',
    body: `
      <p>After the <b>seventh epoch</b> is scored, the player with the highest total
      <b>victory point</b> tally wins. Because the Areas worth the most shift from epoch
      to epoch, and because structures keep paying out, the winner is usually the player
      who read the <b>VP Table</b> best — pushing into the regions about to peak and
      leaving works behind that score for the rest of history.</p>`,
  },
]
