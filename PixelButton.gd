class_name PixelButton
extends RefCounted

# ---------------------------------------------------------------------------
# Skins a Button with the green pixel-art look from assets/buttons.png -- the
# same green as the title bar on the summary/shop parchment panels, so the
# Next Level / Continue button reads as part of that panel instead of a
# stock grey Godot button, and the pause menu's buttons match it.
#
# assets/buttons.png is a whole sheet of buttons; this only uses the big
# blank wide one (the first big green bar in each of the sheet's four
# columns). Its four columns are the four button states, which line up
# one-to-one with Godot's Button style slots:
#     column 1 = normal          column 2 = pressed
#     column 3 = hover           column 4 = hover + pressed
# The "pressed" columns are the same button minus the 1px drop shadow
# along the bottom, so a click looks like the button sinking; the label drops
# one art pixel with it (see the content margins below).
#
# Each state is a 9-slice (StyleBoxTexture): the corners and outline are
# always drawn at the art's own pixel size and only the flat green middle
# stretches, so the button can be any size and the pixels stay crisp.
#
# apply() has two optional extras, both used by the pause menu:
#   - pixel_scale: draw the art enlarged by a whole number (nearest-neighbour),
#     so the button's pixels match a parchment panel drawn at that scale. The
#     enlarged copies are built once per setting and shared between buttons.
#   - shadow_color: swap the sheet's brown drop shadow for another color. The
#     brown suits the dark screen behind the summary panel; the pack's own menu
#     art uses a light tan (PARCHMENT_SHADOW_COLOR) for buttons sitting on
#     parchment.
# With neither (the defaults), the states are cut straight out of the sheet at
# 1x -- how the Next Level / Continue button uses it.
#
# To use a different button from the sheet, change the four regions below
# (x, y, width, height in the sheet's own pixels) and, if its border is
# thicker or thinner, the margins.
# ---------------------------------------------------------------------------

const SHEET_FILE: String = "buttons.png"

const REGION_NORMAL: Rect2 = Rect2(3, 96, 42, 16)
const REGION_PRESSED: Rect2 = Rect2(51, 97, 42, 15)
const REGION_HOVER: Rect2 = Rect2(99, 96, 42, 16)
const REGION_HOVER_PRESSED: Rect2 = Rect2(147, 97, 42, 15)

# Pixels of the art kept un-stretched on each side (in art pixels -- multiplied
# by pixel_scale): the rounded corner, the dark outline, and the highlight/shade
# line inside it. The bottom is one taller on the non-pressed states, which
# carry the extra shadow row.
const MARGIN_SIDE: float = 3.0
const MARGIN_TOP: float = 3.0
const MARGIN_BOTTOM_RAISED: float = 4.0
const MARGIN_BOTTOM_PRESSED: float = 3.0

# Space kept clear of the label. The raised states leave one art pixel at the
# bottom for the shadow; the pressed states move it to the top, which is what
# nudges the label down on press.
const TEXT_PADDING_SIDE: float = 8.0

# The art's own dark outline color -- dark teal text reads well on both the
# normal and the lighter hover green.
const TEXT_COLOR: Color = Color(41.0 / 255.0, 64.0 / 255.0, 64.0 / 255.0)

# The sheet's drop-shadow colors (normal / hover), and the light tan the
# pack's menu art uses for buttons on parchment.
const SHEET_SHADOW_COLORS: Array[Color] = [
	Color(112.0 / 255.0, 73.0 / 255.0, 42.0 / 255.0),
	Color(139.0 / 255.0, 98.0 / 255.0, 49.0 / 255.0),
]
const PARCHMENT_SHADOW_COLOR: Color = Color(205.0 / 255.0, 166.0 / 255.0, 119.0 / 255.0)

# Finished style sets, keyed by "scale|shadow color", so a screen full of
# buttons doesn't rebuild the same textures.
static var _style_cache: Dictionary = {}

