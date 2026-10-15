extends RefCounted
# Pause menu -- opened/closed with Escape (see Game._input). In singleplayer
# this also halts all countdowns/simulation/animation (see the early-return
# in Game._process); in multiplayer the shared game keeps running for every
# peer regardless -- opening this menu is purely local to whoever opened it.
# Deliberately does not use SceneTree.paused: that would also freeze this
# menu's own buttons (and, in multiplayer, nothing local should stop at all
# except this player's own input). Settings is an in-place panel here, not
# the Settings.tscn scene, specifically so closing it returns to this same
# in-progress game -- leaving Game.tscn entirely has nowhere to restore the
# board/players/enemies from, since none of that is currently saved.
#
# Split out of GameUIManager.gd, which kept window sizing/layout, the
# status label/win-state transition, and the in-play HUD (now HUDManager.gd).
# Operates on shared board/combat state via the `game` back-reference, same
# as every other manager.

# LOOK: the layout -- both parchment windows (this menu and the in-place Settings
# view), every label, button, size and position -- lives in PauseMenu.tscn, so
# restyling or moving things is done in the editor. This script only does what
# a scene can't: draw the parchment art (PixelPanel, from assets/main_menu.png),
# skin the buttons (PixelButton, with the pack's tan shadow for sitting on
# parchment), wire button presses, and make the rows that come from data (one
# button per window-size preset and per key binding, from PauseMenuRowButton.tscn).
#
# The pack's art is tiny, so it's enlarged by PAUSE_PIXEL_SCALE whole pixels.
# That number only scales the art -- the scene's sizes are written for 3, and
# each panel's width and height should stay a multiple of it (a warning is
# logged otherwise). To change the scale, change it here AND resize the
# panels and buttons in PauseMenu.tscn to match.
const PAUSE_MENU_SCENE: PackedScene = preload("res://PauseMenu.tscn")
const ROW_BUTTON_SCENE: PackedScene = preload("res://PauseMenuRowButton.tscn")
const PAUSE_PIXEL_SCALE: int = 3
const PIXEL_BUTTON_GROUP: String = "pause_pixel_button"  # buttons in PauseMenu.tscn / the row scene that get the pixel skin

const TOWN_PAUSE_LAYER: int = 110  # above the Town's "Loading/Waiting" popup (layer 100), so the menu stays usable while waiting

# The Town (Town.gd) uses this same menu -- the controls/window settings and the way out to the Main
# Menu -- with the level-only parts (status, Check Answer, Reset) left out. It marks itself with
# an `is_town` field; Game has none.
func _in_town() -> bool:
	return game.get("is_town") == true

var game: Node2D

func _init(game_ref: Node2D) -> void:
	game = game_ref

var pause_canvas: CanvasLayer
var pause_menu_view: Control
var pause_settings_view: Control
var pause_fullscreen_button: Button
var pause_size_buttons: Array[Button] = []
var pause_rebind_buttons: Dictionary = {}  # action -> Button
var pause_listening_action: String = ""  # "" when not capturing a key press

func _toggle_pause_menu() -> void:
	if game.pause_menu_open:
		_close_pause_menu()
	else:
		_open_pause_menu()

func _open_pause_menu() -> void:
	if pause_canvas == null:
		_build_pause_menu()
	game.pause_menu_open = true
	if _in_town():
		game.move_repeater.clear()
	else:
		game.player_mgr._clear_held_move_keys()
	pause_menu_view.visible = true
	pause_settings_view.visible = false
	pause_canvas.visible = true

func _close_pause_menu() -> void:
	game.pause_menu_open = false
	if pause_canvas != null:
		pause_canvas.visible = false
	game.queue_redraw()

# A node the scene marked "unique name in owner" (the % names in PauseMenu.tscn).
func _node(node_name: String) -> Node:
	return pause_canvas.get_node("%" + node_name)

