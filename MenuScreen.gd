class_name MenuScreen
extends Control

# ---------------------------------------------------------------------------
# Base class for standalone menu-style scenes -- Main Menu, Settings, How to
# Play, Stats, Lobby, Cutscene. The UI itself now lives in each scene's
# .tscn (open the scene in the editor to see and edit it); the scripts only
# hold behavior. What's shared here is the window sizing, the F11 fullscreen
# toggle, and the default Back-button behavior.
#
# Every menu scene's root is a Control set to Full Rect. Scenes with a Back
# button connect its "pressed" signal to _on_back_pressed() below (in the
# scene file / Node dock), so no script needs to wire that up itself.
#
# Subclasses that override _ready() or _input() and still want this
# behavior must call super() first (GDScript doesn't auto-chain these the
# way _init does).
# ---------------------------------------------------------------------------

func _ready() -> void:
	SettingsManager.apply_window_size(Constants.DEFAULT_WINDOW_WIDTH, Constants.DEFAULT_WINDOW_HEIGHT)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		SettingsManager.toggle_fullscreen()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(Constants.SCENE_MAIN_MENU)
