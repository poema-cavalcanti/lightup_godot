# Light Up Puzzle - Godot Prototype

## How to run

1. Install Godot 4.x (4.3+ recommended) from godotengine.org — it's free, no installer needed on most platforms.
2. Open Godot, click "Import", and select the `project.godot` file in this folder.
3. Press F5 (or the Play button, top-right) to run. It opens on the **Main Menu**.

To test multiplayer, run two (or more) separate instances of the project — either export a build and launch it alongside the editor, or use Godot's "Run Multiple Instances" debug option — and have one Host while the other(s) Join to `127.0.0.1`.

## Main Menu

- **Singleplayer** — jumps straight into a single-player board.
- **Multiplayer** — opens the Lobby (see below).
- **Toggle Fullscreen** — also bindable any time with **F11**, in the menu, lobby, or game.

## Multiplayer (networked, up to 4 players, cooperative)

This uses Godot's high-level ENet multiplayer API in a straightforward client-server model:

- **Host Game**: starts listening on UDP port `8910` and shows your LAN address (and the port) to share with friends. Up to 3 more players can join (4 total).
- **Join Game**: enter the host's address and connect. On the same Wi-Fi/LAN, that's usually a `192.168.x.x` or `10.x.x.x` address; playing over the open internet needs the host to port-forward `8910` (not automated here — this is a prototype, not a matchmaking service).
- Both host and joiners see a live **connected players** list in the lobby.
- Only the **host** can click **Start Game** — it generates a 10x10 puzzle, assigns each connected player a starting corner (top-left, top-right, bottom-left, bottom-right, snapped to the nearest white cell if the exact corner is black), and sends everyone into the same board.

**The host is authoritative** for all shared state: every player's WASD/P/M input is sent to the host, the host validates and applies it, then broadcasts the result back to everyone (itself included) so all boards can never disagree. In practice this means non-host players see a small round-trip delay between pressing a key and seeing it happen — normal for this kind of networking model, and unnoticeable on a LAN.

It's fully **cooperative** — everyone shares one board, one set of bulbs, and one win condition. Reset and New Puzzle are host-only (clients see a note instead of the buttons); Check Answer works identically for everyone since the board state is always in sync.

### Known limitations (prototype-level, worth hardening later)

- No reconnect flow — if a client disconnects mid-game, their avatar just stops moving; they'd need to rejoin from the Main Menu into a fresh game.
- No mid-game join — the player roster locks in when the host clicks Start Game.
- No lag compensation / client-side prediction — movement waits for the host's round trip rather than moving instantly and correcting later. Fine on a LAN; would feel sluggish over a slow connection.
- LAN/port-forwarded WAN only — there's no relay/NAT-punchthrough service, so play across the open internet needs the host to forward port 8910.

## Controls (same in singleplayer and multiplayer)

- **WASD**: walk your player character around the grid, one cell per key press. Black cells are walls — you can't walk through them.
- **P**: place a bulb at your feet, or pick it back up if one's already there.
- **M**: toggle a pencil "mark" at your feet (a note to yourself, e.g. "don't put a bulb here") — purely a scratchpad, has no effect on solving.
- **F11**: toggle fullscreen.
- **Reset** button (host/singleplayer only): clears all bulbs and marks, and walks everyone back to their starting corner.
- **New Puzzle** button (host/singleplayer only): generates a fresh, randomly-laid-out, uniquely-solvable puzzle at the current grid size. Generation is a synchronous backtracking search, so it can take a moment — the label switches to "Generating..." while it works.
- **Check Answer** button: explicitly verifies the current board against the rules and reports pass/fail (separate from the always-on lit-count status above it).

In multiplayer, your own avatar has a white ring around it so you can tell it apart from your teammates' (each player gets a fixed color: blue, pink, green, orange).

## Files

- `MainMenu.gd` / `MainMenu.tscn` — entry point (`run/main_scene`). Singleplayer / Multiplayer / Fullscreen.
- `Lobby.gd` / `Lobby.tscn` — host/join flow and the connected-players list.
- `NetworkManager.gd` — **autoload singleton** (registered in `project.godot`). Owns the ENet connection, the canonical connected-player list, and hands the puzzle + spawn positions across the scene transition into `Game.tscn` when the host starts a match.
- `Game.gd` / `Game.tscn` — the actual puzzle: grid state, rendering, input, and (new) 1-4 player support with the host-authoritative networking layer described above.
- `BoardUtil.gd` (`BoardUtil`) — shared helper that turns a puzzle's string encoding into player spawn corners (nearest white cell to each corner via BFS). Used by `NetworkManager` (to compute spawns _before_ `Game.tscn` even exists) and by `Game.gd` (to re-spawn everyone on Reset / New Puzzle).
- `Solver.gd` (`LightUpSolver`) — a constraint-propagation + backtracking solver. `solve(grid, rows, cols, max_solutions, max_nodes)` searches for up to N solutions with a node budget so large/lightly-constrained searches degrade safely instead of hanging (`max_solutions=1` checks "is this solvable at all", `max_solutions=2` checks "is the solution unique"). `verify_answer(grid, rows, cols, bulbs)` checks an already-placed board directly with no search — this is the single rule-checking function used by the live in-game status and by "Check Answer", so there's exactly one definition of "correct" in the whole project.
- `Generator.gd` (`LightUpGenerator`) — builds a random black-cell layout, uses the solver to find a valid bulb placement, derives number clues from it, confirms the fully-clued puzzle is uniquely solvable, then randomly trims clues one at a time (re-checking uniqueness after each removal, with a smaller node budget, keeping the clue if a check is inconclusive) so not every black cell ends up numbered.

`BoardUtil.gd`, `Solver.gd`, and `Generator.gd` all declare `class_name`, so Godot registers them globally — no `preload()` needed anywhere in the project.

## Rules implemented

- A bulb lights every cell in its row and column until a black cell (or the grid edge) blocks the light.
- Two bulbs that can see each other (same row/column, no black cell between them) are invalid — they're highlighted red.
- A numbered black cell must have exactly that many bulbs on its (edge-adjacent) neighboring cells.
- The puzzle is solved when: every white cell is lit, no bulbs conflict, and every number clue is satisfied.

## Where the puzzle lives

The singleplayer default grid is a small array of strings at the top of `Game.gd`:

```gdscript
const DEFAULT_PUZZLE_ROWS = [
	"...3.1....",
	".......1..",
	".#.#..3...",
	"..#....#.#",
	"3...##....",
	"....##...#",
	"#.2....2..",
	"...2..1.2.",
	"..2.......",
	"....#.0...",
]
```

`.` = white cell, `#` = black cell (no clue), and a digit `0`-`4` = black cell with that bulb-count clue. Everything else (parsing, rendering, rules, spawn corners) adapts automatically to whatever size grid ends up in `current_puzzle_rows` — including the larger boards New Puzzle or a multiplayer match generate at runtime.
