class_name LobbySlots
extends Control

# ---------------------------------------------------------------------------
# The four player slots on the Hosting / Connected lobby screens: a row of
# pedestals (one per possible player). A slot "fills up" when a player joins --
# their character drops in on the idle animation, sized up and tinted with the
# colour they'll have on the board (Constants.PLAYER_COLORS[slot]), with their
# name underneath. Empty slots are just the bare pedestal and "Open".
#
# Purely visual: Lobby.gd feeds it the roster through set_entries() whenever
# NetworkManager's player list changes, on the host and on every client alike
# (the names arrive with that list -- see NetworkManager._update_player_list).
# ---------------------------------------------------------------------------

const SLOT_COUNT: int = 4  # == NetworkManager.MAX_PLAYERS (an autoload isn't usable in a const)

const CHARACTER_SIZE: float = 160.0        # 5x the 32px sheet frame, so the pixels stay crisp
const FEET_PADDING_RATIO: float = 0.12     # transparent rows under the feet in a sheet frame; raise it if the character floats, lower it if it sinks into the pedestal
const PEDESTAL_HEIGHT: float = 40.0
const PEDESTAL_TOP_HEIGHT: float = 10.0
const PEDESTAL_MAX_WIDTH: float = 180.0
const PEDESTAL_WIDTH_RATIO: float = 0.78   # of the slot's width
const LABEL_AREA_HEIGHT: float = 64.0      # name + role line under the pedestal
const DROP_IN_DURATION: float = 0.35
const DROP_IN_HEIGHT: float = 40.0

const PEDESTAL_TOP_COLOR: Color = Color(0.42, 0.44, 0.58)
const PEDESTAL_BODY_COLOR: Color = Color(0.26, 0.28, 0.40)
const OPEN_TEXT_COLOR: Color = Color(0.62, 0.64, 0.72)

var idle_texture: Texture2D
var idle_timer: float = 0.0
var idle_frame: int = 0

var entries: Array = []  # [{"name": String, "is_host": bool, "is_you": bool}], one per filled slot, in slot order
var fill_age: Array[float] = []  # seconds since each slot filled; -1.0 while it's empty
var name_labels: Array[Label] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	idle_texture = AssetLoader.load_texture("res://assets/player_idle_sheet.png")
	for slot_index in range(SLOT_COUNT):
		fill_age.append(-1.0)
		var name_label: Label = Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		name_label.clip_text = true
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		name_label.add_theme_constant_override("outline_size", 4)
		add_child(name_label)
		name_labels.append(name_label)
	resized.connect(_layout_labels)
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	set_process(is_visible_in_tree())
	_layout_labels()
	_refresh_labels()

# Forget everything (the lobby screen is opening fresh): the next set_entries() drops each player in.
func reset() -> void:
	entries = []
	for slot_index in range(fill_age.size()):
		fill_age[slot_index] = -1.0
	_refresh_labels()
	queue_redraw()

# One dictionary per player in slot order ({"name", "is_host", "is_you"}); anything past SLOT_COUNT is ignored.
func set_entries(new_entries: Array) -> void:
	entries = new_entries.slice(0, SLOT_COUNT)
	for slot_index in range(fill_age.size()):
		var is_filled: bool = slot_index < entries.size()
		if is_filled and fill_age[slot_index] < 0.0:
			fill_age[slot_index] = 0.0  # just joined: play the drop-in
		elif not is_filled:
			fill_age[slot_index] = -1.0
	_refresh_labels()
	queue_redraw()

func _process(delta: float) -> void:
	idle_timer += delta
	if idle_timer >= Constants.PLAYER_IDLE_FRAME_DURATION:
		idle_timer = 0.0
		idle_frame = (idle_frame + 1) % Constants.PLAYER_IDLE_SHEET_FRAME_COUNT
	for slot_index in range(fill_age.size()):
		if fill_age[slot_index] >= 0.0:
			fill_age[slot_index] += delta
	queue_redraw()

func _slot_width() -> float:
	return size.x / float(SLOT_COUNT)

func _slot_center_x(slot_index: int) -> float:
	return _slot_width() * (float(slot_index) + 0.5)

