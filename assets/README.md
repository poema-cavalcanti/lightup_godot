# Pixel art goes here

This folder holds the game's pixel art. Almost all of it is **required**: the
game loads it directly (`AssetLoader.load_texture()`) and has no flat-colour
fallback, so a missing file is a load error. Required: walls and their `_lit`
strips, `floor_N` + `floor_N_lit`, `bulb.png`, the player sheets (`player_idle`,
`player_run`, `player_attack`, `player_interact`), the enemy sheets, boss tiers
1-4, `projectile.png`, the eight `border_*` pieces, the UI sheets (`buttons`,
`main_menu`, `shop_background`, `summary_background`, `inventory_background`,
`town_background`), the HUD icons, and the item art in `ItemData.gd`.

Still optional (loaded with `AssetLoader.load_optional_texture()`): cutscene art
in `assets/cutscenes/`. Some older sections below still describe fallbacks that no
longer exist -- the list above is the source of truth.

## Floor (white cells)

| File                          | What it's used for                    | Suggested size |
|--------------------------------|----------------------------------------|-----------------|
| `floor_0.png`, `floor_1.png`, ... | white cell background variants, scattered across the board for visual variety | 64x64 (square) |
| `floor_0_lit.png`, `floor_1_lit.png`, ... | that same variant's tile while the cell is lit by a bulb, swapped in in place of the plain one | 64x64 (square) |
| `floor.png`                   | single fallback floor tile, only used if no `floor_N.png` files are found | 64x64 (square) |
| `floor_lit.png`               | lit counterpart of `floor.png`, same fallback-only role | 64x64 (square) |

Variants must be numbered sequentially starting at `floor_0.png` with no
gaps — the game keeps loading `floor_1.png`, `floor_2.png`, etc. until a
number is missing, then stops. Each white cell picks a variant via a hash
of its row, column, and a per-puzzle seed, so within one puzzle the same
cell always shows the same variant (no flickering between redraws) without
the game needing to remember anything extra, while a new puzzle gets a
fresh scatter. A `floor_N_lit.png` is entirely optional per variant --
any variant without one just keeps using the old yellow-tint-on-unlit-art
behavior while lit, same as before this existed. Floor tiles still get
**tinted** red on a rule conflict regardless of lit/unlit art, via a color
multiply, so keep them light/neutral -- ideally close to white/gray -- so
that tint reads clearly.

## Walls (black cells)

