# Changelog

All notable changes to SizzleBot are recorded here.

## [1.5.0] — 2026-05-04

### Changed

- **Likeness Architect now produces high-fidelity prompts.** Reports of clothing not matching the source photo led to a full rewrite of the architect's system prompt. New behavior:
  - Reframed as a **forensic visual analyst** — explicit success criterion is that an image generator pasting the prompt should produce an image matching the source's face, outfit, pose, and lighting.
  - "Describe ONLY what is actually visible — do not invent, simplify, beautify, idealize, or generalize. If a detail is unclear or occluded, omit it; never guess."
  - **Per-garment clothing breakdown is now mandatory** — for each visible garment the model must specify color, garment type, neckline / cut, fabric look, fit, sleeves, patterns, and layering (e.g. "white t-shirt under unbuttoned grey flannel"). Tops, bottoms, outerwear, footwear, and visible undershirts are each named.
  - Output length raised from 70–130 → **150–220 words** to fit the structured (subject / clothing / accessories / framing) breakdown.
  - "Re-check the photograph once before composing your answer. Verify each detail you mention is actually present."

- **Vision / utility characters now use a dedicated `utilityPreamble`** instead of the roleplay preamble. The roleplay preamble's opening line — *"You are participating in an immersive fictional roleplay"* — was actively pushing the analyst toward stylized output when we wanted precise output. The new utility preamble keeps every anti-refusal / anti-hedge protection (vision models love to say "I can't identify people in photos") and drops the fiction framing. Routing is automatic: any character with `acceptsImages == true` gets the utility preamble; everyone else still gets the roleplay preamble.

### Added

- **Application icon.** A 🌶️ glyph centered on a vertical purple→pink gradient inside the standard macOS rounded-square mask, rendered at all 10 required sizes (16×16 through 512×512 @2x). Matches the "Sizzle" brand. The icon is reproducible: `tools/generate-icon.swift` regenerates the entire AppIcon set on demand, so future redesigns are a one-line edit.
- `OllamaService.utilityPreamble` static — the new vision/utility framing.
- Tests: utility preamble shape (anti-refusal kept, fiction framing dropped), preamble routing by `supportsImages`, and an architect-prompt-fidelity test that fails if anyone weakens the "describe only what's visible" / per-garment / layering / fit-color-fabric guidance.

### Note for existing users

If you'd previously edited the Likeness Architect, you're still on your old prompt. Right-click → **Reset to Default** (or **Settings → Characters → Reset All Built-in Characters**) to pick up the new prompt. If you'd never touched it, you'll get the new prompt automatically on launch.

## [1.4.0] — 2026-05-04

### Added

- **One-click prompt export from the Likeness Architect.** Every assistant message from a vision-enabled bot now shows an actions panel below the bubble: one row for the plain paragraph plus one row per parsed `Style variants:` tag, each with a `Use ▾` menu containing **Copy to Clipboard**, **Send to Draw Things**, and **Send to DiffusionBee**.
- **Send to Draw Things / DiffusionBee.** Both apps lack a documented URL scheme for prompt prefill (verified against official docs and developer GitHubs), so the integration uses the only flow that works reliably: copy the composed prompt to the clipboard, then bring the target app to the foreground via `NSWorkspace.open(...)`. The user pastes with ⌘V. The panel surfaces this honestly with a tip line and per-action confirmation.
- **Graceful "app not found" handling.** If the target app isn't in `/Applications` or `~/Applications`, the prompt still lands on the clipboard and the panel says so — no silent failure.
- `PromptExporter` service — pure parser (paragraph + variants extraction with case/whitespace/dash/semicolon tolerance and "mid-paragraph mention" disambiguation), `composePrompt(paragraph:variant:)` joiner, `locate(_:)` for app discovery, `send(prompt:to:)` for the copy-and-launch flow.
- `PromptActionsPanel` view — renders below assistant messages from any character with `acceptsImages == true`. Transient confirmation under the panel after each action; auto-clears after 4 seconds.
- 11 new tests covering the parser's tolerance and the prompt composition format.

## [1.3.0] — 2026-05-04

### Added

