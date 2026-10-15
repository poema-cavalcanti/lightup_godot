extends Node2D

# ---------------------------------------------------------------------------
# TOWN
#
# A short walkable area between campaign levels:
#   Cutscene -> Game (level) -> Town -> Cutscene -> Game -> Town -> ...
# Reached from Game._on_next_level_pressed() (instead of going straight to
# Cutscene.tscn); walking off either end of the open road row here is what
# actually continues on to Cutscene.tscn for the next level.
#
# Movement, the hold-to-move feel, and the walk-cycle sprite are all a
# deliberate match for Player.gd's in-level movement -- same constants,
# same two-phase repeat (see Player.gd for the reasoning behind each
# piece), same player_sheet.png/idle/run rendering. Ported by hand rather than
# shared, since this scene has no puzzle/combat state and no `game` node
# to hang a shared manager off of. The layout itself is a plain string
# grid (TOWN_GRID) rather than the level's puzzle-board machinery: '#'
# blocks movement, '.' is open ground, 'D' is a shop door.
#
# Two shop doors sit in the grid; walking onto one immediately prompts a
# Yes/No confirmation, Yes opens a shop panel listing that shop's items
# (from ItemData.SHOP_ITEM_IDS) with a Buy button each -- buying deducts
# gold and adds to CampaignManager.inventory, which the inventory overlay
# (its own 'I' key, open any time) lets the player review. No, or closing the
# shop, animates the player back onto the tile below the door.
#
# MULTIPLAYER: the same town is shared by everyone in a multiplayer match
# (reached from Game._go_to_town()). All of that lives in TownNet.gd; this
# script only branches to it where the campaign's single-player behavior
# differs (marked "net" below) and holds the @rpc wrappers, since RPCs have to
# live on the node. In that mode the Town node also stands in for `game` as
# far as ShopManager.gd and LoadoutManager.gd are concerned (player_gold,
# player_inventory, player_equipped, my_player_index, players, was_solved and
# the RPC entry points further down), so shopping and equipping behave exactly
# as they do after a level.
#
# LAYOUT: the town art, the Yes/No dialog, the shop window and the inventory
# overlay are all nodes in Town.tscn (the art and shop_background.png are
# referenced directly, so both files must exist); each shop item is a
# ShopItemCard.tscn. This script only moves the town art to follow the camera,
# draws the player on top of it, and fills in text/cards as popups open.
# ---------------------------------------------------------------------------

const TOWN_GRID: Array[String] = [
	"####################",
	"####################",
	"####################",
	"####################",
	"####################",
	"####################",
	"######D######D######",
	"######.######.######",
	"######.######.######",
	"....................",
	"####################",
	"####################",
]
const WALL_CHAR: String = "#"
const DOOR_CHAR: String = "D"

const SPAWN_ROW: int = 9
const SPAWN_COL: int = 10
const TownNetLogic := preload("res://TownNet.gd")
const ShopLogic := preload("res://ShopManager.gd")
const LoadoutLogic := preload("res://LoadoutManager.gd")
const PauseMenuLogic := preload("res://PauseMenuManager.gd")

const SHOP_CARD_SCENE: PackedScene = preload("res://ShopItemCard.tscn")
const CONFIRM_PIXEL_SCALE: int = PixelButton.DEFAULT_PIXEL_SCALE # the confirm popup's panel, buttons and X all use this; its sizes in Town.tscn are multiples of it
const SHOP_CARD_TEXT_LEFT_WITHOUT_ICON: float = 16.0 # where a card's text starts when the item has no icon (with one it's in the scene)

var player_sheet_texture: Texture2D
var player_idle_sheet_texture: Texture2D
var player_run_sheet_texture: Texture2D

var grid_rows: int
var grid_cols: int

var shops: Array[Dictionary] = [
	{"name": "Weapons Shop", "prompt": "Enter the weapons shop?", "door_row": 6, "door_col": 6},
	{"name": "Shields Shop", "prompt": "Enter the shields shop?", "door_row": 6, "door_col": 13},
]

