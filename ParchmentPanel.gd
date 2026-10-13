class_name ParchmentPanel
extends RefCounted
# The shared "parchment window" look used by the Town shop panel and the
# post-solve summary panel: a green title bar across the top and a cream
# parchment body below it, drawn from a hand-made background image when one
# exists (assets/shop_background.png, assets/summary_background.png) and from
# plain colored rectangles in the same palette when it doesn't -- so the
# dark-brown-on-cream text colors below read correctly either way.
#
# The art is always drawn at its own native pixel size (never scaled), so
# the panel is exactly as big as the image; fallback_size only applies when
# the image is missing. Children (labels, buttons) are meant to be added to
# the returned Control using local coordinates -- (0, 0) is the panel's
# top-left corner.

const TITLE_BAR_HEIGHT: float = 36.0  # the green bar, in both pieces of art

# Text colors that read well on the cream parchment / green bar.
const TEXT_COLOR: Color = Color(0.24, 0.13, 0.10)
const TITLE_TEXT_COLOR: Color = Color(0.10, 0.16, 0.16)
const GOLD_TEXT_COLOR: Color = Color(0.62, 0.38, 0.05)

# Palette sampled from the art, used for the no-image fallback.
const BORDER_COLOR: Color = Color(96.0 / 255.0, 57.0 / 255.0, 40.0 / 255.0)
const PARCHMENT_COLOR: Color = Color(229.0 / 255.0, 214.0 / 255.0, 161.0 / 255.0)
const TITLE_BAR_COLOR: Color = Color(80.0 / 255.0, 169.0 / 255.0, 120.0 / 255.0)

# art_filename is a file directly under res://assets/ (e.g. "shop_background.png").
static func build(art_filename: String, fallback_size: Vector2) -> Control:
	var root: Control = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var texture: Texture2D = AssetLoader.load_optional_texture("res://assets/" + art_filename)
	if texture != null:
		root.size = texture.get_size()
		root.set_meta("has_art", true)
		var art: TextureRect = TextureRect.new()
		art.texture = texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # keep the pixel art crisp
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.size = root.size
		root.add_child(art)
		return root

	root.size = fallback_size
	root.set_meta("has_art", false)
	var border: ColorRect = ColorRect.new()
	border.color = BORDER_COLOR
	border.size = fallback_size
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(border)
	var body: ColorRect = ColorRect.new()
	body.color = PARCHMENT_COLOR
	body.position = Vector2(10, TITLE_BAR_HEIGHT + 2.0)
	body.size = Vector2(fallback_size.x - 20.0, fallback_size.y - TITLE_BAR_HEIGHT - 12.0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	var bar: ColorRect = ColorRect.new()
	bar.color = TITLE_BAR_COLOR
	bar.size = Vector2(fallback_size.x, TITLE_BAR_HEIGHT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	return root

# A title label vertically centered in the green bar. Not added to anything.
static func make_title_label(text: String, font_size: int, centered: bool) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.size = Vector2(0, TITLE_BAR_HEIGHT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TITLE_TEXT_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

# The close button for a panel from build(). With art, the X is already drawn
# in the image (top-right of the green bar), so this is an invisible button
# sitting on top of it with only a faint hover highlight; without art it's a
# normal visible "X" button in the same spot. Positioned in the panel's local
# coordinates -- add it as a child of the Control build() returned.
static func make_close_button(background: Control) -> Button:
	var button: Button = Button.new()
	if background.get_meta("has_art", false):
		button.size = Vector2(30, 30)
		button.position = Vector2(background.size.x - 42.0, 3.0)
		button.focus_mode = Control.FOCUS_NONE
		var empty_style: StyleBoxEmpty = StyleBoxEmpty.new()
		var hover_style: StyleBoxFlat = StyleBoxFlat.new()
		hover_style.bg_color = Color(1, 1, 1, 0.22)
		for style_name: String in ["normal", "focus", "disabled"]:
			button.add_theme_stylebox_override(style_name, empty_style)
		for style_name: String in ["hover", "pressed", "hover_pressed"]:
			button.add_theme_stylebox_override(style_name, hover_style)
	else:
		button.text = "X"
		button.size = Vector2(32, 28)
		button.position = Vector2(background.size.x - 44.0, 4.0)
	return button
