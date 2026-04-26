#!/usr/bin/env python3
"""
Tic Tac Toe — A polished console game with variable player counts.

Player modes:
  0 players — AI vs AI (spectator / simulation mode)
  1 player  — Human vs AI  (default)
  2 players — Human vs Human

Features:
  • Three AI difficulty levels (Easy / Medium / Hard)
  • Per-player difficulty when both sides are AI
  • Configurable auto-play speed in AI-vs-AI mode
  • Numbered-pad move selection (1-9 maps to the board)
  • Slash commands accessible from ANY prompt (type /help for list)
  • Persistent all-time statistics (JSON)
  • Auto-purging game log (default 30 days, configurable)
  • In-game options menu
  • Full command-line interface via argparse
  • Colorized, box-drawing board display

Slash commands (available everywhere):
  /help [cmd]          List all commands or show help for one command
  /quit [--force]      Quit the game
  /stats               Show all-time statistics
  /log  [--last N]     Show the N most recent log entries (default 20)
  /options             Open the options menu
  /difficulty <level>  Change AI difficulty (easy | medium | hard)
  /speed <seconds>     Set AI-vs-AI auto-play speed
  /purge [--days N]    Purge log entries older than N days (default 30)
  /new                 Abandon the current game and start a new one
  /board               Reprint the current board

Run with --help for CLI options or just launch to use the interactive menu.
"""

# ── Standard-library imports ─────────────────────────────────c───────────────
import argparse
import json
import os
import random
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

# ── Paths for persistent data ──────────────────────────────────────────────
DATA_DIR   = Path.home() / ".tictactoe"               # Hidden config dir
STATS_FILE = DATA_DIR / "stats.json"                   # All-time statistics
LOG_FILE   = DATA_DIR / "game_log.json"                # Per-game log entries

# ═══════════════════════════════════════════════════════════════════════════
# ANSI colour / style helpers
# ═══════════════════════════════════════════════════════════════════════════

class Style:
    """ANSI escape sequences for terminal colouring.  Degrades gracefully
    when output is piped or when --no-color is passed."""

    _enabled = True   # Set to False to suppress all codes

    RESET   = "\033[0m"
    BOLD    = "\033[1m"
    DIM     = "\033[2m"
    # Foreground colours
    RED     = "\033[91m"
    GREEN   = "\033[92m"
    YELLOW  = "\033[93m"
    BLUE    = "\033[94m"
    MAGENTA = "\033[95m"
    CYAN    = "\033[96m"
    WHITE   = "\033[97m"
    GRAY    = "\033[90m"

    @classmethod
    def disable(cls):
        """Turn off all ANSI codes (for pipes / --no-color)."""
        for attr in list(vars(cls)):
            if attr.startswith("_") or callable(getattr(cls, attr)):
                continue
            setattr(cls, attr, "")
        cls._enabled = False

# Convenience shortcuts
S = Style

def colorize(text: str, *codes: str) -> str:
    """Wrap *text* in the given ANSI codes and reset at the end."""
    return "".join(codes) + text + S.RESET


# ═══════════════════════════════════════════════════════════════════════════
# Slash-command system
# ═══════════════════════════════════════════════════════════════════════════
#
# Any string starting with "/" entered at ANY prompt is routed here.
# Commands have their own argument parsers so "--help" and switches work.
#
# Sentinel return values from handle_slash_command():
#   None          → command executed normally; caller re-prompts
#   "quit"        → caller should exit cleanly
#   "new"         → caller should abandon the current game and start fresh
#   "board"       → caller should reprint the board
#   "options"     → caller should open the options menu (legacy sentinel kept
#                   so 'o' shortcut still works)

# ── Per-command help text (shown by /help <cmd>) ────────────────────────

_SLASH_HELP: dict[str, str] = {
    "help": (
        "  /help [command]\n"
        "    Without arguments: list all available slash commands.\n"
        "    With a command name: show detailed help for that command.\n"
        "\n"
        "  Examples:\n"
        "    /help\n"
        "    /help log\n"
        "    /help difficulty\n"
    ),
    "quit": (
        "  /quit [--force]\n"
        "    Exit the program.  Without --force you will be asked to confirm\n"
        "    when a game is in progress.\n"
        "\n"
        "  Flags:\n"
        "    --force   Skip confirmation and quit immediately.\n"
        "\n"
        "  Aliases: /q  /exit\n"
    ),
    "stats": (
        "  /stats\n"
        "    Display all-time statistics broken down by outcome and difficulty.\n"
        "\n"
        "  No additional flags.\n"
    ),
    "log": (
        "  /log [--last N] [--all]\n"
        "    Display recent game log entries.\n"
        "\n"
        "  Flags:\n"
        "    --last N   Show the N most recent entries (default: 20).\n"
        "    --all      Show every entry in the log.\n"
        "\n"
        "  Aliases: /history\n"
    ),
    "options": (
        "  /options\n"
        "    Open the interactive options menu.  You can change difficulty,\n"
        "    log-purge age, view stats/log, and reset statistics from here.\n"
        "\n"
        "  Aliases: /opt  /o\n"
    ),
    "difficulty": (
        "  /difficulty <level>\n"
        "    Change the AI difficulty for the current session (1-player mode).\n"
        "\n"
        "  Arguments:\n"
        "    level   One of: easy  medium  hard\n"
        "            Abbreviations accepted: e  m  h  1  2  3\n"
        "\n"
        "  Examples:\n"
        "    /difficulty hard\n"
        "    /difficulty e\n"
        "    /d medium\n"
        "\n"
        "  Aliases: /d  /diff\n"
    ),
    "speed": (
        "  /speed <seconds>\n"
        "    Set the auto-play delay between moves in AI-vs-AI (0-player) mode.\n"
        "\n"
        "  Arguments:\n"
        "    seconds   A non-negative number (0 = instant).\n"
        "\n"
        "  Examples:\n"
        "    /speed 1.5\n"
        "    /speed 0\n"
    ),
    "purge": (
        "  /purge [--days N]\n"
        "    Remove log entries older than N days and report how many were removed.\n"
        "\n"
        "  Flags:\n"
        "    --days N   Age threshold in days (default: current purge_days setting).\n"
        "\n"
        "  Examples:\n"
        "    /purge\n"
        "    /purge --days 7\n"
    ),
    "new": (
        "  /new\n"
        "    Forfeit the current game and return to the main menu to start a new one.\n"
        "    You will be asked to confirm if a game is in progress.\n"
        "\n"
        "  Aliases: /restart\n"
    ),
    "board": (
        "  /board\n"
        "    Reprint the current game board (useful if the display has scrolled).\n"
        "\n"
        "  Aliases: /b  /show\n"
    ),
    "loop": (
        "  /loop [N | off]\n"
        "    Control auto-repeat mode — games run back-to-back without prompting.\n"
        "\n"
        "  Arguments:\n"
        "    (none)   Show current loop setting.\n"
        "    0 / ∞    Infinite loop (stop with Ctrl-C or /quit).\n"
        "    N        Play exactly N games then stop.\n"
        "    off / 1  Return to interactive mode (ask after each game).\n"
        "\n"
        "  Examples:\n"
        "    /loop          Show current setting\n"
        "    /loop 0        Infinite auto-repeat\n"
        "    /loop 10       Play 10 games\n"
        "    /loop off      Back to interactive\n"
        "\n"
        "  Aliases: /repeat\n"
    ),
}

# Map aliases to canonical names
_SLASH_ALIASES: dict[str, str] = {
    "q": "quit", "exit": "quit",
    "history": "log",
    "opt": "options", "o": "options",
    "d": "difficulty", "diff": "difficulty",
    "restart": "new",
    "b": "board", "show": "board",
    "repeat": "loop",
}

_ALL_COMMANDS = sorted(set(_SLASH_HELP.keys()))


def _slash_help(args: list[str]) -> None:
    """Print help for one command or list all commands."""
    if args:
        name = args[0].lstrip("/").lower()
        name = _SLASH_ALIASES.get(name, name)
        if name in _SLASH_HELP:
            print(f"\n{colorize(_SLASH_HELP[name], S.WHITE)}")
        else:
            print(colorize(f"\n  Unknown command: /{name}  (type /help for a list)\n", S.RED))
        return

    # List all commands
    div = colorize("─" * 50, S.DIM)
    print(f"\n  {S.BOLD}{S.CYAN}Slash Commands  (available at any prompt){S.RESET}")
    print(f"  {div}")
    rows = [
        ("/help [cmd]",          "List commands or show help for one"),
        ("/quit [--force]",      "Exit the program"),
        ("/stats",               "Show all-time statistics"),
        ("/log [--last N]",      "Show recent game log"),
        ("/options",             "Open the options menu"),
        ("/difficulty <level>",  "Change AI difficulty"),
        ("/speed <seconds>",     "Set AI-vs-AI auto-play speed"),
        ("/loop [N|off]",        "Auto-repeat games without prompting"),
        ("/purge [--days N]",    "Remove old log entries"),
        ("/new",                 "Forfeit current game, start new one"),
        ("/board",               "Reprint the current board"),
    ]
    for cmd, desc in rows:
        print(f"  {colorize(f'{cmd:<26}', S.BOLD, S.YELLOW)}{colorize(desc, S.WHITE)}")
    print(f"\n  {S.DIM}Type /help <command> for detailed help on any command.{S.RESET}\n")