# shadow_color with alpha 0 (the default) keeps the sheet's own shadow.
static func apply(button: Button, pixel_scale: int = 1, shadow_color: Color = Color(0, 0, 0, 0)) -> void:
	var cache_key: String = "%d|%s" % [pixel_scale, shadow_color.to_html()]
	var styles: Dictionary = _style_cache.get(cache_key, {})
	if styles.is_empty():
		var sheet: Texture2D = AssetLoader.load_texture("res://assets/" + SHEET_FILE)
		styles = _make_styles(sheet, pixel_scale, shadow_color)
		_style_cache[cache_key] = styles

	var normal_style: StyleBoxTexture = styles["normal"]
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("pressed", styles["pressed"])
	button.add_theme_stylebox_override("hover", styles["hover"])
	button.add_theme_stylebox_override("hover_pressed", styles["hover_pressed"])
	button.add_theme_stylebox_override("disabled", normal_style)
	# No focus outline: the default one is a plain rectangle that would be
	# drawn over the art after a mouse click.
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(color_name, TEXT_COLOR)

	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # keep the pixel art crisp

static func _make_styles(sheet: Texture2D, pixel_scale: int, shadow_color: Color) -> Dictionary:
	var states: Dictionary = {
		"normal": [REGION_NORMAL, false],
		"pressed": [REGION_PRESSED, true],
		"hover": [REGION_HOVER, false],
		"hover_pressed": [REGION_HOVER_PRESSED, true],
	}
	var plain: bool = pixel_scale == 1 and shadow_color.a <= 0.0
	var sheet_image: Image = null
	if not plain:
		sheet_image = sheet.get_image()
		if sheet_image.get_format() != Image.FORMAT_RGBA8:
			sheet_image.convert(Image.FORMAT_RGBA8)

	var styles: Dictionary = {}
	for state_name: String in states:
		var region: Rect2 = states[state_name][0]
		var is_pressed: bool = states[state_name][1]
		if plain:
			# Straight out of the sheet at 1x -- no image work needed.
			styles[state_name] = _make_style(sheet, region, is_pressed, 1)
		else:
			styles[state_name] = _make_style(_make_scaled_texture(sheet_image, region, pixel_scale, shadow_color), Rect2(), is_pressed, pixel_scale)
	return styles

# A copy of one state's art, optionally recolored and enlarged.
static func _make_scaled_texture(sheet_image: Image, region: Rect2, pixel_scale: int, shadow_color: Color) -> Texture2D:
	var image: Image = sheet_image.get_region(Rect2i(region))
	if shadow_color.a > 0.0:
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var pixel: Color = image.get_pixel(x, y)
				for sheet_shadow: Color in SHEET_SHADOW_COLORS:
					if pixel.a > 0.99 and pixel.is_equal_approx(sheet_shadow):
						image.set_pixel(x, y, shadow_color)
						break
	if pixel_scale != 1:
		image.resize(image.get_width() * pixel_scale, image.get_height() * pixel_scale, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)

# region is the part of the texture to use (an empty Rect2 means all of it);
# margins and padding are in art pixels, multiplied by pixel_scale.
static func _make_style(texture: Texture2D, region: Rect2, is_pressed: bool, pixel_scale: int) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = texture
	if region.size != Vector2.ZERO:
		style.region_rect = region
	var scale: float = float(pixel_scale)
	style.texture_margin_left = MARGIN_SIDE * scale
	style.texture_margin_right = MARGIN_SIDE * scale
	style.texture_margin_top = MARGIN_TOP * scale
	style.texture_margin_bottom = (MARGIN_BOTTOM_PRESSED if is_pressed else MARGIN_BOTTOM_RAISED) * scale
	style.content_margin_left = TEXT_PADDING_SIDE
	style.content_margin_right = TEXT_PADDING_SIDE
	style.content_margin_top = 1.0 * scale if is_pressed else 0.0
	style.content_margin_bottom = 0.0 if is_pressed else 1.0 * scale
	return style