- **Likeness Architect** — new built-in vision-capable bot (📸, 18th built-in). Drop a photo of a person; it returns a 70–130-word portrait paragraph plus three style-variant tags, formatted as an image-generation prompt. Designed for the privacy-preserving workflow of generating fresh character art that *resembles* a real person without actually using their photograph. Refuses to name or identify the subject; describes physical reality only; ignores tattoos / scars / logos / context that could re-identify; asks for clarification when the photo has multiple people or no person at all. Ships with `preferredModel = "llama3.2-vision"`.
- **Image attachments in chat.** Vision-enabled characters get a paperclip button and accept drag-and-drop / file-picker images. Attachments appear as a thumbnail tray above the input field with one-click removal, render inline in message bubbles, and open full-size in a click-through sheet. Images are downscaled to a 1024px long edge and re-encoded as JPEG before persistence + transmission, so payloads stay reasonable.
- `Character.acceptsImages: Bool?` (with a `supportsImages` computed property that defaults to false). The character editor gains a **Accept image attachments** toggle so users can build their own vision bots.
- `Message.images: [String]?` carries base64-encoded JPEGs and is threaded through Ollama's `/api/chat` `images` field on user messages. Both new fields are optional, so messages and characters persisted before 1.3.0 decode cleanly with images / image-acceptance disabled.
- `ImageAttachment` service — encodes file URLs / `Data` / `NSImage` into base64 JPEG (downscaled, quality 0.85) and decodes back to `NSImage` for rendering.
- **Vision-capable models in the installer.** `llama3.2-vision`, `llava`, and `moondream` are added to **Settings → Install Models**, each tagged with a new purple **Vision** chip alongside the existing alignment chip.
- `OllamaModel.Kind` enum (`.chat | .vision`) and a `kind` field on `Recommendation`. Vision chip surfaces in both the install list and the active-model picker.
- **Per-character default models.** Several built-ins now ship with a `preferredModel` that better matches their voice: Professor Grimoire / Countess Vesper / AXIOM / Zara Neon / Detective Marlowe / The Shapeshifter → `dolphin-llama3` (stronger reasoning); The Oracle → `nous-hermes2` (poetic); The Baker → `wizard-vicuna-uncensored` (assassin themes); Likeness Architect → `llama3.2-vision`. Other characters keep using the global default.
- **Graceful fallback when a preferred model isn't installed.** `OllamaService.effectiveModel(for:)` returns the preferred model if installed, otherwise the global default, plus a flag indicating fallback occurred. `OllamaService.isInstalled(_:)` recognizes both bare (`dolphin-mistral`) and tagged (`dolphin-mistral:latest`) names.
- **Fallback badge in the chat header.** A small orange "Using <fallback>" capsule appears next to the **⋯** menu when the active character's preferred model isn't installed, with a tooltip pointing to **Settings → Install Models**.
- **Effective-model panel in the chat header menu.** **⋯** now shows both *Preferred model* (if any) and *Running on*, so it's clear which model is actually serving the conversation.
- Tests covering: built-in count = 18, Likeness Architect presence + vision-model preference, `acceptsImages` default & forward-compat decoding, `Message.images` round-trip & forward-compat decoding, vision recommendations present, `effectiveModel(for:)` fallback semantics, `isInstalled(_:)` tag tolerance.

### Changed

- `OllamaModel.Recommendation` is now a struct (was already a struct in 1.2.0; the new `kind` field has a `.chat` default for source compatibility).

## [1.2.0] — 2026-05-03

### Added

- **In-app model installer.** Settings → **Install Models** lists every recommended model with a one-click **Install** button. Pulls run in-process via the Ollama API with a live progress bar; once complete the model appears in the picker without needing a refresh. No more dropping into Terminal to run `ollama pull`.
- **Quick-switch model menu in the sidebar footer.** The `Ollama · <model>` strip is now a menu — click to switch any installed model instantly, jump to Settings, or refresh the model list. Two clicks from "this model is nagging me" to "switched to wizard-vicuna-uncensored."
- **Alignment badges.** Every model in the active-model picker and the install list shows a colored chip — green **Uncensored**, yellow **Lightly aligned**, orange **Aligned** — so it's obvious at a glance which models will hedge and which won't.
- **Per-model state in the install list.** Each recommended model shows one of: **Install** button, in-progress bar with status & percent, **Installed** + **Use** button, or **Active** indicator if it is the current default.
- `OllamaModel.Alignment` enum and `OllamaModel.Recommendation` struct replace the previous tuple-based recommended list.
- `OllamaModel.recommendation(for:)` — tolerant lookup that handles both bare (`dolphin-mistral`) and tagged (`dolphin-mistral:latest`) ollama names; used by the picker to attach alignment chips to installed models.
- `OllamaSetup.pullModelOnDemand(_:then:)` — fire-and-forget install API used by Settings; tracks per-model progress / status / errors via new `pullProgress`, `pullStatus`, `pullErrors` published dictionaries; refreshes the supplied `OllamaService` on completion. Kept separate from the SetupView state machine so user-initiated pulls don't hijack the first-run UI.
- Tests: alignment-tag invariants, `recommendation(for:)` tolerance for tagged ollama names, and an `OllamaSetup` initial-state check.

### Changed

- Settings window grows to 540×640 to accommodate the new install rows comfortably.
- The "Recommended Models" disclosure group (1.1.0) is replaced by the always-visible **Install Models** section.

## [1.1.0] — 2026-05-03

### Changed

- **In-character roleplay framing.** Every chat request now prepends a roleplay preamble to the character's system prompt at the `OllamaService` layer. The preamble instructs the model to stay fully in character, never break the scene to add safety warnings, content advisories, ethical caveats, refusals, or moral lectures, and to avoid AI-disclosure phrasing like "As an AI" or "I'm sorry, but". This addresses the issue where bots — even on uncensored models — would still inject unwanted nags despite the app's existing legal disclaimers and Terms of Use. Applies uniformly to all 17 built-in characters and any user-created characters with no per-character editing required.
- **Recommended models reordered & expanded.** The Settings → Recommended Models list now leads with the strongest uncensored, roleplay-friendly options (`dolphin-mistral`, `dolphin-llama3`, `nous-hermes2`, `wizard-vicuna-uncensored`) and labels each model with its alignment posture so users can pick one that matches the kind of conversation they want. `wizard-vicuna-uncensored` is new to the list.

### Added

- `OllamaService.roleplayPreamble` — public static constant exposing the framing text.
- `OllamaService.fullSystemPrompt(for:)` — public static helper that combines the preamble with a character's system prompt; pure function, unit-testable without hitting the network.
- `OllamaServiceTests` — covers preamble content, prompt composition, and the recommended-models ordering invariant.

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