def handle_slash_command(raw: str, settings: dict,
                         in_game: bool = False,
                         board: list | None = None) -> str | None:
    """Parse and execute a slash command entered by the user.

    Parameters
    ----------
    raw       : The raw input string, starting with '/'.
    settings  : The mutable session-settings dict.
    in_game   : True when called from inside an active game.
    board     : The current board state (needed for /board).

    Returns
    -------
    None        Command executed; caller should re-prompt.
    "quit"      Caller should exit cleanly.
    "new"       Caller should abandon the current game.
    "board"     Caller should reprint the board.
    "options"   Caller should open the options menu.
    """
    parts = raw.strip().split()
    cmd_raw = parts[0].lstrip("/").lower()
    cmd     = _SLASH_ALIASES.get(cmd_raw, cmd_raw)
    args    = parts[1:]

    # ── /help ──────────────────────────────────────────────────────────
    if cmd == "help":
        _slash_help(args)
        return None

    # ── /quit ──────────────────────────────────────────────────────────
    if cmd == "quit":
        force = "--force" in args or "-f" in args
        if in_game and not force:
            confirm = input(colorize(
                "  Quit and abandon this game? (y/n): ", S.YELLOW
            )).strip().lower()
            if confirm != "y":
                print(colorize("  Quit cancelled.", S.DIM))
                return None
        raise KeyboardInterrupt   # propagates to the top-level handler

    # ── /stats ─────────────────────────────────────────────────────────
    if cmd == "stats":
        show_stats()
        return None

    # ── /log ───────────────────────────────────────────────────────────
    if cmd == "log":
        last_n = 20
        if "--all" in args:
            last_n = 9999
        else:
            for i, a in enumerate(args):
                if a == "--last" and i + 1 < len(args):
                    try:
                        last_n = int(args[i + 1])
                        if last_n < 1:
                            raise ValueError
                    except ValueError:
                        print(colorize("  --last requires a positive integer.", S.RED))
                        return None
        show_log(last_n=last_n)
        return None

    # ── /options ───────────────────────────────────────────────────────
    if cmd == "options":
        # Return sentinel so caller (which has access to its local state)
        # can open the full options menu in the right context.
        return "options"

    # ── /difficulty ────────────────────────────────────────────────────
    if cmd == "difficulty":
        if not args or args[0] in ("--help", "-h"):
            _slash_help(["difficulty"])
            return None
        level_map = {
            "1": "easy",  "e": "easy",  "easy": "easy",
            "2": "medium","m": "medium","medium": "medium",
            "3": "hard",  "h": "hard",  "hard": "hard",
        }
        level = level_map.get(args[0].lower())
        if not level:
            print(colorize(f"  Unknown difficulty '{args[0]}'.  Use easy, medium, or hard.", S.RED))
            return None
        settings["difficulty"] = level
        print(colorize(f"  Difficulty set to {level.capitalize()}.", S.GREEN))
        return None

    # ── /speed ─────────────────────────────────────────────────────────
    if cmd == "speed":
        if not args or args[0] in ("--help", "-h"):
            _slash_help(["speed"])
            return None
        try:
            val = float(args[0])
            if val < 0:
                raise ValueError
        except ValueError:
            print(colorize("  Speed must be a non-negative number (seconds).", S.RED))
            return None
        settings["auto_speed"] = val
        print(colorize(f"  Auto-play speed set to {val}s.", S.GREEN))
        return None

    # ── /purge ─────────────────────────────────────────────────────────
    if cmd == "purge":
        days = settings.get("purge_days", 30)
        for i, a in enumerate(args):
            if a == "--days" and i + 1 < len(args):
                try:
                    days = int(args[i + 1])
                    if days < 1:
                        raise ValueError
                except ValueError:
                    print(colorize("  --days requires a positive integer.", S.RED))
                    return None
        removed = purge_log(days)
        print(colorize(f"  Purged {removed} log entries older than {days} days.", S.GREEN))
        return None

    # ── /new ───────────────────────────────────────────────────────────
    if cmd == "new":
        if in_game:
            confirm = input(colorize(
                "  Forfeit this game and start a new one? (y/n): ", S.YELLOW
            )).strip().lower()
            if confirm != "y":
                print(colorize("  Continuing current game.", S.DIM))
                return None
        return "new"

    # ── /board ─────────────────────────────────────────────────────────
    if cmd == "board":
        if board is not None:
            print_board(board)
        else:
            print(colorize("  No board to display outside of a game.", S.DIM))
        return None

    # ── /loop ─────────────────────────────────────────────────────────
    if cmd == "loop":
        if not args:
            current = settings.get("loop", None)
            desc = ("∞" if current == 0 else str(current)) if current is not None else "off"
            print(colorize(f"  Auto-repeat is currently: {desc}", S.WHITE))
            return None
        token = args[0].lower()
        if token in ("off", "1", "interactive", "n", "no"):
            settings["loop"] = None
            print(colorize("  Auto-repeat disabled (interactive mode).", S.GREEN))
        elif token in ("0", "∞", "inf", "infinite"):
            settings["loop"] = 0
            print(colorize("  Auto-repeat set to infinite.", S.GREEN))
        else:
            try:
                n = int(token)
                if n < 0:
                    raise ValueError
                settings["loop"] = n if n > 1 else None
                if n > 1:
                    print(colorize(f"  Auto-repeat set to {n} games.", S.GREEN))
                else:
                    print(colorize("  Auto-repeat disabled.", S.GREEN))
            except ValueError:
                print(colorize("  /loop expects a number, 0 for infinite, or 'off'.", S.RED))
        return None

    # ── unknown ────────────────────────────────────────────────────────
    print(colorize(f"\n  Unknown command: /{cmd_raw}  —  type /help for a list.\n", S.RED))
    return None


def prompt(message: str, settings: dict, *,
           in_game: bool = False,
           board: list | None = None) -> str:
    """Replacement for input() that intercepts slash commands.

    Keeps re-prompting until the user enters something that is NOT a slash
    command (or a slash command that produces a non-None sentinel).

    Returns the raw user input string when it is not a slash command.
    Raises KeyboardInterrupt on /quit.
    Returns a sentinel string ("new", "board", "options") when appropriate
    — callers must check for these.
    """
    while True:
        raw = input(message).strip()
        if raw.startswith("/"):
            result = handle_slash_command(
                raw, settings, in_game=in_game, board=board
            )
            if result is not None:
                # sentinel — pass up to caller
                return f"\x00{result}"   # NUL-prefixed: marks a sentinel
            # None → command handled, re-prompt
            continue
        return raw


def is_sentinel(value: str) -> bool:
    """Return True if *value* is a slash-command sentinel (not normal input)."""
    return value.startswith("\x00")


def sentinel_value(value: str) -> str:
    """Strip the NUL prefix from a sentinel string."""
    return value[1:]


# ═══════════════════════════════════════════════════════════════════════════
# Persistent data helpers
# ═══════════════════════════════════════════════════════════════════════════