var player_row: int = SPAWN_ROW
var player_col: int = SPAWN_COL
var facing_direction: String = "up"
var visual_position: Vector2 # tile-space (x=col, y=row), same convention Player.gd uses
var animation_from: Vector2
var animation_to: Vector2
var animation_progress: float = 1.0
var animation_timer: float = 0.0
var animation_frame_index: int = 0
var idle_timer: float = 0.0
var idle_frame_index: int = 0

var move_repeater: MoveRepeater = MoveRepeater.new()

# The Escape menu is PauseMenuManager's, shared with the levels (it checks `is_town`).
var is_town: bool = true
var pause_menu_open: bool = false
var pause_mgr := PauseMenuLogic.new(self)

var active_shop_index: int = -1 # which shop the open confirm/shop panel refers to

# Multiplayer only (net is null in the campaign). The fields below are what
# ShopManager / LoadoutManager read from their `game` -- see MULTIPLAYER above.
var net: RefCounted = null
var players: Array[Dictionary] = []
var my_player_index: int = 0
var player_gold: Array[int] = []
var player_inventory: Array[Dictionary] = []
var player_equipped: Array[Dictionary] = []
var was_solved: bool = true # the town's shop is always open
var shop_mgr := ShopLogic.new(self)
var loadout_mgr := LoadoutLogic.new(self)

# Popups and the town art, all nodes of Town.tscn.
@onready var background: Sprite2D = %Background
@onready var confirm_canvas: CanvasLayer = %ConfirmDialog
@onready var confirm_label: Label = %ConfirmLabel
@onready var shop_canvas: CanvasLayer = %ShopPanel
@onready var shop_title_label: Label = %ShopTitleLabel
@onready var shop_gold_label: Label = %ShopGoldLabel
@onready var shop_items_root: Control = %ShopItems
@onready var inventory_panel: CanvasLayer = %InventoryPanel

func _ready() -> void:
	grid_rows = TOWN_GRID.size()
	grid_cols = TOWN_GRID[0].length()
	SettingsManager.apply_window_size(int(grid_cols * Constants.CELL_SIZE), int(grid_rows * Constants.CELL_SIZE))
	player_sheet_texture = AssetLoader.load_texture("res://assets/player_sheet.png")
	player_idle_sheet_texture = AssetLoader.load_texture("res://assets/player_idle_sheet.png")
	player_run_sheet_texture = AssetLoader.load_texture("res://assets/player_run_sheet.png")
	visual_position = Vector2(player_col, player_row)
	animation_from = visual_position
	animation_to = visual_position
	%YesButton.pressed.connect(_on_confirm_yes_pressed)
	%NoButton.pressed.connect(_on_confirm_no_pressed)
	# The confirm popup is the pack's parchment panel (see PixelPanel); its X counts as No.
	PixelPanel.setup(%ConfirmPanel, %ConfirmArt, %ConfirmClose, CONFIRM_PIXEL_SCALE, _on_confirm_no_pressed)
	# Yes / No use the shared green button look with the tan shadow made for parchment
	# (see PixelButton); stock buttons if assets/buttons.png is missing.
	PixelButton.apply(%YesButton, CONFIRM_PIXEL_SCALE, PixelButton.PARCHMENT_SHADOW_COLOR)
	PixelButton.apply(%NoButton, CONFIRM_PIXEL_SCALE, PixelButton.PARCHMENT_SHADOW_COLOR)
	%ShopCloseButton.pressed.connect(_on_shop_close_pressed)
	inventory_panel.can_open = func() -> bool: return not pause_menu_open
	if NetworkManager.is_multiplayer:
		_setup_multiplayer()

