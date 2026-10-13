class_name PixelPanel
extends RefCounted

# ---------------------------------------------------------------------------
# Builds the blank parchment window from assets/main_menu.png (the asset
# pack's menu example: a parchment panel with a little X in the corner) at any
# size, scaled up by a whole number so the pixel art stays crisp. Used by the
# pause menu (see PauseMenuManager).
#
# The art is only 80x168 pixels, so it can't just be stretched -- that would
# smear the hand-drawn nicks along its wooden edge. Instead it's rebuilt from
# its own pixels:
#   - columns 5-17 are identical top to bottom (plain parchment between the
#     left and right edges), so repeating one of them makes the panel wider;
#   - rows 91-127 are identical left to right (plain side edges), so repeating
#     one of them makes the panel taller or shorter.
# Everything else -- corners, nicks, the X box -- is copied across untouched
# and keeps its place relative to the nearest corner. The result is then
# enlarged by pixel_scale with nearest-neighbour filtering.
#
# That puts a floor on the size: 68 x 132 art pixels (the 80x168 art with each
# band squeezed down to one pixel). Asking for less just gets that minimum, so
# always lay content out from the returned texture's size, not the request.
#
# Like all the project's art it's optional: if assets/main_menu.png is
# missing, build() returns null and the caller draws a plain fallback.
#
# If the art is ever redrawn, the numbers to update are the constants below
# (all in the sheet's own pixels).
# ---------------------------------------------------------------------------

const SHEET_FILE: String = "main_menu.png"

# The blank panel inside the sheet.
const ART_REGION: Rect2i = Rect2i(96, 4, 80, 168)

# Safe-to-repeat bands, relative to the panel (not the sheet).
const WIDE_BAND_FIRST_COL: int = 5
const WIDE_BAND_LAST_COL: int = 17
const TALL_BAND_FIRST_ROW: int = 91
const TALL_BAND_LAST_ROW: int = 127

# The art's X box (a 9x9 square, top-right), measured from the panel's right
# edge and top edge, in art pixels.
const CLOSE_BOX_FROM_RIGHT: int = 12
const CLOSE_BOX_TOP: int = 2
const CLOSE_BOX_SIZE: int = 9

# min_size is in screen pixels. Returns null if the art is missing.
static func build(min_size: Vector2i, pixel_scale: int) -> Texture2D:
	var sheet: Texture2D = AssetLoader.load_optional_texture("res://assets/" + SHEET_FILE)
	if sheet == null:
		return null
	var sheet_image: Image = sheet.get_image()
	if sheet_image.get_format() != Image.FORMAT_RGBA8:
		sheet_image.convert(Image.FORMAT_RGBA8)
	var source: Image = sheet_image.get_region(ART_REGION)

	var art_width: int = ART_REGION.size.x
	var art_height: int = ART_REGION.size.y
	var wide_band_width: int = WIDE_BAND_LAST_COL - WIDE_BAND_FIRST_COL + 1
	var tall_band_height: int = TALL_BAND_LAST_ROW - TALL_BAND_FIRST_ROW + 1

	var columns: int = maxi(art_width - wide_band_width + 1, ceili(float(min_size.x) / float(pixel_scale)))
	var rows: int = maxi(art_height - tall_band_height + 1, ceili(float(min_size.y) / float(pixel_scale)))
	var wide_band_copies: int = columns - (art_width - wide_band_width)
	var tall_band_copies: int = rows - (art_height - tall_band_height)

	# Pass 1: widen -- left of the band, the band's first column repeated, the rest.
	var widened: Image = Image.create_empty(columns, art_height, false, Image.FORMAT_RGBA8)
	widened.blit_rect(source, Rect2i(0, 0, WIDE_BAND_FIRST_COL, art_height), Vector2i(0, 0))
	for copy_index in range(wide_band_copies):
		widened.blit_rect(source, Rect2i(WIDE_BAND_FIRST_COL, 0, 1, art_height), Vector2i(WIDE_BAND_FIRST_COL + copy_index, 0))
	var right_part_x: int = WIDE_BAND_LAST_COL + 1
	widened.blit_rect(source, Rect2i(right_part_x, 0, art_width - right_part_x, art_height), Vector2i(WIDE_BAND_FIRST_COL + wide_band_copies, 0))

	# Pass 2: heighten -- same idea with rows.
	var result: Image = Image.create_empty(columns, rows, false, Image.FORMAT_RGBA8)
	result.blit_rect(widened, Rect2i(0, 0, columns, TALL_BAND_FIRST_ROW), Vector2i(0, 0))
	for copy_index in range(tall_band_copies):
		result.blit_rect(widened, Rect2i(0, TALL_BAND_FIRST_ROW, columns, 1), Vector2i(0, TALL_BAND_FIRST_ROW + copy_index))
	var bottom_part_y: int = TALL_BAND_LAST_ROW + 1
	result.blit_rect(widened, Rect2i(0, bottom_part_y, columns, art_height - bottom_part_y), Vector2i(0, TALL_BAND_FIRST_ROW + tall_band_copies))

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
