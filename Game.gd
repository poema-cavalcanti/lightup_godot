extends Node2D

# ---------------------------------------------------------------------------
# LIGHT UP (Akari) PUZZLE
#
# Grid encoding (one string per row):
#   '.'   -> white cell (needs to be lit)
#   '#'   -> black cell, no number
#   '0'-'4' -> black cell with a bulb-count clue
#
# Works in two modes:
#   - Singleplayer: everything below runs locally, no networking involved.
#   - Multiplayer: NetworkManager hands us a puzzle + starting positions
#     after the Lobby's "Start Game". The HOST is authoritative for all
#     shared state (bulbs, player positions, health, enemies). Every
#     player's movement/place-light/attack input is sent to the host (directly, if you
#     ARE the host; over RPC otherwise), the host applies and validates it,
#     then broadcasts the result to everyone (itself included) so all
#     boards stay identical.
#
# Combat: while conflicting_bulbs is non-empty (a rule violation on the
# board), a conflict timer counts up. Every CONFLICT_SPAWN_INTERVAL seconds
# of *continuous, unresolved* conflict, one enemy spawns at a conflicting
# cell. Enemies walk one grid step at a time toward the nearest non-
# defeated player and attack when adjacent; players fight back with Space.
# Solving the puzzle (no conflicts, fully lit, all clues satisfied) clears
# every enemy as a reward. All combat simulation (spawning, AI movement,
# attack resolution, respawn timing) is host-only, exactly like the puzzle
# rules -- clients only ever render synced state.
#
# Pixel art: all art lives in res://assets/ and is loaded by AssetLoader (see
# assets/README.md); the files below are REQUIRED -- there are no flat-colour
# fallbacks any more:
#   - wall.png / wall_0.png..wall_4.png : black cell tiles, generic and
#     per-clue-number, each with a wall_lit.png / wall_N_lit.png animation
#     strip (horizontal strip of square frames) shown while lit.
#   - floor_0.png, floor_1.png, ...     : white cell tile variants (each with a
#     floor_N_lit.png), picked per-cell by a hash of (row, col, puzzle) so the
#     scatter looks random but is stable (no flicker) and identical on every peer.
#   - bulb.png                          : tinted red on a conflict. May be an
#     animated strip of square frames (see bulb_frame_count).
#   - player_idle_sheet.png, player_run_sheet.png, player_attack_sheet.png,
#     player_interact_sheet.png         : per-direction row sheets (down/right/
#     up, left mirrored from right), tinted per player. Idle loops while
#     standing still, run plays while a hop is in progress, attack/interact
#     are brief one-shots (interact also loops while blocking).
#   - enemy_*_sheet.png, boss_tier_N_*_sheet.png : animated enemy/boss sheets.
#   - projectile.png, border_*.png      : required.
#
# Player and enemy movement is logically instant (row/col update
# immediately, so rules/combat never wait on animation) but visually eased
# over MOVE_ANIMATION_DURATION via a separate "visual_position" that
# _process() interpolates toward the logical position -- this is also what
# drives the player sprite sheet's facing direction and walk-cycle frame.
# ---------------------------------------------------------------------------