func _build_pause_menu() -> void:
	pause_canvas = PAUSE_MENU_SCENE.instantiate() as CanvasLayer  # hidden until _open_pause_menu()
	if _in_town():
		pause_canvas.layer = TOWN_PAUSE_LAYER
	game.add_child(pause_canvas)
	pause_menu_view = _node("MainView")
	pause_settings_view = _node("SettingsView")

	_setup_main_view()
	_setup_settings_view()

	# Every button the scene put in the group -- including the rows just added
	# above -- gets the pixel-art skin.
	for node: Node in game.get_tree().get_nodes_in_group(PIXEL_BUTTON_GROUP):
		PixelButton.apply(node as Button, PAUSE_PIXEL_SCALE, PixelButton.PARCHMENT_SHADOW_COLOR)

func _setup_main_view() -> void:
	var show_admin_buttons: bool = (not NetworkManager.is_multiplayer) or game.multiplayer.is_server()
	if _in_town():
		_arrange_main_view_for_town()
	PixelPanel.setup(_node("MainPanel"), _node("MainArt"), _node("MainClose"), PAUSE_PIXEL_SCALE, _close_pause_menu)
	if _in_town():
		_node("ResumeButton").pressed.connect(_close_pause_menu)
		_node("SettingsButton").pressed.connect(_on_pause_settings_pressed)
		_node("MainMenuButton").pressed.connect(_on_pause_main_menu_pressed)
		return

	# game.status_label already carries the "N / M white cells lit" text (set in
	# GameUIManager._update_status()), on a placeholder label made when the level
	# started. The scene's own label takes over from it, keeping what it held.
	var placeholder: Label = game.status_label
	var status_label: Label = _node("StatusLabel")
	status_label.text = placeholder.text
	status_label.visible = placeholder.visible
	if placeholder.has_theme_color_override("font_color"):
		status_label.add_theme_color_override("font_color", placeholder.get_theme_color("font_color"))
	game.status_label = status_label
	placeholder.free()

	game.check_button = _node("CheckButton")
	game.check_button.pressed.connect(game._on_check_pressed)

	# Reset is the host's call: everyone else sees a note in its place.
	if show_admin_buttons:
		_node("ResetNote").queue_free()
		game.reset_button = _node("ResetButton")
		game.reset_button.pressed.connect(game._on_reset_pressed)
	else:
		_node("ResetButton").queue_free()

	_node("ResumeButton").pressed.connect(_close_pause_menu)
	_node("SettingsButton").pressed.connect(_on_pause_settings_pressed)
	_node("MainMenuButton").pressed.connect(_on_pause_main_menu_pressed)

# The Town has no board: drop the status line, Check Answer and Reset, move Resume / Settings /
# Main Menu up into their space and shrink the panel to match (both by multiples of the pixel scale).
func _arrange_main_view_for_town() -> void:
	for node_name: String in ["StatusLabel", "CheckButton", "ResetButton", "ResetNote"]:
		_node(node_name).queue_free()
	const SHIFT_UP: float = 102.0  # Resume's top (205) -> where Check Answer was (103)
	for node_name: String in ["ResumeButton", "SettingsButton", "MainMenuButton"]:
		var button: Control = _node(node_name)
		button.offset_top -= SHIFT_UP
		button.offset_bottom -= SHIFT_UP
	var panel: Control = _node("MainPanel")
	panel.offset_top += SHIFT_UP / 2.0
	panel.offset_bottom -= SHIFT_UP / 2.0

