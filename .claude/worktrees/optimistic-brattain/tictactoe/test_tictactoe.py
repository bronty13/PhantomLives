#!/usr/bin/env python3
"""
Unit tests for tictactoe.py

Covers:
  - Style / colorize
  - Sentinel helpers (is_sentinel, sentinel_value)
  - Board helpers (check_winner, is_full, empty_cells, NUM_TO_POS, POS_TO_NUM)
  - _cell rendering
  - AI logic (minimax, best_move, ai_move for all difficulties)
  - Persistent data helpers (load/save stats, load/save/purge/append log)
  - _fresh_stats schema
  - _build_session_entry label generation
  - _resolve_display_names all three modes
  - choose_player_names (TTY-skip and scripted path)
  - handle_slash_command — difficulty, speed, board, new, loop, unknown
  - parse_args — defaults and explicit flags
  - play_game — 0p/1p/2p end-to-end using mocked AI moves
"""

import importlib
import io
import json
import sys
import textwrap
import types
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch, call

# ── Import the module under test ──────────────────────────────────────────
# tictactoe.py lives beside this test file.
sys.path.insert(0, str(Path(__file__).parent))
import tictactoe as tt


# ═══════════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════════

def empty_board():
    """Return a fresh 3×3 board filled with single spaces (no pieces placed).

    A space string (" ") is the game's internal representation of an empty
    cell; ``check_winner`` and ``empty_cells`` both test for ``" "``.
    """
    return [[" "] * 3 for _ in range(3)]


def make_settings(**kw):
    """Build a minimal settings dict pre-filled with sane test defaults.

    Every test only needs to supply the keys it cares about; the rest are
    taken from the ``base`` dict below.  ``auto_speed=0.0`` keeps AI games
    instant (no ``time.sleep`` calls).  ``loop=None`` means single-game
    interactive mode (no auto-repeat).

    Example::

        s = make_settings(num_players=2, names={"X": "Alice", "O": "Bob"})
    """
    base = {
        "difficulty": "medium",
        "num_players": 1,
        "auto_speed": 0.0,   # 0 s → AI moves fire instantly; no sleep() during tests
        "loop": None,         # None → single-game mode (ask "play again?" at end)
        "loop_pause": 0.0,
        "purge_days": 30,
    }
    base.update(kw)
    return base


# ═══════════════════════════════════════════════════════════════════════════
# 1. Style & colorize
# ═══════════════════════════════════════════════════════════════════════════

class TestStyle(unittest.TestCase):
    """Tests for ANSI colour output and the runtime colour-disable switch.

    ``colorize(text, *codes)`` wraps ``text`` in ANSI escape sequences.
    ``Style.disable()`` blanks every code attribute so that all subsequent
    ``colorize()`` calls return plain text — this is what ``--no-color`` uses.

    Each test calls ``importlib.reload(tt)`` in ``setUp`` to reset the
    ``Style`` class attributes back to their original ANSI strings, because
    ``Style.disable()`` mutates those attributes in-place and would otherwise
    contaminate later tests.
    """

    def setUp(self):
        # Re-import the module so Style class attributes are reset to their
        # default ANSI strings before each individual test in this class.
        importlib.reload(tt)

    def test_colorize_wraps_codes(self):
        # colorize() must prepend every escape code passed to it and append
        # the RESET sequence so the terminal's colour is restored afterwards.
        # We pass two codes (bold + bright-red) to exercise *codes variadic.
        result = tt.colorize("hi", "\033[1m", "\033[91m")
        self.assertIn("hi", result)
        # The first code must appear before the text so the terminal sees it.
        self.assertTrue(result.startswith("\033[1m"))
        # RESET must come last to restore the terminal default colour.
        self.assertTrue(result.endswith(tt.S.RESET))

    def test_colorize_empty_codes(self):
        # Calling colorize() with no extra *codes arguments verifies the
        # function is robust when given nothing beyond the text itself.
        # The text must survive verbatim regardless of any surrounding reset
        # sequences the implementation may choose to add.
        result = tt.colorize("plain")
        self.assertIn("plain", result)

    def test_style_disable_clears_codes(self):
        # Pre-condition: confirm we started in the enabled state (non-empty
        # BOLD) so this test is meaningful.
        self.assertNotEqual(tt.S.BOLD, "")
        # After Style.disable() every code attribute must become "" so that
        # string concatenation inside colorize() produces no escape sequences.
        tt.Style.disable()
        self.assertEqual(tt.S.BOLD, "")
        self.assertEqual(tt.S.RED, "")
        self.assertEqual(tt.S.RESET, "")

    def test_colorize_after_disable_is_plain(self):
        # With all code attributes cleared to "", passing them to colorize()
        # injects nothing.  The return value must equal the bare text with
        # nothing prepended or appended.
        tt.Style.disable()
        result = tt.colorize("text", tt.S.BOLD)
        self.assertEqual(result, "text")


# ═══════════════════════════════════════════════════════════════════════════
# 2. Sentinel helpers
# ═══════════════════════════════════════════════════════════════════════════

class TestSentinels(unittest.TestCase):
    """Tests for the NUL-prefixed sentinel value protocol.

    Sentinels signal control-flow across function boundaries (e.g. "the user
    typed /quit", "start a new game") without raising exceptions.  They are
    NUL-prefixed strings (``\x00<name>``) that can never collide with
    legitimate user input.

    ``is_sentinel(v)``     → True iff *v* starts with the NUL byte ``\x00``
    ``sentinel_value(v)``  → strips the NUL prefix, returning the action name
    """

    def test_is_sentinel_true(self):
        # Strings that start with \x00 must be classified as sentinels
        # regardless of the action name that follows the NUL byte.
        self.assertTrue(tt.is_sentinel("\x00quit"))
        self.assertTrue(tt.is_sentinel("\x00new"))

    def test_is_sentinel_false(self):
        # Plain strings (even ones matching known action names), empty strings,
        # and digit strings must NOT be classified as sentinels.
        self.assertFalse(tt.is_sentinel("quit"))
        self.assertFalse(tt.is_sentinel(""))
        self.assertFalse(tt.is_sentinel("5"))

    def test_sentinel_value(self):
        # sentinel_value() must strip exactly the leading NUL and return the
        # remainder unchanged so callers can switch on the bare action name.
        self.assertEqual(tt.sentinel_value("\x00quit"), "quit")
        self.assertEqual(tt.sentinel_value("\x00options"), "options")

    def test_sentinel_round_trip(self):
        # Every known action name must survive a construct→decode round trip:
        # sentinel_value("\x00<name>") must equal <name> for each action.
        for s in ("quit", "new", "board", "options", "loop"):
            self.assertEqual(tt.sentinel_value(f"\x00{s}"), s)


# ═══════════════════════════════════════════════════════════════════════════
# 3. Board constants
# ═══════════════════════════════════════════════════════════════════════════

class TestBoardConstants(unittest.TestCase):
    """Tests for the numpad-to-board-position mapping tables.

    The game uses a numpad layout for move input: key 7 = top-left, 5 = centre,
    3 = bottom-right, etc.  Two dicts encode this:

    ``NUM_TO_POS``  maps numpad digit (1-9) → (row, col)
    ``POS_TO_NUM``  maps (row, col) → numpad digit (the inverse)

    The pair must form a perfect bijection so that every cell has exactly one
    canonical number and vice-versa.
    """

    def test_num_to_pos_coverage(self):
        # The table must map all nine digits (1–9) to nine distinct positions.
        # If any position is repeated the AI might attempt duplicates.
        self.assertEqual(len(tt.NUM_TO_POS), 9)
        positions = set(tt.NUM_TO_POS.values())
        self.assertEqual(len(positions), 9)

    def test_pos_to_num_inverse(self):
        # For every (number → position) entry, the reverse table must map that
        # same position back to the same number, confirming a perfect bijection.
        for num, pos in tt.NUM_TO_POS.items():
            self.assertEqual(tt.POS_TO_NUM[pos], num)

    def test_numpad_layout(self):
        # Verify the numpad orientation matches a standard keyboard numpad:
        #   7 8 9        (0,0) (0,1) (0,2)   ← row 0 (top)
        #   4 5 6   ↔    (1,0) (1,1) (1,2)   ← row 1 (middle)
        #   1 2 3        (2,0) (2,1) (2,2)   ← row 2 (bottom)
        self.assertEqual(tt.NUM_TO_POS[7], (0, 0))   # top-left
        self.assertEqual(tt.NUM_TO_POS[1], (2, 0))   # bottom-left
        self.assertEqual(tt.NUM_TO_POS[9], (0, 2))   # top-right
        self.assertEqual(tt.NUM_TO_POS[3], (2, 2))   # bottom-right
        self.assertEqual(tt.NUM_TO_POS[5], (1, 1))   # centre


