extends Node

# ---------------------------------------------------------------------------
# Autoload (registered in project.godot). Persists display preferences to
# disk (user://settings.cfg) and is the single place every scene goes
# through to size its window, so a preference set once in Settings.tscn
# (or via the F11 shortcut, available everywhere) sticks across every
# scene transition and future launches.
# ---------------------------------------------------------------------------

const SAVE_PATH: String = "user://settings.cfg"
const SAVE_SECTION: String = "display"
const CONTROLS_SECTION: String = "controls"

const SIZE_PRESETS: Array[Vector2i] = [
	Vector2i(1024, 576),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
const DEFAULT_WINDOW_SIZE: Vector2i = Vector2i(Constants.DEFAULT_WINDOW_WIDTH, Constants.DEFAULT_WINDOW_HEIGHT)

# Rebindable actions -- movement, placing a light, attacking, and blocking,
# per the player's own request. Fullscreen (F11) and pause
# (Escape) are intentionally not included here and stay fixed.
const KEY_BINDING_ACTIONS: Array[String] = [
	"move_up", "move_down", "move_left", "move_right", "place_light", "attack", "block",
]
const KEY_BINDING_LABELS: Dictionary = {
	"move_up": "Move Up",
	"move_down": "Move Down",
	"move_left": "Move Left",
	"move_right": "Move Right",
	"place_light": "Place Light",
	"attack": "Attack",
	"block": "Block",
}
const DEFAULT_KEY_BINDINGS: Dictionary = {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"place_light": KEY_P,
	"attack": KEY_SPACE,
	"block": KEY_SHIFT,
}

var is_fullscreen: bool = false
var window_size: Vector2i = DEFAULT_WINDOW_SIZE
var key_bindings: Dictionary = DEFAULT_KEY_BINDINGS.duplicate()

func _ready() -> void:
	_load_settings()
	_apply_fullscreen_mode()

func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var load_result: int = config.load(SAVE_PATH)
	if load_result == OK:
		is_fullscreen = config.get_value(SAVE_SECTION, "fullscreen", false)
		var saved_width: int = config.get_value(SAVE_SECTION, "window_width", DEFAULT_WINDOW_SIZE.x)
		var saved_height: int = config.get_value(SAVE_SECTION, "window_height", DEFAULT_WINDOW_SIZE.y)
		window_size = Vector2i(saved_width, saved_height)
		for action: String in KEY_BINDING_ACTIONS:
			key_bindings[action] = config.get_value(CONTROLS_SECTION, action, DEFAULT_KEY_BINDINGS[action])

func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SAVE_SECTION, "fullscreen", is_fullscreen)
	config.set_value(SAVE_SECTION, "window_width", window_size.x)
	config.set_value(SAVE_SECTION, "window_height", window_size.y)
	for action: String in KEY_BINDING_ACTIONS:
		config.set_value(CONTROLS_SECTION, action, key_bindings[action])
	var save_result: Error = config.save(SAVE_PATH)
	if save_result != OK:
		push_error("Failed to save settings: %s" % error_string(save_result))

func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen)

func set_fullscreen(enabled: bool) -> void:
	is_fullscreen = enabled
	_save_settings()
	_apply_fullscreen_mode()

func _apply_fullscreen_mode() -> void:
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func set_window_size(new_size: Vector2i) -> void:
	window_size = new_size
	_save_settings()
	if not is_fullscreen:
		get_window().size = window_size

func get_key_binding(action: String) -> Key:
	return key_bindings.get(action, DEFAULT_KEY_BINDINGS.get(action, KEY_NONE))

func get_key_label(action: String) -> String:
	return OS.get_keycode_string(get_key_binding(action))

# Swaps rather than allowing a collision: if the chosen key is already bound
# to a different action, that action gets the key being replaced, so two
# actions are never left bound to the same key.
func set_key_binding(action: String, keycode: Key) -> void:
	for other_action: String in KEY_BINDING_ACTIONS:
		if other_action != action and key_bindings[other_action] == keycode:
			key_bindings[other_action] = key_bindings[action]
			break
	key_bindings[action] = keycode
	_save_settings()

func reset_key_bindings_to_default() -> void:
	key_bindings = DEFAULT_KEY_BINDINGS.duplicate()
	_save_settings()

# Every scene calls this from _ready() instead of setting get_window().size
# directly. Applies fullscreen if that's the active preference; otherwise
# sizes the window to the larger of the user's preferred size and whatever
# minimum that particular scene's own content actually needs (e.g. a big
# puzzle board, or a text-heavy page like How to Play).
func apply_window_size(minimum_width: int, minimum_height: int) -> void:
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var applied_width: int = max(window_size.x, minimum_width)
	var applied_height: int = max(window_size.y, minimum_height)
	get_window().size = Vector2i(applied_width, applied_height)