def _ensure_data_dir() -> None:
    """Create the data directory if it does not exist."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)


def load_stats() -> dict:
    """Return the all-time stats dictionary, or fresh defaults."""
    _ensure_data_dir()
    default = {
        "games_played": 0,
        "wins": 0,
        "losses": 0,
        "draws": 0,
        "by_difficulty": {
            "easy":   {"played": 0, "wins": 0, "losses": 0, "draws": 0},
            "medium": {"played": 0, "wins": 0, "losses": 0, "draws": 0},
            "hard":   {"played": 0, "wins": 0, "losses": 0, "draws": 0},
        },
    }
    if STATS_FILE.exists():
        try:
            with open(STATS_FILE, "r") as f:
                data = json.load(f)
            # Merge missing keys from default so older files still work
            for key in default:
                data.setdefault(key, default[key])
            for diff in ("easy", "medium", "hard"):
                data["by_difficulty"].setdefault(diff, default["by_difficulty"][diff])
            return data
        except (json.JSONDecodeError, KeyError):
            pass
    return default


def save_stats(stats: dict) -> None:
    """Persist the stats dictionary to disk."""
    _ensure_data_dir()
    with open(STATS_FILE, "w") as f:
        json.dump(stats, f, indent=2)


# ── Game-log helpers ────────────────────────────────────────────────────────

def load_log() -> list:
    """Return the list of game-log entries."""
    _ensure_data_dir()
    if LOG_FILE.exists():
        try:
            with open(LOG_FILE, "r") as f:
                return json.load(f)
        except (json.JSONDecodeError, TypeError):
            pass
    return []


def save_log(log: list) -> None:
    """Persist the game log to disk."""
    _ensure_data_dir()
    with open(LOG_FILE, "w") as f:
        json.dump(log, f, indent=2)


def purge_log(max_age_days: int = 30) -> int:
    """Remove log entries older than *max_age_days*.  Returns count removed."""
    log = load_log()
    cutoff = (datetime.now() - timedelta(days=max_age_days)).isoformat()
    original_len = len(log)
    log = [entry for entry in log if entry.get("timestamp", "") >= cutoff]
    save_log(log)
    return original_len - len(log)


def append_log_entry(entry: dict) -> None:
    """Add a single game result to the log and save."""
    log = load_log()
    entry["timestamp"] = datetime.now().isoformat()
    log.append(entry)
    save_log(log)


# ═══════════════════════════════════════════════════════════════════════════
# Board display
# ═══════════════════════════════════════════════════════════════════════════

# Number-pad reference layout shown to player before each move:
#   7 | 8 | 9          These map into board positions (row, col):
#   4 | 5 | 6            7→(0,0)  8→(0,1)  9→(0,2)
#   1 | 2 | 3            4→(1,0)  5→(1,1)  6→(1,2)
#                         1→(2,0)  2→(2,1)  3→(2,2)

NUM_TO_POS = {
    7: (0, 0), 8: (0, 1), 9: (0, 2),
    4: (1, 0), 5: (1, 1), 6: (1, 2),
    1: (2, 0), 2: (2, 1), 3: (2, 2),
}

POS_TO_NUM = {v: k for k, v in NUM_TO_POS.items()}


def _cell(value: str, pos_num: int) -> str:
    """Render one board cell with colour.

    Empty cells show their numpad hint in bold blue — clearly visible on both
    dark and light terminal backgrounds, and distinct from X (cyan) / O (magenta).
    """
    if value == "X":
        return colorize(" X ", S.BOLD, S.CYAN)
    elif value == "O":
        return colorize(" O ", S.BOLD, S.MAGENTA)
    else:
        # Bold bright-blue digit — high contrast on dark backgrounds
        return colorize(f" {pos_num} ", S.BOLD, S.BLUE)


def print_board(board: list[list[str]]) -> None:
    """Print the board using box-drawing characters and coloured markers."""
    print()
    top    = f"  {S.BOLD}{S.WHITE}╔═══╤═══╤═══╗{S.RESET}"
    mid    = f"  {S.BOLD}{S.WHITE}╟───┼───┼───╢{S.RESET}"
    bottom = f"  {S.BOLD}{S.WHITE}╚═══╧═══╧═══╝{S.RESET}"
    vbar   = colorize("║", S.BOLD, S.WHITE)
    sep    = colorize("│", S.BOLD, S.WHITE)

    print(top)
    for i, row in enumerate(board):
        nums = [POS_TO_NUM[(i, j)] for j in range(3)]
        cells = [_cell(row[j], nums[j]) for j in range(3)]
        print(f"  {vbar}{cells[0]}{sep}{cells[1]}{sep}{cells[2]}{vbar}")
        if i < 2:
            print(mid)
    print(bottom)
    print()


# ═══════════════════════════════════════════════════════════════════════════
# Game logic
# ═══════════════════════════════════════════════════════════════════════════

def check_winner(board: list[list[str]], player: str) -> bool:
    """Return True if *player* has three in a row."""
    for i in range(3):
        if all(board[i][j] == player for j in range(3)):   # Row
            return True
        if all(board[j][i] == player for j in range(3)):   # Column
            return True
    if all(board[i][i] == player for i in range(3)):        # Main diagonal
        return True
    if all(board[i][2 - i] == player for i in range(3)):    # Anti-diagonal
        return True
    return False


def is_full(board: list[list[str]]) -> bool:
    """Return True when no empty cells remain."""
    return all(board[r][c] != " " for r in range(3) for c in range(3))


def empty_cells(board: list[list[str]]) -> list[tuple[int, int]]:
    """Return a list of (row, col) tuples for every open cell."""
    return [(r, c) for r in range(3) for c in range(3) if board[r][c] == " "]


# ═══════════════════════════════════════════════════════════════════════════
# AI — three difficulty levels
# ═══════════════════════════════════════════════════════════════════════════

def minimax(board: list[list[str]], is_maximizing: bool,
            computer: str, human: str) -> int:
    """Classic minimax on a 3×3 board (no pruning needed at this size).
    Returns +1 if the computer can force a win, -1 if the human can, 0 for
    a draw."""
    if check_winner(board, computer):
        return 1
    if check_winner(board, human):
        return -1
    if is_full(board):
        return 0

    cells = empty_cells(board)
    if is_maximizing:
        best = -2
        for r, c in cells:
            board[r][c] = computer
            best = max(best, minimax(board, False, computer, human))
            board[r][c] = " "
        return best
    else:
        best = 2
        for r, c in cells:
            board[r][c] = human
            best = min(best, minimax(board, True, computer, human))
            board[r][c] = " "
        return best


def best_move(board: list[list[str]], computer: str, human: str) -> tuple[int, int]:
    """Return the optimal (row, col) for the computer via minimax."""
    cells = empty_cells(board)
    best_score, best_cell = -2, cells[0]
    for r, c in cells:
        board[r][c] = computer
        score = minimax(board, False, computer, human)
        board[r][c] = " "
        if score > best_score:
            best_score, best_cell = score, (r, c)
    return best_cell


def ai_move(board: list[list[str]], computer: str, human: str,
            difficulty: str) -> tuple[int, int]:
    """Pick an AI move according to the chosen difficulty.

    Easy   — purely random.
    Medium — 50 % chance of optimal move, otherwise random.
    Hard   — always optimal (minimax).
    """
    cells = empty_cells(board)
    if difficulty == "easy":
        return random.choice(cells)
    elif difficulty == "medium":
        if random.random() < 0.5:
            return best_move(board, computer, human)
        return random.choice(cells)
    else:  # hard
        return best_move(board, computer, human)


# ═══════════════════════════════════════════════════════════════════════════
# Human move input — numpad style
# ═══════════════════════════════════════════════════════════════════════════

def get_human_move(board: list[list[str]], player: str,
                   settings: dict) -> tuple[int, int]:
    """Prompt the player to enter a number 1-9 (numpad layout).

    Slash commands entered here are handled immediately.  Returns:
      (row, col)  on a valid move
      (-1, -1)    sentinel — caller should open the options menu
      (-2, -2)    sentinel — caller should start a new game
      (-3, -3)    sentinel — caller should reprint the board
    """
    display_names = settings.get("_display_names", {})
    player_name   = display_names.get(player, "")
    mark_hint     = colorize(player, S.BOLD, S.CYAN if player == "X" else S.MAGENTA)
    name_part     = f"{S.BOLD}{player_name}{S.RESET} " if player_name else f"{S.BOLD}Your move{S.RESET} "
    msg = (
        f"  {name_part}({mark_hint}) "
        f"[{colorize('1-9', S.WHITE)} / {colorize('/cmd', S.YELLOW)}]: "
    )
    while True:
        try:
            raw = prompt(msg, settings, in_game=True, board=board)

            if is_sentinel(raw):
                sv = sentinel_value(raw)
                if sv == "quit":
                    raise KeyboardInterrupt
                if sv == "options":
                    return (-1, -1)
                if sv == "new":
                    return (-2, -2)
                if sv == "board":
                    return (-3, -3)
                continue   # other sentinels handled in-place

            raw = raw.lower()
            if raw in ("q", "quit"):
                raise KeyboardInterrupt
            if raw in ("o", "options"):
                return (-1, -1)

            num = int(raw)
            if num < 1 or num > 9:
                print(colorize("    Enter a number from 1 to 9.", S.RED))
                continue
            row, col = NUM_TO_POS[num]
            if board[row][col] != " ":
                print(colorize("    That cell is taken. Pick another.", S.RED))
                continue
            return (row, col)

        except ValueError:
            print(colorize("    Invalid input. Type a number 1-9, or /help for commands.", S.RED))


# ═══════════════════════════════════════════════════════════════════════════
# Statistics display
# ═══════════════════════════════════════════════════════════════════════════

def show_stats() -> None:
    """Print a nicely formatted statistics summary."""
    stats = load_stats()
    divider = colorize("─" * 48, S.DIM)

    print(f"\n  {S.BOLD}{S.CYAN}╔══════════════════════════════════════════════╗{S.RESET}")
    print(f"  {S.BOLD}{S.CYAN}║          ALL-TIME  STATISTICS                ║{S.RESET}")
    print(f"  {S.BOLD}{S.CYAN}╚══════════════════════════════════════════════╝{S.RESET}")
    print()
    print(f"  {S.BOLD}Overall{S.RESET}")
    print(f"  {divider}")
    gp = stats["games_played"]
    print(f"    Games Played  : {colorize(str(gp), S.BOLD, S.WHITE)}")
    print(f"    Wins          : {colorize(str(stats['wins']), S.BOLD, S.GREEN)}")
    print(f"    Losses        : {colorize(str(stats['losses']), S.BOLD, S.RED)}")
    print(f"    Draws         : {colorize(str(stats['draws']), S.BOLD, S.YELLOW)}")
    win_pct = (stats["wins"] / gp * 100) if gp else 0
    print(f"    Win Rate      : {colorize(f'{win_pct:.1f}%', S.BOLD)}")
    print()

    print(f"  {S.BOLD}By Difficulty{S.RESET}")
    print(f"  {divider}")
    for diff in ("easy", "medium", "hard"):
        d = stats["by_difficulty"][diff]
        label = colorize(f"  {diff.capitalize():8s}", S.BOLD)
        dp = d["played"]
        wpct = f"{d['wins']/dp*100:.0f}%" if dp else " – "
        print(f"  {label}   Played: {dp:>3}   W: {d['wins']:>3}   "
              f"L: {d['losses']:>3}   D: {d['draws']:>3}   Win%: {wpct}")
    print()


def show_log(last_n: int = 20) -> None:
    """Show the most recent *last_n* log entries, handling all player modes."""
    log = load_log()
    if not log:
        print(colorize("\n  No game log entries yet.\n", S.DIM))
        return

    entries = log[-last_n:]
    print(f"\n  {S.BOLD}{S.CYAN}╔══════════════════════════════════════════════╗{S.RESET}")
    print(f"  {S.BOLD}{S.CYAN}║            RECENT GAME LOG                   ║{S.RESET}")
    print(f"  {S.BOLD}{S.CYAN}╚══════════════════════════════════════════════╝{S.RESET}\n")
    for e in entries:
        ts = e.get("timestamp", "?")[:19].replace("T", " ")
        result   = e.get("result", "?")
        mode     = e.get("mode", "1p")       # "0p", "1p", "2p"
        diff_x   = e.get("diff_x", "")       # difficulty for X
        diff_o   = e.get("diff_o", "")       # difficulty for O
        winner   = e.get("winner", "")       # "X", "O", or "draw"

        if result == "win":
            tag = colorize(" WIN  ", S.BOLD, S.GREEN)
        elif result == "loss":
            tag = colorize(" LOSS ", S.BOLD, S.RED)
        elif result == "draw":
            tag = colorize(" DRAW ", S.BOLD, S.YELLOW)
        else:
            tag = colorize(f" {result.upper():5s}", S.BOLD, S.WHITE)

        if mode == "0p":
            nx = e.get("name_x", "") or f"AI({diff_x.capitalize()})"
            no = e.get("name_o", "") or f"AI({diff_o.capitalize()})"
            info = f"{nx} vs {no}  Winner: {winner or 'draw'}"
        elif mode == "2p":
            nx = e.get("name_x", "") or "Player X"
            no = e.get("name_o", "") or "Player O"
            info = f"{nx} vs {no}  Winner: {winner or 'draw'}"
        else:
            # 1p — show player and computer names when available
            diff  = e.get("difficulty", diff_x or "?").capitalize()
            mark  = e.get("player_mark", "?")
            pname = e.get("name_x" if mark == "X" else "name_o", "") or "Player"
            cname = e.get("name_o" if mark == "X" else "name_x", "") or "Computer"
            info  = f"{pname} vs {cname}  Diff: {diff:6s}"

        print(f"    {S.DIM}{ts}{S.RESET}  {tag}  {info}")
    print()


# ═══════════════════════════════════════════════════════════════════════════
# Menus
# ═══════════════════════════════════════════════════════════════════════════

BANNER = r"""
   ╔════════════════════════════════════════════╗
   ║                                            ║
   ║      ████████╗██╗ ██████╗                  ║
   ║      ╚══██╔══╝██║██╔════╝                  ║
   ║         ██║   ██║██║                        ║
   ║         ██║   ██║██║                        ║
   ║         ██║   ██║╚██████╗                   ║
   ║         ╚═╝   ╚═╝ ╚═════╝                  ║
   ║      ████████╗ █████╗  ██████╗             ║
   ║      ╚══██╔══╝██╔══██╗██╔════╝             ║
   ║         ██║   ███████║██║                   ║
   ║         ██║   ██╔══██║██║                   ║
   ║         ██║   ██║  ██║╚██████╗              ║
   ║         ╚═╝   ╚═╝  ╚═╝ ╚═════╝             ║
   ║      ████████╗ ██████╗ ███████╗             ║
   ║      ╚══██╔══╝██╔═══██╗██╔════╝            ║
   ║         ██║   ██║   ██║█████╗               ║
   ║         ██║   ██║   ██║██╔══╝               ║
   ║         ██║   ╚██████╔╝███████╗             ║
   ║         ╚═╝    ╚═════╝ ╚══════╝             ║
   ║                                            ║
   ╚════════════════════════════════════════════╝"""


def print_banner() -> None:
    """Print the title art in colour."""
    print(colorize(BANNER, S.BOLD, S.CYAN))
    print()


def choose_difficulty(label: str = "Select Difficulty",
                      default: str = "medium",
                      settings: dict | None = None) -> str:
    """Interactive difficulty picker.  Returns 'easy', 'medium', or 'hard'."""
    _settings = settings or {"difficulty": default, "purge_days": 30,
                              "num_players": 1, "auto_speed": 0.8}
    print(f"  {S.BOLD}{label}:{S.RESET}")
    print(f"    {colorize('1', S.GREEN)}  Easy   — AI picks randomly")
    print(f"    {colorize('2', S.YELLOW)}  Medium — AI is sometimes optimal")
    print(f"    {colorize('3', S.RED)}  Hard   — AI plays perfectly (minimax)")
    print()
    while True:
        raw = prompt(f"  Choice [{default[0].upper()}]: ", _settings).strip().lower()
        if is_sentinel(raw):
            sv = sentinel_value(raw)
            if sv == "quit":
                raise KeyboardInterrupt
            continue   # other commands already handled
        if raw in ("1", "e", "easy"):
            return "easy"
        if raw in ("2", "m", "medium", ""):
            return "medium"
        if raw in ("3", "h", "hard"):
            return "hard"
        print(colorize("    Please enter 1, 2, or 3.", S.RED))


def choose_num_players(settings: dict) -> int:
    """Interactively ask how many human players (0, 1, or 2)."""
    print(f"  {S.BOLD}Number of Players:{S.RESET}")
    print(f"    {colorize('0', S.MAGENTA)}  Zero  — AI vs AI (spectator / simulation)")
    print(f"    {colorize('1', S.CYAN)}  One   — Human vs AI")
    print(f"    {colorize('2', S.GREEN)}  Two   — Human vs Human")
    print()
    while True:
        raw = prompt("  Choice [1]: ", settings).strip()
        if is_sentinel(raw):
            sv = sentinel_value(raw)
            if sv == "quit":
                raise KeyboardInterrupt
            continue
        if raw in ("", "1"):
            return 1
        if raw == "0":
            return 0
        if raw == "2":
            return 2
        print(colorize("    Please enter 0, 1, or 2.", S.RED))


def choose_loop(settings: dict) -> None:
    """Interactively ask whether to auto-repeat and how many times.

    Updates settings['loop'] and settings['loop_pause'] in-place.
    """
    print(f"  {S.BOLD}Auto-repeat games?{S.RESET}")
    print(f"    {colorize('n', S.WHITE)}  No  — ask after each game (default)")
    print(f"    {colorize('0', S.MAGENTA)}  Yes — infinite loop (Ctrl-C or /quit to stop)")
    print(f"    {colorize('N', S.CYAN)}  Yes — play N games then stop")
    print()
    while True:
        raw = prompt("  Choice [n]: ", settings).strip().lower()
        if is_sentinel(raw):
            if sentinel_value(raw) == "quit":
                raise KeyboardInterrupt
            continue
        if raw in ("", "n", "no", "off"):
            settings["loop"] = None
            return
        if raw in ("0", "\u221e", "inf", "infinite", "y", "yes"):
            settings["loop"] = 0
            _ask_loop_pause(settings)
            return
        try:
            n = int(raw)
            if n < 1:
                raise ValueError
            settings["loop"] = n if n > 1 else None
            if n > 1:
                _ask_loop_pause(settings)
            return
        except ValueError:
            print(colorize("    Enter 'n', '0' for infinite, or a number of games.", S.RED))


def _ask_loop_pause(settings: dict) -> None:
    """Ask how long to pause between games in auto-loop mode."""
    default = settings.get("loop_pause", 1.5)
    while True:
        raw = prompt(
            f"  Pause between games (seconds) [{default}]: ",
            settings,
        ).strip()
        if is_sentinel(raw):
            if sentinel_value(raw) == "quit":
                raise KeyboardInterrupt
            continue
        if raw == "":
            settings["loop_pause"] = default
            return
        try:
            val = float(raw)
            if val < 0:
                raise ValueError
            settings["loop_pause"] = val
            return
        except ValueError:
            print(colorize("    Enter a non-negative number of seconds.", S.RED))


def choose_auto_speed(default: float = 0.8, settings: dict | None = None) -> float:
    """Ask the user how fast to step through an AI-vs-AI game (seconds/move)."""
    _settings = settings or {"difficulty": "medium", "purge_days": 30,
                              "num_players": 0, "auto_speed": default}
    print(f"  {S.BOLD}Auto-play speed (seconds between moves):{S.RESET}")
    print(f"    Press Enter for default ({default}s).")
    print(f"    Enter {colorize('0', S.YELLOW)} for instant (no pause).")
    print()
    while True:
        raw = prompt(f"  Seconds [{default}]: ", _settings).strip()
        if is_sentinel(raw):
            sv = sentinel_value(raw)
            if sv == "quit":
                raise KeyboardInterrupt
            continue
        if raw == "":
            return default
        try:
            val = float(raw)
            if val < 0:
                raise ValueError
            return val
        except ValueError:
            print(colorize("    Enter a non-negative number.", S.RED))


def options_menu(settings: dict) -> dict:
    """In-game / main options menu.  Mutates and returns *settings*.

    The 'difficulty' key is only relevant in 1-player mode; in 0-player mode
    the per-AI difficulties are configured during game setup each round.
    """
    while True:
        num_players = settings.get("num_players", 1)
        loop_val    = settings.get("loop", None)
        loop_desc   = ("∞" if loop_val == 0 else str(loop_val)) if loop_val is not None else "off"
        loop_pause  = settings.get("loop_pause", 1.5)
        print(f"\n  {S.BOLD}{S.CYAN}── Options ──{S.RESET}")
        if num_players == 1:
            print(f"    {colorize('1', S.WHITE)}  Change AI difficulty (current: {settings['difficulty'].capitalize()})")
        else:
            print(f"    {colorize('1', S.WHITE)}  (difficulty set per-game for this mode)")
        print(f"    {colorize('2', S.WHITE)}  Set log purge days  (current: {settings['purge_days']})")
        print(f"    {colorize('3', S.WHITE)}  Purge old log entries now")
        print(f"    {colorize('4', S.WHITE)}  View statistics")
        print(f"    {colorize('5', S.WHITE)}  View recent game log")
        print(f"    {colorize('6', S.WHITE)}  Reset all statistics")
        print(f"    {colorize('7', S.WHITE)}  Auto-repeat (loop)   (current: {loop_desc}, pause: {loop_pause}s)")
        print(f"    {colorize('r', S.YELLOW)}  Return to game")
        print()
        raw = prompt("  Option: ", settings)
        if is_sentinel(raw):
            sv = sentinel_value(raw)
            if sv == "quit":
                raise KeyboardInterrupt
            if sv == "options":   # /options inside options — just refresh
                continue
            continue
        choice = raw.lower()

        if choice == "1" and num_players == 1:
            settings["difficulty"] = choose_difficulty(
                default=settings["difficulty"], settings=settings
            )
        elif choice == "2":
            try:
                raw2 = prompt("  Purge entries older than how many days? [30]: ", settings).strip()
                if is_sentinel(raw2):
                    continue
                days = int(raw2 or "30")
                if days < 1:
                    raise ValueError
                settings["purge_days"] = days
                print(colorize(f"    Log purge age set to {days} days.", S.GREEN))
            except ValueError:
                print(colorize("    Invalid number; keeping previous value.", S.RED))
        elif choice == "3":
            removed = purge_log(settings["purge_days"])
            print(colorize(f"    Purged {removed} old log entries.", S.GREEN))
        elif choice == "4":
            show_stats()
        elif choice == "5":
            show_log()
        elif choice == "6":
            raw2 = prompt(colorize("    Really reset all stats? (y/n): ", S.RED), settings).strip().lower()
            if is_sentinel(raw2):
                continue
            if raw2 == "y":
                save_stats({
                    "games_played": 0, "wins": 0, "losses": 0, "draws": 0,
                    "by_difficulty": {
                        "easy":   {"played": 0, "wins": 0, "losses": 0, "draws": 0},
                        "medium": {"played": 0, "wins": 0, "losses": 0, "draws": 0},
                        "hard":   {"played": 0, "wins": 0, "losses": 0, "draws": 0},
                    },
                })
                print(colorize("    Statistics reset.", S.GREEN))
        elif choice == "7":
            choose_loop(settings)
        elif choice in ("r", ""):
            break
        else:
            print(colorize("    Unknown option. Type /help for slash commands.", S.RED))

    return settings


def main_menu(settings: dict) -> str:
    """Show the main menu and return the user's choice."""
    # settings is needed so prompt() can handle slash commands here too
    print(f"  {S.BOLD}Main Menu{S.RESET}")
    print(f"    {colorize('1', S.GREEN)}  New Game")
    print(f"    {colorize('2', S.YELLOW)}  Options")
    print(f"    {colorize('3', S.CYAN)}  Statistics")
    print(f"    {colorize('4', S.CYAN)}  Game Log")
    print(f"    {colorize('q', S.RED)}  Quit")
    print()
    hint = colorize(" (or /help)", S.DIM)
    while True:
        raw = prompt(f"  Choice{hint}: ", settings)
        if is_sentinel(raw):
            sv = sentinel_value(raw)
            if sv == "quit":
                raise KeyboardInterrupt
            if sv == "new":
                return "1"   # treat /new at main menu as "New Game"
            if sv == "options":
                return "2"
            # other sentinels handled in-place, re-prompt
            continue
        return raw.lower()