const DEFAULT_PUZZLE_ROWS: = [
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

const MARGIN: int = 24
const HUD_HEIGHT: int = 110  # reserved top strip: hamburger menu, status icons, minimap
const GENERATOR_DENSITY: float = 0.22

# Stone border: a full ring of border tiles drawn *around* the board, one
# cell thick on every side -- for a 2x2 board it's a 4x4 grid whose outer ring
# is border (see _draw_border and assets/README.md). Each border tile is
# drawn at CELL_SIZE x CELL_SIZE, so the art is meant to be 64x64 like every
# other tile.

# The very first board of a run (DEFAULT_PUZZLE_ROWS above for Endless,
# Lobby.gd's MULTIPLAYER_ROWS/COLS for Multiplayer) is always 10x10; every
# new-puzzle advance after that -- in both Endless and Multiplayer, which share
# this same button/handler -- picks a random size from here instead.
const SUBSEQUENT_PUZZLE_SIZES: Array[Vector2i] = [
	Vector2i(10, 10), Vector2i(14, 14), Vector2i(25, 25),
]

# --- Shared across multiple managers, kept central rather than duplicated --
const COMBAT_MAX_HEALTH: int = 100
const CONFLICT_SPAWN_INTERVAL: float = 5.0
const RESPAWN_DURATION: float = 10.0
const MOVE_ANIMATION_DURATION: float = 0.15
const LEVEL_TIME_LIMIT: float = 300.0  # 5 minutes
const LEVEL_TIMER_BONUS_SECONDS: float = 30.0  # extends the boss deadline when a clue is freshly satisfied

var rows: int
var cols: int
var grid: Array = []              # grid[row][col] = {type, number}
var bulbs: Array = []             # bulbs[row][col] = bool
var lit: Array = []               # lit[row][col] = bool (computed each frame)
var wall_lit: Array = []          # wall_lit[row][col] = bool: black cell is in line of sight of at least one bulb
var conflicting_bulbs: Dictionary = {}  # {[row,col]: true} bulbs that illuminate another bulb
var error_flash_cells: Array = []  # [[row,col], ...] flagged by Check Answer when not yet solved
var error_flash_timer: float = 0.0
const ERROR_FLASH_DURATION: float = 1.5
var current_puzzle_rows: PackedStringArray = DEFAULT_PUZZLE_ROWS
var players: Array[Dictionary] = []  # index == player_index, see _create_player_state()
var my_player_index: int = 0

var enemies: Array[Dictionary] = []  # see _create_enemy_state()
var next_enemy_id: int = 0
var conflict_timer: float = 0.0
var next_enemy_spawn_threshold: float = CONFLICT_SPAWN_INTERVAL
var level_timer: float = 0.0
var boss_spawn_evaluated: bool = false
var boss_was_summoned_this_level: bool = false  # feeds CampaignManager.record_level_result()
var boss_killed_this_level: bool = false  # feeds CampaignManager.credit_level_earnings() -- see CombatManager._damage_enemy_by_id
var enemies_killed_this_level: int = 0  # ditto, regular (non-boss) kills only
var level_earnings: Dictionary = {}  # this level's gold breakdown, set once on solve -- see GameUIManager._update_status()
var earnings_credited: bool = false  # this board's earnings have been paid out already, so un-solving and re-solving it can't pay twice. Reset only when a NEW puzzle loads (not on Reset -- or Reset would be a re-farm button).

# --- Endless Mode session stats (see SaveManager.record_endless_run) -------
var next_job: GenerationJob = null  # background-generated next Endless/host puzzle
var generating_new_puzzle: bool = false
# Gold in Endless / multiplayer, one entry per player (index == player_index). Session-only: never saved,
# gone when the Game scene closes. The campaign uses CampaignManager.gold instead. Deliberately NOT a field of
# players[i]: those dictionaries are rebuilt from scratch on every Reset, new puzzle and respawn.
var player_gold: Array[int] = []
# What each player has bought this session, parallel to player_gold: item_id -> quantity. Same rules (session-only,
# kept out of players[i]).
var player_inventory: Array[Dictionary] = []
# What each player has equipped, parallel to the two above: {slot: item_id} (see LoadoutManager.gd).
var player_equipped: Array[Dictionary] = []
@onready var gen_overlay: CanvasLayer = %GenerationOverlay  # "Generating a puzzle..." -- a node of Game.tscn
@onready var gen_overlay_label: Label = %GenerationLabel
var current_streak: int = 0  # puzzles solved in a row this Endless Mode run
var endless_run_start_ms: int = 0
var endless_run_finalized: bool = false
var was_party_wiped: bool = false
var current_level_time_limit: float = LEVEL_TIME_LIMIT  # grows via clue bonuses
var clue_bonus_granted: Array = []  # clue_bonus_granted[row][col] = bool, parallel to grid
var timer_bonus_popups: Array[Dictionary] = []  # visual-only floating "+30s" text
var tutorial_hints: Array[Dictionary] = []  # visual-only fading text bubbles near the player
var movement_tutorial_shown: bool = false
var combat_tutorial_shown: bool = false
var pause_menu_open: bool = false
var projectiles: Array[Dictionary] = []  # visual-only, see _sync_spawn_projectile()

var status_label: Label
var combat_status_label: Label
var reset_button: Button
var shop_button: Button  # on the post-solve screen, Endless / multiplayer only -- opens the shop
var check_button: Button
var next_level_button: Button
# Endless / multiplayer equivalent of next_level_button: shown on the solve
# summary so the next puzzle only loads when the player says so. Only the
# singleplayer player / multiplayer host gets the button (only they can
# generate the next board); everyone else sees continue_waiting_label.
var continue_button: Button
var continue_waiting_label: Label
var try_again_button: Button  # centered "Try Again" shown only on a full party wipe

# The post-solve summary panel (EarningsPanel.tscn, inside HUD.tscn's solve
# screen): shown above next_level_button / continue_button once solved_now flips
# true, and filled in by its populate(). Set by HUD.setup().
var earnings_panel: Control

# Inventory/equipment overlay (campaign-only) -- see InventoryPanel.gd.
# Toggled by its own 'I' key listener, not by anything here; Game._input()
# below only ever reads its is_open() to hold off on movement/attack/block
# input while it's up.
var inventory_panel: CanvasLayer
var font: Font  # used by HUDManager for the minimap numbers, popups, hints and win banner

var offset_x: int = 0
var offset_y: int = 0

# Thin wrappers around GridGeometry's shared math with this board's own
# origin (MARGIN + offset_x/y) and CELL_SIZE plugged in -- see GridGeometry.gd
# for why the math itself lives there instead of here.
func _tile_to_pixel(row: float, col: float) -> Vector2:
	return GridGeometry.tile_to_pixel(row, col, Vector2(MARGIN + offset_x, MARGIN + offset_y), Constants.CELL_SIZE)

func _tile_center_to_pixel(row: float, col: float) -> Vector2:
	return GridGeometry.tile_center_to_pixel(row, col, Vector2(MARGIN + offset_x, MARGIN + offset_y), Constants.CELL_SIZE)

# --- Scrolling viewport: the play area shows a window of the puzzle large --
# --- enough to fill the screen, centered on the local player, and clamped --
# --- to the puzzle's edges. Recomputed every _draw() call. ---
var view_col_start: int = 0
var view_row_start: int = 0
var view_cols: int = 0
var view_rows: int = 0
# Visible row/col range *including* the border ring (inclusive, board indices
# that may be -1 or rows/cols). Equals the view_* range above whenever the
# camera isn't at an edge; set by HUDManager._compute_view_window().
var border_first_row: int = 0
var border_last_row: int = -1
var border_first_col: int = 0
var border_last_col: int = -1

# The in-play HUD (icon row, hamburger, combat text, solve/defeat buttons) is a
# child scene -- see HUD.tscn / HUD.gd. GameUIManager._build_ui() hands it the
# session's mode, and _process() below keeps its numbers current.
@onready var hud: Node = $HUD

var was_solved: bool = false
var win_animation_active: bool = false
var win_animation_time: float = 0.0
var confetti_pieces: Array[Dictionary] = []

var wall_textures: Dictionary = {}          # clue number (-1 for blank) -> Texture2D
var floor_seed: int = 0  # set per puzzle in parse_puzzle; scatters floor variants
var floor_textures: Array[Texture2D] = []   # ordered list of floor tile variants
var floor_lit_textures: Array[Texture2D] = []  # same order/length as floor_textures
var bulb_texture: Texture2D = null
# bulb.png is a horizontal strip of equal-width frames (frame count = width / height,
# worked out in AssetLoader); a plain single-image bulb.png just comes out as 1 frame.
var bulb_frame_count: int = 1
var bulb_anim_time: float = 0.0  # advanced in _process(), so it freezes with the pause menu like the enemies do
const BULB_FRAME_DURATION: float = 0.12  # seconds per frame (6 frames = a ~0.7s loop)
const WALL_FRAME_DURATION: float = 0.12  # seconds per frame of a lit wall's animation strip (shares bulb_anim_time)
const BULB_SPRITE_SCALE: float = 1.0  # 1.0 = each frame drawn at CELL_SIZE (native pixel scale for 64x64 frames)
var player_attack_sheet_texture: Texture2D = null
var player_interact_sheet_texture: Texture2D = null
var player_idle_sheet_texture: Texture2D = null
var player_run_sheet_texture: Texture2D = null
var projectile_texture: Texture2D = null
# Animated enemy/boss sheets -- each a multi-row strip of equal-size square
# frames (4 rows: down/up/left/right; frame count inferred from width/height).
# See assets/README.md for the full convention.
var enemy_sheets: Dictionary = {}  # "enemy_idle", "boss_tier_1_attack", ... -> Texture2D (see Enemy.gd ANIMS)
# "top", "bottom", "left", "right", "top_left", "top_right", "bottom_left",
# "bottom_right" -> Texture2D (loaded from border_*.png / border_corner_*.png).
var border_textures: Dictionary = {}

const PlayerLogic := preload("res://Player.gd")
const LoadoutLogic := preload("res://LoadoutManager.gd")
const EnemyLogic := preload("res://Enemy.gd")
const CombatLogic := preload("res://CombatManager.gd")
const UILogic := preload("res://GameUIManager.gd")
const HUDLogic := preload("res://HUDManager.gd")
const PauseMenuLogic := preload("res://PauseMenuManager.gd")
const AssetLogic := preload("res://AssetLoader.gd")
const PuzzleLogic := preload("res://PuzzleBoard.gd")
const ShopLogic := preload("res://ShopManager.gd")

var player_mgr := PlayerLogic.new(self)
var enemy_mgr := EnemyLogic.new(self)
var combat_mgr := CombatLogic.new(self)
var ui_mgr := UILogic.new(self)
var hud_mgr := HUDLogic.new(self)
var pause_mgr := PauseMenuLogic.new(self)
var asset_mgr := AssetLogic.new(self)
var puzzle_mgr := PuzzleLogic.new(self)
var shop_mgr := ShopLogic.new(self)
var loadout_mgr := LoadoutLogic.new(self)

func _ready() -> void:
	%GenerationCancelButton.pressed.connect(_on_generation_cancel_pressed)
	if NetworkManager.is_multiplayer:
		current_puzzle_rows = NetworkManager.pending_puzzle_rows
		var peer_order: Array = NetworkManager.pending_peer_order
		my_player_index = peer_order.find(multiplayer.get_unique_id())
		players.clear()
		for player_index in range(peer_order.size()):
			var starting_position: Array = NetworkManager.pending_start_positions[player_index]
			players.append(player_mgr._create_player_state(starting_position[0], starting_position[1]))
	else:
		if CampaignManager.is_campaign_active:
			current_puzzle_rows = CampaignManager.get_current_level_puzzle_rows()
		else:
			current_puzzle_rows = DEFAULT_PUZZLE_ROWS
			endless_run_start_ms = Time.get_ticks_msec()
		my_player_index = 0
		players.clear()
		players.append(player_mgr._create_player_state(0, 0))

	if SessionEconomy.take(players.size()):
		# Back from the multiplayer Town: carry on with the match's gold, items and gear.
		player_gold = SessionEconomy.gold
		player_inventory = SessionEconomy.inventory
		player_equipped = SessionEconomy.equipped
	else:
		player_gold.clear()
		player_gold.resize(players.size())
		player_gold.fill(0)
		player_inventory.clear()
		player_equipped.clear()
		for _player_index in range(players.size()):
			player_inventory.append({})
			player_equipped.append(LoadoutLogic.empty_loadout())

	puzzle_mgr.parse_puzzle()

	if not NetworkManager.is_multiplayer:
		var starting_position: Array = BoardUtil.corner_positions(current_puzzle_rows, 1)[0]
		players[0] = player_mgr._create_player_state(starting_position[0], starting_position[1])

	font = ThemeDB.fallback_font
	asset_mgr._load_pixel_art()
	_start_pregeneration()
	ui_mgr._resize_window()
	ui_mgr._build_ui()
	get_window().size_changed.connect(ui_mgr._update_layout)
	puzzle_mgr.recompute_state()

	if not movement_tutorial_shown and (not CampaignManager.is_campaign_active or CampaignManager.get_current_level_number() == 1):
		movement_tutorial_shown = true
		var move_keys: String = "%s/%s/%s/%s" % [
			SettingsManager.get_key_label("move_up"), SettingsManager.get_key_label("move_left"),
			SettingsManager.get_key_label("move_down"), SettingsManager.get_key_label("move_right"),
		]
		hud_mgr._show_tutorial_hint("Move with %s\nPlace a light with %s" % [move_keys, SettingsManager.get_key_label("place_light")], 5.0)

	if NetworkManager.is_multiplayer and not multiplayer.is_server():
		rpc_id(1, "_client_ready", multiplayer.get_unique_id())

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == SettingsManager.get_key_binding("block") and not event.echo:
		if event.pressed and pause_mgr._handle_rebind_key(event):
			return
		if event.pressed and _is_modal_open():
			return
		player_mgr._handle_block_input(event.pressed)
		return
	if event is InputEventKey and not event.echo and player_mgr._is_move_keycode(event.keycode):
		if event.pressed and pause_mgr._handle_rebind_key(event):
			return
		if event.pressed and (pause_menu_open or _is_modal_open()):
			return  # ignore new presses while paused/inventory/shop open; releases still fall through so nothing stays stuck held
		player_mgr._handle_move_key_event(event.keycode, event.pressed)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if pause_mgr._handle_rebind_key(event):
			return
		if event.keycode == KEY_ESCAPE:
			if shop_mgr.is_open():
				shop_mgr.close_shop()  # Escape closes the shop first, like any window
			else:
				pause_mgr._toggle_pause_menu()
			return
		if pause_menu_open or _is_modal_open():
			return
		var keycode: int = event.keycode
		if keycode == SettingsManager.get_key_binding("place_light"):
			puzzle_mgr._handle_bulb_input()
		elif keycode == SettingsManager.get_key_binding("attack"):
			player_mgr._handle_attack_input()
		elif keycode == KEY_F11:
			SettingsManager.toggle_fullscreen()
			ui_mgr.call_deferred("_update_layout")

func _is_inventory_open() -> bool:
	return inventory_panel != null and inventory_panel.is_open()

# Any overlay that should hold off gameplay input (placing bulbs, attacking, moving) while it is up.
func _is_modal_open() -> bool:
	return _is_inventory_open() or shop_mgr.is_open()

func _notification(what: int) -> void:
	# The window losing OS focus (alt-tab, etc.) can eat the key-up event
	# entirely, which would otherwise leave a movement key "stuck" held and
	# repeating forever once focus returns.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		player_mgr._clear_held_move_keys()

@rpc("any_peer", "call_remote", "reliable")
func _request_move(player_index: int, delta_row: int, delta_col: int) -> void:
	player_mgr._request_move(player_index, delta_row, delta_col)

@rpc("authority", "call_local", "reliable")
func _sync_player_position(player_index: int, row: int, col: int) -> void:
	player_mgr._sync_player_position(player_index, row, col)

@rpc("any_peer", "call_remote", "reliable")
func _request_toggle_bulb(player_index: int) -> void:
	puzzle_mgr._request_toggle_bulb(player_index)

@rpc("authority", "call_local", "reliable")
func _sync_bulb(player_index: int, row: int, col: int, bulb_value: bool) -> void:
	puzzle_mgr._sync_bulb(player_index, row, col, bulb_value)

@rpc("any_peer", "call_remote", "reliable")
func _request_attack(player_index: int) -> void:
	combat_mgr._request_attack(player_index)

@rpc("any_peer", "call_remote", "reliable")
func _request_block(player_index: int, is_blocking: bool) -> void:
	player_mgr._request_block(player_index, is_blocking)

@rpc("authority", "call_local", "reliable")
func _sync_block_state(player_index: int, is_blocking: bool) -> void:
	player_mgr._sync_block_state(player_index, is_blocking)

@rpc("authority", "call_local", "reliable")
func _sync_player_health(player_index: int, health: int, is_defeated: bool) -> void:
	player_mgr._sync_player_health(player_index, health, is_defeated)

@rpc("authority", "call_local", "reliable")
func _sync_player_respawn(player_index: int, row: int, col: int) -> void:
	player_mgr._sync_player_respawn(player_index, row, col)

func _on_reset_pressed() -> void:
	if NetworkManager.is_multiplayer and not multiplayer.is_server():
		return
	var cleared_bulbs: Array = puzzle_mgr._empty_bool_grid()
	var new_positions: Array = BoardUtil.corner_positions(current_puzzle_rows, players.size())
	if NetworkManager.is_multiplayer:
		rpc("_sync_full_reset", cleared_bulbs, new_positions)
	else:
		_sync_full_reset(cleared_bulbs, new_positions)

@rpc("authority", "call_local", "reliable")
func _sync_full_reset(new_bulbs: Array, new_positions: Array) -> void:
	bulbs = new_bulbs
	shop_mgr.close_shop()
	error_flash_cells.clear()
	error_flash_timer = 0.0
	for player_index in range(players.size()):
		var new_position: Array = new_positions[player_index]
		players[player_index] = player_mgr._create_player_state(new_position[0], new_position[1])
	enemies.clear()
	conflict_timer = 0.0
	next_enemy_spawn_threshold = CONFLICT_SPAWN_INTERVAL
	level_timer = 0.0
	boss_spawn_evaluated = false
	boss_was_summoned_this_level = false
	boss_killed_this_level = false
	enemies_killed_this_level = 0
	current_level_time_limit = LEVEL_TIME_LIMIT
	puzzle_mgr._reset_clue_bonus_tracking()
	if not NetworkManager.is_multiplayer and not CampaignManager.is_campaign_active:
		endless_run_finalized = false
		endless_run_start_ms = Time.get_ticks_msec()
	puzzle_mgr.recompute_state()

# Called once, the first moment an Endless Mode run ends -- either the whole
# party being wiped (see _process()) or the player quitting to the Main
# Menu (see GameUIManager._on_pause_main_menu_pressed). Singleplayer-only:
# multiplayer has no single "the player" to attribute a personal streak to.
func _finalize_endless_run() -> void:
	if NetworkManager.is_multiplayer or CampaignManager.is_campaign_active or endless_run_finalized:
		return
	endless_run_finalized = true
	var elapsed_seconds: float = (Time.get_ticks_msec() - endless_run_start_ms) / 1000.0
	# A solved board still sitting on its summary screen hasn't been advanced
	# past yet (current_streak only ticks up when the next board loads), but
	# it was solved -- count it so quitting from the summary doesn't lose it.
	SaveManager.record_endless_run(current_streak + (1 if was_solved else 0), elapsed_seconds)

# Starts generating the NEXT puzzle in the background while the current one is
# being solved, so New Puzzle is usually instant. Only whoever generates boards
# (singleplayer / multiplayer host) does this; campaign levels are premade.
func _start_pregeneration() -> void:
	if next_job != null or CampaignManager.is_campaign_active:
		return
	if NetworkManager.is_multiplayer and not multiplayer.is_server():
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	next_job = GenerationJob.new()
	next_job.start(SUBSEQUENT_PUZZLE_SIZES[rng.randi() % SUBSEQUENT_PUZZLE_SIZES.size()], GENERATOR_DENSITY)

func _exit_tree() -> void:
	if next_job != null:
		next_job.cancel()
		next_job.finish()

func _on_generation_cancel_pressed() -> void:
	if next_job != null:
		next_job.cancel()

# Every peer: fills the post-solve panel and pays out the level's earnings. Every player gets the FULL total
# (it isn't split). Each peer applies the same host broadcast to its own copy, so the copies stay identical.
@rpc("authority", "call_local", "reliable")
func _show_solve_summary(breakdown: Dictionary) -> void:
	for player_index in range(player_gold.size()):
		player_gold[player_index] += breakdown["total"]
	earnings_panel.populate(breakdown)

# --- Shopping (Endless / multiplayer): the logic lives in ShopManager.gd; these are just
# --- its RPC entry points, like the other managers' wrappers.

@rpc("any_peer", "call_remote", "reliable")
func _request_purchase(player_index: int, item_id: String) -> void:
	shop_mgr._request_purchase(player_index, item_id)

@rpc("authority", "call_local", "reliable")
func _sync_purchase(player_index: int, item_id: String, new_gold: int, new_quantity: int) -> void:
	shop_mgr._sync_purchase(player_index, item_id, new_gold, new_quantity)

@rpc("authority", "call_remote", "reliable")
func _purchase_rejected(item_id: String, message: String) -> void:
	shop_mgr._purchase_rejected(item_id, message)

# Equipping (Endless / multiplayer): logic in LoadoutManager.gd.

@rpc("any_peer", "call_remote", "reliable")
func _request_equip(player_index: int, slot: String, item_id: String) -> void:
	loadout_mgr._request_equip(player_index, slot, item_id)

@rpc("authority", "call_local", "reliable")
func _sync_equipped(player_index: int, slot: String, item_id: String) -> void:
	loadout_mgr._sync_equipped(player_index, slot, item_id)

# Endless / multiplayer: the summary's Continue button (host / singleplayer
# only -- see GameUIManager._build_ui). Mirrors Next Level in campaign: the
# board only advances when the player presses it. Ignored if Reset/an edit
# has since un-solved the board.
func _on_continue_pressed() -> void:
	if not puzzle_mgr._is_solved():
		return
	if NetworkManager.is_multiplayer:
		if multiplayer.is_server():
			rpc("_go_to_town")  # multiplayer: the Town comes between levels; it generates the next board itself
		return
	_advance_to_new_puzzle()

# Multiplayer, every peer: off to the shared Town (Town.gd) with this match's economy.
@rpc("authority", "call_local", "reliable")
func _go_to_town() -> void:
	SessionEconomy.store(player_gold, player_inventory, player_equipped)
	get_tree().change_scene_to_file(Constants.SCENE_TOWN)

func _advance_to_new_puzzle() -> void:
	if NetworkManager.is_multiplayer and not multiplayer.is_server():
		return
	if generating_new_puzzle:
		return
	generating_new_puzzle = true
	_start_pregeneration()
	var job: GenerationJob = next_job
	if not job.done:
		gen_overlay.visible = true
		while not job.done:
			var elapsed_seconds: float = (Time.get_ticks_msec() - job.started_ms) / 1000.0
			gen_overlay_label.text = "Generating a %dx%d puzzle...\nAttempt %d  (%.0fs)" % [job.size.x, job.size.y, job.attempts, elapsed_seconds]
			await get_tree().process_frame
		gen_overlay.visible = false
	job.finish()
	next_job = null
	generating_new_puzzle = false
	if not job.cancelled:
		current_streak += 1  # only counts once a board has actually been found
		var new_rows_array: PackedStringArray = job.result_rows
		var new_positions: Array = BoardUtil.corner_positions(new_rows_array, players.size())
		if NetworkManager.is_multiplayer:
			rpc("_sync_new_puzzle", new_rows_array, new_positions)
		else:
			_sync_new_puzzle(new_rows_array, new_positions)
	_start_pregeneration()

@rpc("authority", "call_local", "reliable")
func _sync_new_puzzle(new_rows_array: PackedStringArray, new_positions: Array) -> void:
	current_puzzle_rows = new_rows_array
	earnings_credited = false
	shop_mgr.close_shop()
	error_flash_cells.clear()
	error_flash_timer = 0.0
	puzzle_mgr.parse_puzzle()
	for player_index in range(players.size()):
		var new_position: Array = new_positions[player_index]
		players[player_index] = player_mgr._create_player_state(new_position[0], new_position[1])
	enemies.clear()
	conflict_timer = 0.0
	next_enemy_spawn_threshold = CONFLICT_SPAWN_INTERVAL
	level_timer = 0.0
	boss_spawn_evaluated = false
	boss_was_summoned_this_level = false
	boss_killed_this_level = false
	enemies_killed_this_level = 0
	current_level_time_limit = LEVEL_TIME_LIMIT
	ui_mgr._resize_window()
	puzzle_mgr.recompute_state()

# --- Next Level: campaign mode only, always singleplayer -- no RPC routing --
# --- needed here, unlike Reset/New Puzzle which also exist in multiplayer. --

func _on_next_level_pressed() -> void:
	SaveManager.record_level_best_time(CampaignManager.current_level_index, level_timer, current_level_time_limit - level_timer)
	CampaignManager.record_level_result(boss_was_summoned_this_level)
	CampaignManager.advance_to_next_level()
	get_tree().change_scene_to_file("res://Town.tscn")

# --- Check Answer: purely local, always consistent since state is synced --

func _on_check_pressed() -> void:
	if LightUpSolver.verify_answer(grid, rows, cols, bulbs):
		status_label.text = "Correct! That's a valid, complete solution."
		status_label.add_theme_color_override("font_color", Constants.STATUS_SUCCESS_ON_PARCHMENT)
		error_flash_cells.clear()
		error_flash_timer = 0.0
	else:
		status_label.text = "Not solved yet -- check the lit count and any red conflicts above."
		status_label.add_theme_color_override("font_color", Constants.STATUS_ERROR_ON_PARCHMENT)
		error_flash_cells = puzzle_mgr._compute_error_cells()
		error_flash_timer = ERROR_FLASH_DURATION
	pause_mgr._close_pause_menu()
	queue_redraw()

# --- Late-join / reconnect safety net: a fresh client asks the host for a --
# --- full state snapshot right after loading, in case any sync RPC sent  --
# --- before its Game.tscn instance existed got silently dropped.         --

@rpc("any_peer", "call_remote", "reliable")
func _client_ready(_claimed_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Ignore the client-supplied id (kept in the signature so the RPC stays
	# compatible) and reply only to whoever actually asked.
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id == 0 or not NetworkManager.player_roster().has(peer_id):
		return
	if not NetworkManager.rate_limit_ok(peer_id, "client_ready", 1.0):
		return
	rpc_id(peer_id, "_full_state_sync", bulbs, _players_positions_array(), _players_combat_array(), enemy_mgr._build_enemy_snapshot(), level_timer, boss_spawn_evaluated, current_level_time_limit, {"gold": player_gold, "inventory": player_inventory, "equipped": player_equipped})

@rpc("authority", "call_remote", "reliable")
func _full_state_sync(new_bulbs: Array, new_positions: Array, new_combat: Array, enemy_snapshot: Array, new_level_timer: float, new_boss_spawn_evaluated: bool, new_level_time_limit: float, new_economy: Dictionary) -> void:
	bulbs = new_bulbs
	player_gold.assign(new_economy["gold"])
	player_inventory.assign(new_economy["inventory"])
	player_equipped.assign(new_economy["equipped"])
	for player_index in range(players.size()):
		var new_position: Array = new_positions[player_index]
		var combat_entry: Dictionary = new_combat[player_index]
		players[player_index] = player_mgr._create_player_state(new_position[0], new_position[1])
		players[player_index]["health"] = combat_entry["health"]
		players[player_index]["is_defeated"] = combat_entry["is_defeated"]
	enemy_mgr._apply_enemy_snapshot(enemy_snapshot)
	level_timer = new_level_timer
	boss_spawn_evaluated = new_boss_spawn_evaluated
	current_level_time_limit = new_level_time_limit
	puzzle_mgr._reset_clue_bonus_tracking()
	puzzle_mgr._mark_currently_satisfied_clues_as_granted()
	puzzle_mgr.recompute_state()

func _players_positions_array() -> Array:
	var positions: Array = []
	for player_state: Dictionary in players:
		positions.append([player_state["row"], player_state["col"]])
	return positions

func _players_combat_array() -> Array:
	var combat_states: Array = []
	for player_state: Dictionary in players:
		combat_states.append({"health": player_state["health"], "is_defeated": player_state["is_defeated"]})
	return combat_states

# ---------------------------------------------------------------------------
# Enemy sync -- the host broadcasts a lightweight snapshot (id/row/col/
# health only) any time enemies change; every peer reconciles it against
# its local enemies list by id, preserving visual/animation state for ids
# it already knows about so movement keeps interpolating smoothly rather
# than snapping.
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync_enemies(snapshot: Array) -> void:
	enemy_mgr._sync_enemies(snapshot)

@rpc("authority", "call_local", "reliable")
func _sync_spawn_projectile(from_row: int, from_col: int, to_row: int, to_col: int, shooter_enemy_id: int) -> void:
	combat_mgr._sync_spawn_projectile(from_row, from_col, to_row, to_col, shooter_enemy_id)

@rpc("authority", "call_local", "reliable")
func _sync_player_attack_flash(player_index: int) -> void:
	combat_mgr._sync_player_attack_flash(player_index)

@rpc("authority", "call_local", "reliable")
func _sync_enemy_attack_flash(enemy_id: int) -> void:
	combat_mgr._sync_enemy_attack_flash(enemy_id)

func _process(delta: float) -> void:
	if pause_menu_open and not NetworkManager.is_multiplayer:
		return

	bulb_anim_time += delta
	player_mgr._advance_player_animations(delta)
	if not _is_modal_open():
		# Mirrors Town.gd's equivalent guard in its own _tick_move_repeat --
		# without this, holding a direction and then opening the inventory
		# (which, unlike the pause menu, doesn't clear held keys on open)
		# would keep the held direction repeating behind the panel.
		player_mgr._tick_move_repeat(delta)
	enemy_mgr._advance_enemy_animations(delta)
	combat_mgr._advance_projectiles(delta)
	hud_mgr._advance_timer_bonus_popups(delta)
	hud_mgr._advance_tutorial_hints(delta)

	if not combat_tutorial_shown and not enemies.is_empty():
		combat_tutorial_shown = true
		hud_mgr._show_tutorial_hint("Press %s to attack an adjacent enemy!\nHold Shift to block: takes less melee damage\nand no ranged damage, but you can't attack." % SettingsManager.get_key_label("attack"), 6.0)

	player_mgr._tick_respawn_display_timers(delta)
	if error_flash_timer > 0.0:
		error_flash_timer = max(0.0, error_flash_timer - delta)
	if not was_solved:
		hud_mgr._tick_level_timer_display(delta)
	combat_mgr._update_combat_status_label()

	var party_wiped_now: bool = player_mgr._all_players_defeated()
	if party_wiped_now and not was_party_wiped:
		_finalize_endless_run()
		current_streak = 0
	was_party_wiped = party_wiped_now

	if not was_solved and (not NetworkManager.is_multiplayer or multiplayer.is_server()):
		combat_mgr._tick_combat_simulation(delta)

	if win_animation_active:
		hud_mgr._advance_win_animation(delta)

	hud.update_stats()

	# Always redraw, not just when something is mid-animation: the minimap is
	# custom-drawn in _draw() rather than being a Control with its own
	# independent rendering, so without this it'd only visually refresh
	# whenever some other event (movement, combat) happened to trigger a redraw.
	queue_redraw()

# How many cells thick the border ring is on each side. The camera treats the
# ring as extra rows/cols of the world (see HUDManager._compute_view_window), so
# no screen space is ever reserved for it -- it just takes its place as the
# outermost row/col when the camera scrolls to that edge.
func _border_cells() -> int:
	return 1

# Draws the border ring around the puzzle's outer edge: the tiles at
# row -1 / row `rows` and col -1 / col `cols`, i.e. just outside the board.
# Positioned with the same _tile_to_pixel as the cells, so it scrolls with
# the board. Only tiles inside the camera's visible range (border_first_row
# .. border_last_col, computed by HUDManager) are drawn. Edges are drawn
# first, corners on top.
func _draw_border() -> void:
	var first_row: int = border_first_row
	var last_row: int = border_last_row
	var first_col: int = border_first_col
	var last_col: int = border_last_col
	for row: int in range(first_row, last_row + 1):
		for col: int in range(first_col, last_col + 1):
			var on_row_edge: bool = row == -1 or row == rows
			var on_col_edge: bool = col == -1 or col == cols
			if not on_row_edge and not on_col_edge:
				continue
			if on_row_edge and on_col_edge:
				continue  # corners are drawn in the second pass below
			var piece_name: String = ("top" if row == -1 else "bottom") if on_row_edge else ("left" if col == -1 else "right")
			_draw_border_tile(piece_name, row, col)
	for corner: Array in [
		["top_left", -1, -1], ["top_right", -1, cols],
		["bottom_left", rows, -1], ["bottom_right", rows, cols],
	]:
		if corner[1] >= first_row and corner[1] <= last_row and corner[2] >= first_col and corner[2] <= last_col:
			_draw_border_tile(corner[0], corner[1], corner[2])

func _draw_border_tile(piece_name: String, row: int, col: int) -> void:
	var texture: Texture2D = border_textures[piece_name]
	var destination: Rect2 = Rect2(_tile_to_pixel(row, col), Vector2(Constants.CELL_SIZE, Constants.CELL_SIZE))
	if destination.intersects(get_viewport_rect()):
		draw_texture_rect(texture, destination, false)

func _draw() -> void:
	# (The background and the icon row are on HUD.tscn's back layer, which
	# renders underneath everything drawn here.)
	hud_mgr._compute_view_window()

	for row in range(view_row_start, view_row_start + view_rows):
		for col in range(view_col_start, view_col_start + view_cols):
			var cell_position: Vector2 = _tile_to_pixel(row, col)
			var cell_rectangle: Rect2 = Rect2(cell_position, Vector2(Constants.CELL_SIZE, Constants.CELL_SIZE))
			var cell_data: Dictionary = grid[row][col]

			if cell_data["type"] == Constants.CellType.BLACK:
				var wall_number: int = cell_data["number"]
				# Clues 1-4 light up while exactly satisfied; the 0 clue and the
				# blank wall light up while any bulb has line of sight to them.
				var is_wall_lit: bool = (puzzle_mgr._bulb_neighbor_count(row, col) == wall_number) if wall_number >= 1 else wall_lit[row][col]
				var wall_texture: Texture2D = asset_mgr._get_wall_texture(wall_number, is_wall_lit)
				# A strip of square frames (the plain wall is just a 1-frame strip).
				# Per-cell frame offset (same trick as the bulbs) so a field of
				# lit walls doesn't pulse in lockstep.
				var wall_frames: int = AssetLoader.wall_frame_count(wall_texture)
				var wall_frame: int = (int(bulb_anim_time / WALL_FRAME_DURATION) + row * 5 + col * 3) % wall_frames
				var wall_frame_width: float = float(wall_texture.get_width()) / float(wall_frames)
				draw_texture_rect_region(wall_texture, cell_rectangle, Rect2(wall_frame * wall_frame_width, 0.0, wall_frame_width, float(wall_texture.get_height())))
			else:
				var floor_variant_index: int = hash([row, col, floor_seed]) % floor_textures.size()
				var floor_texture: Texture2D = floor_lit_textures[floor_variant_index] if lit[row][col] else floor_textures[floor_variant_index]
				var tile_tint: Color = Color(1, 1, 1)
				if conflicting_bulbs.has([row, col]):
					tile_tint = tile_tint.lerp(Color(1, 0.35, 0.35), 0.6)
				draw_texture_rect(floor_texture, cell_rectangle, false, tile_tint)

				if bulbs[row][col]:
					var cell_center: Vector2 = _tile_center_to_pixel(row, col)
					var bulb_tint: Color = Color(1, 1, 1)
					if conflicting_bulbs.has([row, col]):
						bulb_tint = Color(1.4, 0.4, 0.4)
					var bulb_size: float = Constants.CELL_SIZE * BULB_SPRITE_SCALE
					var bulb_rectangle: Rect2 = Rect2(cell_center.x - bulb_size / 2.0, cell_center.y - bulb_size / 2.0, bulb_size, bulb_size)
					# Offset each cell's start frame by its position so a field of
					# bulbs flickers out of step instead of in lockstep (stable per
					# cell, so no popping when the board redraws).
					var bulb_frame: int = (int(bulb_anim_time / BULB_FRAME_DURATION) + row * 5 + col * 3) % bulb_frame_count
					var bulb_frame_width: float = float(bulb_texture.get_width()) / float(bulb_frame_count)
					var bulb_source_rectangle: Rect2 = Rect2(bulb_frame * bulb_frame_width, 0.0, bulb_frame_width, float(bulb_texture.get_height()))
					draw_texture_rect_region(bulb_texture, bulb_rectangle, bulb_source_rectangle, bulb_tint)

	_draw_border()

	hud_mgr._draw_error_flash()

	enemy_mgr._draw_enemies()
	player_mgr._draw_players()
	combat_mgr._draw_projectiles()

	# Minimap next, so it sits on top of the board/entities but still
	# underneath the tutorial hints, popups, and win banner drawn after --
	# those need to never be obscured by the HUD strip (whose icon row is
	# on HUD.tscn's back layer, below all of this).
	hud_mgr._draw_minimap()

	hud_mgr._draw_timer_bonus_popups()
	hud_mgr._draw_tutorial_hints()

	if win_animation_active:
		hud_mgr._draw_win_animation()