func _setup_multiplayer() -> void:
	player_gold = SessionEconomy.gold
	player_inventory = SessionEconomy.inventory
	player_equipped = SessionEconomy.equipped
	net = TownNetLogic.new(self)
	net.setup()
	shop_mgr.build_panel()  # the shared shop window replaces this scene's own ShopPanel node
	shop_mgr.panel.closed.connect(net.on_shop_closed)
	inventory_panel.can_open = func() -> bool: return not shop_mgr.is_open() and not confirm_canvas.visible and not pause_menu_open
	inventory_panel.get_inventory = loadout_mgr.my_inventory
	inventory_panel.get_gold = loadout_mgr.my_gold
	inventory_panel.get_equipped = loadout_mgr.my_equipped_item_id
	inventory_panel.do_equip = loadout_mgr.equip
	inventory_panel.do_unequip = loadout_mgr.unequip

func _exit_tree() -> void:
	if net != null:
		net.cleanup()

func _process(delta: float) -> void:
	_advance_animation(delta)
	_tick_move_repeat(delta)
	background.position = _grid_origin()
	queue_redraw()

func _advance_animation(delta: float) -> void:
	if net != null:
		net.advance(delta)
		return
	if animation_progress < 1.0:
		animation_progress = min(animation_progress + delta / Constants.MOVE_ANIMATION_DURATION, 1.0)
		var eased_progress: float = ease(animation_progress, -2.0)
		visual_position = animation_from.lerp(animation_to, eased_progress)

		var run_frame_count: int = Constants.PLAYER_RUN_SHEET_FRAME_COUNT
		animation_timer += delta
		if animation_timer >= Constants.PLAYER_ANIMATION_FRAME_DURATION:
			animation_timer = 0.0
			animation_frame_index = (animation_frame_index + 1) % run_frame_count
	else:
		animation_timer = 0.0
		animation_frame_index = 0

		# Idle loops continuously for as long as the player stands still,
		# independent of animation_progress above (that one only exists
		# while a hop is actually playing).
		idle_timer += delta
		if idle_timer >= Constants.PLAYER_IDLE_FRAME_DURATION:
			idle_timer = 0.0
			idle_frame_index = (idle_frame_index + 1) % Constants.PLAYER_IDLE_SHEET_FRAME_COUNT

func _notification(what: int) -> void:
	# The window losing OS focus (alt-tab, etc.) can eat the key-up event
	# entirely, which would otherwise leave a movement key "stuck" held.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_held_move_keys()

func _input(event: InputEvent) -> void:
	# A key-rebind capture in the Escape menu's settings gets the first look at every press.
	if event is InputEventKey and event.pressed and not event.echo and pause_mgr._handle_rebind_key(event):
		return
	if event is InputEventKey and not event.echo and _is_move_keycode(event.keycode):
		if _is_any_popup_open():
			return # movement locked out while a popup is open
		_handle_move_key_event(event.keycode, event.pressed)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			SettingsManager.toggle_fullscreen()
		elif event.keycode == KEY_ESCAPE:
			_on_escape_pressed()
		elif net != null and event.keycode == SettingsManager.get_key_binding("attack") and not _is_any_popup_open():
			net.request_attack()

func _is_any_popup_open() -> bool:
	return confirm_canvas.visible or shop_canvas.visible or inventory_panel.is_open() or shop_mgr.is_open() or pause_menu_open

# Escape closes whatever is on top first (the menu, a shop, the shop prompt, the inventory) and
# otherwise opens the Escape menu. Like in a multiplayer level, nothing pauses -- the menu is local.
func _on_escape_pressed() -> void:
	if pause_menu_open:
		pause_mgr._close_pause_menu()
	elif shop_mgr.is_open():
		shop_mgr.close_shop()  # the multiplayer shop; closing it brings the player back out (see TownNet.on_shop_closed)
	elif shop_canvas.visible:
		_on_shop_close_pressed()
	elif confirm_canvas.visible:
		_on_confirm_no_pressed()
	elif inventory_panel.is_open():
		inventory_panel.close()
	else:
		pause_mgr._open_pause_menu()

# --- Hold-to-move: a hand-ported match for Player.gd's in-level movement --
# --- (see Player.gd for the reasoning behind the two-phase repeat, the ----
# --- live-key re-check before firing, and the focus-loss/pause safety -----
# --- nets -- this is deliberately the same system, just without a `game` --
# --- node or a `game.players` array to hang it off of). --------------------

