class_name AssetLoader
extends RefCounted
# Pixel-art asset loading: looks for hand-drawn art in res://assets/ and
# falls back to plain-shape drawing wherever a specific file is missing.
# Split out of Game.gd -- operates on shared texture state via the `game`
# back-reference.
#
# The static load_optional_texture() below is the shared, cached "safely
# load a maybe-missing texture" primitive -- used by the instance method
# right under it (for everything this class loads into `game`'s own
# texture vars), and directly by Town.gd, Cutscene.gd, and ItemData.gd too,
# so there's exactly one place that knows how to do this rather than four
# near-identical copies. Caching matters for more than just avoiding a
# repeat disk read: a Texture2D referenced *only* by a local variable in a
# _draw()-time caller can be freed before Godot's deferred draw actually
# runs (drawing just records a command referencing the texture, it doesn't
# happen immediately) -- see ItemData.gd's git history for exactly that
# bug. Keeping every loaded texture in this cache for the life of the app
# means something is always holding a real reference.

static var _texture_cache: Dictionary = {}

# path is a full res:// path (callers each know their own directory
# convention -- e.g. Cutscene's art lives under res://assets/cutscenes/,
# everything else directly under res://assets/ -- so this stays generic
# rather than assuming one fixed prefix).
static func load_optional_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var loaded_resource: Resource = load(path)
	if loaded_resource is Texture2D:
		var texture: Texture2D = loaded_resource as Texture2D
		_texture_cache[path] = texture
		return texture
	return null

var game: Node2D

func _init(game_ref: Node2D) -> void:
	game = game_ref

const ASSET_DIRECTORY: String = "res://assets/"
const WALL_CLUE_NUMBER_COUNT: int = 5  # wall_0.png .. wall_4.png
const BOSS_TIER_COUNT: int = 4  # boss_tier_1.png .. boss_tier_4.png (levels 1-3 / 4-6 / 7-9 / 10)

func _load_pixel_art() -> void:
	game.wall_textures.clear()
	_load_wall_variant_set(-1, "wall")  # blank wall: no clue number
	for clue_number in range(WALL_CLUE_NUMBER_COUNT):
		_load_wall_variant_set(clue_number, "wall_%d" % clue_number)

	game.floor_textures.clear()
	game.floor_lit_textures.clear()
	var floor_variant_index: int = 0
	while true:
		var floor_variant_texture: Texture2D = _load_optional_texture("floor_%d.png" % floor_variant_index)
		if floor_variant_texture == null:
			break
		game.floor_textures.append(floor_variant_texture)
		game.floor_lit_textures.append(_load_optional_texture("floor_%d_lit.png" % floor_variant_index))
		floor_variant_index += 1
	if game.floor_textures.is_empty():
		var legacy_floor_texture: Texture2D = _load_optional_texture("floor.png")
		if legacy_floor_texture != null:
			game.floor_textures.append(legacy_floor_texture)
			game.floor_lit_textures.append(_load_optional_texture("floor_lit.png"))

	game.bulb_texture = _load_optional_texture("bulb.png")
	game.bulb_frame_count = 1
	if game.bulb_texture != null:
		# Square frames side by side, so width / height is the frame count (a
		# single static image comes out as 1 and just never animates).
		game.bulb_frame_count = maxi(1, roundi(float(game.bulb_texture.get_width()) / float(game.bulb_texture.get_height())))
	game.mark_texture = _load_optional_texture("mark.png")
	game.player_sheet_texture = _load_optional_texture("player_sheet.png")
	if game.player_sheet_texture == null:
		game.player_static_texture = _load_optional_texture("player.png")
	game.player_attack_sheet_texture = _load_optional_texture("player_attack_sheet.png")
	game.player_interact_sheet_texture = _load_optional_texture("player_interact_sheet.png")
	game.player_idle_sheet_texture = _load_optional_texture("player_idle_sheet.png")
	game.player_run_sheet_texture = _load_optional_texture("player_run_sheet.png")
	game.enemy_texture = _load_optional_texture("enemy.png")
	game.boss_texture = _load_optional_texture("boss.png")
	game.enemy_sheets.clear()
	for anim: String in ["idle", "move", "attack", "hurt", "death"]:
		var sheet: Texture2D = _load_optional_texture("enemy_%s_sheet.png" % ("walk" if anim == "move" else anim))
		if sheet != null:
			game.enemy_sheets["enemy_" + anim] = sheet
	for tier in range(1, BOSS_TIER_COUNT + 1):
		for anim: String in ["idle", "move", "attack", "hurt", "death"]:
			var boss_sheet: Texture2D = _load_optional_texture("boss_tier_%d_%s_sheet.png" % [tier, "walk" if anim == "move" else anim])
			if boss_sheet != null:
				game.enemy_sheets["boss_tier_%d_%s" % [tier, anim]] = boss_sheet

	game.boss_tier_textures.clear()
	for tier in range(1, BOSS_TIER_COUNT + 1):
		var tier_texture: Texture2D = _load_optional_texture("boss_tier_%d.png" % tier)
		if tier_texture != null:
			game.boss_tier_textures[tier] = tier_texture

	# Required art (no fallback): CombatManager._draw_projectiles() assumes this exists.
	game.projectile_texture = load(ASSET_DIRECTORY + "projectile.png") as Texture2D

	game.background_texture = _load_optional_texture("background.png")

	game.border_textures.clear()
	for piece_name: String in ["top", "bottom", "left", "right"]:
		var edge_texture: Texture2D = _load_optional_texture("border_%s.png" % piece_name)
		if edge_texture != null:
			game.border_textures[piece_name] = edge_texture
	for corner_name: String in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		var corner_texture: Texture2D = _load_optional_texture("border_corner_%s.png" % corner_name)
		if corner_texture != null:
			game.border_textures[corner_name] = corner_texture
	game.icon_timer_texture = _load_optional_texture("hourglass_icon.png")
	game.icon_health_texture = _load_optional_texture("heart_icon.png")
	game.icon_weapon_texture = _load_optional_texture("default_staff_hud_icon.png")
	game.icon_shield_texture = _load_optional_texture("default_hat_hud_icon.png")
	game.icon_gold_texture = _load_optional_texture("gold_icon.png")

	var any_pixel_art_found: bool = (
		not game.wall_textures.is_empty() or not game.floor_textures.is_empty()
		or game.bulb_texture != null or game.mark_texture != null
		or game.player_sheet_texture != null or game.player_static_texture != null
		or game.player_attack_sheet_texture != null or game.player_interact_sheet_texture != null
		or game.player_idle_sheet_texture != null or game.player_run_sheet_texture != null
		or game.enemy_texture != null or game.boss_texture != null
		or not game.enemy_sheets.is_empty()
		or not game.boss_tier_textures.is_empty() or game.projectile_texture != null
		or game.icon_gold_texture != null
		or not game.border_textures.is_empty()
	)
	if any_pixel_art_found:
		# keep pixel art crisp instead of the default linear-filter blur
		game.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _load_optional_texture(filename: String) -> Texture2D:
	return AssetLoader.load_optional_texture(ASSET_DIRECTORY + filename)

