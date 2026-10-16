class_name SheetAnimation
extends TextureRect

# ---------------------------------------------------------------------------
# Plays an animation stored as a spritesheet -- a PNG with every frame in it,
# like one exported from an animated GIF -- on a TextureRect, so it takes part
# in normal UI layout (containers, minimum sizes, stretch modes). Godot can't
# import GIFs itself, which is what this stands in for.
#
# Set these three in the Inspector on each node using this script:
#   sheet    the spritesheet PNG
#   frames   how many frames it holds
#   fps      playback speed (a GIF's frame delay in 1/100 s -> fps = 100 / delay)
#   columns  how many frames per row; leave at 0 for a single row (a strip). Set
#            it if the sheet is a grid, e.g. made with ImageMagick's montage.
#
# Frames run left to right, then top to bottom, and loop forever. Every frame
# is assumed to be the same size and to fill the sheet exactly (sheet width /
# columns by sheet height / rows), and to last the same time -- one fps for the
# whole animation.
# ---------------------------------------------------------------------------

@export var sheet: Texture2D
@export var frames: int = 1
@export var fps: float = 8.0
@export var columns: int = 0

var frame_atlas: AtlasTexture = AtlasTexture.new()
var frame_size: Vector2
var columns_per_row: int
var elapsed: float = 0.0
var shown_frame: int = -1

func _ready() -> void:
	columns_per_row = columns if columns > 0 else frames
	var rows: int = ceili(float(frames) / float(columns_per_row))
	frame_size = Vector2(float(sheet.get_width()) / columns_per_row, float(sheet.get_height()) / rows)
	frame_atlas.atlas = sheet
	texture = frame_atlas
	_show_frame(0)

func _process(delta: float) -> void:
	elapsed += delta
	_show_frame(int(elapsed * fps) % frames)

func _show_frame(frame: int) -> void:
	if frame == shown_frame:
		return
	shown_frame = frame
	var cell: Vector2 = Vector2(frame % columns_per_row, floori(float(frame) / columns_per_row))
	frame_atlas.region = Rect2(cell * frame_size, frame_size)
