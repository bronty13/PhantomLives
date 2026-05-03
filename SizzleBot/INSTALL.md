# SizzleBot — Installation Guide

## Prerequisites

| Requirement | Notes |
|---|---|
| macOS 14 Sonoma or later | Required for `NavigationSplitView`, `AttributedString(markdown:)` |
| Xcode 15+ (16 recommended) | Install from the Mac App Store |
| XcodeGen | Generates `SizzleBot.xcodeproj` from `project.yml` |
| Ollama | Manages and runs local LLM models; free and open source |

---

## Step 1 — Install Xcode

Install Xcode from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835) if you don't have it.  
Xcode 16 is recommended. Xcode 15 will also work.

After installation, accept the license agreement:

```bash
sudo xcodebuild -license accept
```

---

## Step 2 — Install XcodeGen

XcodeGen reads `project.yml` and generates the `.xcodeproj` file.

```bash
brew install xcodegen
```

If you don't have Homebrew:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

---

## Step 3 — Install Ollama and pull a model

**Option A — Automated (recommended)**

Run the included setup script from inside the `SizzleBot/` directory:

```bash
./setup.sh
```

This script:
1. Installs Homebrew if missing
2. Installs Ollama via `brew install ollama`
3. Starts the Ollama server (`ollama serve`)
4. Pulls the default model `dolphin-mistral` (~4 GB)

To use a different model:

```bash
./setup.sh llama3.2
```

**Option B — Manual**

1. Install Ollama: download from [ollama.com](https://ollama.com) or `brew install ollama`
2. Start the server: `ollama serve` (runs on `localhost:11434`)
3. Pull a model: `ollama pull dolphin-mistral`

The server must be running before you launch SizzleBot. The app will attempt to start it automatically on launch, but it is safest to start it yourself for the first run.

---

## Step 4 — Generate the Xcode project

From inside the `SizzleBot/` directory:

```bash
xcodegen generate
```

This produces `SizzleBot.xcodeproj`. Re-run this command any time you add or remove Swift source files.

---

## Step 5 — Build and run

```bash
open SizzleBot.xcodeproj
```

In Xcode, press **⌘R** or click the Run button.  
The app opens, detects Ollama, connects, and is ready to chat.

---

## Verifying the setup

The sidebar status bar at the bottom shows:

- 🟢 **Ollama · dolphin-mistral** — connected and ready
- 🔴 **Ollama offline** — server not running; click **Retry** or run `ollama serve` in Terminal

You can also verify from Terminal:

```bash
curl http://localhost:11434/api/tags   # should return a JSON list of models
ollama list                            # lists installed models
```

---

## Changing models

After installing additional models with `ollama pull <name>`, go to **SizzleBot → Settings** (⌘,) and select the model from the **Active Model** picker.

To assign a model to a specific character, open the character editor (right-click a character → **Edit**) and enter the model name in the **Preferred Model** field.

---

## Updating Ollama

```bash
brew upgrade ollama
```

Restart the server after upgrading:

```bash
pkill ollama && ollama serve &
```

---

## Uninstalling

To remove SizzleBot data:

```bash
defaults delete com.bronty.SizzleBot   # clears all UserDefaults (conversations, settings)
```

To remove Ollama and its models:

```bash
brew uninstall ollama
rm -rf ~/.ollama
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Ollama offline" in status bar | Run `ollama serve` in Terminal; click Retry in the app |
| Model pull hangs | Check disk space (`df -h ~`); at least 5 GB free recommended |
| App opens to setup screen on every launch | Ollama server not starting; add `ollama serve &` to your shell profile |
| `xcodegen generate` fails | Ensure XcodeGen ≥ 2.40: `brew upgrade xcodegen` |
| Build error: "missing entitlement" | In Xcode, set Signing & Capabilities → Team to your Apple ID |
| No characters visible | Reset app data: `defaults delete com.bronty.SizzleBot` then relaunch |
