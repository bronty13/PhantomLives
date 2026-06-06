# Quizzer — User Manual

Quizzer lets you build a quiz — or a **Spin-the-Wheel** activity — and hand out a
single file that anyone can open in their web browser, on a computer or a phone, even
with no internet. This manual is for the person *creating* them.

## 1. Opening Quizzer

Open `dist/index.html` (the Quizzer Creator) in any modern browser. Everything you
make is saved automatically in that browser on that computer. To move your work to
another machine, use **Export** (below).

The top bar has four areas: **Quizzes**, **Wheels**, **Branding**, and **Settings**.

## 2. Set up Branding (do this first)

**Branding → New Branding.** A branding profile is a reusable look you can apply to
any quiz:

- **Colors** — click a swatch to pick, or type a hex code. Primary is the main
  accent; Accent is used for highlights and the certificate.
- **Logo** — upload an image; it appears on every page of the quiz.
- **Font** — pick one of 10 built-in fonts, **or** upload your own `.ttf` for an
  exact match. (Built-in fonts use the closest font already on the viewer's device;
  uploading a TTF guarantees everyone sees the same font.)

A live preview shows your colors and font. Click **Save**. You can keep several
branding profiles and reuse them.

## 3. Global Settings (optional)

**Settings** sets the defaults used when you create a *new* quiz: time limit
(default 30:00), attempts (3), passing score (80%), randomize-questions (off), and
the default correct/incorrect feedback messages. Changing these never touches quizzes
you've already made.

## 4. Create a quiz

**Quizzes → New Quiz.** Fill in:

- **Quiz name** — also the title of the file you'll hand out.
- **Branding** — pick one of your profiles.
- **Introduction text** — shown on the welcome screen (rich text).
- **Intro image or video** — optional; plays/shows after the quiz opens.
- **Additional instructions** — optional rich text.
- **Rules** — turn a time limit on/off and set it; attempts allowed; passing score;
  randomize question order; and whether to offer a completion certificate.

### Adding questions

Click **+ Add Question**, then pick a type from the dropdown:

- **True / False**
- **Multiple Choice** — 2–10 choices; mark the one correct answer; optionally
  randomize the order.
- **Multiple Answer** — 2–10 choices; mark *all* correct answers (the respondent must
  select exactly those to get credit).
- **Fill in the Blank** — one or more blanks; for each blank, type the accepted
  answers separated by `|` (e.g. `oxygen | O2`). Toggle case-sensitivity.
- **Short Answer** — single line or paragraph. Grade by **Keyword** (the answer must
  contain at least N of your keywords) or **Manual**. *Manual answers can't be graded
  inside an offline quiz, so the respondent is automatically given credit and the
  question is marked "self-graded."*

**Question image (optional):** each question can have an image shown between the
question text and the answer choices — upload it right under the question text.

Under **Scoring & feedback** for each question: set the point **weight**, the
**correct/incorrect feedback** text, and whether to **reveal the correct answer**
after the respondent submits.

Use **↑ / ↓** to reorder and **Delete** to remove. Click **Save** when done.

## 5. Hand out the quiz — Deploy

From the quiz list (or inside the editor), click **Deploy**. Choose:

- **Single HTML file** — best for most quizzes. You get one `.html` file. Email it,
  put it on a shared drive, or host it anywhere. The recipient just opens it.
- **Zip** — use this if your quiz has a large intro video. You get a `.zip`; the
  recipient unzips it and opens `index.html`.

The file downloads to your browser's download folder (set it to
`~/Downloads/Quizzer/` to stay organized). The quiz works **offline** — no internet
needed to take it.

## 6. What the respondent sees

They open the file, read your intro, enter their name, and click **Start**. They
answer one question at a time, getting your feedback after each. At the end they see
their **score** and **PASS/FAIL**. If they passed and you enabled certificates, they
can **download a PDF certificate** with their name, the date, the quiz name, and a
signature line. Attempts are limited to the number you set.

## 6b. Make a Spin-the-Wheel instead

Prefer a fun prize wheel to a graded quiz? Go to **Wheels → New Spin the Wheel**.

Fill in:

- **Title** — also the name of the file you'll hand out.
- **Branding** — pick one of your profiles (same look as your quizzes).
- **Description** — rich text shown above the wheel (defaults to *"Spin the Wheel for
  a Prize."*, which you can change here or in Settings).
- **Image or video** — optional, shown after the description.
- **Wheel choices** — add **1 to 30** labels (the slices of the wheel). Use **↑ / ↓**
  to reorder and **✕** to remove.
- **Advanced odds** (optional toggle) — give a choice a **weight** to make it more or
  less likely; **0 = never lands**. The slices still look equal-sized — only the odds
  change. Leave everything at 1 for a perfectly fair wheel.
- **Number of spins permitted** — `0` means unlimited.
- **Spin length (seconds)** — how long the wheel spins before stopping (default 6).
- **Result caption** — the text shown above the winning prize (default *"You won"*).
- **PDF results to list** — `1` shows just the latest win on the certificate; a bigger
  number lists that many recent spins; `0` lists the whole session.
- **Sound on by default** — whether the wheel starts with sound on (the player can
  toggle it).

Click **Save**, then **Deploy** (single HTML or zip, exactly like a quiz).

**What the player sees:** your branding, title, description, and media, then the
wheel. They tap **SPIN**, the wheel spins with ticking sound and lands on a slice, and
the prize appears in big animated text — with a little chime. They can mute with the
🔊 button, and once they've spun they can **Download Result (PDF)** to keep a record of
what they won. If you set a spin limit, the SPIN button stops once it's reached.

## 7. Save, move, and reuse quizzes

- **Export** writes a `.quizzer.json` bundle (quiz + its branding) you can back up or
  move to another computer.
- **Import** loads a bundle back in.
- **Duplicate** makes a copy to use as a starting point.

## 8. Good to know

- **Answers live in the file.** Grading happens on the viewer's device, so the
  correct answers are inside the quiz file (scrambled, but recoverable by someone
  technical). Quizzer is great for training and practice — not for high-stakes,
  cheat-proof exams.
- Your quizzes are stored in the browser you created them in. Use **Export** to keep
  a safe copy.
