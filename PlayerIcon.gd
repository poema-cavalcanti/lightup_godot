class_name PlayerIcon
extends Panel

# ---------------------------------------------------------------------------
# One player's circle in the HUD's players row (HUD.tscn's PlayersStat; built
# by HUD.gd in multiplayer only): the first frame of the idle sheet in that
# player's board colour, ringed in the same colour. Hovering it shows the
# player's name underneath.
# ---------------------------------------------------------------------------

@onready var texture_rect: TextureRect = %Texture
@onready var name_label: Label = %NameLabel

# Call after adding to the tree. slot_index picks the colour (Constants.PLAYER_COLORS).
func setup(slot_index: int, display_name: String) -> void:
	var tint: Color = Constants.PLAYER_COLORS[slot_index % Constants.PLAYER_COLORS.size()]
	texture_rect.modulate = tint
	var ring_style: StyleBoxFlat = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	ring_style.border_color = tint
	add_theme_stylebox_override("panel", ring_style)
	name_label.text = display_name
	name_label.add_theme_color_override("font_color", tint)
	name_label.visible = false
	mouse_entered.connect(func() -> void: name_label.visible = true)
	mouse_exited.connect(func() -> void: name_label.visible = false)
