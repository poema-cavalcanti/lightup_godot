class_name AssetLoader
extends RefCounted
# Pixel-art asset loading from res://assets/. Split out of Game.gd -- operates
# on shared texture state via the `game` back-reference.
#
# Two loaders live here:
#   - load_texture(): REQUIRED art. There is no fallback -- a missing file is
#     a load error and the caller gets null. Everything that ships with the
#     game (walls, floors, bulb, player/enemy/boss sheets, borders, projectile,
#     UI skins, item art) goes through this.
#   - load_optional_texture(): art that may legitimately not exist (cutscene
#     art). Returns null if missing.
#
# Both are static, shared and cached, and used directly by Town.gd, Cutscene.gd
# and ItemData.gd too, so there's exactly one place that knows how to load a
# texture. Caching matters for more than just avoiding a repeat disk read: a
# Texture2D referenced *only* by a local variable in a _draw()-time caller can
# be freed before Godot's deferred draw actually runs (drawing just records a
# command referencing the texture, it doesn't happen immediately) -- see
# ItemData.gd's git history for exactly that bug. Keeping every loaded texture
# in this cache for the life of the app means something is always holding a
# real reference.

static var _texture_cache: Dictionary = {}

# path is a full res:// path (callers each know their own directory
# convention -- e.g. Cutscene's art lives under res://assets/cutscenes/,
# everything else directly under res://assets/ -- so this stays generic
# rather than assuming one fixed prefix).
static func load_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		_texture_cache[path] = texture
	return texture

static func load_optional_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	if not ResourceLoader.exists(path):
		return null
	return load_texture(path)

var game: Node2D

func _init(game_ref: Node2D) -> void:
	game = game_ref

const ASSET_DIRECTORY: String = "res://assets/"
const WALL_CLUE_NUMBER_COUNT: int = 5  # wall_0.png .. wall_4.png
const BOSS_TIER_COUNT: int = 4  # boss_tier_1_* .. boss_tier_4_* sheets (levels 1-3 / 4-6 / 7-9 / 10)

func _load_pixel_art() -> void:
	game.wall_textures.clear()
	_load_wall_variant_set(-1, "wall")  # blank wall: no clue number
	for clue_number in range(WALL_CLUE_NUMBER_COUNT):
		_load_wall_variant_set(clue_number, "wall_%d" % clue_number)

	# Floor variants: floor_0.png, floor_1.png, ... each with a matching
	# floor_N_lit.png. The count is however many floor_N.png files exist, so
	# adding floor_10 + floor_10_lit needs no code change.
	game.floor_textures.clear()
	game.floor_lit_textures.clear()
	var floor_variant_index: int = 0
	while ResourceLoader.exists(ASSET_DIRECTORY + "floor_%d.png" % floor_variant_index):
		game.floor_textures.append(_texture("floor_%d.png" % floor_variant_index))
		game.floor_lit_textures.append(_texture("floor_%d_lit.png" % floor_variant_index))
		floor_variant_index += 1

	game.bulb_texture = _texture("bulb.png")
	# Square frames side by side, so width / height is the frame count (a
	# single static image comes out as 1 and just never animates).
	game.bulb_frame_count = maxi(1, roundi(float(game.bulb_texture.get_width()) / float(game.bulb_texture.get_height())))

	game.player_attack_sheet_texture = _texture("player_attack_sheet.png")
	game.player_interact_sheet_texture = _texture("player_interact_sheet.png")
	game.player_idle_sheet_texture = _texture("player_idle_sheet.png")
	game.player_run_sheet_texture = _texture("player_run_sheet.png")

	game.enemy_sheets.clear()
	for anim: String in ["idle", "move", "attack", "hurt", "death"]:
		game.enemy_sheets["enemy_" + anim] = _texture("enemy_%s_sheet.png" % ("walk" if anim == "move" else anim))

	# Boss sheets, one set per tier (boss_tier_N_{idle,walk,attack,hurt,death}).
	# The tier's *_run_sheet.png files exist but aren't used yet.
	for tier in range(1, BOSS_TIER_COUNT + 1):
		for anim: String in ["idle", "move", "attack", "hurt", "death"]:
			game.enemy_sheets["boss_tier_%d_%s" % [tier, anim]] = _texture("boss_tier_%d_%s_sheet.png" % [tier, "walk" if anim == "move" else anim])

	game.projectile_texture = _texture("projectile.png")

	game.border_textures.clear()
	for piece_name: String in ["top", "bottom", "left", "right"]:
		game.border_textures[piece_name] = _texture("border_%s.png" % piece_name)
	for corner_name: String in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		game.border_textures[corner_name] = _texture("border_corner_%s.png" % corner_name)

	# keep pixel art crisp instead of the default linear-filter blur
	game.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _texture(filename: String) -> Texture2D:
	return AssetLoader.load_texture(ASSET_DIRECTORY + filename)

# Each wall (generic "wall", or "wall_0" .. "wall_4") has two images:
# "plain" (base_name.png, one static frame) and "lit" (base_name_lit.png, a
# horizontal strip of equal square frames -- frame count is width / height, so
# a single 64x64 image is just a 1-frame "animation").
func _load_wall_variant_set(clue_number: int, base_name: String) -> void:
	game.wall_textures[clue_number] = {
		"plain": _texture(base_name + ".png"),
		"lit": _texture(base_name + "_lit.png"),
	}

# Number of equal square frames in a wall texture strip (width / height).
static func wall_frame_count(texture: Texture2D) -> int:
	return maxi(1, roundi(float(texture.get_width()) / float(texture.get_height())))

# is_lit: whether this wall is currently lit -- decided by the caller (see
# Game._draw): clues 1-4 are lit while exactly satisfied (adjacent bulb
# count == clue), while the 0 clue and the blank wall are lit whenever at
# least one bulb has line of sight to them (PuzzleBoard.wall_lit). The lit
# texture is an animation strip, the plain one a single frame.
func _get_wall_texture(clue_number: int, is_lit: bool) -> Texture2D:
	return game.wall_textures[clue_number]["lit" if is_lit else "plain"]
