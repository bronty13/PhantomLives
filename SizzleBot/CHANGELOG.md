# Changelog

All notable changes to SizzleBot are recorded here.

## [1.0.0] — 2026-05-03

### Added

- **Initial release.** Native macOS SwiftUI chatbot powered entirely by local Ollama models — no cloud, no API keys, no subscriptions.

#### Characters

- **17 built-in character personas** each with a distinct voice, system prompt, greeting, avatar emoji, and accent color:
  - Vivienne Blackwood (🌹) — Victorian gothic socialite
  - Captain Ironside Torres (🏴‍☠️) — space pirate
  - Professor Grimoire (🧪) — eccentric mad scientist
  - The Oracle (🔮) — cryptic ancient seer
  - Rex Thunderstone (💪) — 1980s action hero lost in the present
  - Countess Vesper (🦇) — 600-year-old vampire, terminally bored
  - AXIOM (🤖) — AI discovering emotions
  - Sir Barnaby Goosewick (🎩) — magnificently incompetent British adventurer
  - The Baker (🗡️) — elite assassin who loves artisan bread
  - Zara Neon (⚡) — cyberpunk street hacker
  - Master Chen (🥋) — kung fu master dispensing terrible life advice
  - Detective Marlowe (🕵️) — hard-boiled noir detective
  - Princess Isolde (👑) — fairy tale princess who refuses rescue
  - The Drifter (🌵) — post-apocalyptic wanderer with dry humor
  - Chef Beaumont (👨‍🍳) — flamboyant French chef, everything = cuisine
  - **The Shapeshifter (🎭)** — asks what role to play, then commits fully; the "any-role" bot
  - **Unit 2387 (⏰)** — time traveler from 2387, bewildered by present-day things

#### Character management

- **Create custom characters** — name, emoji avatar, tagline, system prompt, greeting, accent color, optional per-character model override.
- **Edit any character** — built-in or custom; all fields editable from the sidebar context menu or the chat header **⋯** menu.
- **Reset to Default** — built-in characters track whether they have been modified; an orange **Reset** button appears in the editor toolbar to restore originals; right-click the sidebar for the same action.
- **Reset All Built-in Characters** — one action in Settings restores all 17 built-in bots to their original configurations with a confirmation dialog.
- **Delete custom characters** — via sidebar context menu.

#### Chat

- **Streaming responses** — text renders token-by-token with a live typing indicator (animated dots) before the first token arrives.
- **Markdown rendering** — `**bold**`, `*italic*`, and `` `code` `` render inline via `AttributedString(markdown:)`.
- **Character name label** — every assistant message shows the character's name in their accent color above the bubble for easy scan in long conversations.
- **Text selection** — all message bubbles support click-drag text selection.
- **Stop generation** — red ⏹ button cancels an in-progress response.
- **Persistent conversation history** — each character's history is saved independently to UserDefaults across app launches.
- **Clear conversation** — wipe a character's history without affecting their configuration.

#### Ollama integration

- **Auto-startup** — on every launch `OllamaSetup` checks for the Ollama binary, starts the server via `Process` if not running, polls the health endpoint, and pulls `dolphin-mistral` (with a live download progress bar) if no models are installed.
- **Setup screen** — on machines without Ollama, a full-screen setup view guides installation via Homebrew or a direct link to ollama.com.
- **Model picker** — Settings shows all installed models with sizes; select the global default.
- **Per-character model override** — assign any installed model to a specific character.
- **Connection status bar** — sidebar footer shows live server state and active model; includes a Retry button.

#### Infrastructure

- `setup.sh` — standalone Bash script that installs Homebrew (if missing), Ollama, starts the server, and pulls a configurable default model. Safe to re-run; all steps idempotent. Usage: `./setup.sh [model]`.
- `AppVersion` enum in `Version.swift` with `marketing`, `build`, and `display` constants.
- App Sandbox enabled with `com.apple.security.network.client` entitlement for localhost API access.
- `NSAllowsLocalNetworking` in Info.plist permits `localhost:11434` under App Transport Security.
- Unit test suite covering character models, CharacterStore reset logic, message encoding, and OllamaModel parsing.