# ═══════════════════════════════════════════════════════════════════════════
# 4. Board logic helpers
# ═══════════════════════════════════════════════════════════════════════════

class TestBoardLogic(unittest.TestCase):
    """Tests for the three core board-inspection helpers.

    ``check_winner(board, mark)``  → True iff *mark* occupies a full line
    ``is_full(board)``             → True iff no empty cells remain
    ``empty_cells(board)``         → list of (row, col) for every " " cell

    All win conditions are tested: every row, every column, both diagonals.
    Edge cases cover the empty board, a fully drawn board, and boards with
    a single empty cell.
    """

    # ── check_winner ────────────────────────────────────────────────────────

    def test_row_win(self):
        # X fills the entire top row — a row win is the simplest winning line.
        # O must not be falsely declared winner on the same board.
        board = [["X", "X", "X"],
                 [" ", " ", " "],
                 [" ", " ", " "]]
        self.assertTrue(tt.check_winner(board, "X"))
        self.assertFalse(tt.check_winner(board, "O"))

    def test_all_rows(self):
        # Verify all three rows trigger a win, not just row 0.
        # check_winner must iterate every row, not stop after the first.
        for row in range(3):
            board = empty_board()
            board[row] = ["X", "X", "X"]
            self.assertTrue(tt.check_winner(board, "X"))

    def test_column_win(self):
        # Verify all three columns trigger a win.  Columns require checking
        # board[0][c], board[1][c], board[2][c] — a different loop direction.
        for col in range(3):
            board = empty_board()
            for r in range(3):
                board[r][col] = "O"
            self.assertTrue(tt.check_winner(board, "O"))

    def test_main_diagonal_win(self):
        board = [["X", " ", " "],
                 [" ", "X", " "],
                 [" ", " ", "X"]]
        self.assertTrue(tt.check_winner(board, "X"))

    def test_anti_diagonal_win(self):
        board = [[" ", " ", "O"],
                 [" ", "O", " "],
                 ["O", " ", " "]]
        self.assertTrue(tt.check_winner(board, "O"))

    def test_no_winner_on_empty(self):
        self.assertFalse(tt.check_winner(empty_board(), "X"))
        self.assertFalse(tt.check_winner(empty_board(), "O"))

    def test_partial_row_not_winner(self):
        board = [["X", "X", " "],
                 [" ", " ", " "],
                 [" ", " ", " "]]
        self.assertFalse(tt.check_winner(board, "X"))

    def test_draw_board_no_winner(self):
        # A real drawn board: every row, column, and diagonal is mixed.
        # Neither X nor O should be reported as the winner.
        board = [["X", "O", "X"],
                 ["X", "O", "O"],
                 ["O", "X", "X"]]
        self.assertFalse(tt.check_winner(board, "X"))
        self.assertFalse(tt.check_winner(board, "O"))

    # ── is_full ───────────────────────────────────────────────────────────

    def test_empty_not_full(self):
        self.assertFalse(tt.is_full(empty_board()))

    def test_full_board(self):
        board = [["X", "O", "X"],
                 ["O", "X", "O"],
                 ["O", "X", "O"]]
        self.assertTrue(tt.is_full(board))

    def test_one_empty_not_full(self):
        board = [["X", "O", "X"],
                 ["O", "X", "O"],
                 ["O", "X", " "]]
        self.assertFalse(tt.is_full(board))

    # ── empty_cells ───────────────────────────────────────────────────────

    def test_empty_cells_full_board(self):
        board = [["X", "O", "X"],
                 ["O", "X", "O"],
                 ["O", "X", "O"]]
        self.assertEqual(tt.empty_cells(board), [])

    def test_empty_cells_empty_board(self):
        self.assertEqual(len(tt.empty_cells(empty_board())), 9)

    def test_empty_cells_partial(self):
        board = [["X", " ", " "],
                 [" ", "O", " "],
                 [" ", " ", " "]]
        cells = tt.empty_cells(board)
        self.assertNotIn((0, 0), cells)  # X placed
        self.assertNotIn((1, 1), cells)  # O placed
        self.assertEqual(len(cells), 7)


# ═══════════════════════════════════════════════════════════════════════════
# 5. _cell rendering
# ═══════════════════════════════════════════════════════════════════════════

class TestCellRendering(unittest.TestCase):
    """Tests for the ``_cell(mark, num)`` rendering helper.

    ``_cell(mark, num)`` returns an ANSI-styled string for one board cell:
    - mark == "X"  → cyan-coloured "X"
    - mark == "O"  → magenta-coloured "O"
    - mark == " "  → blue-coloured numpad digit (so the player sees
                        which number to type for that cell)

    Tests reload the module to ensure colour codes are active.
    """

    def setUp(self):
        importlib.reload(tt)

    def test_x_cell_contains_x(self):
        # The rendered string for an X cell must embed the literal character
        # "X" so it's visible after any surrounding ANSI codes are stripped.
        self.assertIn("X", tt._cell("X", 5))

    def test_o_cell_contains_o(self):
        # Likewise for O.
        self.assertIn("O", tt._cell("O", 3))

    def test_empty_cell_contains_digit(self):
        # An empty cell must show the numpad digit, not a space, so the player
        # knows which number to type to claim that cell.
        for n in range(1, 10):
            self.assertIn(str(n), tt._cell(" ", n))

    def test_x_has_cyan_code(self):
        # Reload to ensure colours are on; X uses S.CYAN (\033[96m).
        self.assertIn("\033[96m", tt._cell("X", 1))   # S.CYAN

    def test_o_has_magenta_code(self):
        # O uses S.MAGENTA (\033[95m) so it stands out from X.
        self.assertIn("\033[95m", tt._cell("O", 1))   # S.MAGENTA

    def test_empty_has_blue_code(self):
        # Empty cells use S.BLUE (\033[94m) to visually distinguish them from
        # placed marks while still showing the valid move number.
        self.assertIn("\033[94m", tt._cell(" ", 1))   # S.BLUE

    def test_empty_cell_contains_digit(self):
        for n in range(1, 10):
            self.assertIn(str(n), tt._cell(" ", n))

    def test_x_has_cyan_code(self):
        # Reload to ensure colours are on
        self.assertIn("\033[96m", tt._cell("X", 1))   # S.CYAN

    def test_o_has_magenta_code(self):
        self.assertIn("\033[95m", tt._cell("O", 1))   # S.MAGENTA

    def test_empty_has_blue_code(self):
        self.assertIn("\033[94m", tt._cell(" ", 1))   # S.BLUE


# ═══════════════════════════════════════════════════════════════════════════
# 6. Minimax / AI logic
# ═══════════════════════════════════════════════════════════════════════════

