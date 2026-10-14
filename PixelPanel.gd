class_name PixelPanel
extends RefCounted

# ---------------------------------------------------------------------------
# Builds the blank parchment window from assets/main_menu.png (the asset
# pack's menu example: a parchment panel with a little X in the corner) at any
# size, scaled up by a whole number so the pixel art stays crisp. Used by the
# pause menu (PauseMenuManager) and Town's "Enter the ___ shop?" popup.
#
# The art is only 80x168 pixels, so it can't just be stretched -- that would
# smear the hand-drawn nicks along its wooden edge. Instead it's rebuilt from
# its own pixels:
#   - columns 5-17 are identical top to bottom (plain parchment between the
#     left and right edges), so repeating one of them makes the panel wider;
#   - rows 12-162 are identical left to right except for small nicks at the two
#     side edges, so a run of plain rows can be repeated to make the panel
#     taller. Two cuts are used, depending on how tall the panel needs to be:
#       FULL    keeps rows 0-90 and 128-167 around a repeated plain row, so the
#               edge nicks of the original are all there (68 x 132 art pixels
#               minimum -- the pause menu's size);
#       COMPACT keeps only rows 0-29 and 149-167, dropping the middle's nicks,
#               for short popups (68 x 50 art pixels minimum).
# Everything kept -- corners, nicks, the X box -- is copied across untouched and
# stays in place relative to the nearest corner. The result is then enlarged by
# pixel_scale with nearest-neighbour filtering.
#
# build() takes the size the caller wants and gives back at least that; always
# lay content out from the returned texture's size, not the request. setup()
# does the common dressing-up of a panel scene (see its comment).
#
# assets/main_menu.png is required art -- there is no fallback; a missing file
# is a load error.
#
# If the art is ever redrawn, the numbers to update are the constants below
# (all in the sheet's own pixels).
# ---------------------------------------------------------------------------

const SHEET_FILE: String = "main_menu.png"

# The blank panel inside the sheet.
const ART_REGION: Rect2i = Rect2i(96, 4, 80, 168)

# Widening: this run of columns is identical top to bottom.
const WIDE_BAND_FIRST_COL: int = 5
const WIDE_BAND_LAST_COL: int = 17

# Heightening: how many rows are kept at the top, and where the kept part at the
# bottom starts, for each cut; the rows between are replaced by a repeated
# plain row (REPEAT_ROW). All of the cut rows are plain at their sides, so the
# join is invisible.
const FULL_TOP_ROWS: int = 91
const FULL_BOTTOM_START: int = 128
const COMPACT_TOP_ROWS: int = 30
const COMPACT_BOTTOM_START: int = 149
const REPEAT_ROW: int = 100

# The art's X box (a 9x9 square, top-right), measured from the panel's right
# edge and top edge, in art pixels. It's in the part kept by both cuts.
const CLOSE_BOX_FROM_RIGHT: int = 12
const CLOSE_BOX_TOP: int = 2
const CLOSE_BOX_SIZE: int = 9

# min_size is in screen pixels.
static func build(min_size: Vector2i, pixel_scale: int) -> Texture2D:
	var sheet: Texture2D = AssetLoader.load_texture("res://assets/" + SHEET_FILE)
	var sheet_image: Image = sheet.get_image()
	if sheet_image.get_format() != Image.FORMAT_RGBA8:
		sheet_image.convert(Image.FORMAT_RGBA8)
	var source: Image = sheet_image.get_region(ART_REGION)

	var art_width: int = ART_REGION.size.x
	var art_height: int = ART_REGION.size.y
	var wide_band_width: int = WIDE_BAND_LAST_COL - WIDE_BAND_FIRST_COL + 1

	var wanted_rows: int = ceili(float(min_size.y) / float(pixel_scale))
	var full_min_rows: int = FULL_TOP_ROWS + 1 + (art_height - FULL_BOTTOM_START)
	var use_full: bool = wanted_rows >= full_min_rows
	var top_rows: int = FULL_TOP_ROWS if use_full else COMPACT_TOP_ROWS
	var bottom_start: int = FULL_BOTTOM_START if use_full else COMPACT_BOTTOM_START
	var bottom_rows: int = art_height - bottom_start

	var columns: int = maxi(art_width - wide_band_width + 1, ceili(float(min_size.x) / float(pixel_scale)))
	var rows: int = maxi(top_rows + 1 + bottom_rows, wanted_rows)
	var wide_band_copies: int = columns - (art_width - wide_band_width)
	var repeat_copies: int = rows - top_rows - bottom_rows

	# Pass 1: widen -- left of the band, the band's first column repeated, the rest.
	var widened: Image = Image.create_empty(columns, art_height, false, Image.FORMAT_RGBA8)
	widened.blit_rect(source, Rect2i(0, 0, WIDE_BAND_FIRST_COL, art_height), Vector2i(0, 0))
	for copy_index in range(wide_band_copies):
		widened.blit_rect(source, Rect2i(WIDE_BAND_FIRST_COL, 0, 1, art_height), Vector2i(WIDE_BAND_FIRST_COL + copy_index, 0))
	var right_part_x: int = WIDE_BAND_LAST_COL + 1
	widened.blit_rect(source, Rect2i(right_part_x, 0, art_width - right_part_x, art_height), Vector2i(WIDE_BAND_FIRST_COL + wide_band_copies, 0))

	# Pass 2: heighten -- the top part, a plain row repeated, the bottom part.
	var result: Image = Image.create_empty(columns, rows, false, Image.FORMAT_RGBA8)
	result.blit_rect(widened, Rect2i(0, 0, columns, top_rows), Vector2i(0, 0))
	for copy_index in range(repeat_copies):
		result.blit_rect(widened, Rect2i(0, REPEAT_ROW, columns, 1), Vector2i(0, top_rows + copy_index))
	result.blit_rect(widened, Rect2i(0, bottom_start, columns, bottom_rows), Vector2i(0, top_rows + repeat_copies))

	result.resize(columns * pixel_scale, rows * pixel_scale, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(result)

# Where the art's drawn X box sits on a panel of panel_size (screen pixels),
# so an invisible button can be laid over it.
static func close_box_rect(panel_size: Vector2, pixel_scale: int) -> Rect2:
	return Rect2(
		panel_size.x - CLOSE_BOX_FROM_RIGHT * pixel_scale,
		CLOSE_BOX_TOP * pixel_scale,
		CLOSE_BOX_SIZE * pixel_scale,
		CLOSE_BOX_SIZE * pixel_scale
	)

# Dresses a parchment panel laid out in a scene: builds the art at the size the
# scene gave `panel` (its offsets), puts it in `art_rect`, and wires the X
# (`close_button`, which the scene places over the art's drawn one) to on_close.
# The panel's width and height should be multiples of pixel_scale; a warning is
# logged if not, since the art would then be slightly stretched.
static func setup(panel: Control, art_rect: TextureRect, close_button: Button, pixel_scale: int, on_close: Callable) -> void:
	var design_size: Vector2i = Vector2i(roundi(panel.offset_right - panel.offset_left), roundi(panel.offset_bottom - panel.offset_top))
	if design_size.x % pixel_scale != 0 or design_size.y % pixel_scale != 0:
		push_warning("%s is %s, not a multiple of the pixel scale (%d) -- the parchment art will be slightly stretched." % [panel.name, design_size, pixel_scale])
	art_rect.texture = build(design_size, pixel_scale)
	close_button.pressed.connect(on_close)
