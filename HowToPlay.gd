extends MenuScreen

# ---------------------------------------------------------------------------
# A scrolling text page: the Back button and title stay pinned top-left
# outside the ScrollContainer, and everything else lives inside it and
# wraps/stacks via a VBoxContainer (see HowToPlay.tscn), so the page works
# regardless of how long the rules text gets.
#
# The only thing done in code is filling in the player's current key
# bindings: the Controls text in the scene contains {move_up}, {attack}, etc.
# placeholders, which are replaced here since the bindings are rebindable.
# ---------------------------------------------------------------------------

@onready var controls_body: Label = %ControlsBody

func _ready() -> void:
	super._ready()
	controls_body.text = controls_body.text.format({
		"move_up": SettingsManager.get_key_label("move_up"),
		"move_left": SettingsManager.get_key_label("move_left"),
		"move_down": SettingsManager.get_key_label("move_down"),
		"move_right": SettingsManager.get_key_label("move_right"),
		"place_light": SettingsManager.get_key_label("place_light"),
		"attack": SettingsManager.get_key_label("attack"),
		"block": SettingsManager.get_key_label("block"),
	})