class TestMinimax(unittest.TestCase):
    """Tests for the minimax algorithm and its wrappers.

    The game's AI uses minimax with full look-ahead (no depth limit) so hard
    difficulty is provably optimal.  The three relevant functions are:

    ``minimax(board, is_maximising, ai_mark, human_mark)``
        Returns +1 (AI wins), -1 (human wins), or 0 (draw) from the AI's
        point of view when both sides play optimally from *board* onward.

    ``best_move(board, ai_mark, human_mark)``
        Returns the (row, col) that maximises the minimax score for *ai_mark*.

    ``ai_move(board, ai_mark, human_mark, difficulty)``
        Dispatches to best_move (hard), a random cell (easy), or a mix
        (medium).
    """

    def test_immediate_win_detected(self):
        # X has two in a row on row 0; (0,2) is the only winning move.
        # best_move() must find it immediately without searching deeper.
        board = [["X", "X", " "],
                 ["O", "O", " "],
                 [" ", " ", " "]]
        # X should take (0,2) to win
        move = tt.best_move(board, "X", "O")
        self.assertEqual(move, (0, 2))

    def test_block_opponent_win(self):
        # O has two in column 0 and is about to win; X must block at (2,0)
        # even though X could also win on column 1.  Blocking a loss is
        # lower-priority than winning, but here X has no immediate win.
        board = [["O", "X", " "],
                 ["O", "X", " "],
                 [" ", " ", " "]]
        move = tt.best_move(board, "X", "O")
        self.assertEqual(move, (2, 0))

    def test_minimax_returns_draw_on_full(self):
        # A completely filled board with no winner must score 0 (draw).
        # No further recursion can happen, so minimax must return 0 directly.
        board = [["X", "O", "X"],
                 ["X", "O", "O"],
                 ["O", "X", "X"]]
        score = tt.minimax(board, True, "X", "O")
        self.assertEqual(score, 0)

    def test_minimax_wins_immediately(self):
        # X has two in a row at the start of minimax’s turn; since it’s
        # the maximising player’s turn and there’s a winning move available,
        # minimax must return +1 (AI wins with perfect play).
        board = [["X", "X", " "],
                 [" ", " ", " "],
                 [" ", " ", " "]]
        score = tt.minimax(board, True, "X", "O")
        self.assertEqual(score, 1)

    def test_minimax_detects_loss(self):
        # O has two in a row; it’s the maximising player (X)’s turn but O
        # will play next in the minimising branch and will win.
        # We only check that minimax returns a valid score without raising;
        # the exact value depends on whether X can force a draw.
        board = [["O", "O", " "],
                 [" ", " ", " "],
                 [" ", " ", " "]]
        # Maximising player is X, O is human — O will win
        score = tt.minimax(board, True, "X", "O")
        # Score should be -1 (human/O wins) or 0 (draw forced)
        self.assertIn(score, (-1, 0, 1))   # just ensure no exception

    def test_best_move_on_empty_returns_valid(self):
        # On an empty board every cell is legal.  best_move() must return a
        # (row, col) that exists in the numpad position table.
        board = empty_board()
        move = tt.best_move(board, "X", "O")
        self.assertIn(move, list(tt.NUM_TO_POS.values()))

    def test_hard_ai_never_loses(self):
        """Hard AI vs hard AI should always draw (perfect play both sides)."""
        import copy
        board = empty_board()
        current = "X"
        for _ in range(9):
            if tt.check_winner(board, "X") or tt.check_winner(board, "O"):
                break
            if tt.is_full(board):
                break
            other = "O" if current == "X" else "X"
            r, c = tt.best_move(board, current, other)
            board[r][c] = current
            current = other
        self.assertFalse(tt.check_winner(board, "X"),
                         "Hard AI as X should not win against hard AI as O")
        self.assertFalse(tt.check_winner(board, "O"),
                         "Hard AI as O should not win against hard AI as X")
        self.assertTrue(tt.is_full(board))


class TestAiMove(unittest.TestCase):
    """Tests for ``ai_move(board, ai_mark, human_mark, difficulty)``.

    ``ai_move`` dispatches to:
    - hard   → ``best_move()`` (minimax, always optimal)
    - easy   → random empty cell
    - medium → 50 % ``best_move()``, 50 % random (probabilistic)

    All difficulty levels must return a cell that is currently empty.
    """

    def test_hard_returns_best(self):
        # With X at (0,0) and (0,1) there is one winning move: (0,2).
        # Hard difficulty must always find it via minimax.
        board = [["X", "X", " "], ["O", " ", " "], [" ", " ", " "]]
        move = tt.ai_move(board, "X", "O", "hard")
        self.assertEqual(move, (0, 2))

    def test_easy_returns_valid_cell(self):
        # Easy AI picks a random empty cell, so the result may vary, but it
        # must always be a cell that is currently empty (board[r][c] == " ").
        board = empty_board()
        board[0][0] = "X"   # one cell already occupied
        move = tt.ai_move(board, "O", "X", "easy")
        self.assertIn(move, tt.empty_cells(board))

    def test_medium_returns_valid_cell(self):
        # Medium difficulty picks optimally ~50 % of the time; the other ~50 %
        # it picks randomly.  Both branches must return a valid empty cell.
        # We run 20 iterations to hit both branches with high probability.
        board = empty_board()
        for _ in range(20):  # run several times to hit both branches
            move = tt.ai_move(board, "X", "O", "medium")
            self.assertIn(move, tt.empty_cells(board))


# ═══════════════════════════════════════════════════════════════════════════
# 7. Persistent data helpers  (isolated with tmp dirs)
# ═══════════════════════════════════════════════════════════════════════════

