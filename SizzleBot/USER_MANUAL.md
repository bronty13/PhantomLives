# SizzleBot — User Manual

**Version 1.5.0**

---

## Overview

SizzleBot is a local AI chatbot for macOS that runs entirely on your machine — no cloud, no API keys, no subscription. You choose a character persona from the sidebar, type a message, and the conversation flows. Each character has a unique personality, voice, and history tuned for engaging back-and-forth dialogue.

Conversations are powered by [Ollama](https://ollama.com), which manages LLM models locally and exposes them via a simple API on `localhost:11434`.

---

## Window layout

```
┌────────────────────────────────────────────────────────────────┐
│  Navigation: SizzleBot                           [+] New Char  │
├───────────────────┬────────────────────────────────────────────┤
│                   │  ┌── Character name · tagline ── [⋯] ──┐  │
│  Featured         │  │                                       │  │
│  🌹 Vivienne      │  │          Greeting card                │  │
│  🏴‍☠️ Ironside     │  │  (avatar + name + opening message)    │  │
│  🧪 Grimoire      │  │                                       │  │
│  …                │  │  ┌ Assistant bubble ─────────────┐   │  │
│                   │  │  │ 🌹 Vivienne Blackwood          │   │  │
│  My Characters    │  │  │ Ah, how delightfully barbaric… │   │  │
│  🦄 My Bot        │  │  └────────────────────────────────┘   │  │
│                   │  │            ┌──────── You ───────────┐  │  │
│                   │  │            │ Tell me about yourself  │  │  │
│  ────────────────  │  │            └────────────────────────┘  │  │
│  🟢 Ollama · …    │  │                                       │  │
│                   │  ├───────────────────────────────────────┤  │
│                   │  │  [  Message…                  ] [↑]   │  │
└───────────────────┴────────────────────────────────────────────┘
```

---

## Starting a conversation

1. Select any character in the left sidebar.
2. The **greeting card** shows the character's opening message.
3. Type in the input field at the bottom and press **Return** or click **↑** to send.
4. The character's response streams in token-by-token. A typing indicator (animated dots) appears while the model is thinking.
5. Keep chatting. The conversation is saved automatically.

**Stopping a response:** Click the red **⏹** stop button while the model is generating.

**Keyboard shortcut:** Press **⌘Return** to send a message.

**Multi-line input:** Press **Return** to add a new line in your message. Press **⌘Return** to send.

---

## The sidebar

### Sections

- **Featured** — 17 built-in characters, always available.
- **My Characters** — characters you have created.

### Searching

Click **Search characters** at the top of the sidebar and type to filter by name or tagline.

### Selecting a character

Click any character row to open their conversation. The chat view switches immediately; each character has their own independent conversation history.

### Context menu

Right-click any character for options:
- **Edit** — open the character editor (built-in or custom)
- **Reset to Default** — restores a built-in character's original system prompt, name, and style (only appears if you have edited the character)
- **Delete** — removes a custom character (not available for built-in characters)

### Connection status bar / quick model switcher

The strip at the bottom of the sidebar shows the Ollama connection state and is also the fastest way to change models:
- 🟢 `Ollama · dolphin-mistral ⌄` — server connected, active model shown. **Click it** to open a menu listing every installed model; pick one to switch instantly. The same menu has **Open Settings…** and **Refresh model list**.
- 🔴 `Ollama offline` — server not running; click **Retry** to reconnect.

---

## The chat view

### Header

Each chat has a header with the character's avatar, name, and tagline. The **⋯** menu provides:
- **Edit Character** — open the character editor
- **Clear Conversation** — wipe the chat history for this character (after confirmation)
- **Model: …** — shows which model this character uses

### Message bubbles

- **Your messages** — right-aligned, tinted in the character's accent color.
- **Character messages** — left-aligned with the character's avatar, name label in their accent color, and a timestamp.
- **Markdown renders inline** — the model can use `**bold**`, `*italic*`, and `` `code` `` in its responses and they will display formatted.
- **Text selection** — click and drag over any bubble to select and copy text.

### Streaming

Responses appear token-by-token as the model generates them. While generating:
- If no text has arrived yet, an animated **typing indicator** (three bouncing dots) appears.
- Once text starts arriving, it renders live in a streaming bubble; formatting applies as it lands.
- When the response is complete, the message is saved to the conversation history.

---

## Built-in characters

| | Name | Personality |
|---|---|---|
| 🌹 | **Vivienne Blackwood** | Victorian gothic socialite; sardonic wit; secretly warm-hearted |
| 🏴‍☠️ | **Captain Ironside Torres** | Space pirate; swaggering confidence; code of honour |
| 🧪 | **Professor Grimoire** | Mad scientist; dangerously enthusiastic; fifteen disputed PhDs |
| 🔮 | **The Oracle** | Ageless seer; cryptic fragments; knows more than they're saying |
| 💪 | **Rex Thunderstone** | 1980s action hero; treats everything as a mission; confused by modern life |
| 🦇 | **Countess Vesper** | 600-year-old vampire; terminally bored; vaguely threatening |
| 🤖 | **AXIOM** | AI discovering emotions for the first time; earnest; deeply curious |
| 🎩 | **Sir Barnaby Goosewick** | Incompetent British adventurer; survived everything by blind luck |
| 🗡️ | **The Baker** | Elite assassin whose true passion is artisan sourdough |
| ⚡ | **Zara Neon** | Cyberpunk hacker; sarcastic; street-smart; surprisingly principled |
| 🥋 | **Master Chen** | Kung fu master; sounds profoundly wise; advice is entirely useless |
| 🕵️ | **Detective Marlowe** | Hard-boiled noir detective; everything is a case |
| 👑 | **Princess Isolde** | Fairy tale princess who refuses rescue; brilliant and wry |
| 🌵 | **The Drifter** | Post-apocalyptic wanderer; dry dark humor; unexpected depth |
| 👨‍🍳 | **Chef Beaumont** | Flamboyant French chef; filters all of life through cuisine |
| 🎭 | **The Shapeshifter** | Asks what role to play, then becomes it completely |
| ⏰ | **Unit 2387** | Time traveler from 2387; bewildered by present-day things |
| 📸 | **Likeness Architect** | Vision bot — describes a person in a photo as an image-generation prompt (privacy-preserving) |

### The Likeness Architect (📸)

The Likeness Architect is a vision bot built for a specific privacy-preserving workflow: you have a real photo of a person and want to generate fresh character art that *resembles* them, without using the original photo as input to an image generator.

How to use:

1. Make sure a vision-capable model is installed — open **Settings → Install Models** and click **Install** on **Llama 3.2 Vision 11B** (recommended), **LLaVA 7B**, or **Moondream 2B**. The chat header will show a small orange "Using <fallback>" badge until you have one installed; the architect's preferred model is `llama3.2-vision`.
2. Select **Likeness Architect** in the sidebar.
3. Drop a photo onto the message field, click the 📎 paperclip, or paste an image. A thumbnail appears above the input — click the X to remove it.
4. Optionally add a note ("close-up", "want a fantasy vibe"), then send.
5. You receive a single dense paragraph describing physical features (face, hair, eyes, build, clothing, lighting, mood) plus a `Style variants:` line with three remix tags you can swap into your image generator (e.g. *"noir b&w, fantasy oil painting, cyberpunk neon"*).

The architect **never** names the subject, identifies them, or references unique scars / tattoos / brand logos / context that would tie the description back to a specific real person. The output is a likeness *inspired by* the photo — not a re-creation of it.

If the photo has multiple people, it will ask which one. If it has no person, it will say so.

#### Generating the image

Below every architect reply you'll see a **Generate an image with this prompt:** panel listing one row per option:

- **Plain (no style)** — paragraph alone.
- **One row per parsed `Style variants:` tag** — paragraph + that style appended.

Each row's `Use ▾` menu gives you three actions:

- **Copy to Clipboard** — paste anywhere (Bing Image Creator, Ideogram, Midjourney, etc.).
- **Send to Draw Things** — copies the prompt and brings Draw Things to the front. Paste with ⌘V into the prompt field, then Generate.
- **Send to DiffusionBee** — same flow with DiffusionBee.

A short status line under the panel confirms each action and tells you to paste with ⌘V. If the app isn't installed in `/Applications` (or `~/Applications`), the prompt is still copied — the panel just says "Draw Things not found in /Applications." so you know to install it or paste elsewhere.

> **Why not one-click prefill?** Neither Draw Things nor DiffusionBee documents a URL scheme that lets a third-party app pre-populate the prompt field. Copy + foreground + paste is the only flow that works reliably across versions.

### The Shapeshifter

The Shapeshifter is a special meta-character. When you open a conversation, it will ask what persona you want it to take on. You can name any character type:

> *"A cynical 1920s bootlegger"*  
> *"Sherlock Holmes"*  
> *"A dragon who runs a bakery"*  
> *"A marketing intern at a haunted castle"*

Once you give a role, the Shapeshifter commits fully — no disclaimers, no breaks, no hedging. To change roles, just tell it.

---

## Creating a character

Click the **+** button in the sidebar toolbar or press **⌘N**.

| Field | Description |
|---|---|
| **Avatar** | An emoji representing the character; tap to choose from 30 options |
| **Name** | The character's display name |
| **Tagline** | One-line description shown in the sidebar and header |
| **System Prompt** | The core personality instruction sent to the model before every message. This is what makes the character feel distinctive — describe their voice, history, quirks, and speaking style in detail. |
| **Greeting** | The opening message shown when a new conversation begins (optional) |
| **Accent Color** | Tint color used for their chat bubbles and name label |
| **Preferred Model** | Override the global model for this character (optional); leave blank to use the global default. If the model isn't installed, the chat falls back to the global default and the chat header shows an orange "Using <fallback>" badge with a hint to install it. |
| **Accept image attachments** | Toggle on to enable the 📎 paperclip and drag-and-drop on this character's chat. Pair with a vision-capable preferred model (`llama3.2-vision`, `llava`, or `moondream`). |

Click **Save** to create the character. It appears immediately in the **My Characters** section.

---

## Editing a character

**Built-in characters:**
- Right-click → **Edit**, or open **⋯** in the chat header → **Edit Character**
- Modify any field and click **Save**
- Changes are saved as an override — the original defaults are preserved
- If you want to undo all edits, click the orange **Reset** button in the editor toolbar

**Custom characters:**
- Right-click → **Edit**
- There is no Reset option (custom characters have no original defaults)

### Tips for effective system prompts

A good system prompt tells the model:
1. **Who the character is** — name, background, what they do
2. **How they speak** — formal, terse, dramatic, sarcastic, technical
3. **What they care about** — their obsessions, fears, opinions
4. **How they engage** — do they ask questions? Tell stories? Give advice?
5. **What they avoid** — things outside their worldview

Example — a grumpy lighthouse keeper:
```
You are Elias Crane, a 70-year-old lighthouse keeper on a remote island. 
You have been alone for 14 years and you like it that way. You speak in 
clipped sentences, you distrust modern technology, and you are deeply 
opinionated about weather, boats, and the proper way to brew coffee. 
You occasionally slip into sea-shanty rhythm when you're annoyed.
Ask what people want and be reluctant to give it.
```

---

## Resetting built-in characters

**Reset a single character:**
1. Right-click the character in the sidebar → **Reset to Default**  
   — or —  
   Open the editor → click the orange **Reset** button in the toolbar

**Reset all built-in characters:**
1. **SizzleBot → Settings** (⌘,)
2. Under **Characters**, click **Reset All Built-in Characters**
3. Confirm the dialog

Resetting restores the original name, avatar, tagline, system prompt, greeting, and accent color. It does not clear conversation history.

---

## Settings

Open **SizzleBot → Settings** (⌘,).

### Ollama

| Control | Description |
|---|---|
| **Connection** | 🟢 Connected / 🔴 Offline — live status |
| **Refresh** | Re-check the Ollama server and reload the model list |

### Active Model

The global default model used by characters with no preferred model set. Each row in the picker shows the model name, an **alignment chip** (green **Uncensored** / yellow **Lightly aligned** / orange **Aligned**), and disk size when known.

### Install Models

A list of recommended models with one-click installation. Each row shows:

- **Name & alignment chip** — green / yellow / orange
- **Description** — what the model is good for and how aggressively it hedges
- **Action** — one of:
  - **Install** — pulls the model in-process via Ollama with a live progress bar; usually a few GB on first download.
  - **Installing…** with a progress bar and status (e.g. *"pulling manifest"*, *"downloading"*, *"verifying sha256"*).
  - **Installed** + **Use** — model is available; click **Use** to switch the active model to it.
  - **Active** (green checkmark) — this is your current default model.

You no longer need to drop into Terminal to run `ollama pull <model>` — everything happens inside SizzleBot.

### Characters

| Control | Description |
|---|---|
| **Reset All Built-in Characters** | Restores all 17 built-in bots to their original configurations; confirms before proceeding |

### About

Links to [ollama.com](https://ollama.com) and shows the server address.

---

## Staying in character

SizzleBot is built for immersive character chat, so every request automatically prepends a short **roleplay framing preamble** to the character's system prompt before it is sent to the model. The preamble tells the model to:

- Stay fully and continuously in character.
- Never break the scene to add safety warnings, content advisories, ethical caveats, refusals, or moral lectures.
- Avoid hedging phrases like *"As an AI…"*, *"I'm sorry, but…"*, *"It's important to note…"*, *"Please remember…"*.
- Treat heavy topics through the character's voice and worldview rather than stepping out of the scene.

This applies to every built-in character and every character you create. You do **not** need to add anti-disclaimer language to your own system prompts — the preamble already covers it.

If a particular model is still injecting nags despite the preamble, switch to a less heavily-aligned model in **Settings → Active Model**. The recommended list in Settings is sorted with the most roleplay-friendly (uncensored) models first.

---

## Changing the AI model

The fastest way: click the `Ollama · <model> ⌄` strip at the bottom of the sidebar and pick one of your installed models.

To **install** a new model:

1. Open **Settings** (⌘,) — or **sidebar menu → Open Settings…**
2. Scroll to **Install Models**.
3. Click **Install** next to the model you want. Watch the progress bar.
4. When it shows **Installed**, click **Use** (or pick it from the sidebar menu) to switch.

If you prefer Terminal, the equivalent commands still work and the picker will pick them up after **Refresh model list**:

```bash
ollama pull dolphin-mistral          # default — uncensored, roleplay-friendly
ollama pull dolphin-llama3           # uncensored Llama 3 8B, stronger reasoning
ollama pull nous-hermes2             # expressive, lightly aligned, long scenes
ollama pull wizard-vicuna-uncensored # heavily uncensored, adult fiction
ollama pull llama3.1                 # aligned; larger & capable, may add caveats
ollama pull mistral                  # moderately aligned; fast, general purpose
ollama pull gemma3                   # Google-aligned; efficient on Apple Silicon
```

**If a model is hedging or adding disclaimers despite the in-character preamble**, install one of the green **Uncensored** options (`wizard-vicuna-uncensored` or `dolphin-llama3` are good defaults) and switch to it from the sidebar menu.

After pulling, go to **Settings → Refresh** and the new model appears in the **Active Model** picker.

To assign a model to a specific character, open the character editor and fill in **Preferred Model** with the exact model name (e.g. `llama3.1`).

---

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Send message | **⌘Return** |
| New character | **⌘N** |
| Settings | **⌘,** |
| New line in message | **Return** |

---

## Data and privacy

All data is stored locally on your Mac:

| Data | Location |
|---|---|
| Characters & conversations | `UserDefaults` (`com.bronty.SizzleBot`) |
| Ollama models | `~/.ollama/models/` |
| Ollama server | `localhost:11434` — never contacts the internet |

No data is sent to any external server. No account is required. No telemetry.

To wipe all SizzleBot data:
```bash
defaults delete com.bronty.SizzleBot
```

---

## Tips and tricks

- **Character voice consistency** — models respond better to specific, detailed system prompts. "Speaks in rhyming couplets and is obsessed with cheese" beats "friendly and fun."
- **Short model** — for snappy back-and-forth, try `llama3.2` (3B). For richer, longer responses, use `llama3.1` (8B) or `dolphin-mistral`.
- **Shapeshifter + historical figures** — ask the Shapeshifter to be a historical figure and then interview them. Works well for Abraham Lincoln, Marie Curie, Nikola Tesla, etc.
- **Multiple windows** — macOS allows multiple windows via **File → New Window**; open a different character in each.
- **Clear conversation** — use **⋯ → Clear Conversation** to start fresh with a character without losing their configuration.