func _is_move_keycode(keycode: int) -> bool:
	return MoveRepeater.is_move_keycode(keycode)

func _handle_move_key_event(keycode: int, is_pressed: bool) -> void:
	var delta: Array = move_repeater.handle_key_event(keycode, is_pressed)
	if not delta.is_empty():
		_try_move(delta[0], delta[1])

func _tick_move_repeat(delta_time: float) -> void:
	if _is_any_popup_open():
		return
	var hop_in_progress: bool = net.local_busy() if net != null else animation_progress < 1.0
	var delta: Array = move_repeater.tick(delta_time, hop_in_progress, Constants.MOVE_ANIMATION_DURATION)
	if not delta.is_empty():
		_try_move(delta[0], delta[1])

func _clear_held_move_keys() -> void:
	move_repeater.clear()

# --- Grid movement: walls / doors / leaving town ---------------------------

func _try_move(delta_row: int, delta_col: int) -> void:
	if net != null:
		net.request_move(delta_row, delta_col)
		return
	if animation_progress < 1.0:
		return

	var next_row: int = player_row + delta_row
	var next_col: int = player_col + delta_col

	# Only the fully-open road row has no wall at either end -- walking off
	# either edge of it is what leaves the town. Every other row is walled
	# at both ends, so this out-of-grid check never fires for them.
	if next_col < 0 or next_col >= grid_cols:
		_leave_town()
		return
	if next_row < 0 or next_row >= grid_rows:
		return
	if TOWN_GRID[next_row][next_col] == WALL_CHAR:
		return

	# Facing only updates on an actual successful step, same as Player.gd
	# (bumping into a wall doesn't turn the player to face it).
	if delta_row < 0:
		facing_direction = "up"
	elif delta_row > 0:
		facing_direction = "down"
	elif delta_col < 0:
		facing_direction = "left"
	elif delta_col > 0:
		facing_direction = "right"

	_move_to(next_row, next_col)

	if TOWN_GRID[next_row][next_col] == DOOR_CHAR:
		var shop_index: int = _shop_index_at(next_row, next_col)
		if shop_index != -1:
			active_shop_index = shop_index
			_open_confirm_panel(shop_index)

func _move_to(row: int, col: int) -> void:
	player_row = row
	player_col = col
	animation_from = visual_position
	animation_to = Vector2(col, row)
	animation_progress = 0.0

func _shop_index_at(row: int, col: int) -> int:
	for shop_index in range(shops.size()):
		if shops[shop_index]["door_row"] == row and shops[shop_index]["door_col"] == col:
			return shop_index
	return -1

func _leave_town() -> void:
	get_tree().change_scene_to_file(Constants.SCENE_CUTSCENE)

# --- Confirm panel: "Enter the ___ shop? Yes/No" ------------------------

func _open_confirm_panel(shop_index: int) -> void:
	confirm_label.text = shops[shop_index]["prompt"]
	confirm_canvas.visible = true

func _on_confirm_yes_pressed() -> void:
	confirm_canvas.visible = false
	if net != null:
		net.request_hidden(true)  # the shop opens once the host has hidden us (open_shop_panel_for_multiplayer)
		return
	_open_shop_panel(active_shop_index)

func _on_confirm_no_pressed() -> void:
	confirm_canvas.visible = false
	if net != null:
		net.request_move(1, 0)  # step back down off the door
		return
	var shop: Dictionary = shops[active_shop_index]
	facing_direction = "down"
	_move_to(shop["door_row"] + 1, shop["door_col"])

# --- Shop panel: name, close, gold, and a card per item it sells --------

func _open_shop_panel(shop_index: int) -> void:
	shop_title_label.text = shops[shop_index]["name"]
	_refresh_shop_gold_label()
	_populate_shop_items(shop_index)
	shop_canvas.visible = true

# Multiplayer: the host has hidden us, so open the shared shop window for the door we're on.
func open_shop_panel_for_multiplayer() -> void:
	var shop_name: String = shops[active_shop_index]["name"]
	shop_mgr.panel.open(shop_name, ItemData.SHOP_ITEM_IDS.get(shop_name, []))