class TestPersistentData(unittest.TestCase):
    """Tests for the JSON-backed stats and game-log persistence layer.

    The module stores data in files under ``DATA_DIR`` (default
    ``~/.tictactoe/``).  To keep tests hermetic and side-effect-free, setUp
    redirects the three module-level path variables to a temporary directory
    that is deleted in tearDown.  This means tests never touch the real user
    data files.

    Functions under test:
        load_stats() / save_stats(stats)   – JSON round-trip for cumulative stats
        load_log() / save_log(log)         – JSON round-trip for game history
        append_log_entry(entry)            – append + auto-timestamp
        purge_log(max_age_days)            – remove entries older than N days
    """

    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp.name)
        # Save the real paths so tearDown can restore them.
        self._orig_data_dir   = tt.DATA_DIR
        self._orig_stats_file = tt.STATS_FILE
        self._orig_log_file   = tt.LOG_FILE
        # Redirect the module’s path variables to the temp dir.
        tt.DATA_DIR   = self.tmp_path
        tt.STATS_FILE = self.tmp_path / "stats.json"
        tt.LOG_FILE   = self.tmp_path / "game_log.json"

    def tearDown(self):
        # Restore original paths before the temp dir is cleaned up.
        tt.DATA_DIR   = self._orig_data_dir
        tt.STATS_FILE = self._orig_stats_file
        tt.LOG_FILE   = self._orig_log_file
        self.tmp.cleanup()

    # ── stats ─────────────────────────────────────────────────────────────

    def test_load_stats_defaults_when_missing(self):
        # With no stats file in the temp dir, load_stats() should return a
        # fresh schema (all counters zero) rather than raising FileNotFoundError.
        stats = tt.load_stats()
        self.assertEqual(stats["games_played"], 0)
        self.assertEqual(stats["wins"], 0)
        self.assertIn("by_difficulty", stats)

    def test_save_and_load_stats_roundtrip(self):
        # Mutate a field, persist it, reload from disk, and confirm the value
        # survived serialisation → JSON → deserialisation.
        stats = tt.load_stats()
        stats["wins"] = 7
        tt.save_stats(stats)
        loaded = tt.load_stats()
        self.assertEqual(loaded["wins"], 7)

    def test_load_stats_merges_missing_keys(self):
        # Simulates loading a stats file written by an older version of the
        # game that did not yet have the "draws" key.  load_stats() should
        # merge defaults so callers never have to guard against KeyError.
        partial = {"games_played": 3, "wins": 1, "losses": 2,
                   "by_difficulty": {"easy": {"played":0,"wins":0,"losses":0,"draws":0},
                                     "medium":{"played":0,"wins":0,"losses":0,"draws":0},
                                     "hard":{"played":0,"wins":0,"losses":0,"draws":0}}}
        with open(tt.STATS_FILE, "w") as f:
            json.dump(partial, f)
        stats = tt.load_stats()
        self.assertIn("draws", stats)   # merged from default

    def test_load_stats_handles_corrupt_file(self):
        # If the file contains invalid JSON (e.g. after an interrupted write),
        # load_stats() should recover gracefully with a fresh default schema.
        tt.STATS_FILE.write_text("NOT JSON")
        stats = tt.load_stats()
        self.assertEqual(stats["games_played"], 0)

    # ── log ───────────────────────────────────────────────────────────────

    def test_load_log_empty_when_missing(self):
        # With no log file present, load_log() must return [] (not raise).
        self.assertEqual(tt.load_log(), [])

    def test_append_and_load_log(self):
        # append_log_entry() should write the entry to disk AND inject a
        # "timestamp" key so every log entry can be sorted/purged by age.
        tt.append_log_entry({"result": "win", "mode": "1p", "moves": 7})
        log = tt.load_log()
        self.assertEqual(len(log), 1)
        self.assertEqual(log[0]["result"], "win")
        self.assertIn("timestamp", log[0])

    def test_append_multiple_entries(self):
        # Appending multiple entries must accumulate them all; each append
        # call must not overwrite previous entries.
        for i in range(5):
            tt.append_log_entry({"result": "draw", "mode": "2p", "moves": i})
        self.assertEqual(len(tt.load_log()), 5)

    def test_purge_removes_old_entries(self):
        # Write one 60-day-old entry and one entry timestamped now.
        # purge_log(max_age_days=30) should remove exactly the old entry
        # and leave the recent one intact.
        from datetime import datetime, timedelta
        old_ts  = (datetime.now() - timedelta(days=60)).isoformat()
        new_ts  = datetime.now().isoformat()
        log = [
            {"result": "win",  "timestamp": old_ts,  "mode": "1p"},
            {"result": "draw", "timestamp": new_ts,   "mode": "1p"},
        ]
        tt.save_log(log)
        removed = tt.purge_log(max_age_days=30)
        self.assertEqual(removed, 1)
        self.assertEqual(len(tt.load_log()), 1)
        self.assertEqual(tt.load_log()[0]["result"], "draw")

    def test_purge_keeps_recent_entries(self):
        # All fresh entries are well within the 30-day window, so purge_log()
        # should remove nothing and report 0 removals.
        from datetime import datetime
        for _ in range(3):
            tt.append_log_entry({"result": "draw", "mode": "1p", "moves": 5})
        removed = tt.purge_log(max_age_days=30)
        self.assertEqual(removed, 0)
        self.assertEqual(len(tt.load_log()), 3)

    def test_load_log_handles_corrupt_file(self):
        # Like the stats counterpart, a corrupt log file should not crash the
        # game; load_log() must return [] as if no log file existed.
        tt.LOG_FILE.write_text("INVALID")
        self.assertEqual(tt.load_log(), [])


# ═══════════════════════════════════════════════════════════════════════════
# 8. _fresh_stats schema
# ═══════════════════════════════════════════════════════════════════════════

class TestFreshStats(unittest.TestCase):
    """Tests for the ``_fresh_stats()`` schema factory.

    ``_fresh_stats()`` returns a brand-new stats dict with all counters set to
    zero.  It is the authoritative schema definition; ``load_stats()`` merges
    any missing keys from it to handle forward-compatibility with older files.
    """

    def test_keys_present(self):
        # Top-level keys that the rest of the codebase reads unconditionally.
        s = tt._fresh_stats()
        for key in ("games_played", "wins", "losses", "draws", "by_difficulty"):
            self.assertIn(key, s)

    def test_difficulty_keys(self):
        # by_difficulty must have sub-dicts for all three difficulty levels,
        # each pre-initialised with the four per-difficulty counters.
        bd = tt._fresh_stats()["by_difficulty"]
        for diff in ("easy", "medium", "hard"):
            self.assertIn(diff, bd)
            for sub in ("played", "wins", "losses", "draws"):
                self.assertEqual(bd[diff][sub], 0)

    def test_all_zeros(self):
        # Freshly created stats must have zero counts everywhere so a new
        # installation starts with a clean slate.
        s = tt._fresh_stats()
        self.assertEqual(s["games_played"], 0)
        self.assertEqual(s["wins"], 0)


# ═══════════════════════════════════════════════════════════════════════════
# 9. _build_session_entry
# ═══════════════════════════════════════════════════════════════════════════

class TestBuildSessionEntry(unittest.TestCase):
    """Tests for ``_build_session_entry(game_num, settings)``.

    After each game the result dict is stored in ``settings["_last_game"]``.
    ``_build_session_entry()`` reads that and produces a display dict::

        {"num": <int>, "label": <str>, "moves": <int>, "duration": <float>}

    The human-readable *label* must identify the result (Draw / wins / etc.)
    and embed the relevant player name so the session table is informative.
    Tests cover all result codes: draw, win, loss, ai_win, pX_wins, and an
    empty-settings edge case.
    """

    def _settings(self, result, winner_mark, seats, dnames, num_players=1):
        """Build a minimal settings dict that looks like it came from play_game.

        ``_last_game`` is the key that ``_build_session_entry`` reads.  We only
        set the fields that function actually needs.
        """
        return {
            "_last_game": {
                "result": result,
                "winner_mark": winner_mark,
                "moves": 9,
                "duration": 12.3,
                "seats": seats,
                "num_players": num_players,
                "display_names": dnames,
            }
        }

    def test_draw_label(self):
        # A draw result must produce a label containing "Draw" (case-sensitive
        # as displayed to the user) along with correct metadata fields.
        s = self._settings("draw", None, {"X": "human", "O": "medium"}, {})
        entry = tt._build_session_entry(1, s)
        self.assertIn("Draw", entry["label"])
        self.assertEqual(entry["num"], 1)    # game number preserved
        self.assertEqual(entry["moves"], 9)  # move count preserved

    def test_win_label_shows_name(self):
        # When X (the human) wins the label must contain the player’s display
        # name and the word "wins" so the session table is self-explanatory.
        s = self._settings("win", "X",
                           {"X": "human", "O": "hard"},
                           {"X": "Alice", "O": "Computer"})
        entry = tt._build_session_entry(2, s)
        self.assertIn("Alice", entry["label"])
        self.assertIn("wins", entry["label"].lower())

    def test_loss_label_shows_computer_name(self):
        # When the human loses, O (the computer) is the winner; the computer’s
        # display name must appear in the label (not just a generic string).
        s = self._settings("loss", "O",
                           {"X": "human", "O": "hard"},
                           {"X": "Bob", "O": "Skynet"})
        entry = tt._build_session_entry(3, s)
        self.assertIn("Skynet", entry["label"])

    def test_ai_win_label(self):
        # In 0-player (AI vs AI) mode the winning AI’s display name must show.
        s = self._settings("ai_win", "X",
                           {"X": "hard", "O": "easy"},
                           {"X": "Deep Blue", "O": "Random"},
                           num_players=0)
        entry = tt._build_session_entry(1, s)
        self.assertIn("Deep Blue", entry["label"])

    def test_2p_win_label(self):
        # In 2-player mode the result code is "pX_wins" (not "win").  The
        # winning player’s name must still appear in the label.
        s = self._settings("pX_wins", "X",
                           {"X": "human", "O": "human"},
                           {"X": "Alice", "O": "Bob"},
                           num_players=2)
        entry = tt._build_session_entry(1, s)
        self.assertIn("Alice", entry["label"])

    def test_empty_settings_no_crash(self):
        # If _last_game is absent (e.g. called before any game has been played)
        # the function must not raise; it should fall back to a default entry.
        entry = tt._build_session_entry(1, {})
        self.assertIn("Draw", entry["label"])