# ═══════════════════════════════════════════════════════════════════════════
# Game loop helpers — per-player label formatting
# ═══════════════════════════════════════════════════════════════════════════

def _mark_label(mark: str) -> str:
    """Return a colourised mark string (X → cyan, O → magenta)."""
    return colorize(mark, S.BOLD, S.CYAN if mark == "X" else S.MAGENTA)


def choose_player_names(settings: dict) -> None:
    """Ask for a display name for every seat and store in settings['names'].

    Skips silently when stdin is not a TTY (piped / scripted runs).
    Once names are stored they are NOT re-asked inside auto-loop iterations.
    """
    if not sys.stdin.isatty():
        return
    num_players = settings.get("num_players", 1)
    # Do not re-prompt if names are already configured for this session
    if settings.get("names"):
        return
    # In 0-player mode with a pre-set difficulty the run is fully scripted;
    # assign default AI names silently so the session table is still populated.
    if num_players == 0 and settings.get("difficulty") in ("easy", "medium", "hard"):
        settings["names"] = {"X": "AI-X", "O": "AI-O"}
        return

    print(f"\n  {S.BOLD}── Player Names ──{S.RESET}")
    print(colorize("  (Press Enter to keep the default)", S.DIM))
    names: dict[str, str] = {}

    def _ask_name(label: str, default: str) -> str | None:
        """Prompt for one name; return chosen value or None to abort."""
        try:
            raw = prompt(f"  {label} [{default}]: ", settings).strip()
        except (EOFError, KeyboardInterrupt):
            return None
        if is_sentinel(raw):
            sv = sentinel_value(raw)
            if sv == "quit":
                raise KeyboardInterrupt
            return None   # any other slash command → skip rest of names
        return raw or default

    if num_players == 1:
        v = _ask_name("Your name", "Player")
        if v is None:
            return
        names["human"] = v
        v = _ask_name("Computer name", "Computer")
        if v is None:
            settings["names"] = names
            return
        names["computer"] = v

    elif num_players == 2:
        for mark in ("X", "O"):
            mc = colorize(mark, S.BOLD, S.CYAN if mark == "X" else S.MAGENTA)
            v = _ask_name(f"Name for {mc}", f"Player {mark}")
            if v is None:
                settings["names"] = names
                return
            names[mark] = v

    else:  # 0-player — AI names
        for mark in ("X", "O"):
            mc = colorize(mark, S.BOLD, S.CYAN if mark == "X" else S.MAGENTA)
            v = _ask_name(f"Name for AI {mc}", f"AI-{mark}")
            if v is None:
                settings["names"] = names
                return
            names[mark] = v

    settings["names"] = names


