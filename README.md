# Light Up Puzzle - Godot Prototype

A Light Up (Akari) puzzle game with a story campaign, real-time combat, a shop town, an endless mode, and cooperative multiplayer for up to 4 players. Leaving two bulbs lighting each other spawns enemies, and running out of time spawns a boss, so the puzzle is also a fight.

## How to run

1. Install Godot 4.7 from godotengine.org (the project is set up for 4.7, Forward Plus renderer) — it's free, no installer needed on most platforms.
2. Open Godot, click "Import", and select the `project.godot` file in this folder.
3. Press F5 (or the Play button, top-right) to run. It opens on the **Main Menu**.

To test multiplayer on one machine, run two (or more) separate instances of the project — either export a build and launch it alongside the editor, or use Godot's "Run Multiple Instances" debug option — and have one Host while the other(s) Join to `127.0.0.1`. Steam multiplayer is covered in [`STEAM_SETUP.md`](STEAM_SETUP.md).

## Main Menu

- **Campaign** / **Continue Campaign** — the story mode (see below). Once a campaign is in progress this becomes Continue Campaign, and a **Start New Campaign** button appears next to it.
- **Endless Mode** — locked until you complete the campaign once.
- **Multiplayer** — opens the Lobby (see below).
- **How to Play** — the rules and your current key bindings.
- **Stats** — best time per campaign level, endings seen (out of 7) and your Endless Mode records.
- **Settings** — fullscreen, window size and key rebinding.
- **Quit Game**.
- **F11** toggles fullscreen at any time, in any scene.

## Game modes

### Campaign (singleplayer)

A 10-level story campaign. The flow between levels is:

Cutscene → level → Town → cutscene → level → Town → …

- Each level has a 5-minute clock. If it runs out while any cell is still unlit, a **boss** spawns. Correctly satisfying a numbered clue for the first time adds 30 seconds to the clock.
- Whether you summoned the boss on each level is recorded, and the history decides which branch of the story you get (the post-level-1 and post-level-2 cutscenes have their own branches, later ones split 7 ways, and there are 7 endings).
- Finishing a level earns **gold** (time left, enemies killed, boss kill). Gold is spent in the **Town** shops, and bought gear shows in the inventory (**I**), where weapons and armor can be equipped.
- Progress (current level, boss history, gold, inventory, equipment) is saved when you advance, so quitting to the Main Menu and choosing Continue Campaign resumes where you left off.

### Endless Mode (singleplayer)

Chain freshly generated puzzles back to back. Your longest streak and best survival time are saved and shown on the Stats screen. The run ends when you die.

### Multiplayer (cooperative, up to 4 players)

One shared board, one set of bulbs, one win condition. See the next section.

## Combat

- Two bulbs that can see each other are a conflict. If a conflict stays unresolved for 5 seconds, an enemy spawns at it, and another every 5 seconds after that.
- Enemies walk toward the nearest player and attack when adjacent. Solving the puzzle clears every enemy.
- You have 100 health. Attack hits an adjacent enemy for 5 damage (normal enemies have 10 health, the boss 50). Blocking (hold) takes 25% less melee damage and no ranged damage, but you can't attack while blocking.
- The boss attacks in melee when adjacent, or at range along a clear row or column. Its ranged attack can't pass through walls. Boss art gets more imposing every few levels (tiers cover levels 1–3, 4–6, 7–9 and 10).

## Controls

All of these except F11 and Escape can be rebound in Settings (or the in-game pause menu).