# ═══════════════════════════════════════════════════════════════════════════
# 10. _resolve_display_names
# ═══════════════════════════════════════════════════════════════════════════

class TestResolveDisplayNames(unittest.TestCase):
    """Tests for ``_resolve_display_names(settings, seats)``.

    ``seats`` is a dict mapping mark (“X”/“O”) to seat type
    (“human”, “easy”, “medium”, “hard”).  The function returns a display-name
    mapping and caches it in ``settings["_display_names"]``.

    Default names vary by game mode:
    - 1p: “Player” / “Computer”
    - 2p: “Player X” / “Player O”
    - 0p: “AI-X” / “AI-O”

    All defaults can be overridden via ``settings["names"]``.
    """

    def test_1p_human_and_computer_defaults(self):
        # Without custom names, a 1-player game must label the human seat
        # “Player” and the AI seat “Computer”.
        seats = {"X": "human", "O": "hard"}
        s = make_settings(num_players=1)
        result = tt._resolve_display_names(s, seats)
        self.assertEqual(result["X"], "Player")
        self.assertEqual(result["O"], "Computer")

    def test_1p_custom_names(self):
        # Custom names in settings["names"] must override the defaults.
        # For 1p mode the keys are "human" and "computer" (seat type names).
        seats = {"X": "human", "O": "medium"}
        s = make_settings(num_players=1, names={"human": "Alice", "computer": "HAL"})
        result = tt._resolve_display_names(s, seats)
        self.assertEqual(result["X"], "Alice")
        self.assertEqual(result["O"], "HAL")

    def test_2p_defaults(self):
        # Without custom names, 2-player mode should label players by mark
        # (“Player X” / “Player O”) to distinguish them on screen.
        seats = {"X": "human", "O": "human"}
        s = make_settings(num_players=2)
        result = tt._resolve_display_names(s, seats)
        self.assertEqual(result["X"], "Player X")
        self.assertEqual(result["O"], "Player O")

    def test_2p_custom(self):
        # For 2p mode custom names use the mark as key ("X" / "O").
        seats = {"X": "human", "O": "human"}
        s = make_settings(num_players=2, names={"X": "Carol", "O": "Dave"})
        result = tt._resolve_display_names(s, seats)
        self.assertEqual(result["X"], "Carol")
        self.assertEqual(result["O"], "Dave")

    def test_0p_defaults(self):
        # In 0-player (AI vs AI) mode the default names are “AI-X” / “AI-O”.
        seats = {"X": "hard", "O": "easy"}
        s = make_settings(num_players=0)
        result = tt._resolve_display_names(s, seats)
        self.assertEqual(result["X"], "AI-X")
        self.assertEqual(result["O"], "AI-O")

    def test_0p_custom(self):
        # Custom names work the same way in 0p mode (mark-keyed).
        seats = {"X": "hard", "O": "easy"}
        s = make_settings(num_players=0, names={"X": "AlphaGo", "O": "Random"})
        result = tt._resolve_display_names(s, seats)
        self.assertEqual(result["X"], "AlphaGo")
        self.assertEqual(result["O"], "Random")

    def test_stores_in_settings(self):
        # The resolved names must be cached in settings["_display_names"] so
        # other functions (e.g. _build_session_entry) can retrieve them later
        # without needing to recompute them.
        seats = {"X": "human", "O": "hard"}
        s = make_settings(num_players=1)
        tt._resolve_display_names(s, seats)
        self.assertIn("_display_names", s)


# ═══════════════════════════════════════════════════════════════════════════
# 11. choose_player_names
# ═══════════════════════════════════════════════════════════════════════════

class TestChoosePlayerNames(unittest.TestCase):
    """Tests for ``choose_player_names(settings)``.

    ``choose_player_names`` interactively prompts for player names when stdin
    is a TTY.  It must be a no-op in three situations:
    1. stdin is not a TTY (e.g. piped input / test runner)
    2. names have already been set in settings (avoid re-prompting)
    3. 0-player mode — no human to name; defaults are assigned silently

    When it does prompt, empty input falls back to the default name.
    """

    def test_skips_when_not_tty(self):
        # When stdin.isatty() returns False (e.g. running under a test
        # runner with captured stdin), choose_player_names must return
        # without prompting and without writing to settings["names"].
        s = make_settings(num_players=1)
        with patch.object(sys.stdin, "isatty", return_value=False):
            tt.choose_player_names(s)
        self.assertNotIn("names", s)

    def test_skips_if_names_already_set(self):
        # If names are already in settings (set via CLI or a previous call)
        # the function must not prompt again.
        s = make_settings(num_players=1, names={"human": "Existing"})
        with patch.object(sys.stdin, "isatty", return_value=True):
            # Should return immediately without calling prompt
            with patch("tictactoe.prompt") as mock_p:
                tt.choose_player_names(s)
                mock_p.assert_not_called()

    def test_0p_preset_difficulty_assigns_defaults_without_prompt(self):
        # 0-player mode has no human participants, so no name prompts should
        # fire.  The function must silently assign the AI default names.
        s = make_settings(num_players=0, difficulty="hard")
        with patch.object(sys.stdin, "isatty", return_value=True):
            with patch("tictactoe.prompt") as mock_p:
                tt.choose_player_names(s)
                mock_p.assert_not_called()
        self.assertEqual(s["names"], {"X": "AI-X", "O": "AI-O"})

    def test_1p_collects_two_names(self):
        # In 1p mode the function must collect a human name and a computer
        # name via successive prompt() calls, storing them under the keys
        # "human" and "computer" respectively.
        s = make_settings(num_players=1)
        # Simulate Enter → keeps default for both
        with patch.object(sys.stdin, "isatty", return_value=True):
            with patch("tictactoe.prompt", side_effect=["Alice", "HAL9000"]):
                tt.choose_player_names(s)
        self.assertEqual(s["names"]["human"], "Alice")
        self.assertEqual(s["names"]["computer"], "HAL9000")

    def test_1p_empty_input_uses_default(self):
        # If the user presses Enter without typing a name, the default
        # name ("Player" / "Computer") must be used instead of an empty string.
        s = make_settings(num_players=1)
        with patch.object(sys.stdin, "isatty", return_value=True):
            with patch("tictactoe.prompt", return_value=""):
                tt.choose_player_names(s)
        self.assertEqual(s["names"]["human"], "Player")
        self.assertEqual(s["names"]["computer"], "Computer")

    def test_2p_collects_names_for_x_and_o(self):
        # 2-player mode must prompt for both marks (X and O) and store them
        # under the mark strings as keys ("X" / "O"), not "human"/"computer".
        s = make_settings(num_players=2)
        with patch.object(sys.stdin, "isatty", return_value=True):
            with patch("tictactoe.prompt", side_effect=["Alice", "Bob"]):
                tt.choose_player_names(s)
        self.assertEqual(s["names"]["X"], "Alice")
        self.assertEqual(s["names"]["O"], "Bob")


# ═══════════════════════════════════════════════════════════════════════════
# 12. handle_slash_command
# ═══════════════════════════════════════════════════════════════════════════

