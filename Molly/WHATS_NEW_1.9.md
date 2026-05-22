# What's new in Molly 💕 — v1.9

Hi Sallie 💖

This one is a *big* update — a whole new tab. Nothing else is touched: your customers, clips, reminders, income, journal, C4S Store, everything you use day-to-day is exactly where you left it. The new bit is **additional**, sitting in the sidebar between C4S Store and Customers. Take a peek when you're ready.

---

## 🎁 A brand new Bundles tab

Look at your sidebar — there's a new **🎁 Bundles** entry, right under C4S Store. This is for *making delivery packages for Robert*.

You know the routine — you've shot a clip, you have the files, you want to send everything to Robert in one bundle with title, categories, a description, the date it goes live, all the little notes. Up until now that's been a Slack message + a Dropbox link + a separate email + a few "wait did I send you the right file?" follow-ups.

Bundles makes it one click.

### How it works (Content bundle, today)

1. Click **🎁 Bundles → ＋ New Content Bundle**.
2. Molly assigns a UID (like `2026-05-22-0001`) and drops you into the form.
3. Fill in the fields — save as you go, drafts persist forever until you delete them. Walk away mid-bundle and pick it back up tomorrow if you need to.
   - **Persona** — required.
   - **Title** — at least two words. (Sweet safeguards: blank, `none`, `blank`, `custom`, or a single word all get a gentle reject 💕.)
   - **Description** — pick **📝 Type** for text or **🎙️ Upload audio** for a voice note. One or the other; both are fine but only one at a time.
   - **Categories** — at least three. Type to filter; type a new name and hit Return to create. Drag the chips to reorder — order matters in the bundle.
   - **Go-live date** — required, no past dates. If you pick today or within 5 days, Molly *gently* asks *"Are you allowing enough time for editing?"* (She's not blocking you — just looking out for you 🌷.)
   - **Files** — drag in videos and images. Order matters; drag to reorder. Each file gets a `00001_` prefix in the bundle so the order is *exactly* right when Robert opens it.
   - **Special instructions** — optional notes for Robert.
4. When you're ready, click **🎁 Review & Publish…**. A wizard slides in from the right showing every field — read-only — with **audio playback**, **image thumbnails**, and a pre-flight checklist of anything still missing. Click any missing item in the checklist to jump straight to the field that needs love.
5. When everything's green, click **✨ Approve & Publish**. Molly hashes every file, builds a deterministic two-layer ZIP, and drops it at **`~/Downloads/Molly bundles/<UID>.zip`** ready to drag into Slack.

### Categories already seeded for you ✨

The category picker isn't empty out of the gate — it's pre-populated with **every category from MasterClipper** (read-only — Molly never touches MasterClipper's data, just reads it). So the third bundle you make won't require retyping your favorite 50 names.

### A clip row gets created automatically

When you publish a Content bundle, Molly *also* creates (or updates) a row in your **Clips** tab with status `Bundled` and the same UID. That means the go-live date shows up on your **📅 Calendar** alongside everything else. If you've added Molly-side notes on that clip, they're preserved across re-publishes.

### Editing after publish

A published bundle is locked — the form goes read-only so you can't accidentally edit something that's already in the ZIP. If you need to change something, click **🗑 Delete bundle** on the list row. The ZIP gets removed from disk, the bundle reopens for editing, and your linked Clip row (and any Molly notes on it) survives untouched.

---

## ⚙️ Settings → 🎁 Bundler

Tucked into Settings, between C4S and Data:

- **Output folder** — default is `~/Downloads/Molly bundles/`. Move it if you want; **Reveal** to open Finder there.
- **Warn threshold (days)** — drafts older than this get a soft 🌷 / 🌼 badge on the list so you don't forget them.
- **Auto-purge threshold (days)** — *published* bundles older than this have their ZIP cleaned up automatically (the bundle row stays for history, just the file goes). Runs at most once per day at launch; **Run purge now** bypasses the debounce if you want to clean up right away.
- **Auto-purge enabled** — separate toggle, so you can flip it off to test things without losing your number.
- **Prohibited words** — the description scanner looks for these and gently flags them. Seeded with `blackmail`, `mommy`, `addiction`, `addicted`. Add/remove any time.

---

## 🛡️ A note on integrity

Every file you upload gets hashed at upload time. When you publish, every file gets re-read from disk and re-hashed; if anything doesn't match (someone edited a file outside Molly between upload and publish), Molly **refuses to publish** and tells you exactly which file changed so you can re-upload. The bundle's `hashes.json` lets Robert verify on his end that nothing got mangled in transit.

The inner ZIP contains:
- `info.md` — your wizard inputs rendered as a friendly markdown doc
- `Molly.log` — the technical build log of *this* bundle (every input, every file hash, verify-match markers). Confusingly named because of historical accident — it's the bundle's audit log, not your personal Molly's Log journal.
- `Audio/`, `Video/`, `Photos/` folders with your files in order.

You don't need to think about any of this — Molly handles it. It's just nice to know it's all under the hood. 💕

---

## What's next

This release ships the **Content** bundle type end-to-end. Two more types are on the way in v1.10:

- **Custom Bundle** — for delivering a custom video to a specific platform / user / price.
- **Fan Site Bundle** — a whole month of fan-site posts on a calendar.

You can already create drafts of either type today (Molly assigns a UID and saves your work), but the publish wiring lands in the next release.

---

## What's still the same

Everything else. Your customers, kinks, products, sales, expenses, reminders, schedules, calendar, Molly's Log, MasterClipper clips, C4S Store, promos, reports, backups, exports — all unchanged. Auto-backup on every launch is still humming.

---

You're doing the work. Molly is just trying to make the *delivery* part a little softer. If anything feels off or you want me to change something — color, wording, layout, validation rules, the warning threshold defaults, whatever — just tell Robert in Slack and it'll get fixed.

Go make something pretty. ✨💕

— Molly, your soft little helper

*(v1.9.0, posted 2026-05-22)*