# Each wall (generic "wall", or "wall_0" .. "wall_4") has up to 2 variants:
# "plain" (base_name.png, one static frame) and "lit" (base_name_lit.png, a
# horizontal strip of equal square frames -- frame count is width / height, so
# a single 64x64 image is just a 1-frame "animation"). A missing variant is 
# just left out of the dictionary -- _get_wall_texture() below degrades 
# gracefully.
func _load_wall_variant_set(clue_number: int, base_name: String) -> void:
	var variants: Dictionary = {}
	var plain_texture: Texture2D = _load_optional_texture(base_name + ".png")
	if plain_texture != null:
		variants["plain"] = plain_texture
	var lit_texture: Texture2D = _load_optional_texture(base_name + "_lit.png")
	if lit_texture != null:
		variants["lit"] = lit_texture
	if not variants.is_empty():
		game.wall_textures[clue_number] = variants

# Number of equal square frames in a wall texture strip (width / height).
static func wall_frame_count(texture: Texture2D) -> int:
	if texture == null or texture.get_height() <= 0:
		return 1
	return maxi(1, roundi(float(texture.get_width()) / float(texture.get_height())))

# is_lit: whether this wall is currently lit -- decided by the caller (see
# Game._draw): clues 1-4 are lit while exactly satisfied (adjacent bulb
# count == clue), while the 0 clue and the blank wall are lit whenever at
# least one bulb has line of sight to them (PuzzleBoard.wall_lit).
#
# Degrades: lit -> plain, then falls back to the blank wall's own variants if
# this clue's set has no art for it at all.
#
# Returns {"texture": Texture2D (may be null), "has_own_art": bool,
# "animated": bool}. has_own_art is true only when the texture came from this
# specific clue number's own variant set, never from the generic blank-wall
# fallback (the caller uses that to decide whether the clue number still needs
# drawing as text). animated is true when the texture is the lit strip, which
# the caller should play frame by frame instead of drawing whole.
func _get_wall_texture(clue_number: int, is_lit: bool = false) -> Dictionary:
	var variants: Dictionary = game.wall_textures.get(clue_number, {})
	var candidate_keys: Array[String] = ["plain"]
	if is_lit:
		candidate_keys = ["lit", "plain"]
	for key in candidate_keys:
		if variants.has(key):
			return {"texture": variants[key], "has_own_art": true, "animated": key == "lit"}
	if clue_number != -1 and game.wall_textures.has(-1):
		var fallback_result: Dictionary = _get_wall_texture(-1, is_lit)
		return {"texture": fallback_result["texture"], "has_own_art": false, "animated": fallback_result["animated"]}
	return {"texture": null, "has_own_art": false, "animated": false}

# Levels 1-3 -> tier 1, 4-6 -> tier 2, 7-9 -> tier 3, 10 -> tier 4. Outside
# campaign mode (Endless Mode, Multiplayer) there's no level number at all,
# so it defaults to tier 1.
