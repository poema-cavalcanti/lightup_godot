extends CanvasLayer

# ---------------------------------------------------------------------------
# "Loading..." popup shown while a multiplayer board is being generated (see
# Lobby.gd and TownNet.gd), so a wait doesn't look like a frozen game. The
# parchment window is the same PixelPanel art as the pause menu and the
# Town's shop prompt; the three dots loop (via the label's visible_characters,
# so the text doesn't shift around as they come and go). Layout is in
# LoadingPopup.tscn. Sits above everything (layer 100) and swallows clicks
# on the dimmed backdrop.
# ---------------------------------------------------------------------------

const DOT_INTERVAL: float = 0.4
const BASE_LENGTH: int = 7  # the characters of "Loading" -- the dots come after
const MAX_DOTS: int = 3

@onready var panel: Control = %LoadingPanel
@onready var art: TextureRect = %LoadingArt
@onready var label: Label = %LoadingLabel

var dot_timer: float = 0.0
var dot_count: int = MAX_DOTS

func _ready() -> void:
	var design_size: Vector2i = Vector2i(roundi(panel.offset_right - panel.offset_left), roundi(panel.offset_bottom - panel.offset_top))
	art.texture = PixelPanel.build(design_size, PixelButton.DEFAULT_PIXEL_SCALE)
	label.text = "Loading..."
	_apply_dots()

func show_popup() -> void:
	dot_timer = 0.0
	dot_count = 0
	_apply_dots()
	visible = true

func hide_popup() -> void:
	visible = false

func _process(delta: float) -> void:
	if not visible:
		return
	dot_timer += delta
	if dot_timer >= DOT_INTERVAL:
		dot_timer = 0.0
		dot_count = (dot_count + 1) % (MAX_DOTS + 1)
		_apply_dots()

func _apply_dots() -> void:
	label.visible_characters = BASE_LENGTH + dot_count