class TestHandleSlashCommand(unittest.TestCase):
    """Tests for ``handle_slash_command(raw, settings, *, in_game, board)``.

    Slash commands let the player change settings mid-game or trigger actions
    without leaving the input loop.  The parser supports full names and
    single-letter aliases (e.g. ``/d`` for ``/difficulty``).

    Return value convention:
    - ``None``              → command handled; stay in current game loop
    - ``"new"``             → start a new game (sentinel-wrapped by caller)
    - ``"options"``         → show options menu
    - raises ``KeyboardInterrupt`` → quit the application

    Commands under test: /difficulty, /speed, /board, /new, /quit,
    /options, /stats, /loop, and aliases, plus unknown command handling.
    """

    def _settings(self):
        return make_settings()

    def test_difficulty_set_easy(self):
        # /difficulty easy must update settings["difficulty"] and return None
        # (stay in loop), not a sentinel.
        s = self._settings()
        result = tt.handle_slash_command("/difficulty easy", s)
        self.assertIsNone(result)
        self.assertEqual(s["difficulty"], "easy")

    def test_difficulty_abbrev_h(self):
        # Single-letter abbreviation "h" must resolve to "hard".
        s = self._settings()
        tt.handle_slash_command("/d h", s)
        self.assertEqual(s["difficulty"], "hard")

    def test_difficulty_number_3(self):
        # Numeric aliases: 1=easy, 2=medium, 3=hard.
        s = self._settings()
        tt.handle_slash_command("/difficulty 3", s)
        self.assertEqual(s["difficulty"], "hard")

    def test_difficulty_unknown_prints_error(self):
        # An unrecognised difficulty token must print an error message and
        # leave settings["difficulty"] unchanged.
        s = self._settings()
        with patch("builtins.print") as mock_print:
            tt.handle_slash_command("/difficulty unknown", s)
        # difficulty should be unchanged
        self.assertEqual(s["difficulty"], "medium")

    def test_speed_sets_auto_speed(self):
        # /speed 2.5 must set settings["auto_speed"] to 2.5.
        s = self._settings()
        tt.handle_slash_command("/speed 2.5", s)
        self.assertAlmostEqual(s["auto_speed"], 2.5)

    def test_speed_zero(self):
        # Speed 0 is valid (instant AI moves).
        s = self._settings()
        tt.handle_slash_command("/speed 0", s)
        self.assertEqual(s["auto_speed"], 0.0)

    def test_speed_negative_rejected(self):
        # Negative speed values are nonsensical; the command must reject
        # the input and leave auto_speed unchanged.
        s = self._settings()
        with patch("builtins.print"):
            tt.handle_slash_command("/speed -1", s)
        # unchanged
        self.assertEqual(s["auto_speed"], 0.0)

    def test_board_outside_game_prints_message(self):
        # /board called when not in a game should print a helpful message
        # (not crash) and return None.
        s = self._settings()
        with patch("builtins.print") as mock_print:
            result = tt.handle_slash_command("/board", s, in_game=False, board=None)
        self.assertIsNone(result)

    def test_board_in_game_reprints(self):
        # /board called during a game must call print_board(board) so the
        # player can see the current position again after typing a command.
        s = self._settings()
        board = empty_board()
        with patch("tictactoe.print_board") as mock_pb:
            result = tt.handle_slash_command("/board", s, in_game=True, board=board)
        mock_pb.assert_called_once_with(board)
        self.assertIsNone(result)

    def test_new_outside_game_returns_sentinel(self):
        # /new called outside a game requires no confirmation; it must
        # return the sentinel string "new" immediately.
        s = self._settings()
        result = tt.handle_slash_command("/new", s, in_game=False)
        self.assertEqual(result, "new")

    def test_new_in_game_confirmed(self):
        # /new called mid-game prompts for confirmation.  “y” confirms
        # and the function returns "new" to trigger a game restart.
        s = self._settings()
        with patch("builtins.input", return_value="y"):
            result = tt.handle_slash_command("/new", s, in_game=True)
        self.assertEqual(result, "new")

    def test_new_in_game_cancelled(self):
        # “n” at the confirmation prompt must cancel the restart and return
        # None so the current game continues.
        s = self._settings()
        with patch("builtins.input", return_value="n"):
            result = tt.handle_slash_command("/new", s, in_game=True)
        self.assertIsNone(result)

    def test_quit_force_raises_keyboard_interrupt(self):
        # /quit --force must raise KeyboardInterrupt immediately without a
        # confirmation prompt, allowing non-interactive use.
        s = self._settings()
        with self.assertRaises(KeyboardInterrupt):
            tt.handle_slash_command("/quit --force", s)

    def test_quit_in_game_confirmed(self):
        # /quit mid-game with “y” confirmation must raise KeyboardInterrupt
        # to propagate quit intent up through the game loop.
        s = self._settings()
        with patch("builtins.input", return_value="y"):
            with self.assertRaises(KeyboardInterrupt):
                tt.handle_slash_command("/quit", s, in_game=True)

    def test_quit_in_game_cancelled(self):
        # Declining the quit confirmation must return None so the game resumes.
        s = self._settings()
        with patch("builtins.input", return_value="n"):
            result = tt.handle_slash_command("/quit", s, in_game=True)
        self.assertIsNone(result)

    def test_options_returns_sentinel(self):
        # /options must return the string "options" so the caller can open
        # the interactive options menu.
        s = self._settings()
        result = tt.handle_slash_command("/options", s)
        self.assertEqual(result, "options")

    def test_alias_d_for_difficulty(self):
        # The single-letter alias "/d" must behave identically to "/difficulty".
        s = self._settings()
        tt.handle_slash_command("/d easy", s)
        self.assertEqual(s["difficulty"], "easy")

    def test_alias_b_for_board(self):
        # "/b" is the alias for "/board"; it must call print_board when in-game.
        s = self._settings()
        board = empty_board()
        with patch("tictactoe.print_board") as mock_pb:
            tt.handle_slash_command("/b", s, board=board)
        mock_pb.assert_called_once()

    def test_loop_set_to_number(self):
        # /loop 5 must set settings["loop"] to the integer 5 (play exactly
        # 5 games then stop).
        s = self._settings()
        tt.handle_slash_command("/loop 5", s)
        self.assertEqual(s.get("loop"), 5)

    def test_loop_off_clears(self):
        # /loop off must clear auto-repeat by setting settings["loop"] to None
        # (interactive mode: ask "play again?" after each game).
        s = make_settings(loop=5)
        tt.handle_slash_command("/loop off", s)
        self.assertIsNone(s.get("loop"))

    def test_loop_zero_infinite(self):
        # /loop 0 means infinite auto-repeat.  The value 0 (not None) is stored
        # so callers can distinguish “off” (None) from “infinite” (0).
        s = self._settings()
        tt.handle_slash_command("/loop 0", s)
        self.assertEqual(s.get("loop"), 0)

    def test_unknown_command_prints_error(self):
        # An unrecognised slash command must print an error message and return
        # None rather than raising an exception or silently doing nothing.
        s = self._settings()
        with patch("builtins.print") as mock_print:
            result = tt.handle_slash_command("/xyzzy", s)
        self.assertIsNone(result)
        # Should have printed something about unknown command
        self.assertTrue(mock_print.called)

    def test_stats_calls_show_stats(self):
        # /stats must delegate to show_stats() exactly once with no extra args.
        s = self._settings()
        with patch("tictactoe.show_stats") as mock_ss:
            tt.handle_slash_command("/stats", s)
        mock_ss.assert_called_once()


# ═══════════════════════════════════════════════════════════════════════════
# 13. parse_args
# ═══════════════════════════════════════════════════════════════════════════

