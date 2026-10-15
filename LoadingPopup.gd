extends CanvasLayer

# ---------------------------------------------------------------------------
# "Loading..." / "Waiting..." popup for multiplayer waits (see TownNet.gd): Loading
# while the next board is being generated, Waiting for a player who has left town
# and is waiting on the others -- so a wait doesn't look like a frozen game. The
# parchment window is the same PixelPanel art as the pause menu and the
# Town's shop prompt; the three dots loop (via the label's visible_characters,
# so the text doesn't shift around as they come and go). Layout is in
# LoadingPopup.tscn. Sits above everything (layer 100) and swallows clicks
# on the dimmed backdrop.
# ---------------------------------------------------------------------------

const DOT_INTERVAL: float = 0.4
const DEFAULT_WORD: String = "Loading"  # also "Waiting" (see show_popup); the dots come after it
const MAX_DOTS: int = 3

@onready var panel: Control = %LoadingPanel
@onready var art: TextureRect = %LoadingArt
@onready var label: Label = %LoadingLabel

var dot_timer: float = 0.0
var dot_count: int = MAX_DOTS
var word_length: int = DEFAULT_WORD.length()

func _ready() -> void:
	var design_size: Vector2i = Vector2i(roundi(panel.offset_right - panel.offset_left), roundi(panel.offset_bottom - panel.offset_top))
	art.texture = PixelPanel.build(design_size, PixelButton.DEFAULT_PIXEL_SCALE)
	label.text = "Loading..."
	_apply_dots()

func show_popup(word: String = DEFAULT_WORD) -> void:
	label.text = word + "..."
	word_length = word.length()
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
	label.visible_characters = word_length + dot_count
