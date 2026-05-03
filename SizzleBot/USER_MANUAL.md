# SizzleBot — User Manual

**Version 1.0.0**

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

### Connection status bar

The strip at the bottom of the sidebar shows the Ollama connection state:
- 🟢 `Ollama · dolphin-mistral` — server connected, active model shown
- 🔴 `Ollama offline` — server not running; click **Retry** to reconnect

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
| **Preferred Model** | Override the global model for this character (optional); leave blank to use the global default |

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
| **Active Model** | The global default model used by characters with no preferred model set |
| **Recommended Models** | Expandable list of suggested models with `ollama pull` commands you can copy |

### Characters

| Control | Description |
|---|---|
| **Reset All Built-in Characters** | Restores all 17 built-in bots to their original configurations; confirms before proceeding |

### About

Links to [ollama.com](https://ollama.com) and shows the server address.

---

## Changing the AI model

SizzleBot uses whatever Ollama models you have installed. To add more:

```bash
ollama pull mistral          # fast, general purpose
ollama pull llama3.1         # larger and more capable
ollama pull dolphin-llama3   # uncensored Llama 3
ollama pull gemma3           # efficient on Apple Silicon
```

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