- **W / A / S / D**: walk your character around the grid, one cell per key press (hold to keep moving). Black cells are walls — you can't walk through them.
- **P**: place a bulb at your feet, or pick it back up if one's already there.
- **Space**: attack an adjacent enemy.
- **Shift** (hold): block.
- **I**: open the inventory (Town, Endless Mode and multiplayer; in the multiplayer Town the attack key also fights other players) to equip or unequip what you've bought.
- **Escape**: pause menu. In singleplayer it pauses the clock and combat; in multiplayer it's just your own local menu and the game keeps running.
- **F11**: toggle fullscreen.
- **Reset** (pause menu, host/singleplayer only): clears all bulbs and walks everyone back to their starting corner.
- **Check Answer** (pause menu): explicitly verifies the current board against the rules and reports pass/fail (separate from the always-on lit-count status).
- **Next Level** / **Continue** (after solving a puzzle): in the campaign this goes on to the Town; in Endless Mode and multiplayer it loads a freshly generated, uniquely solvable puzzle (the next one is generated on a worker thread while you play, so it's usually instant). **Try Again** appears if the whole party is defeated.

In multiplayer, your own avatar has a white ring around it so you can tell it apart from your teammates' (each player gets a fixed color: blue, pink, green, orange).

## Multiplayer (networked, up to 4 players, cooperative)

This uses Godot's high-level multiplayer API in a straightforward client-server model, with two transports:

- **Steam** (when the GodotSteam extension is installed and the Steam client is running): the host sends friend invites from the Lobby; friends join through the invite. Setup and the first-test checklist are in [`STEAM_SETUP.md`](STEAM_SETUP.md). The Steam transport has not been run yet.
- **LAN / direct IP** (always available): **Host Game** listens on UDP port `8910` and shows your LAN address and port. Up to 3 more players can **Join Game** by entering it. On the same Wi-Fi/LAN that's usually a `192.168.x.x` or `10.x.x.x` address; playing over the open internet needs the host to port-forward `8910`.

Both host and joiners see a live **connected players** list in the lobby. Only the **host** can click **Start Game** — it generates a puzzle, assigns each connected player a starting corner (top-left, top-right, bottom-left, bottom-right, snapped to the nearest white cell if the exact corner is black), and sends everyone into the same board.

**The host is authoritative** for all shared state: every player's input is sent to the host, the host validates and applies it, then broadcasts the result back to everyone (itself included) so all boards can never disagree. All combat (enemy spawning, AI, attack resolution, respawns) is simulated only on the host as well. In practice this means non-host players see a small round-trip delay between pressing a key and seeing it happen — normal for this kind of networking model, and unnoticeable on a LAN.

Reset and Continue are host-only (clients see a note instead of the buttons); Check Answer works identically for everyone since the board state is always in sync. Endless and multiplayer gold, purchases and equipment are session-only and tracked per player: a level's earnings go to everyone, a purchase only comes off the buyer's gold, and teammates can see each other's equipped armor.

**Multiplayer Town:** after a solved board, the host's **Continue** takes everyone to a shared Town (instead of straight to the next board). Everyone walks it together, and you can shop at either door and use the inventory (**I**). Unlike in the puzzles, players can fight each other here with the attack key; a player who's "killed" just respawns at the spawn tile at full health, with no penalty. Shopping happens only here in multiplayer (Endless Mode keeps its Shop button on the solved screen). Saying **Yes** at a shop door hides you (invisible and impossible to hit) until you close the shop. Walking off the left or right end of the road leaves town, and once every player has left, the next board loads for everyone. (The next puzzle is generated while you're in town.)

### Known limitations (prototype-level, worth hardening later)

- No reconnect flow — if a client disconnects mid-game, their avatar just stops moving; they'd need to rejoin from the Main Menu into a fresh game.
- No mid-game join — the player roster locks in when the host clicks Start Game.
- No lag compensation / client-side prediction — movement waits for the host's round trip rather than moving instantly and correcting later. Fine on a LAN; would feel sluggish over a slow connection.
- No relay/NAT-punchthrough service for the LAN transport — play across the open internet needs the host to forward port 8910 (or use Steam).

## Rules implemented

- A bulb lights every cell in its row and column until a black cell (or the grid edge) blocks the light.
- Two bulbs that can see each other (same row/column, no black cell between them) are invalid — they're highlighted red.
- A numbered black cell must have exactly that many bulbs on its (edge-adjacent) neighboring cells.
- The puzzle is solved when: every white cell is lit, no bulbs conflict, and every number clue is satisfied.

## Files

The project is organized around a few scenes and a set of single-purpose scripts. Most of the gameplay in `Game.gd` is split into manager classes that talk back to it through a `game` reference.

**Scenes and screens** (UI layout lives in the `.tscn` files; scripts hold behavior):

- `MainMenu`, `Lobby`, `Settings`, `HowToPlay`, `Stats`, `Cutscene` — standalone menu-style screens. They all extend `MenuScreen.gd` (window sizing, F11, Back button); shared literal values are in `Constants.gd`.
- `Game` — the puzzle level itself (campaign, Endless and multiplayer).
- `Town` — the walkable area between campaign levels, with two shops and the `InventoryPanel`.
- `HUD`, `PauseMenu`, `EarningsPanel` and the item/shop scenes (`InventorySlot`, `InventoryTile`, `ShopItemCard`, `PauseMenuRowButton`) — overlays and reusable pieces.

**Autoloads** (registered in `project.godot`):

- `SteamBridge.gd` — optional GodotSteam integration (Steam lobbies and invites).
- `NetworkManager.gd` — owns the multiplayer connection, the canonical connected-player list, and hands the puzzle and spawn positions across the scene change into `Game.tscn`.
- `SaveManager.gd` — persists campaign progress, best times, Endless records and endings seen (Godot `ConfigFile`).
- `CampaignManager.gd` — tracks progress through the campaign, picks the next cutscene, and handles gold, inventory and equipment.
- `SettingsManager.gd` — display and key-binding preferences (`user://settings.cfg`); the one place every scene goes through to size its window.

**Game managers** (split out of `Game.gd`):

- `PuzzleBoard.gd` — parsing the puzzle, bulb placement, lit cells, conflicts and the solved check.
- `Player.gd` / `Enemy.gd` / `CombatManager.gd` — player movement and input, enemy and boss AI and animation, attacks, damage and projectiles.
- `HUDManager.gd` / `GameUIManager.gd` / `PauseMenuManager.gd` — in-play overlays (minimap, popups, hints, win animation), window layout and win/lose state, and the pause menu.
- `AssetLoader.gd` — loads and caches all the pixel art. Required art has no fallback, so a missing file is a load error; only cutscene art is optional.

**Puzzle logic** (all `class_name`d, so Godot registers them globally — no `preload()` needed):

- `Solver.gd` (`LightUpSolver`) — a constraint-propagation + backtracking solver with a node budget so large searches degrade safely instead of hanging. `verify_answer()` checks an already-placed board directly with no search — it's the single rule-checking function used by the live status and by Check Answer, so there's exactly one definition of "correct" in the project.
- `Generator.gd` (`LightUpGenerator`) — builds a random layout, derives clues from a valid solution, confirms the puzzle is uniquely solvable, then trims clues while it stays unique. `GenerationJob.gd` runs it on a worker thread.
- `BoardUtil.gd` — turns a puzzle's string encoding into player spawn corners. `GridGeometry.gd` — shared grid/camera math used by both the level and the Town.
- `MoveRepeater.gd` — hold-to-move input timing, shared by `Player.gd` and `Town.gd`.

**Data and UI helpers:**

- `CampaignData.gd` — the 10 levels (with their interchangeable puzzle layouts), all cutscene text, and the boss-history → story-branch logic.
- `ShopManager.gd` / `LoadoutManager.gd` — host-authoritative per-player purchases and equipment for Endless and multiplayer.
- `TownNet.gd` — the shared multiplayer Town (synced walking, town fights, shop hiding, leaving together); `SessionEconomy.gd` carries a match's gold and items between a level and the Town.
- `ItemData.gd` — the item catalog, shop stock, icons and armor overlay art.
- `PixelButton.gd` / `PixelPanel.gd` — pixel-art UI skinning.

**Other:**

- `assets/` — all the art (see [`assets/README.md`](assets/README.md) for every filename, sheet layout and frame convention).
- `fonts/`, `addons/` (GodotSteam, Script-IDE).
- `STEAM_SETUP.md` — Steam multiplayer setup.

## Where the puzzle lives

Puzzles are arrays of strings. The default board (used as the very first Endless Mode board) is at the top of `Game.gd`, and each campaign level's layouts are in `CampaignData.LEVELS`:

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

`.` = white cell, `#` = black cell (no clue), and a digit `0`-`4` = black cell with that bulb-count clue. Everything else (parsing, rendering, rules, spawn corners) adapts automatically to whatever size grid ends up in `current_puzzle_rows` — including the larger boards Endless Mode and multiplayer matches generate at runtime.