# y of the pedestal's top edge (what the characters stand on).
func _pedestal_top_y() -> float:
	return size.y - LABEL_AREA_HEIGHT - PEDESTAL_HEIGHT

func _slot_color(slot_index: int) -> Color:
	return Constants.PLAYER_COLORS[slot_index % Constants.PLAYER_COLORS.size()]

func _layout_labels() -> void:
	var label_top: float = _pedestal_top_y() + PEDESTAL_HEIGHT + 6.0
	for slot_index in range(name_labels.size()):
		name_labels[slot_index].position = Vector2(_slot_center_x(slot_index) - _slot_width() / 2.0, label_top)
		name_labels[slot_index].size = Vector2(_slot_width(), LABEL_AREA_HEIGHT - 6.0)

func _refresh_labels() -> void:
	for slot_index in range(name_labels.size()):
		var name_label: Label = name_labels[slot_index]
		if slot_index < entries.size():
			var entry: Dictionary = entries[slot_index]
			var role_parts: Array[String] = []
			if entry.get("is_host", false):
				role_parts.append("Host")
			if entry.get("is_you", false):
				role_parts.append("You")
			name_label.text = "%s\n%s" % [entry.get("name", ""), " - ".join(role_parts)]
			name_label.add_theme_color_override("font_color", _slot_color(slot_index))
		else:
			name_label.text = "Open"
			name_label.add_theme_color_override("font_color", OPEN_TEXT_COLOR)

func _draw() -> void:
	var pedestal_top: float = _pedestal_top_y()
	var pedestal_width: float = minf(_slot_width() * PEDESTAL_WIDTH_RATIO, PEDESTAL_MAX_WIDTH)
	for slot_index in range(SLOT_COUNT):
		var center_x: float = _slot_center_x(slot_index)
		var is_filled: bool = slot_index < entries.size() and fill_age[slot_index] >= 0.0
		var tint: Color = _slot_color(slot_index)
		var left: float = center_x - pedestal_width / 2.0

		# Pedestal: lit top face, darker body, and a band in the slot's colour (dim until somebody's there).
		var top_color: Color = PEDESTAL_TOP_COLOR.lerp(tint, 0.35) if is_filled else PEDESTAL_TOP_COLOR
		var band_color: Color = tint if is_filled else tint.darkened(0.55)
		draw_rect(Rect2(left, pedestal_top, pedestal_width, PEDESTAL_TOP_HEIGHT), top_color)
		draw_rect(Rect2(left, pedestal_top + PEDESTAL_TOP_HEIGHT, pedestal_width, PEDESTAL_HEIGHT - PEDESTAL_TOP_HEIGHT), PEDESTAL_BODY_COLOR)
		draw_rect(Rect2(left, pedestal_top + PEDESTAL_TOP_HEIGHT + 8.0, pedestal_width, 6.0), band_color)

		if not is_filled or idle_texture == null:
			continue
		# The character: first idle row ("down", facing the viewer), staggered per slot so they don't all bob in unison.
		var drop_progress: float = clampf(fill_age[slot_index] / DROP_IN_DURATION, 0.0, 1.0)
		var eased_progress: float = 1.0 - pow(1.0 - drop_progress, 3.0)
		var feet_y: float = pedestal_top + CHARACTER_SIZE * FEET_PADDING_RATIO - (1.0 - eased_progress) * DROP_IN_HEIGHT
		var destination_rectangle: Rect2 = Rect2(center_x - CHARACTER_SIZE / 2.0, feet_y - CHARACTER_SIZE, CHARACTER_SIZE, CHARACTER_SIZE)
		var source_rectangle: Rect2 = Rect2(
			((idle_frame + slot_index) % Constants.PLAYER_IDLE_SHEET_FRAME_COUNT) * Constants.PLAYER_SHEET_FRAME_WIDTH,
			Constants.PLAYER_SHEET_DIRECTION_ROWS["down"] * Constants.PLAYER_SHEET_FRAME_HEIGHT,
			Constants.PLAYER_SHEET_FRAME_WIDTH,
			Constants.PLAYER_SHEET_FRAME_HEIGHT
		)
		draw_texture_rect_region(idle_texture, destination_rectangle, source_rectangle, Color(tint, eased_progress))