func _refresh_shop_gold_label() -> void:
	shop_gold_label.text = "Your gold: %d" % CampaignManager.gold

func _populate_shop_items(shop_index: int) -> void:
	# remove_child first so the old cards leave the list immediately rather than
	# lingering (and taking up space) until the end of the frame.
	for child in shop_items_root.get_children():
		shop_items_root.remove_child(child)
		child.queue_free()

	var shop_name: String = shops[shop_index]["name"]
	var item_ids: Array = ItemData.SHOP_ITEM_IDS.get(shop_name, [])
	for item_id: String in item_ids:
		_add_shop_item_card(item_id)

func _add_shop_item_card(item_id: String) -> void:
	var item: Dictionary = ItemData.get_item(item_id)
	if item.is_empty():
		return

	var card: Control = SHOP_CARD_SCENE.instantiate()
	shop_items_root.add_child(card)

	var icon_texture: Texture2D = ItemData.get_item_icon(item_id)
	var icon_rect: TextureRect = card.get_node("Icon")
	icon_rect.texture = icon_texture
	icon_rect.visible = icon_texture != null
	var text_column: Control = card.get_node("TextColumn")
	if icon_texture == null:
		text_column.position.x = SHOP_CARD_TEXT_LEFT_WITHOUT_ICON

	var name_label: Label = card.get_node("TextColumn/NameLabel")
	name_label.text = item.get("name", item_id)
	var cost_label: Label = card.get_node("TextColumn/CostLabel")
	cost_label.text = "%d gold" % int(item.get("cost", 0))
	var owned_label: Label = card.get_node("TextColumn/OwnedLabel")
	owned_label.text = "Owned: %d" % CampaignManager.get_item_quantity(item_id)
	var status_label: Label = card.get_node("TextColumn/StatusLabel")

	var buy_button: Button = card.get_node("BuyButton")
	buy_button.pressed.connect(_on_buy_item_pressed.bind(item_id, owned_label, status_label))
	PixelButton.apply(buy_button) # the shared green button look; default button if assets/buttons.png is missing

func _on_buy_item_pressed(item_id: String, owned_label: Label, status_label: Label) -> void:
	var item: Dictionary = ItemData.get_item(item_id)
	var cost: int = int(item.get("cost", 0))
	if CampaignManager.gold < cost:
		status_label.text = "Not enough gold!"
		status_label.add_theme_color_override("font_color", Constants.STATUS_ERROR_COLOR)
		return
	CampaignManager.gold -= cost
	CampaignManager.add_item(item_id) # also persists the purchase -- see the comment on add_item()
	status_label.text = "Purchased!"
	status_label.add_theme_color_override("font_color", Constants.STATUS_SUCCESS_COLOR)
	owned_label.text = "Owned: %d" % CampaignManager.get_item_quantity(item_id)
	_refresh_shop_gold_label()

func _on_shop_close_pressed() -> void:
	shop_canvas.visible = false
	var shop: Dictionary = shops[active_shop_index]
	facing_direction = "down"
	_move_to(shop["door_row"] + 1, shop["door_col"])

# --- Drawing -------------------------------------------------------------

# Where the town's top-left corner is on screen -- the same camera math the
# level's puzzle board uses (GridGeometry.compute_view_window). Town's window is
# sized to fit its whole grid (see _ready()), so this normally just comes out as
# centering; using the shared function anyway (rather than a Town-only formula)
# means a bigger-than-one-screen town would scroll for free. Used both to place
# the town art node (in _process) and to draw the player over it (in _draw), so
# the two always agree.
func _grid_origin() -> Vector2:
	var viewport_size: Vector2 = get_viewport_rect().size
	var view_window: Dictionary = GridGeometry.compute_view_window(grid_rows, grid_cols, Constants.CELL_SIZE, player_row, player_col, viewport_size.x, viewport_size.y)
	return Vector2(view_window["extra_x"], view_window["extra_y"]) - Vector2(view_window["view_col_start"], view_window["view_row_start"]) * Constants.CELL_SIZE