def _resolve_display_names(settings: dict, seats: dict) -> dict[str, str]:
    """Return a mark→display-name mapping for one game.

    Uses settings['names'] when available; falls back gracefully to
    role-based defaults.  Stores the result in settings['_display_names']
    so get_human_move can read it without an extra parameter.
    """
    src         = settings.get("names", {})
    num_players = settings.get("num_players", 1)
    display: dict[str, str] = {}

    for mark in ("X", "O"):
        seat = seats.get(mark, "human")
        if num_players == 1:
            if seat == "human":
                display[mark] = src.get("human", "Player")
            else:
                display[mark] = src.get("computer", "Computer")
        elif num_players == 2:
            display[mark] = src.get(mark, f"Player {mark}")
        else:  # 0-player
            display[mark] = src.get(mark, f"AI-{mark}")

    settings["_display_names"] = display
    return display


# ═══════════════════════════════════════════════════════════════════════════
# Main game loop — supports 0 / 1 / 2 human players
# ═══════════════════════════════════════════════════════════════════════════

def play_game(settings: dict) -> dict:
    """Run a single game.

    Reads settings['num_players'] (0, 1, or 2) to determine game mode:

      0 — Two AI players.  Each AI's difficulty is chosen before the game.
          Moves happen automatically with a configurable delay (auto_speed).
      1 — One human vs one AI.  Human difficulty picked from settings.
          Supports in-game Options menu via 'o' at the move prompt.
      2 — Two humans playing locally, taking turns at the same terminal.

    Returns the updated settings dict (difficulty or purge_days may have
    changed via the in-game options menu).
    """
    num_players = settings.get("num_players", 1)
    board       = [[" "] * 3 for _ in range(3)]

    # X always moves first; assignment of marks to seats is random.
    marks = ["X", "O"]
    random.shuffle(marks)       # randomise which seat gets X

    # ── Configure seats ────────────────────────────────────────────────
    # seats[mark] is "human" or an AI difficulty string ("easy"/"medium"/"hard")
    seats: dict[str, str] = {}

    if num_players == 0:
        # Both seats are AI.
        # If a specific difficulty was pre-set (e.g. via --difficulty on the
        # CLI or locked via the options menu) use it for both seats without
        # prompting — this allows fully unattended auto-loop runs.
        preset = settings.get("difficulty")
        if preset and preset in ("easy", "medium", "hard"):
            seats["X"] = preset
            seats["O"] = preset
        else:
            # Ask for each AI's difficulty independently
            print(f"\n  {S.BOLD}{S.CYAN}── AI vs AI Setup ──{S.RESET}")
            for mark in ("X", "O"):
                seats[mark] = choose_difficulty(
                    label=f"Difficulty for AI playing {_mark_label(mark)}",
                    default=settings.get("difficulty", "medium"),
                    settings=settings,
                )
        auto_speed    = settings.get("auto_speed", 0.8)
        display_names = _resolve_display_names(settings, seats)

        nx = colorize(display_names["X"], S.BOLD, S.CYAN)
        no = colorize(display_names["O"], S.BOLD, S.MAGENTA)
        print(f"\n  {nx} [{seats['X'].capitalize()}]  vs  "
              f"{no} [{seats['O'].capitalize()}]")
        print(f"  {S.DIM}Auto-play delay: {auto_speed}s per move{S.RESET}")
        if auto_speed > 0:
            print(colorize("  Press Ctrl-C at any time to stop.", S.DIM))

    elif num_players == 1:
        # One human, one AI
        human_mark    = marks[0]
        computer_mark = marks[1]
        seats[human_mark]    = "human"
        seats[computer_mark] = settings.get("difficulty", "medium")

        hc            = S.CYAN if human_mark == "X" else S.MAGENTA
        display_names = _resolve_display_names(settings, seats)
        print(f"\n  {S.BOLD}Difficulty:{S.RESET}  {colorize(seats[computer_mark].capitalize(), S.YELLOW)}")
        print(f"  {S.BOLD}You are:{S.RESET}     "
              f"{colorize(display_names[human_mark], S.BOLD, hc)} "
              f"[{colorize(human_mark, S.BOLD, hc)}]   "
              f"{'(you go first)' if human_mark == 'X' else '(computer goes first)'}")
        print(f"  {S.BOLD}Computer:{S.RESET}    "
              f"{colorize(display_names[computer_mark], S.DIM)}")
        print(f"\n  {S.DIM}Board positions (numpad layout):{S.RESET}")
        print(f"  {S.DIM}  7 │ 8 │ 9{S.RESET}")
        print(f"  {S.DIM}  ──┼───┼──{S.RESET}")
        print(f"  {S.DIM}  4 │ 5 │ 6{S.RESET}")
        print(f"  {S.DIM}  ──┼───┼──{S.RESET}")
        print(f"  {S.DIM}  1 │ 2 │ 3{S.RESET}")

    else:  # num_players == 2
        # Both seats are human
        seats["X"] = "human"
        seats["O"] = "human"
        display_names = _resolve_display_names(settings, seats)
        print(f"\n  {S.BOLD}Human vs Human{S.RESET}")
        nx = colorize(display_names["X"], S.BOLD, S.CYAN)
        print(f"  {nx} [{colorize('X', S.BOLD, S.CYAN)}] goes first.  Players share this terminal.")
        print(f"\n  {S.DIM}Board positions (numpad layout):{S.RESET}")
        print(f"  {S.DIM}  7 │ 8 │ 9{S.RESET}")
        print(f"  {S.DIM}  ──┼───┼──{S.RESET}")
        print(f"  {S.DIM}  4 │ 5 │ 6{S.RESET}")
        print(f"  {S.DIM}  ──┼───┼──{S.RESET}")
        print(f"  {S.DIM}  1 │ 2 │ 3{S.RESET}")

    current    = "X"          # X always moves first
    moves_made = 0
    start_time = time.time()
    opponent   = "O" if current == "X" else "X"   # used for AI minimax framing

    while True:
        print_board(board)
        seat_type = seats[current]

        if seat_type == "human":
            # ── Human move ────────────────────────────────────────────
            row, col = get_human_move(board, current, settings)
            if (row, col) == (-1, -1):       # /options or 'o'
                settings = options_menu(settings)
                if num_players == 1:
                    seats[computer_mark] = settings["difficulty"]
                continue
            if (row, col) == (-2, -2):       # /new
                return "new", settings
            if (row, col) == (-3, -3):       # /board
                continue                    # board was already reprinted inside get_human_move

        else:
            # ── AI move ───────────────────────────────────────────────
            # In AI-vs-AI mode the "opponent" for minimax is the other AI mark.
            other_mark = "O" if current == "X" else "X"
            difficulty = seat_type          # seat stores difficulty string

            dnames = settings.get("_display_names", {})
            if num_players == 0:
                if auto_speed > 0:
                    time.sleep(auto_speed)
                label = (f"  {dnames.get(current, 'AI')} ({_mark_label(current)}) "
                         f"[{difficulty.capitalize()}] is thinking …")
            else:
                label = colorize(
                    f"  {dnames.get(current, 'Computer')} ({current}) is thinking …",
                    S.DIM,
                )
                time.sleep(0.4)

            print(colorize(label, S.DIM))
            row, col = ai_move(board, current, other_mark, difficulty)
            num = POS_TO_NUM[(row, col)]
            print(f"  {_mark_label(current)} plays {colorize(str(num), S.BOLD, S.WHITE)}")

        board[row][col] = current
        moves_made += 1

        # ── Check for game end ────────────────────────────────────────
        if check_winner(board, current):
            print_board(board)
            elapsed = time.time() - start_time
            winner_mark = current

            dnames = settings.get("_display_names", {})
            if num_players == 0:
                # Both sides are AI; no "win/loss" from player perspective
                diff_winner  = seats[winner_mark]
                diff_loser   = seats["O" if winner_mark == "X" else "X"]
                name_winner  = dnames.get(winner_mark, f"AI-{winner_mark}")
                name_loser   = dnames.get("O" if winner_mark == "X" else "X", "AI")
                print(colorize(
                    f"  🏆  {name_winner} ({winner_mark}) wins!  "
                    f"[{diff_winner.capitalize()} beat {diff_loser.capitalize()}]",
                    S.BOLD, S.GREEN,
                ))
                result = "ai_win"          # neutral result code for stats

            elif num_players == 1:
                human_mark = next(m for m, s in seats.items() if s == "human")
                if winner_mark == human_mark:
                    name = dnames.get(human_mark, "Player")
                    print(colorize(f"  🎉  {name} wins!  Congratulations!", S.BOLD, S.GREEN))
                    result = "win"
                else:
                    name = dnames.get("O" if human_mark == "X" else "X", "Computer")
                    print(colorize(f"  💻  {name} wins!  Better luck next time.", S.BOLD, S.RED))
                    result = "loss"

            else:  # 2 players
                name = dnames.get(winner_mark, f"Player {winner_mark}")
                print(colorize(f"  🏆  {name} ({winner_mark}) wins!", S.BOLD, S.GREEN))
                result = f"p{winner_mark}_wins"  # "pX_wins" or "pO_wins"

            break

        if is_full(board):
            print_board(board)
            elapsed = time.time() - start_time
            print(colorize("  🤝  It's a draw!", S.BOLD, S.YELLOW))
            result = "draw"
            break

        current = "O" if current == "X" else "X"

    # ── Record stats (only for 1-player mode; others logged but not tallied) ──
    stats = load_stats()
    stats["games_played"] += 1

    if num_players == 1:
        diff_key = seats.get(next(m for m, s in seats.items() if s != "human"), "medium")
        stats["by_difficulty"][diff_key]["played"] += 1
        if result == "win":
            stats["wins"] += 1
            stats["by_difficulty"][diff_key]["wins"] += 1
        elif result == "loss":
            stats["losses"] += 1
            stats["by_difficulty"][diff_key]["losses"] += 1
        else:
            stats["draws"] += 1
            stats["by_difficulty"][diff_key]["draws"] += 1
    else:
        # For 0p / 2p, count the game but don't skew 1p win/loss stats
        if result == "draw":
            stats["draws"] += 1

    save_stats(stats)

    # ── Save metadata for the session game list ──────────────────────
    winner_mark_final = current if result not in ("draw",) else None
    settings["_last_game"] = {
        "result":        result,
        "winner_mark":   winner_mark_final,
        "moves":         moves_made,
        "duration":      elapsed,
        "seats":         dict(seats),
        "num_players":   num_players,
        "display_names": dict(settings.get("_display_names", {})),
    }

    # ── Build log entry ───────────────────────────────────────────────
    dnames    = settings.get("_display_names", {})
    log_entry: dict = {
        "result":     result,
        "mode":       f"{num_players}p",
        "moves":      moves_made,
        "duration_s": round(elapsed, 1),
        "name_x":     dnames.get("X", ""),
        "name_o":     dnames.get("O", ""),
    }
    if num_players == 0:
        log_entry["diff_x"]  = seats["X"]
        log_entry["diff_o"]  = seats["O"]
        log_entry["winner"]  = current if result == "ai_win" else "draw"
    elif num_players == 1:
        human_mark = next(m for m, s in seats.items() if s == "human")
        log_entry["difficulty"]   = seats["O" if human_mark == "X" else "X"]
        log_entry["player_mark"]  = human_mark
    else:
        log_entry["winner"] = current if result != "draw" else "draw"

    append_log_entry(log_entry)
    purge_log(settings["purge_days"])

    print(f"  {S.DIM}({moves_made} moves in {elapsed:.1f}s){S.RESET}\n")
    return settings
