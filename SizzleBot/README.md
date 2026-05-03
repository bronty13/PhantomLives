# SizzleBot

**Version 1.0.0** — macOS 14+ (Sonoma and later)

SizzleBot is a native macOS chatbot app powered entirely by local LLMs via [Ollama](https://ollama.com). No cloud, no API keys, no subscriptions — conversations stay on your Mac. You interact through hand-crafted character personas, each with a distinct personality, voice, and backstory, or create your own.

---

## Features

- **17 built-in characters** — gothic Victorian socialite, space pirate, mad scientist, time traveler, and more; every one with a distinct voice tuned for engaging back-and-forth conversation.
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
│   ├── Models/            # Character, Message, Conversation, OllamaModel, SampleCharacters
│   ├── Services/          # OllamaService, OllamaSetup, CharacterStore, ConversationStore
│   └── Views/             # ContentView, SidebarView, ChatView, MessageBubble,
│                          # TypingIndicator, MessageInputView, CharacterEditorView,
│                          # SettingsView, SetupView, WelcomeView
├── Tests/SizzleBotTests/  # Unit tests
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

| Model | Command | Notes |
|---|---|---|
| `dolphin-mistral` | `ollama pull dolphin-mistral` | Default; uncensored, great for roleplay |
| `dolphin-llama3` | `ollama pull dolphin-llama3` | Uncensored Llama 3 8B |
| `llama3.2` | `ollama pull llama3.2` | Compact, fast on Apple Silicon |
| `mistral` | `ollama pull mistral` | Fast, well-rounded |
| `gemma3` | `ollama pull gemma3` | Efficient on Apple Silicon |
| `qwen2.5` | `ollama pull qwen2.5` | Strong multilingual |

---

## Running tests

```bash
./run-tests.sh
```

---

## License

Personal / private use. All rights reserved.