# The town art itself is the Background node; this just draws the player on top
# (the node is show_behind_parent, so it sits underneath what's drawn here).
func _draw() -> void:
	if net != null:
		net.draw(_grid_origin())
		return
	_draw_player(_grid_origin())

func _draw_player(grid_origin: Vector2) -> void:
	var body_center: Vector2 = GridGeometry.tile_center_to_pixel(visual_position.y, visual_position.x, grid_origin, Constants.CELL_SIZE)
	var is_moving: bool = animation_progress < 1.0
	_draw_character(body_center, is_moving, animation_frame_index if is_moving else idle_frame_index, facing_direction, Constants.PLAYER_COLORS[0], CampaignManager.get_equipped_item_id("armor"))

# One walker: body sprite (run sheet while hopping, idle sheet otherwise) in the given tint, plus
# the armor overlay for armor_item_id ("" = none). Shared by the campaign's single player and
# TownNet's many.
func _draw_character(body_center: Vector2, is_moving: bool, active_frame_index: int, facing: String, tint: Color, armor_item_id: String) -> void:
	var active_texture: Texture2D
	# Which sheet kind is showing, for picking the matching equipped-armor
	# overlay art and offset -- see Player.gd's _draw_players.
	var overlay_kind: String
	if is_moving:
		active_texture = player_run_sheet_texture
		overlay_kind = "run"
	else:
		active_texture = player_idle_sheet_texture
		overlay_kind = "idle"

	var source_direction: String = "right" if facing == "left" else facing
	var direction_row: int = Constants.PLAYER_SHEET_DIRECTION_ROWS.get(source_direction, 0)
	var source_rectangle: Rect2 = Rect2(
		active_frame_index * Constants.PLAYER_SHEET_FRAME_WIDTH,
		direction_row * Constants.PLAYER_SHEET_FRAME_HEIGHT,
		Constants.PLAYER_SHEET_FRAME_WIDTH,
		Constants.PLAYER_SHEET_FRAME_HEIGHT
	)
	var sprite_size: float = Constants.CELL_SIZE * 0.9
	var destination_rectangle: Rect2 = Rect2(
		body_center.x - sprite_size / 2.0, body_center.y - sprite_size / 2.0,
		sprite_size, sprite_size
	)
	var flip_horizontally: bool = facing == "left"
	if flip_horizontally:
		# Same mirror-via-canvas-transform approach as Player.gd (see the
		# comment there for why not a negative-width source rect): rects
		# drawn while it's active are relative to body_center.
		draw_set_transform(body_center, 0.0, Vector2(-1.0, 1.0))
		destination_rectangle.position -= body_center
	draw_texture_rect_region(active_texture, destination_rectangle, source_rectangle, tint)
	_draw_equipped_armor_overlay(armor_item_id, facing, overlay_kind, active_frame_index, destination_rectangle)
	if flip_horizontally:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# Equipped armor's visual (e.g. a hat), drawn over the just-drawn body