# ═══════════════════════════════════════════════════════════════════════════

def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Tic Tac Toe — 0 / 1 / 2 player console game with AI.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  %(prog)s                          Launch interactive menu\n"
            "  %(prog)s --players 1 -d hard      Human vs Hard AI\n"
            "  %(prog)s --players 0              AI vs AI spectator mode\n"
            "  %(prog)s --players 2              Two humans\n"
            "  %(prog)s --stats                  Show all-time statistics\n"
            "  %(prog)s --log                    Show recent game log\n"
            "  %(prog)s --purge --purge-days 7   Purge log entries > 7 days\n"
        ),
    )
    parser.add_argument("-p", "--players",
                        type=int, choices=[0, 1, 2],
                        default=None,
                        help="Number of human players: 0 (AI vs AI), 1 (Human vs AI), 2 (Human vs Human)")
    parser.add_argument("-d", "--difficulty",
                        choices=["easy", "medium", "hard"],
                        default=None,
                        help="AI difficulty for 1-player mode (default: ask interactively)")
    parser.add_argument("--auto-speed",
                        type=float, default=0.8,
                        metavar="SECONDS",
                        help="Pause between moves in AI-vs-AI mode (default: 0.8; 0 = instant)")
    parser.add_argument("--loop",
                        type=int, default=None,
                        metavar="N",
                        help="Auto-repeat games: 0 = infinite, N = play N games (default: ask)")
    parser.add_argument("--loop-pause",
                        type=float, default=1.5,
                        metavar="SECONDS",
                        help="Pause between auto-repeat games in seconds (default: 1.5)")
    parser.add_argument("--no-color", action="store_true",
                        help="Disable coloured output")
    parser.add_argument("--stats", action="store_true",
                        help="Show statistics and exit")
    parser.add_argument("--log", action="store_true",
                        help="Show game log and exit")
    parser.add_argument("--purge", action="store_true",
                        help="Purge old log entries and exit")
    parser.add_argument("--purge-days", type=int, default=30,
                        help="Max age (days) for log entries (default: 30)")
    parser.add_argument("--reset-stats", action="store_true",
                        help="Reset all-time statistics and exit")
    return parser.parse_args()