func _setup_settings_view() -> void:
	# The X here goes back to the pause menu, same as the Back button -- it also
	# has to drop any half-finished key-rebind capture, which is why it's not
	# just "close the whole menu".
	PixelPanel.setup(_node("SettingsPanel"), _node("SettingsArt"), _node("SettingsClose"), PAUSE_PIXEL_SCALE, _on_pause_settings_back_pressed)

	pause_fullscreen_button = _node("FullscreenButton")
	pause_fullscreen_button.pressed.connect(_on_pause_fullscreen_pressed)

	# One row per window-size preset and per rebindable action -- how many comes
	# from SettingsManager, so these are made here rather than placed in the scene.
	pause_size_buttons.clear()
	var size_column: Control = _node("SizeColumn")
	for preset: Vector2i in SettingsManager.SIZE_PRESETS:
		var size_button: Button = ROW_BUTTON_SCENE.instantiate()
		size_button.pressed.connect(_on_pause_size_selected.bind(preset))
		size_column.add_child(size_button)
		pause_size_buttons.append(size_button)

	pause_rebind_buttons.clear()
	var rebind_column: Control = _node("RebindColumn")
	for action: String in SettingsManager.KEY_BINDING_ACTIONS:
		var rebind_button: Button = ROW_BUTTON_SCENE.instantiate()
		rebind_button.pressed.connect(_on_pause_rebind_pressed.bind(action))
		rebind_column.add_child(rebind_button)
		pause_rebind_buttons[action] = rebind_button

	_node("ResetControlsButton").pressed.connect(_on_pause_reset_controls_pressed)
	_node("BackButton").pressed.connect(_on_pause_settings_back_pressed)
	_refresh_pause_settings_labels()

func _refresh_pause_settings_labels() -> void:
	pause_fullscreen_button.text = "Fullscreen: ON" if SettingsManager.is_fullscreen else "Fullscreen: OFF"
	for button_index in range(pause_size_buttons.size()):
		var preset: Vector2i = SettingsManager.SIZE_PRESETS[button_index]
		var label_text: String = "%dx%d" % [preset.x, preset.y]
		if preset == SettingsManager.window_size:
			label_text = "[%s]" % label_text
		pause_size_buttons[button_index].text = label_text
	for action: String in SettingsManager.KEY_BINDING_ACTIONS:
		if action == pause_listening_action:
			pause_rebind_buttons[action].text = "%s: press a key…" % SettingsManager.KEY_BINDING_LABELS[action]
		else:
			pause_rebind_buttons[action].text = "%s: %s" % [SettingsManager.KEY_BINDING_LABELS[action], SettingsManager.get_key_label(action)]

func _on_pause_settings_pressed() -> void:
	pause_menu_view.visible = false
	pause_settings_view.visible = true

func _on_pause_settings_back_pressed() -> void:
	pause_listening_action = ""
	_refresh_pause_settings_labels()
	pause_settings_view.visible = false
	pause_menu_view.visible = true

# The level re-lays itself out after a window change; the Town just follows the viewport on its own.
func _refresh_layout() -> void:
	if not _in_town():
		game.ui_mgr.call_deferred("_update_layout")

func _on_pause_fullscreen_pressed() -> void:
	SettingsManager.toggle_fullscreen()
	_refresh_layout()
	_refresh_pause_settings_labels()

func _on_pause_size_selected(preset: Vector2i) -> void:
	SettingsManager.set_window_size(preset)
	_refresh_layout()
	_refresh_pause_settings_labels()

func _on_pause_rebind_pressed(action: String) -> void:
	pause_listening_action = action
	_refresh_pause_settings_labels()

func _on_pause_reset_controls_pressed() -> void:
	SettingsManager.reset_key_bindings_to_default()
	_refresh_pause_settings_labels()

# Called from Game._input for every key press, before anything else (Escape
# included) gets a chance to act on it. Returns true if a rebind capture was
# in progress and this key was consumed by it -- the caller should stop
# processing the event in that case. Escape cancels the capture without
# changing the binding (rather than opening/closing the pause menu); F11 is
# rejected the same way since it's reserved for fullscreen.
func _handle_rebind_key(event: InputEventKey) -> bool:
	if pause_listening_action == "":
		return false
	if event.keycode != KEY_ESCAPE and event.keycode != KEY_F11:
		SettingsManager.set_key_binding(pause_listening_action, event.keycode)
	pause_listening_action = ""
	_refresh_pause_settings_labels()
	return true

func _on_pause_main_menu_pressed() -> void:
	if not _in_town():
		game._finalize_endless_run()
	game.pause_menu_open = false
	NetworkManager.leave_game()
	game.get_tree().change_scene_to_file(Constants.SCENE_MAIN_MENU)