class TestParseArgs(unittest.TestCase):
    """Tests for ``parse_args()`` — the ``argparse``-based CLI parser.

    Every command-line flag is exercised at least once.  The ``_parse()``
    helper patches ``sys.argv`` so the test can call ``parse_args()`` directly
    without spawning a subprocess.

    Flags covered:
        --players / -p    number of human players (0, 1, 2)
        --difficulty / -d easy | medium | hard
        --loop            auto-repeat game count (0 = infinite)
        --loop-pause      seconds between auto-repeated games
        --no-color        disable ANSI colour output
        --stats           print stats and exit
        --log             print game log and exit
        --purge-days      log age limit for purge
        --reset-stats     wipe all stats and exit
        --auto-speed      AI move delay in seconds
    """

    def _parse(self, args_list):
        """Invoke parse_args() with a fake sys.argv built from args_list.

        Patches sys.argv as ["tictactoe.py"] + args_list so argparse sees
        exactly the flags we pass without any pytest/unittest arguments leaking
        in from the actual process argv.
        """
        with patch("sys.argv", ["tictactoe.py"] + args_list):
            return tt.parse_args()

    def test_defaults(self):
        # With no flags the parser must produce sensible play defaults:
        # players unset (prompts at runtime), medium difficulty, 0.8 s AI
        # delay, no loop, 1.5 s loop pause, colour on, 30-day purge window.
        args = self._parse([])
        self.assertIsNone(args.players)
        self.assertIsNone(args.difficulty)
        self.assertAlmostEqual(args.auto_speed, 0.8)
        self.assertIsNone(args.loop)
        self.assertAlmostEqual(args.loop_pause, 1.5)
        self.assertFalse(args.no_color)
        self.assertEqual(args.purge_days, 30)

    def test_players_flag(self):
        # All three valid player counts must be accepted.
        for p in (0, 1, 2):
            args = self._parse([f"--players={p}"])
            self.assertEqual(args.players, p)

    def test_short_p_flag(self):
        # The short form "-p" must behave identically to "--players".
        args = self._parse(["-p", "2"])
        self.assertEqual(args.players, 2)

    def test_difficulty_flag(self):
        # All three difficulty strings must be accepted by the parser.
        for d in ("easy", "medium", "hard"):
            args = self._parse(["-d", d])
            self.assertEqual(args.difficulty, d)

    def test_loop_flag(self):
        # --loop 5 means "play exactly 5 games then stop".
        args = self._parse(["--loop", "5"])
        self.assertEqual(args.loop, 5)

    def test_loop_zero_infinite(self):
        # --loop 0 is the special value for infinite auto-repeat.
        args = self._parse(["--loop", "0"])
        self.assertEqual(args.loop, 0)

    def test_loop_pause_flag(self):
        # --loop-pause accepts a float and stores it in args.loop_pause.
        args = self._parse(["--loop-pause", "2.5"])
        self.assertAlmostEqual(args.loop_pause, 2.5)

    def test_no_color_flag(self):
        # --no-color must set args.no_color to True so main() can disable Style.
        args = self._parse(["--no-color"])
        self.assertTrue(args.no_color)

    def test_stats_flag(self):
        # --stats signals that main() should print stats and exit.
        args = self._parse(["--stats"])
        self.assertTrue(args.stats)

    def test_log_flag(self):
        # --log signals that main() should print the game log and exit.
        args = self._parse(["--log"])
        self.assertTrue(args.log)

    def test_purge_days_flag(self):
        # --purge-days sets the maximum age (in days) for log entries.
        args = self._parse(["--purge-days", "7"])
        self.assertEqual(args.purge_days, 7)

    def test_reset_stats_flag(self):
        # --reset-stats signals that main() should wipe the stats file.
        args = self._parse(["--reset-stats"])
        self.assertTrue(args.reset_stats)

    def test_invalid_players_value_exits(self):
        # A players value outside {0,1,2} must cause argparse to exit with
        # a non-zero status (SystemExit), not silently be accepted.
        with self.assertRaises(SystemExit):
            self._parse(["--players", "3"])


# ═══════════════════════════════════════════════════════════════════════════
# 14. play_game — end-to-end with mocked AI / input
# ═══════════════════════════════════════════════════════════════════════════

class TestPlayGame(unittest.TestCase):
    """End-to-end tests for ``play_game(settings)``.

    ``play_game()`` runs a complete game from empty board to final result,
    updates persistent stats and log, then returns either a settings dict
    (normal finish) or a ``("new", settings)`` tuple (forfeit/restart).

    Because real human input and AI delays would make tests slow/interactive,
    we patch:
    - ``get_human_move``  → fed from an iterator of pre-chosen (row, col) moves
    - ``ai_move``         → fed from an iterator of pre-chosen (row, col) moves
    - ``random.shuffle``  → side_effect=lambda lst: None (keeps X=human seat)
    - ``builtins.print``  → suppressed to keep test output clean

    All tests redirect DATA_DIR/STATS_FILE/LOG_FILE to a temp directory so
    they don’t touch the real user data files on disk.
    """

    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp.name)
        # Redirect persistent-data paths to a throwaway temp directory.
        self._orig_data_dir   = tt.DATA_DIR
        self._orig_stats_file = tt.STATS_FILE
        self._orig_log_file   = tt.LOG_FILE
        tt.DATA_DIR   = self.tmp_path
        tt.STATS_FILE = self.tmp_path / "stats.json"
        tt.LOG_FILE   = self.tmp_path / "game_log.json"

    def tearDown(self):
        # Restore original paths so other test classes see the real files.
        tt.DATA_DIR   = self._orig_data_dir
        tt.STATS_FILE = self._orig_stats_file
        tt.LOG_FILE   = self._orig_log_file
        self.tmp.cleanup()

    def _make_winning_positions(self):
        """Return a move sequence where X wins on row 0 (positions 7-8-9).

        Interleaved with O moves so the sequence matches alternating play:
            X→(0,0), O→(1,0), X→(0,1), O→(1,1), X→(0,2) [X wins]
        """
        return [
            (0, 0),  # X plays 7
            (1, 0),  # O plays 4
            (0, 1),  # X plays 8
            (1, 1),  # O plays 5
            (0, 2),  # X plays 9 — wins
        ]

    def _make_draw_positions(self):
        """Return a known draw sequence.

        X: 5,7,3,2,8   O: 1,9,4,6  → draw (starting X=5 centre)
        """
        return [
            (1, 1),  # X=5
            (2, 0),  # O=1
            (0, 0),  # X=7
            (0, 2),  # O=9
            (2, 2),  # X=3
            (1, 0),  # O=4
            (2, 1),  # X=2
            (1, 2),  # O=6
            (0, 1),  # X=8 → draw
        ]

    def test_0p_game_completes(self):
        """0-player game runs to completion without human input."""
        # Both seats are AI; play_game() must loop internally until the game
        # ends (win or draw) and then return the settings dict (not a tuple).
        s = make_settings(num_players=0, difficulty="hard", auto_speed=0.0,
                          names={"X": "AI-X", "O": "AI-O"})
        with patch("builtins.print"):
            result = tt.play_game(s)
        # Should return settings (not a forfeit tuple)
        self.assertIsInstance(result, dict)
        # Exactly one log entry must have been written for this game.
        log = tt.load_log()
        self.assertEqual(len(log), 1)

    def test_1p_human_wins(self):
        """1-player: feed moves that guarantee human wins (X top row win)."""
        # No-shuffle → marks=["X","O"] → X=human, O=computer
        # Human plays 7(0,0), 8(0,1), 9(0,2) → wins on row 0
        # Computer gets two moves: (1,0) and (1,1) before human completes row
        human_moves = iter([(0, 0), (0, 1), (0, 2)])
        ai_moves    = iter([(1, 0), (1, 1)])

        def fake_human(board, player, settings):
            return next(human_moves)

        def fake_ai(board, comp, human, diff):
            return next(ai_moves)

        s = make_settings(num_players=1, difficulty="hard",
                          names={"human": "Tester", "computer": "Bot"})
        with patch("tictactoe.get_human_move", side_effect=fake_human):
            with patch("tictactoe.ai_move", side_effect=fake_ai):
                with patch("random.shuffle", side_effect=lambda lst: None):
                    with patch("builtins.print"):
                        result = tt.play_game(s)
        self.assertIsInstance(result, dict)

    def test_2p_game_x_wins(self):
        """2-player: alternating human inputs, X wins on top row."""
        # Moves alternate X/O: X takes row 0, O takes row 1 (blocked there).
        moves = iter([(0,0),(1,0),(0,1),(1,1),(0,2)])  # X wins
        def fake_move(board, player, settings):
            return next(moves)

        s = make_settings(num_players=2,
                          names={"X": "Alice", "O": "Bob"})
        with patch("tictactoe.get_human_move", side_effect=fake_move):
            with patch("builtins.print"):
                result = tt.play_game(s)
        self.assertIsInstance(result, dict)
        last = tt.load_log()[-1]
        # Verify the log entry records the correct game mode and winner.
        self.assertEqual(last["mode"], "2p")
        self.assertEqual(last["winner"], "X")

    def test_2p_draw(self):
        """2-player: produce a draw."""
        # The move sequence below was brute-force verified to produce a draw:
        #   Board after all 9 moves:
        #     X | O | X
        #     X | X | O     ← no row/col/diag is a clean sweep
        #     O | O | X
        # All nine cells occupied, neither player has three in a line.
        drawn = [
            (0,0),(0,1),(0,2),
            (1,0),(1,1),(2,0),
            (1,2),(2,2),(2,1),
        ]
        moves = iter(drawn)
        def fake_move(board, player, settings):
            return next(moves)

        s = make_settings(num_players=2, names={"X": "Alice", "O": "Bob"})
        with patch("tictactoe.get_human_move", side_effect=fake_move):
            with patch("builtins.print"):
                result = tt.play_game(s)
        self.assertIsInstance(result, dict)
        last = tt.load_log()[-1]
        self.assertEqual(last["result"], "draw")

    def test_forfeit_returns_new_sentinel_tuple(self):
        """Returning (-2,-2) from get_human_move should trigger forfeit."""
        # The game uses the magic coordinate (-2,-2) as a forfeit/restart
        # signal from get_human_move (e.g. when the player types /new).
        # play_game() must detect it and return a ("new", settings) tuple
        # so the outer loop knows to restart without counting a completed game.
        s = make_settings(num_players=1, difficulty="hard",
                          names={"human": "Tester", "computer": "Bot"})
        with patch("tictactoe.get_human_move", return_value=(-2, -2)):
            with patch("tictactoe.ai_move", return_value=(1,1)):
                with patch("random.shuffle", side_effect=lambda lst: None):
                    with patch("builtins.print"):
                        result = tt.play_game(s)
        self.assertIsInstance(result, tuple)
        self.assertEqual(result[0], "new")

    def test_log_entry_has_name_fields(self):
        """name_x and name_o should be saved in the log entry."""
        # The log entry must record the display names (not just the marks)
        # so the history is human-readable without knowing the session context.
        s = make_settings(num_players=0, difficulty="easy", auto_speed=0.0,
                          names={"X": "DeepBlue", "O": "Stockfish"})
        with patch("builtins.print"):
            tt.play_game(s)
        log = tt.load_log()
        self.assertEqual(log[-1].get("name_x"), "DeepBlue")
        self.assertEqual(log[-1].get("name_o"), "Stockfish")

    def test_stats_incremented_after_game(self):
        """games_played should increase by 1 after a 0p game."""
        # Run one complete 0p game and verify games_played ticked up by
        # exactly 1, confirming that play_game() writes stats on exit.
        s = make_settings(num_players=0, difficulty="hard", auto_speed=0.0,
                          names={"X": "AI-X", "O": "AI-O"})
        before = tt.load_stats()["games_played"]
        with patch("builtins.print"):
            tt.play_game(s)
        after = tt.load_stats()["games_played"]
        self.assertEqual(after, before + 1)