# ═══════════════════════════════════════════════════════════════════════════
# Entry point
# ═══════════════════════════════════════════════════════════════════════════

def _fresh_stats() -> dict:
    """Return an empty stats dict with the canonical schema."""
    return {
        "games_played": 0, "wins": 0, "losses": 0, "draws": 0,
        "by_difficulty": {
            "easy":   {"played": 0, "wins": 0, "losses": 0, "draws": 0},
            "medium": {"played": 0, "wins": 0, "losses": 0, "draws": 0},
            "hard":   {"played": 0, "wins": 0, "losses": 0, "draws": 0},
        },
    }


def _build_session_entry(game_num: int, settings: dict) -> dict:
    """Summarise the last game into a compact dict for the session table."""
    lg            = settings.get("_last_game", {})
    result        = lg.get("result", "draw")
    dnames        = lg.get("display_names", {})
    seats_snap    = lg.get("seats", {})
    num_players   = lg.get("num_players", 1)
    winner_mark   = lg.get("winner_mark")       # None for draws

    if result == "draw":
        label = "\U0001f91d Draw"
    elif result == "win":
        human_mark = next((m for m, s in seats_snap.items() if s == "human"), "X")
        name = dnames.get(human_mark, "Player")
        label = f"\U0001f389 {name} ({human_mark}) wins"
    elif result == "loss":
        comp_mark = next((m for m, s in seats_snap.items() if s != "human"), "O")
        name = dnames.get(comp_mark, "Computer")
        label = f"\U0001f4bb {name} ({comp_mark}) wins"
    elif result == "ai_win" and winner_mark:
        name = dnames.get(winner_mark, f"AI-{winner_mark}")
        label = f"\U0001f3c6 {name} ({winner_mark}) wins"
    elif winner_mark:          # pX_wins / pO_wins
        name = dnames.get(winner_mark, f"Player {winner_mark}")
        label = f"\U0001f3c6 {name} ({winner_mark}) wins"
    else:
        label = "\U0001f91d Draw"

    return {
        "num":      game_num,
        "label":    label,
        "moves":    lg.get("moves", 0),
        "duration": lg.get("duration", 0.0),
    }


def _wait_or_stop(pause: float) -> bool:
    """Wait up to *pause* seconds; return True if the user pressed a stop key.

    In TTY mode a single raw keypress is read via the OS file descriptor
    (bypassing Python's buffered stdin so setcbreak works reliably):
      Space, Q/q, Enter → returns True  (stop looping)
      Any other key     → returns False (skip remaining pause, continue)
      Timeout           → returns False (keep looping automatically)

    Falls back to plain time.sleep() when stdin is not a TTY.
    Always waits at least 0.5 s so there is a key-press window even when
    loop_pause is 0.
    """
    import os as _os
    import select as _select
    import termios as _termios
    import tty as _tty

    if not sys.stdin.isatty():
        if pause > 0:
            try:
                time.sleep(pause)
            except KeyboardInterrupt:
                raise
        return False

    fd  = sys.stdin.fileno()
    old = _termios.tcgetattr(fd)
    # Guarantee enough dwell time even for pause=0
    effective = max(pause, 0.5)
    try:
        _tty.setcbreak(fd)                       # raw single-char, no echo
        ready, _, _ = _select.select([fd], [], [], effective)
        if not ready:
            return False                         # timed out — keep looping
        ch = _os.read(fd, 1)                     # read directly from the fd
        return ch in (b' ', b'q', b'Q', b'\r', b'\n')
    finally:
        _termios.tcsetattr(fd, _termios.TCSADRAIN, old)


