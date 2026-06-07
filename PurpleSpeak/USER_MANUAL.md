# PurpleSpeak — User Manual

PurpleSpeak reads documents aloud (text-to-speech) and turns recordings into
text (speech-to-text), entirely on your Mac. Nothing leaves the machine.

---

## 1. Getting text in

There are four ways to add something to read, all from the **Import** toolbar
button, the sidebar **+** menu, or the empty-state buttons:

1. **Import documents / images** (⌘O) — choose one or more files. Supported:
   - **PDF** — uses the text layer; scanned PDFs with no text layer fall back
     to OCR automatically.
   - **EPUB** — chapters are read in spine order.
   - **Word** (`.docx`, `.doc`), **RTF/RTFD**, **HTML**, **Markdown**,
     **plain text**.
   - **Images** (`.png`, `.jpg`, `.heic`, …) — text is recognized with Vision
     OCR.
2. **New from Pasted Text** (⌘N) — paste any text and give it a title.
3. **Read Web Article** (⇧⌘L) — paste a link; PurpleSpeak fetches the page and
   extracts the article body.
4. **Drag and drop** files onto the sidebar.

Everything you add appears in the **Library** on the left and is saved between
launches. Right-click a library item to **Read Aloud**, **Rename**, **Reveal
Original in Finder**, or **Delete**.

---

## 2. Reading aloud

Select a document and use the **playback bar** at the bottom:

| Control | Action | Shortcut |
|---|---|---|
| ▶ / ⏸ | Play / pause | Space |
| ⏮ / ⏭ | Previous / next paragraph | ⌘← / ⌘→ |
| ⏹ | Stop | ⌘. |
| Speed slider | 0.5× – 4× | — |
| Voice picker | Choose any installed voice | — |
| Export Audio | Save narration to a file | ⇧⌘E |

- **Synced highlighting:** as PurpleSpeak speaks, the **current word** is
  highlighted in yellow and the surrounding **sentence** gets a soft purple
  glow. The view scrolls to keep the spoken line in sight.
- **Click to start anywhere:** click a paragraph to begin reading from there.
- **Speeds above ~2×** saturate at the speech engine's maximum rate — that's a
  limit of Apple's on-device synthesizer, not a bug.

### Voices

PurpleSpeak lists every voice installed on your Mac, with its quality tier
(Default / Enhanced / Premium) and language. Your locale's voice is the default.

To get higher-quality voices, open **System Settings → Accessibility → Spoken
Content → System Voices** and download Enhanced or Premium voices (and set up a
Personal Voice if you like) — they then appear in PurpleSpeak's picker.

### Reading comfort (Settings → Reading)

- **Font size** and **line spacing** for the reader pane.
- **Line focus** — dims every paragraph except the one being read.

---

## 3. Exporting audio

With a document selected, click **Export Audio** (⇧⌘E). PurpleSpeak renders the
narration and saves it to `~/Downloads/PurpleSpeak/`, then reveals it in Finder.

- Default format is **M4A (AAC)** — small and plays everywhere.
- To export true **MP3**, install Homebrew `lame` (`brew install lame`) and pick
  MP3 in **Settings → Output**. Without `lame`, MP3 requests fall back to M4A.

---

## 4. Transcribing audio & video (speech-to-text)

Click **Transcribe** in the toolbar (or the sidebar footer), or press ⇧⌘T, and
choose an audio or video file — or drop one onto the Transcribe pane.

The first time, download a Whisper model in **Settings → Transcription**:

- **Large v3 Turbo** — best accuracy (~1.5 GB).
- **Base English** — fast, small (~150 MB).
- **Small** — multilingual (~500 MB).

Models are stored in `~/Library/Application Support/PurpleSpeak/models/` and
transcription runs fully on-device via `whisper.cpp`.

When it finishes you get a **timestamped transcript**. From there:

- **Send to Reader** — save it as a document and listen to it.
- **Export .txt** / **Export .srt** — save to `~/Downloads/PurpleSpeak/`.

> Transcription requires the bundled `whisper-cli`. If it isn't present, the
> panel will tell you to `brew install whisper-cpp` and rebuild the app.

---

## 5. Settings

- **Playback** — default voice, speed, pitch, sentence highlighting.
- **Reading** — font size, line spacing, line focus.
- **Transcription** — active model, downloads, language.
- **Output** — where audio/transcripts are saved (default
  `~/Downloads/PurpleSpeak/`), and audio format.
- **Backup** — see below.

---

## 6. Backups

PurpleSpeak automatically backs up your library and settings **on launch** (at
most once every 5 minutes) to `~/Downloads/PurpleSpeak backup/`, keeping 14
days of archives by default.

In **Settings → Backup** you can:

- Turn auto-backup on/off, change the folder and retention.
- **Run Backup Now** and **Reveal in Finder**.
- For each recent backup: **Test** (verify it), **Restore** (replaces your
  current library — a safety backup is taken first), or **Reveal**.

After a restore, quit and relaunch PurpleSpeak.

---

## 7. Window

If the layout ever looks wrong, use **Window → Reset Window State…** and
relaunch.