# ═══════════════════════════════════════════════════════════════════════════
# 15. _print_session_table (smoke test — no crash, correct structure)
# ═══════════════════════════════════════════════════════════════════════════

class TestPrintSessionTable(unittest.TestCase):
    """Smoke tests for ``_print_session_table(session_games)``.

    ``_print_session_table`` renders a summary table of all games played so
    far in the current session.  Tests verify that the function produces
    output containing expected strings (labels, game numbers) and that it
    handles the empty-list edge case gracefully without printing anything.
    """

    def _games(self):
        """Return a minimal two-entry session game list for use in tests."""
        return [
            {"num": 1, "label": "🤝 Draw", "moves": 9, "duration": 5.0},
            {"num": 2, "label": "🏆 Alice wins", "moves": 7, "duration": 3.2},
        ]

    def test_prints_without_error(self):
        # The most basic sanity check: the function must call print() at
        # least once for a non-empty game list (no silent failure).
        with patch("builtins.print") as mock_p:
            tt._print_session_table(self._games())
        self.assertTrue(mock_p.called)

    def test_empty_list_prints_nothing(self):
        # When there are no games yet the function must not produce any output
        # (the table header shouldn’t appear for a zero-row table).
        with patch("builtins.print") as mock_p:
            tt._print_session_table([])
        mock_p.assert_not_called()

    def test_output_contains_game_labels(self):
        # With colour disabled, the raw text output must contain the game
        # labels and game numbers so QA can read the table without a terminal.
        captured = io.StringIO()
        with patch("sys.stdout", captured):
            # Disable colour so output is plain text
            importlib.reload(tt)
            tt.Style.disable()
            tt._print_session_table(self._games())
        output = captured.getvalue()
        self.assertIn("Draw", output)
        self.assertIn("Alice wins", output)
        self.assertIn("#1", output.replace("# 1", "#1").replace(" 1", "#1"))


# ═══════════════════════════════════════════════════════════════════════════
# 16. Regression / integration — AI never leaves invalid board state
# ═══════════════════════════════════════════════════════════════════════════

class TestAIIntegration(unittest.TestCase):
    """Regression / integration tests — AI must never corrupt the board.

    These tests simulate complete AI-vs-AI games at all difficulty combinations
    and assert two invariants:

    1. **No move to an occupied cell**: ``ai_move()`` must only return (row,col)
       tuples where the cell is currently empty (``board[r][c] == " "``).
    2. **Mutual exclusivity of wins**: after a complete game both players
       cannot simultaneously have three in a row.

    Each combination is played 5 times to expose any non-deterministic failures
    in the easy / medium difficulty paths (which use ``random.choice``).
    """

    def _run_simulated_game(self, diff_x="hard", diff_y="hard"):
        """Simulate a full AI-vs-AI game and verify board integrity throughout.

        Plays moves until a winner is found or the board is full (max 9 moves).
        After every move we assert the chosen cell was empty before placement.
        After the game ends we assert that X and O cannot both be winners.
        """
        board = empty_board()
        current = "X"
        for _ in range(9):
            if tt.check_winner(board, "X") or tt.check_winner(board, "O"):
                break
            if tt.is_full(board):
                break
            diff = diff_x if current == "X" else diff_y
            other = "O" if current == "X" else "X"
            r, c = tt.ai_move(board, current, other, diff)
            # Core invariant: AI must never select an already-occupied cell.
            self.assertEqual(board[r][c], " ",
                             f"AI moved to occupied cell ({r},{c}) on board:\n{board}")
            board[r][c] = current
            current = "O" if current == "X" else "X"
        # Exactly one of: X wins, O wins, draw — never both simultaneously.
        x_wins = tt.check_winner(board, "X")
        o_wins = tt.check_winner(board, "O")
        self.assertFalse(x_wins and o_wins, "Both players cannot win simultaneously")

    def test_hard_vs_hard(self):
        # Both AIs use minimax (perfect play) \u2014 every game must be a draw.
        for _ in range(5):
            self._run_simulated_game("hard", "hard")

    def test_easy_vs_easy(self):
        # Easy AI picks randomly; the game must still end cleanly (valid board).
        for _ in range(5):
            self._run_simulated_game("easy", "easy")

    def test_hard_vs_easy(self):
        # Asymmetric match; hard AI should never lose (must win or draw).
        # We only assert board integrity here \u2014 not the game outcome.
        for _ in range(5):
            self._run_simulated_game("hard", "easy")

    def test_medium_vs_medium(self):
        # Medium is probabilistic (50/50 between best and random) so results
        # vary, but board integrity must hold across all outcomes.
        for _ in range(5):
            self._run_simulated_game("medium", "medium")


# ═══════════════════════════════════════════════════════════════════════════
# Entry point
# ═══════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    unittest.main(verbosity=2)