def _print_session_table(session_games: list[dict]) -> None:
    """Print a compact numbered table of all games played this session."""
    if not session_games:
        return
    n   = len(session_games)
    sep = colorize("─" * 54, S.DIM)
    print(f"\n  {sep}")
    print(f"  {S.BOLD}  Session — {n} game{'s' if n != 1 else ''} so far{S.RESET}")
    print(f"  {sep}")
    for g in session_games:
        num   = g["num"]
        label = g["label"]
        moves = g["moves"]
        dur   = g["duration"]
        print(f"    {colorize(f'#{num:2d}', S.BOLD, S.WHITE)}  "
              f"{label:<38s}  "
              f"{colorize(f'{moves} moves', S.DIM)}  "
              f"{colorize(f'{dur:.1f}s', S.DIM)}")
    print(f"  {sep}")


def _run_game_loop(settings: dict) -> None:
    """Play games in a loop.

    settings['loop'] controls repeat behaviour:
      None    — interactive: ask "play again?" after every game (default)
      0       — infinite auto-repeat; press Space/Q during pause or Ctrl-C to stop
      N > 1   — play exactly N games then stop automatically

    settings['loop_pause'] (default 1.5s) governs the delay inserted between
    games when in auto-repeat mode.

    A running tally (Win / Loss / Draw) and game counter are shown between
    games when looping.
    """
    loop        = settings.get("loop", None)     # None | 0 | int
    loop_pause  = settings.get("loop_pause", 1.5)
    game_num    = 0
    tally: dict[str, int]  = {"win": 0, "loss": 0, "draw": 0}
    session_games: list[dict] = []

    # Ask for player names once before the first game
    choose_player_names(settings)

    while True:
        game_num += 1

        # Print a compact header in auto-loop mode so it's easy to tell games apart
        if loop is not None:
            limit_str = "∞" if loop == 0 else str(loop)
            sep = colorize("─" * 44, S.DIM)
            # Show session history starting from game 2 onward
            if session_games:
                _print_session_table(session_games)
            print(f"\n  {sep}")
            print(f"  {S.BOLD}{S.CYAN}  Game {game_num} / {limit_str}{S.RESET}  "
                  f"  {colorize('W', S.GREEN)}: {tally['win']}  "
                  f"{colorize('L', S.RED)}: {tally['loss']}  "
                  f"{colorize('D', S.YELLOW)}: {tally['draw']}")
            print(f"  {sep}")

        result = play_game(settings)

        # play_game returns either settings or ("new", settings)
        if isinstance(result, tuple):
            sentinel, settings = result
            if sentinel == "new":
                game_num -= 1    # forfeited: don't count this game
                loop        = settings.get("loop", None)    # may have changed
                loop_pause  = settings.get("loop_pause", 1.5)
                print(colorize("  Starting a new game…\n", S.DIM))
                continue
        else:
            settings = result

        # Refresh loop settings in case /loop changed them during the game
        loop        = settings.get("loop", None)
        loop_pause  = settings.get("loop_pause", 1.5)

        # Append this game to the session history
        session_games.append(_build_session_entry(game_num, settings))

        # Update the in-memory tally from the last log entry
        log = load_log()
        if log:
            last_result = log[-1].get("result", "")
            if last_result in tally:
                tally[last_result] += 1

        if loop is not None:
            # ── Auto-repeat mode ────────────────────────────────────────
            if loop > 0 and game_num >= loop:
                # Played the requested number; print final tally and stop
                _print_session_table(session_games)
                total = sum(tally.values())
                print(colorize(
                    f"\n  ✔  Completed {loop} game{'s' if loop != 1 else ''}.  "
                    f"Final: W {tally['win']} / L {tally['loss']} / D {tally['draw']} "
                    f"({tally['win']/total*100:.0f}% wins)\n",
                    S.BOLD, S.GREEN,
                ))
                break

            # Pause between games; for infinite loops the user can press
            # Space / Q / Enter during this pause to stop gracefully.
            if loop == 0 and sys.stdin.isatty():
                # Infinite loop — show the stop hint and use key-aware wait
                print(colorize(
                    "  [ Space / Q = stop looping   any other key = next game now ]",
                    S.DIM,
                ))
                if _wait_or_stop(loop_pause):
                    _print_session_table(session_games)
                    total = sum(tally.values())
                    pct   = f"{tally['win']/total*100:.0f}%" if total else "–"
                    print(colorize(
                        f"\n  Stopped after {game_num} game{'s' if game_num != 1 else ''}.  "
                        f"W {tally['win']} / L {tally['loss']} / D {tally['draw']} "
                        f"({pct} wins)\n",
                        S.BOLD, S.YELLOW,
                    ))
                    break
            elif loop_pause > 0:
                try:
                    time.sleep(loop_pause)
                except KeyboardInterrupt:
                    raise
            continue

        else:
            # ── Interactive mode ────────────────────────────────────────
            # Show what's been played this session before asking to replay
            if session_games:
                _print_session_table(session_games)
            raw = prompt(
                f"  {S.BOLD}Play again? (y/n): {S.RESET}",
                settings,
            ).strip().lower()
            if is_sentinel(raw):
                sv = sentinel_value(raw)
                if sv == "quit":
                    raise KeyboardInterrupt
                if sv == "new":
                    print(colorize("  Starting a new game…\n", S.DIM))
                    continue
                # loop/speed/etc handled in-place; re-check loop setting
                loop = settings.get("loop", None)
                if loop is not None:
                    # user just enabled loop mode via /loop — continue looping
                    continue
                break
            if raw != "y":
                break


def main() -> None:
    args = parse_args()

    # Disable colour when requested or when stdout is not a TTY (pipe/redirect)
    if args.no_color or not sys.stdout.isatty():
        Style.disable()

    # ── One-shot CLI commands ───────────────────────────────────────────
    if args.stats:
        show_stats()
        return
    if args.log:
        show_log(last_n=50)
        return
    if args.purge:
        removed = purge_log(args.purge_days)
        print(f"Purged {removed} log entries older than {args.purge_days} days.")
        return
    if args.reset_stats:
        save_stats(_fresh_stats())
        print("Statistics reset.")
        return

    # ── Build the session settings dict ────────────────────────────────
    # Normalize --loop: treat 1 the same as "not set" (playing a single game
    # is the normal interactive default — no special repeat behaviour needed).
    raw_loop = args.loop
    if raw_loop is not None and raw_loop < 0:
        print(colorize("  --loop must be 0 (infinite) or a positive integer.", S.RED))
        sys.exit(1)
    effective_loop = None if (raw_loop is None or raw_loop == 1) else raw_loop

    settings: dict = {
        "difficulty":  args.difficulty or "medium",
        "num_players": args.players,          # None means "ask at menu time"
        "auto_speed":  args.auto_speed,
        "loop":        effective_loop,        # None=ask each time, 0=∞, N=N games
        "loop_pause":  args.loop_pause,       # seconds between auto-loop games
        "purge_days":  args.purge_days,
    }

    try:
        print_banner()

        # If --players was given on the CLI skip straight to a game
        if args.players is not None:
            if args.players == 1 and args.difficulty is None:
                settings["difficulty"] = choose_difficulty(settings=settings)
            _run_game_loop(settings)
            print(colorize("\n  Thanks for playing!  👋\n", S.BOLD, S.CYAN))
            return

        # ── Interactive main-menu loop ──────────────────────────────────
        while True:
            choice = main_menu(settings)
            if choice in ("1", "n"):
                num_players = choose_num_players(settings)
                settings["num_players"] = num_players

                if num_players == 1:
                    settings["difficulty"] = choose_difficulty(
                        default=settings.get("difficulty", "medium"),
                        settings=settings,
                    )
                elif num_players == 0:
                    settings["auto_speed"] = choose_auto_speed(
                        default=settings.get("auto_speed", 0.8),
                        settings=settings,
                    )
                    # Offer auto-repeat for 0-player simulation mode
                    choose_loop(settings)

                _run_game_loop(settings)

            elif choice in ("2", "o"):
                settings = options_menu(settings)
            elif choice in ("3", "s"):
                show_stats()
            elif choice in ("4", "l"):
                show_log()
            elif choice in ("q", "5"):
                break
            else:
                print(colorize("  Unknown choice — try again.", S.RED))
            print()

        print(colorize("\n  Thanks for playing!  👋\n", S.BOLD, S.CYAN))

    except KeyboardInterrupt:
        print(colorize("\n\n  Game interrupted — goodbye!  👋\n", S.BOLD, S.YELLOW))
        sys.exit(0)


if __name__ == "__main__":
    main()