# sprite -- mirrors Player.gd's _draw_equipped_armor_overlay exactly (see
# there for why the math is what it is); the caller says whose armor it is.
func _draw_equipped_armor_overlay(armor_item_id: String, facing: String, sheet_kind: String, frame_index: int, body_destination_rectangle: Rect2) -> void:
	if armor_item_id == "":
		return
	var overlay_direction: String = "right" if facing == "left" else facing
	var overlay_texture: Texture2D = ItemData.get_item_overlay_texture(armor_item_id, sheet_kind, overlay_direction)
	if overlay_texture == null:
		return

	var overlay_frame_width: int = Constants.PLAYER_SHEET_FRAME_WIDTH
	var overlay_frame_count: int = maxi(1, overlay_texture.get_width() / overlay_frame_width)
	var body_frame_count: int = Constants.OVERLAY_BODY_FRAME_COUNTS.get(sheet_kind, overlay_frame_count)
	var overlay_frame_index: int = frame_index
	if overlay_frame_count != body_frame_count:
		overlay_frame_index = int(float(frame_index) * overlay_frame_count / body_frame_count)
	overlay_frame_index = clampi(overlay_frame_index, 0, overlay_frame_count - 1)

	var overlay_source_rectangle: Rect2 = Rect2(
		overlay_frame_index * overlay_frame_width, 0,
		overlay_frame_width, overlay_texture.get_height()
	)
	var scale_factor: float = body_destination_rectangle.size.x / float(Constants.PLAYER_SHEET_FRAME_WIDTH)
	var top_offset: float = float(Constants.OVERLAY_TOP_OFFSET_PIXELS.get(sheet_kind, 0)) * scale_factor
	var overlay_destination_rectangle: Rect2 = Rect2(
		body_destination_rectangle.position.x,
		body_destination_rectangle.position.y - top_offset,
		overlay_frame_width * scale_factor,
		overlay_texture.get_height() * scale_factor
	)
	# No source flip needed here for left-facing: _draw_player has already
	# mirrored the canvas around the body when facing left.
	draw_texture_rect_region(overlay_texture, overlay_destination_rectangle, overlay_source_rectangle, Color(1, 1, 1, 1))

# --- Multiplayer RPC entry points: the logic is in TownNet.gd / ShopManager.gd / LoadoutManager.gd ---

@rpc("any_peer", "call_remote", "reliable")
func _town_ready() -> void:
	if net != null:
		net._request_ready()

@rpc("authority", "call_remote", "reliable")
func _town_full_sync(snapshot: Array) -> void:
	if net != null:
		net._full_sync(snapshot)

@rpc("any_peer", "call_remote", "reliable")
func _town_request_move(player_index: int, delta_row: int, delta_col: int) -> void:
	if net != null:
		net._request_move(player_index, delta_row, delta_col)

@rpc("authority", "call_local", "reliable")
func _town_sync_move(player_index: int, row: int, col: int, facing: String) -> void:
	if net != null:
		net._sync_move(player_index, row, col, facing)

@rpc("any_peer", "call_remote", "reliable")
func _town_request_hidden(player_index: int, should_hide: bool) -> void:
	if net != null:
		net._request_hidden(player_index, should_hide)

@rpc("authority", "call_local", "reliable")
func _town_sync_hidden(player_index: int, should_hide: bool, row: int, col: int, facing: String) -> void:
	if net != null:
		net._sync_hidden(player_index, should_hide, row, col, facing)

@rpc("any_peer", "call_remote", "reliable")
func _town_request_attack(player_index: int) -> void:
	if net != null:
		net._request_attack(player_index)

@rpc("authority", "call_local", "reliable")
func _town_sync_hit(attacker_index: int, target_index: int, new_health: int, died: bool) -> void:
	if net != null:
		net._sync_hit(attacker_index, target_index, new_health, died)

@rpc("authority", "call_local", "reliable")
func _town_sync_departed(player_index: int) -> void:
	if net != null:
		net._sync_departed(player_index)

@rpc("authority", "call_local", "reliable")
func _town_sync_loading() -> void:
	if net != null:
		net._sync_loading()

@rpc("any_peer", "call_remote", "reliable")
func _request_purchase(player_index: int, item_id: String) -> void:
	shop_mgr._request_purchase(player_index, item_id)

@rpc("authority", "call_local", "reliable")
func _sync_purchase(player_index: int, item_id: String, new_gold: int, new_quantity: int) -> void:
	shop_mgr._sync_purchase(player_index, item_id, new_gold, new_quantity)

@rpc("authority", "call_remote", "reliable")
func _purchase_rejected(item_id: String, message: String) -> void:
	shop_mgr._purchase_rejected(item_id, message)

@rpc("any_peer", "call_remote", "reliable")
func _request_equip(player_index: int, slot: String, item_id: String) -> void:
	loadout_mgr._request_equip(player_index, slot, item_id)

@rpc("authority", "call_local", "reliable")
func _sync_equipped(player_index: int, slot: String, item_id: String) -> void:
	loadout_mgr._sync_equipped(player_index, slot, item_id)