| File                                  | What it's used for                     | Suggested size |
|-----------------------------------------|------------------------------------------|-----------------|
| `wall.png`                            | generic black cell (blank blockers, and a fallback for numbered clue cells that don't have their own art) | 64x64 (square) |
| `wall_0.png` ... `wall_4.png`         | a distinct tile for a black cell whose clue number is 0-4 | 64x64 (square) |
| `wall_top.png`, `wall_N_top.png`      | used instead of the plain tile whenever the cell directly below is also a wall -- a "capped" top edge rather than the tile repeating down a vertical run of walls | 64x64 (square) |
| `wall_N_lit.png`                      | used instead of the plain numbered tile while that clue is exactly satisfied (its adjacent bulb count matches N) -- switches back the moment it stops matching, whether from too few or too many | 64x64 (square) |
| `wall_N_top_lit.png`                  | both at once: a lit numbered wall that also has a wall below it | 64x64 (square) |

The clue number (drawn as white text) is only drawn when this cell fell
back to the generic `wall.png` or the plain rectangle -- any of the 4
variants from the clue's own set is assumed to already encode the number
visually, so the text is skipped whenever one of those was used.
Fallback per cell degrades from most to
least specific: top+lit → top → lit → plain `wall_N.png` → generic
`wall.png` → the plain dark rectangle if nothing exists at all. Top/lit
variants are entirely optional per clue number -- a clue with only
`wall_N.png` made just never shows anything different when capped or lit,
same as before this feature existed. `wall.png` and the clue text both
want contrast, so keep it on the darker side.

## Bulbs and the player

| File                | What it's used for                            | Suggested size |
|----------------------|-------------------------------------------------|-----------------|
| `bulb.png`          | the light bulb                                   | roughly square, transparent background |
| `player_sheet.png`  | an animated player sprite sheet (see below); also reused as-is for the walking character in Town.tscn between levels | see below |
| `player_idle_sheet.png`     | idle pose sheet (see below), looped continuously while standing still (also used in Town.tscn) | see below |
| `player_run_sheet.png`      | run pose sheet (see below), played while a movement key is held down / a hop is in progress (also used in Town.tscn) | see below |
| `player_attack_sheet.png`   | attack pose sheet (see below), briefly swapped in whenever the player lands a swing | see below |
| `player_interact_sheet.png` | interact pose sheet (see below), briefly swapped in when placing/removing a bulb, and looped continuously while blocking | see below |
| `enemy_idle_sheet.png`, `enemy_walk_sheet.png`, `enemy_attack_sheet.png`, `enemy_hurt_sheet.png`, `enemy_death_sheet.png` | animated enemy poses (see below) | see below |
| `boss_tier_N_idle_sheet.png`, `boss_tier_N_walk_sheet.png`, `boss_tier_N_attack_sheet.png`, `boss_tier_N_hurt_sheet.png`, `boss_tier_N_death_sheet.png` (N = 1-4) | the same five poses for the boss, one full set per campaign tier. The boss's ranged shot reuses the attack sheet | see below |
| `projectile.png`    | **required** (no fallback). The boss's ranged attack: a horizontal strip of 32x16 frames. Frames 1-5 play once across the flight (art points right; the game rotates it to the travel direction), frames 6-9 are an impact burst played once, upright, at the target. The split is `PROJECTILE_FLIGHT_FRAME_COUNT` in `CombatManager.gd` | 288x16 (9 frames of 32x16), transparent background |

All the enemy/boss sheets and `projectile.png` are drawn as-is with no tint
(unlike the bulb/floor/player art below). Normal enemies are drawn at about
0.55 of a cell and bosses at about 0.85, whatever the source image's own size.
Neither enemy type needs to encode health -- both already get a health bar
drawn above them automatically. `projectile.png` is described in its table row.

### Animated enemy/boss sheets

Each enemy/boss sheet is a grid of equal-size square frames: frames run left to
right, and there are **4 rows, one per facing direction -- down, up, left,
right, in that order** (no mirroring; left and right are separate rows). All of
these are **required**; there is no static-image or drawn-shape fallback.

- **Enemy** sheets (`enemy_{idle,walk,attack,hurt,death}_sheet.png`) have a
  fixed frame count in `Enemy.gd`'s `ANIMS` table, so each must have exactly that
  many columns. Current art is 64x64 per frame.
- **Boss** sheets (`boss_tier_N_{idle,walk,attack,hurt,death}_sheet.png`, N = 1-4:
  tier 1 = levels 1-3, tier 2 = 4-6, tier 3 = 7-9, tier 4 = level 10; outside the
  campaign it is always tier 1) have their frame count **read from each image**
  (width / (height / 4)), so tiers may differ. Tiers 1-3 are 64x64 per frame,
  tier 4 is 128x128; every tier is drawn at the same on-screen size.

| Sheet    | Enemy frames | Boss frames (T1-3 / T4) | How it plays |
|----------|--------------|-------------------------|--------------|
| `idle`   | 6  | 4 / 4   | looped while standing still |
| `walk`   | 8  | 6 / 6   | looped while hopping between tiles |
| `attack` | 9  | 12 / 10 | played once per melee hit (boss: also each ranged shot) |
| `hurt`   | 5  | 4 / 4   | played once when damage lands |
| `death`  | 10 | 11 / 13 | played once when it dies |

One-shot sheets are stretched to a fixed duration (attack 0.25s, hurt 0.25s,
death 0.5s), so gameplay timing always matches the art whatever the frame
count. If you change an enemy sheet's frame count, update `ANIMS` to match.

Which sheet shows is chosen by priority: death > hurt > attack (a boss's
ranged shot also plays the attack sheet -- there's no separate ranged sheet) >
walk > idle. A dying enemy also shrinks and fades out over the death animation.

Note: `enemy_run_sheet.png` and `boss_tier_N_run_sheet.png` are **not read by
anything** right now. A run pose is planned, driven by distance to the player;
until then the walk sheet is used for movement.

### Which player sheet is drawn

Checked in this order, first match wins (each step is skipped if its file is
missing): attack sheet while a swing is playing → interact sheet while a
bulb is being placed/removed → interact sheet (looped) while blocking → run
sheet while a hop is in progress → idle sheet while standing still → the
plain `player_sheet.png` walk frames → `player.png` static sprite → the
plain shape.

### Player sprite sheet layout

`player_sheet.png` is a grid of 32x32 frames, 4 columns wide. The game only
reads rows 0, 2, and 4 -- down, right, and up -- so the sheet can have
other rows in between (e.g. diagonals) purely for your own reference/reuse
in an art tool; they're just never drawn. There's no "facing left" row at
all: the game reuses row 2 (right) and flips it horizontally at draw time,
so draw that row facing right and left comes for free.

- Row 0: facing down
- Row 2: facing right (also used, mirrored, for facing left)
- Row 4: facing up
- Each used row's 4 columns are that direction's walk-cycle frames, played in order

The game only animates through the frames while a player is actually mid-move
between cells; it holds on frame 0 (the first column) while standing still,
so column 0 of each row also doubles as that direction's idle pose.

If you don't want to draw a full walk cycle, a sheet where all 4 columns in
each row are identical still works fine — you'll just get a static sprite
that changes to face the direction you're moving, which is already most of
the way to "more motion" over a single fixed image.

### Idle and run sprite sheets

`player_idle_sheet.png` and `player_run_sheet.png` follow the same
32x32-frame, down/right/up (row 0/2/4, left mirrored from right) layout as
`player_sheet.png` above, just with their own column counts:

- `player_idle_sheet.png`: 4 columns per row, looped continuously (at a
  slower pace than movement) for as long as the player is standing still.
- `player_run_sheet.png`: 6 columns per row, looped for as long as a hop is
  actually in progress -- i.e. while a movement key is held down.

Either is entirely optional and independent of the other and of
`player_sheet.png`: a missing run sheet falls back to `player_sheet.png`'s
own walk-cycle frames while moving, and a missing idle sheet falls back to
frame 0 of whichever sheet is otherwise in use while standing still (so a
project with none of the new sheets looks exactly like it did before they
existed). Both are tinted per-player the same way `player_sheet.png` is.

### Attack and interact sprite sheets

`player_attack_sheet.png` and `player_interact_sheet.png` follow the exact
same 32x32-frame, down/right/up (row 0/2/4, left mirrored from right) layout
as `player_sheet.png` above -- same row meanings, same left-flip trick, just
a different number of columns:

- `player_attack_sheet.png`: 7 columns per row, played once start-to-finish
  whenever the player successfully lands a melee hit (synced to every peer
  the same way the existing hit-flash ring already is).
- `player_interact_sheet.png`: 4 columns per row, used two ways -- played
  once start-to-finish when the player places or removes a bulb, and looped
  continuously (cycling its 4 frames) for as long as the player is holding
  block.

Either file is entirely optional and independent of the other and of
`player_sheet.png`: missing one just means that moment keeps using the
regular walk sheet's current pose instead of swapping in a dedicated one.
Both are tinted per-player the same way `player_sheet.png` is, so draw them
in white/light gray like the walk sheet rather than pre-colored.

## General notes

- During a level (Game.tscn), the game automatically switches to
  nearest-neighbor texture filtering the moment it finds any of the
  gameplay art: walls, floors, bulbs, player/enemy/boss art and
  sheets, the projectile, border pieces, or `icon_gold.png`. That keeps
  pixel art crisp instead of going blurry (Godot's default is a smoothing
  filter, which looks bad on pixel art). `background.png` and the other
  HUD icons alone don't trigger it. Town.tscn, cutscenes, and the
  shop/inventory panels don't set a filter of their own, so they use
  Godot's default.
- None of this affects puzzle rules or solving — it's purely how an
  already-known cell/player state gets drawn.

## Board border

A ring of border tiles drawn *around* the puzzle, one full cell thick on every
side -- the border adds to the grid rather than sitting on top of it. For a
2x2 board it's effectively a 4x4 grid whose outer ring is border (B):

```
BBBB
B..B
B..B
BBBB
```

Every piece is a 64x64 tile, drawn at the same size as a normal cell
(`Game.CELL_SIZE`), so nothing overlaps the board. Tiles are placed with the
same math as the cells, so the ring scrolls with the board on big puzzles and
only appears once the camera reaches that edge. Edges are drawn first, corners
on top; any missing piece is simply skipped.

| File                          | What it's used for                        | Size |
|--------------------------------|--------------------------------------------|------|
| `border_top.png`, `border_bottom.png` | one tile per column, in the row above/below the board | 64x64 |
| `border_left.png`, `border_right.png` | one tile per row, in the column left/right of the board | 64x64 |
| `border_corner_top_left.png`, `border_corner_top_right.png`, `border_corner_bottom_left.png`, `border_corner_bottom_right.png` | the four corner cells | 64x64 |

Border art is drawn as-is with no tint.

The border counts as extra rows and columns of the world for the camera, so no
screen space is ever reserved for it: mid-board the whole play area shows board
cells, and the ring only appears as the outermost row/column once the camera
scrolls to that edge. (When the whole board fits on screen, the full ring is
visible.) With no border art, none of this applies and the layout is exactly as
it was.

## Background and HUD icons

The window background is the flat `Background` ColorRect in `HUD.tscn` (no
`background.png`), and the HUD icons (hourglass, heart, default staff/hat, gold)
are assigned directly on the nodes in `HUD.tscn`.

The minimap (top-right of the HUD) is deliberately always flat colors and
clue numbers, with no art lookups — it's meant to read at a glance, not
match the main board's art style.


## Town (between levels)

| File                     | What it's used for                            | Suggested size |
|---------------------------|-----------------------------------------------|-----------------|
| `town_background.png`   | the whole Town.tscn backdrop -- houses, road, everything | exactly 1280x768 (20x12 tiles at 64px each, matching Town.gd's TOWN_GRID) |

Falls back to a plain dark fill if missing. `player_sheet.png`,
`player_idle_sheet.png`, and `player_run_sheet.png` (see above) are all
reused as-is for the walking character here, tinted the same blue as
Player 1 in a level, with the same idle/run/walk animation and directional
facing -- so custom player art shows up in both places automatically, no
separate town-specific player art needed. (The attack and interact sheets
aren't used in Town.) Equipped-armor overlays are drawn here too.

Town.gd's walkable layout (TOWN_GRID) is a plain string grid, not pixel
art -- '#' blocks movement, '.' is open ground, 'D' is a shop door (there are two: the Weapons Shop and the Shields Shop) — so it
has to be hand-edited in the script to line up with whatever
`town_background.png` actually shows, rather than being something a new
image file alone can change.


## Items and equipment (shop + inventory)

Every purchasable item is defined in ItemData.gd (id -> name, description,
cost, and the fields below), not a fixed filename convention here -- adding
a new item is a script edit, not just dropping in art. What each item's
data can point at:

| Field           | What it's used for                            | Suggested size |
|-----------------|------------------------------------------------|-----------------|
| `icon`          | the item's picture in the shop and inventory panels (the Wizard Hat uses `hat_0_store_icon.png`) | roughly square, e.g. 64x64-ish after scaling; transparent background |
| `overlays`      | armor only -- how the item looks equipped on the character: sheet kind -> direction -> filename (see below) | see below |

Items also carry non-art fields (name, description, cost, `slot`, and
gameplay effects such as `melee_damage_reduction`) -- see ItemData.gd. The
two placeholder items (`sample_weapon`, `sample_armor`) have no art.

All art fields are optional per item: no `icon` just shows the item as text-only, and
no `overlays` just means equipping it changes nothing visually.

Each overlay file is a single-row strip of 32-pixel-wide frames (any
height), one frame per column, matching the frame count of the body sheet
it goes with: 4 for walk/idle/interact, 6 for run. One strip per sheet kind
(`walk`, `idle`, `interact`, `run`) per direction (`down`, `right`, `up`);
there's no `left`, since left-facing mirrors `right` the same way the
player sheets do. The hat's files are named `hat_0_<kind>_<down|side|up>.png`.

Each body sheet poses the head at a slightly different height, so where the
art's own (0, 0) pixel lands relative to the top of the player frame
depends on the sheet kind -- these offsets are a property of the body
sheets, not the item, and live in Player.gd/Town.gd
(`OVERLAY_TOP_OFFSET_PIXELS`):

| Sheet kind | Pixels above the body frame's top edge |
|------------|-----------------------------------------|
| walk       | 1 |
| idle       | 2 |
| interact   | 0 |
| run        | 2 |
| attack     | 0 |

There's no dedicated attack overlay art yet, so `attack` borrows the `run`
strips (`OVERLAY_ART_FALLBACK` in ItemData.gd) while keeping its own 0px
offset. Attack's body sheet has 7 frames but run's art has 6, so the hat's
frames are spread evenly across the attack's rather than indexing past the
end. Drop in real attack art by adding an `attack` entry to the item's
`overlays` -- it takes priority over the fallback automatically.


## Cutscenes (optional)
Drop an image named after the cutscene's scene_key into assets/cutscenes/ (e.g. assets/cutscenes/chapter_1_intro.png) to show it in the top scene panel. Falls back to a plain colored panel with the chapter title if not found. Scene keys in use: chapter_1_intro, after_level_1, after_level_2, boss_path_1..7, ending_1..7. (`assets/cutscenes/` is currently empty, so every cutscene uses the colored-panel fallback.)
