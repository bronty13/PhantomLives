# Tic Tac Toe — Console Game

A polished, fully-featured Tic Tac Toe game for the terminal, written in Python. Play against an AI opponent with three difficulty levels, track all-time statistics, and review a persistent game log.

---

## Table of Contents

1. [Requirements](#requirements)
2. [Quick Start](#quick-start)
3. [Running the Game](#running-the-game)
   - [Interactive Mode](#interactive-mode)
   - [Command-Line Options](#command-line-options)
4. [How to Play](#how-to-play)
   - [Move Selection](#move-selection)
   - [In-Game Commands](#in-game-commands)
5. [Difficulty Levels](#difficulty-levels)
6. [Menus](#menus)
   - [Main Menu](#main-menu)
   - [Options Menu](#options-menu)
7. [Statistics](#statistics)
8. [Game Log](#game-log)
9. [Persistent Data](#persistent-data)
10. [Code Architecture](#code-architecture)
    - [Module Layout](#module-layout)
    - [Key Functions](#key-functions)
    - [AI Algorithm](#ai-algorithm)
    - [Data Structures](#data-structures)
11. [Configuration](#configuration)
12. [Colour / Accessibility](#colour--accessibility)
13. [Error Handling](#error-handling)

---

## Requirements

- Python **3.10** or newer (uses `list[...]` and `tuple[...]` built-in generics)
- A terminal that supports **ANSI escape codes** for colour (macOS Terminal, iTerm2, Windows Terminal, most Linux terminals)
- No third-party packages — uses only the Python standard library

---

## Quick Start

```bash
python3 tictactoe.py
```

---

## Running the Game

### Interactive Mode

Launch with no arguments to enter the full interactive menu:

```bash
python3 tictactoe.py
```

You will see the TIC TAC TOE banner followed by the main menu.

### Command-Line Options

```
usage: tictactoe.py [-h] [-d {easy,medium,hard}] [--no-color] [--stats]
                    [--log] [--purge] [--purge-days PURGE_DAYS]
                    [--reset-stats]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--difficulty easy\|medium\|hard` | `-d` | Skip the menu and start a game at the given difficulty |
| `--no-color` | | Disable all ANSI colour output (useful for pipes or terminals without colour support) |
| `--stats` | | Print all-time statistics and exit |
| `--log` | | Print the 50 most recent game log entries and exit |
| `--purge` | | Purge log entries older than `--purge-days` and exit |
| `--purge-days N` | | Override the default 30-day log retention when used with `--purge` (default: `30`) |
| `--reset-stats` | | Zero out all statistics and exit |
| `--help` | `-h` | Show help text and exit |

**Examples:**

```bash
# Jump straight into a Hard game
python3 tictactoe.py --difficulty hard

# View statistics
python3 tictactoe.py --stats

# View the recent game log
python3 tictactoe.py --log

# Purge log entries older than 7 days
python3 tictactoe.py --purge --purge-days 7

# Reset all statistics
python3 tictactoe.py --reset-stats

# Plain text output (no ANSI colour)
python3 tictactoe.py --no-color
```

---

## How to Play

### Move Selection

Moves are selected using the **numpad layout** (1–9). The number on the key corresponds to the matching board position:

```
 7 │ 8 │ 9        ← top row
 ──┼───┼──
 4 │ 5 │ 6        ← middle row
 ──┼───┼──
 1 │ 2 │ 3        ← bottom row
```

Empty cells on the board display their numpad number as a hint. Simply type the
number and press Enter.

**Example:** To play the centre cell, type `5` and press Enter.

### In-Game Commands

At your move prompt you may also type:

| Input | Action |
|-------|--------|
| `1`–`9` | Place your mark on that board position |
| `o` | Open the **Options** menu without forfeiting the game |
| `q` | Quit immediately (Ctrl-C also works) |

---

## Difficulty Levels

| Level | Behaviour | Keyboard Shortcut |
|-------|-----------|-------------------|
| **Easy** | AI picks a random empty cell every turn | `1` or `e` |
| **Medium** | AI plays the optimal move 50% of the time; randomly otherwise | `2` or `m` |
| **Hard** | AI always plays the perfect move using the Minimax algorithm — the best you can achieve is a draw | `3` or `h` |

At the start of each game the difficulty is shown on screen. You can change
difficulty mid-session via the Options menu without losing your overall stats.

---

## Menus

### Main Menu

```
  Main Menu
    1  New Game
    2  Options
    3  Statistics
    4  Game Log
    q  Quit
```

| Choice | Action |
|--------|--------|
| `1` / `n` | Choose a difficulty and start a new game |
| `2` / `o` | Open the Options menu |
| `3` / `s` | View all-time statistics |
| `4` / `l` | View the recent game log |
| `q` / `5` | Exit the program |

### Options Menu

Accessible from the main menu (`2`) or in-game by typing `o` at your move prompt.

```
  ── Options ──
    1  Change difficulty   (current: Medium)
    2  Set log purge days  (current: 30)
    3  Purge old log entries now
    4  View statistics
    5  View recent game log
    6  Reset all statistics
    r  Return to game
```

| Choice | Action |
|--------|--------|
| `1` | Pick a new difficulty for future games in this session |
| `2` | Set how many days of log history to keep (minimum 1) |
| `3` | Immediately remove all log entries older than the configured purge age |
| `4` | Display the statistics screen |
| `5` | Display the recent game log |
| `6` | Permanently zero out all statistics (prompts for confirmation) |
| `r` / Enter | Return to the game or main menu |

---

## Statistics

Statistics are tracked **per session and all-time** across the following categories:

- **Games Played** — total number of completed games
- **Wins** — games where the human player won
- **Losses** — games where the computer won
- **Draws** — games that ended without a winner
- **Win Rate** — wins as a percentage of games played
- **By Difficulty** — the above breakdown repeated for each of Easy, Medium, and Hard

### Viewing Statistics

```bash
# Via CLI (no game launched)
python3 tictactoe.py --stats

# From main menu
Choose option 3

# From in-game options
Type 'o' at your move prompt, then choose 4
```

### Resetting Statistics

```bash
# Via CLI
python3 tictactoe.py --reset-stats

# From options menu
Choose option 6, confirm with 'y'
```

---

## Game Log

Every completed game is appended to a log file. Each entry records:

| Field | Description |
|-------|-------------|
| `timestamp` | ISO 8601 date/time of the game (e.g. `2026-03-18T14:32:07.123456`) |
| `result` | `"win"`, `"loss"`, or `"draw"` |
| `difficulty` | `"easy"`, `"medium"`, or `"hard"` |
| `player_mark` | `"X"` or `"O"` — which mark the human was assigned |
| `moves` | Total number of moves made in the game |
| `duration_s` | How long the game lasted in seconds |

### Viewing the Log

```bash
# Via CLI (shows last 50 entries)
python3 tictactoe.py --log

# From main menu
Choose option 4

# From in-game options
Type 'o', then choose 5
```

### Log Retention / Purging

By default, entries older than **30 days** are automatically purged at the end of every game. The retention period is configurable:

```bash
# Purge manually with a custom age
python3 tictactoe.py --purge --purge-days 7

# Change the age interactively
Options menu → 2
```

---

## Persistent Data

All persistent data is stored in the hidden directory `~/.tictactoe/` in your home folder.

```
~/.tictactoe/
├── stats.json      ← All-time statistics
└── game_log.json   ← Per-game log entries
```

The directory and files are created automatically on first run. You may safely delete `~/.tictactoe/` to wipe all data.

### `stats.json` Schema

```json
{
  "games_played": 12,
  "wins": 5,
  "losses": 4,
  "draws": 3,
  "by_difficulty": {
    "easy":   { "played": 4, "wins": 3, "losses": 0, "draws": 1 },
    "medium": { "played": 5, "wins": 2, "losses": 2, "draws": 1 },
    "hard":   { "played": 3, "wins": 0, "losses": 2, "draws": 1 }
  }
}
```

### `game_log.json` Schema

```json
[
  {
    "result": "win",
    "difficulty": "easy",
    "player_mark": "X",
    "moves": 7,
    "duration_s": 12.4,
    "timestamp": "2026-03-18T14:32:07.123456"
  }
]
```

---

## Code Architecture

### Module Layout

```
tictactoe.py
│
├── Imports & constants
│   ├── DATA_DIR, STATS_FILE, LOG_FILE       Persistent data paths
│
├── Style / colorize                         ANSI terminal colour helpers
│
├── Persistent data helpers
│   ├── _ensure_data_dir()                   Create ~/.tictactoe/ if absent
│   ├── load_stats() / save_stats()          Read/write stats.json
│   ├── load_log() / save_log()              Read/write game_log.json
│   ├── purge_log()                          Remove stale log entries
│   └── append_log_entry()                  Add one game record to the log
│
├── Board display
│   ├── NUM_TO_POS / POS_TO_NUM             Numpad ↔ (row, col) mappings
│   ├── _cell()                             Render a single coloured cell
│   └── print_board()                       Render the full board
│
├── Game logic
│   ├── check_winner()                      Win detection (row/col/diagonal)
│   ├── is_full()                           Draw detection
│   └── empty_cells()                       List available moves
│
├── AI
│   ├── minimax()                           Recursive optimal-play search
│   ├── best_move()                         Select the minimax best cell
│   └── ai_move()                           Dispatch by difficulty level
│
├── Human input
│   └── get_human_move()                    Numpad input with validation
│
├── Display helpers
│   ├── show_stats()                        Format and print statistics
│   └── show_log()                          Format and print game log
│
├── Menus
│   ├── BANNER                              ASCII-art title string
│   ├── print_banner()                      Print banner in colour
│   ├── choose_difficulty()                 Interactive difficulty picker
│   ├── options_menu()                      In-game / main options screen
│   └── main_menu()                         Top-level menu
│
├── Game loop
│   └── play_game()                         Run one full game, record result
│
├── CLI
│   └── parse_args()                        argparse configuration
│
└── Entry point
    └── main()                              Arg dispatch + interactive loop
```

### Key Functions

#### `play_game(settings) → settings`

Runs a single complete game. At the start of each call:
- Assigns X and O randomly between human and computer.
- X always moves first (so who goes first is also random).

Returns the (possibly modified) `settings` dict so difficulty changes made via the in-game Options menu persist for subsequent games.

#### `ai_move(board, computer, human, difficulty) → (row, col)`

Dispatcher that selects how the computer picks its cell:

```
difficulty == "easy"   → random.choice(empty_cells)
difficulty == "medium" → best_move (50%) or random (50%)
difficulty == "hard"   → best_move (always)
```

#### `minimax(board, is_maximizing, computer, human) → int`

Classic minimax — explores the full game tree (feasible on a 3×3 board) and returns:
- `+1` if the computer can force a win from this state
- `-1` if the human can force a win
- `0` for a forced draw

No alpha-beta pruning is needed; the search space is at most 9! = 362,880 nodes.

#### `get_human_move(board, player) → (row, col)`

Reads a single character `1`–`9` (numpad), validates that the cell is empty, and returns `(-1, -1)` as a sentinel when the player types `o` to open options.

#### `purge_log(max_age_days) → int`

Compares each entry's ISO timestamp string against a computed cutoff. Returns the number of entries removed. Called automatically after every game.

### AI Algorithm

The AI on **Hard** difficulty uses the **Minimax** algorithm:

```
minimax(board, is_maximizing):
    if computer has won  → return +1
    if human has won     → return -1
    if board is full     → return 0

    for each empty cell:
        place the current player's mark
        score = minimax(board, not is_maximizing)
        remove the mark

    return best score for the current player
```

`best_move()` calls `minimax` for each available cell, choosing the cell that yields the highest score for the computer. This guarantees optimal play — the computer will never lose.

### Data Structures

#### `board`

```python
board: list[list[str]]   # 3×3 grid; cells are "X", "O", or " "
```

Row 0 is the top of the board; row 2 is the bottom.

#### `settings`

A plain `dict` passed between functions as a mutable session-state bag:

```python
settings = {
    "difficulty": "medium",   # str: "easy" | "medium" | "hard"
    "purge_days": 30,         # int: max age of log entries in days
}
```

#### `NUM_TO_POS` / `POS_TO_NUM`

```python
NUM_TO_POS: dict[int, tuple[int, int]]   # numpad number → (row, col)
POS_TO_NUM: dict[tuple[int, int], int]   # (row, col)    → numpad number
```

---

## Configuration

There is no external config file. All runtime options are controlled through:

1. **Command-line flags** (`--difficulty`, `--purge-days`, etc.) — take effect for that invocation
2. **Options menu** — change difficulty and purge age interactively; changes persist for the current session only
3. **Direct file edits** — the constants at the top of `tictactoe.py` can be changed to alter defaults:

| Constant | Default | Effect |
|----------|---------|--------|
| `DATA_DIR` | `~/.tictactoe` | Where stats and log are stored |
| `STATS_FILE` | `DATA_DIR / "stats.json"` | Statistics file path |
| `LOG_FILE` | `DATA_DIR / "game_log.json"` | Game log file path |

---

## Colour / Accessibility

- Colour is **automatically disabled** when stdout is not a TTY (e.g. when piping output to a file or another command).
- Pass `--no-color` to force plain text output in any environment.
- The `Style.disable()` classmethod blanks all ANSI codes at runtime; no code paths branch on colour — all display code runs the same either way.

Colour meanings:

| Colour | Used for |
|--------|----------|
| Cyan | Player X, headings |
| Magenta | Player O |
| Green | Wins, success messages |
| Red | Losses, errors |
| Yellow | Draws, warnings, options prompt |
| Gray / Dim | Empty cells, secondary info |

---

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| Invalid move input (non-numeric) | Prints a red error message and re-prompts |
| Out-of-range move (not 1–9) | Prints a red error message and re-prompts |
| Cell already occupied | Prints a red error message and re-prompts |
| Corrupt `stats.json` | Silent fallback to fresh default statistics |
| Corrupt `game_log.json` | Silent fallback to an empty log |
| `~/.tictactoe/` missing | Created automatically (including parent directories) |
| Ctrl-C / `q` at any prompt | Prints a goodbye message and exits cleanly with code `0` |
| Invalid options-menu input | Prints "Unknown option" and re-displays the menu |
| Non-positive purge-days value | Prints an error and keeps the previous value |
