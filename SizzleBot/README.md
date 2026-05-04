# SizzleBot

**Version 1.5.0** — macOS 14+ (Sonoma and later)

SizzleBot is a native macOS chatbot app powered entirely by local LLMs via [Ollama](https://ollama.com). No cloud, no API keys, no subscriptions — conversations stay on your Mac. You interact through hand-crafted character personas, each with a distinct personality, voice, and backstory, or create your own.

---

## Features

- **In-character by default** — every request injects a roleplay framing preamble that keeps the model fully in character; no unsolicited safety nags, content disclaimers, "As an AI…" interruptions, or moral lectures.
- **In-app model installer** — pull any recommended Ollama model from Settings with a one-click **Install** button and a live progress bar. No Terminal required.
- **Quick-switch model menu** — click the `Ollama · <model>` strip in the sidebar to switch the active model from anywhere in the app.
- **Alignment badges** — every model is tagged green **Uncensored** / yellow **Lightly aligned** / orange **Aligned** so you can pick the right one for the conversation you want.
- **18 built-in characters** — gothic Victorian socialite, space pirate, mad scientist, time traveler, and the new **Likeness Architect** (vision bot for image-to-prompt workflows); every one with a distinct voice tuned for engaging back-and-forth conversation.
- **Image attachments** — drop a photo on a vision-enabled bot (paperclip or drag-and-drop). The Likeness Architect ships ready to turn a portrait into a privacy-preserving image-generation prompt.
- **Per-character default models** — built-ins ship with sensible model preferences (e.g. The Baker → `wizard-vicuna-uncensored`, AXIOM → `dolphin-llama3`); custom characters can override too. Missing preferred models silently fall back to the global default with a header badge.
- **Shapeshifter bot** — tells you to name any role, then fully commits to that persona for the whole conversation.
- **Create your own characters** — build personas from scratch with a name, avatar emoji, tagline, system prompt, greeting, and accent color.
- **Edit built-in characters** — tweak any built-in persona's system prompt or style, with a one-click **Reset to Default** to restore the original.
- **Per-character model override** — assign a specific Ollama model to any character.
- **Streaming responses** — text appears token-by-token with a live typing indicator; markdown renders inline (**bold**, *italic*, `code`).
- **Persistent conversations** — each character remembers your full chat history across launches.
- **Auto Ollama startup** — on launch the app checks for Ollama, starts the server if it is not running, and pulls a default model if none are installed.
- **Local-first** — no data leaves your machine; no accounts required.

---

## Requirements

| | |
|---|---|
| macOS | 14.0 Sonoma or later |
| Xcode | 15+ (16 recommended) |
| XcodeGen | `brew install xcodegen` |
| Ollama | Installed separately — see INSTALL.md |
| Disk space | ~4 GB for `dolphin-mistral` (default model) |

---

## Quick start

```bash
cd SizzleBot
./setup.sh              # installs Ollama + pulls dolphin-mistral
xcodegen generate       # only needed after adding/removing source files
open SizzleBot.xcodeproj
# ⌘R to build and run
```

See [INSTALL.md](INSTALL.md) for full instructions and [USER_MANUAL.md](USER_MANUAL.md) for feature reference.

---

## Project layout

```
SizzleBot/
├── Sources/SizzleBot/
│   ├── App/               # SizzleBotApp, RootView, Version, Info.plist, entitlements
│   ├── Assets.xcassets/   # AppIcon at all 10 macOS sizes
│   ├── Models/            # Character, Message, Conversation, OllamaModel, SampleCharacters
│   ├── Services/          # OllamaService, OllamaSetup, CharacterStore, ConversationStore,
│   │                      # ImageAttachment, PromptExporter
│   └── Views/             # ContentView, SidebarView, ChatView, MessageBubble,
│                          # TypingIndicator, MessageInputView, CharacterEditorView,
│                          # PromptActionsPanel, SettingsView, SetupView, WelcomeView
├── Tests/SizzleBotTests/  # Unit tests
├── tools/
│   └── generate-icon.swift  # Regenerates AppIcon at all sizes (re-run when redesigning)
├── project.yml            # XcodeGen spec
├── setup.sh               # One-shot Ollama + model install script
└── run-tests.sh           # Test runner
```

---

## Architecture

| Layer | Details |
|---|---|
| **OllamaService** | `@MainActor` class; streams responses from `localhost:11434` via `URLSession.AsyncBytes`; per-character model override; configurable `temperature`, `top_p`, token limit |
| **OllamaSetup** | Runs at app launch; detects binary, starts server via `Process`, polls health endpoint, pulls default model with progress reporting if none installed |
| **CharacterStore** | `@MainActor`; merges static defaults with UserDefaults overrides; full reset-to-default per character or all at once |
| **ConversationStore** | `@MainActor`; keyed `[UUID: Conversation]` in UserDefaults; each character has an independent history |
| **Views** | `NavigationSplitView` sidebar + detail; streaming bubble + typing indicator; markdown via `AttributedString(markdown:)` |

---

## Recommended models

Models are ordered by how roleplay-friendly they are out of the box. The roleplay preamble (added in 1.1.0) helps any model behave, but uncensored models still feel most natural for character chat.

| Model | Command | Notes |
|---|---|---|
| `dolphin-mistral` | `ollama pull dolphin-mistral` | **Default.** Uncensored — ideal for character roleplay |
| `dolphin-llama3` | `ollama pull dolphin-llama3` | Uncensored Llama 3 8B — stronger reasoning |
| `nous-hermes2` | `ollama pull nous-hermes2` | Lightly aligned; expressive, great for long scenes |
| `wizard-vicuna-uncensored` | `ollama pull wizard-vicuna-uncensored` | Heavily uncensored; adult fiction friendly |
| `llama3.2` | `ollama pull llama3.2` | Aligned; compact & fast — may inject safety caveats |
| `llama3.1` | `ollama pull llama3.1` | Aligned; larger & more capable |
| `mistral` | `ollama pull mistral` | Moderately aligned; fast, well-rounded |
| `gemma3` | `ollama pull gemma3` | Google-aligned; efficient on Apple Silicon |
| `qwen2.5` | `ollama pull qwen2.5` | Moderately aligned; strong multilingual |

---

## Running tests

```bash
./run-tests.sh
```

---

## License

Personal / private use. All rights reserved.
