extends RefCounted
# In-play HUD and overlays: the scrolling-viewport math, background, top
# icon row + minimap, the Check Answer error flash, timer-bonus popups,
# tutorial hint bubbles, the win animation, and the level-timer tick/format.
# Split out of GameUIManager.gd, which kept window sizing/layout, the
# status label/win-state transition, and the pause menu. Operates on
# shared board/combat state via the `game` back-reference, same as every
# other manager.

var game: Node2D

func _init(game_ref: Node2D) -> void:
	game = game_ref

const CONFETTI_COLORS: Array[Color] = [
	Color(1, 0.82, 0.15), Color(0.15, 0.65, 0.95), Color(0.90, 0.25, 0.55),
	Color(0.25, 0.80, 0.35), Color(0.95, 0.60, 0.10),
]
const CONFETTI_GRAVITY: float = 220.0
const CONFETTI_PIECE_COUNT: int = 90
const WIN_ANIMATION_DURATION: float = 2.5
const TIMER_BONUS_POPUP_DURATION: float = 1.2
const MINIMAP_SIZE: float = 150.0
const ICON_RADIUS: float = 28.0
const ICON_ROW_X: float = 90.0
const ICON_ROW_Y: float = 54.0
const HUD_ICON_GAP: float = 30.0  # gap left after each top-row element before the next one starts
const HUD_GOLD_ICON_TEXT_GAP: float = 8.0  # tighter than HUD_ICON_GAP -- the count reads as part of the gold icon, not a separate element

# --- Attached bars (health now, see _draw_hud_health_bar; the timer bar --
# --- planned for icon_timer_texture will reuse these same constants) ----
const HUD_BAR_WIDTH: float = 120.0
const HUD_BAR_HEIGHT: float = 24.0
const HUD_BAR_BORDER_WIDTH: float = 3.0
const HUD_BAR_BORDER_COLOR: Color = Color(0.08, 0.08, 0.1)
const HUD_BAR_TRACK_COLOR: Color = Color(0.16, 0.16, 0.19)
const HUD_BAR_ICON_OVERLAP: float = 14.0  # how far the bar tucks under its icon so they read as one connected piece, like the reference art

# ---------------------------------------------------------------------------
# Scrolling viewport -- shows as much of the puzzle as fits the current
# window, centered on the local player, clamped so the view never scrolls
# past the puzzle's edges. game.offset_x/offset_y keep their old meaning
# (the pixel origin that col/row 0 would sit at, however far off-screen)
# so every other draw call (players, enemies, projectiles, hints, popups)
# keeps working unchanged.
# ---------------------------------------------------------------------------

func _compute_view_window() -> void:
	var viewport_size: Vector2 = game.get_viewport_rect().size
	var play_width: float = max(game.CELL_SIZE, viewport_size.x - game.MARGIN * 2)
	var play_height: float = max(game.CELL_SIZE, viewport_size.y - game.HUD_HEIGHT - game.MARGIN)

	var focus_row: int = 0
	var focus_col: int = 0
	if game.my_player_index >= 0 and game.my_player_index < game.players.size():
		var focus_player: Dictionary = game.players[game.my_player_index]
		focus_row = focus_player["row"]
		focus_col = focus_player["col"]

	# The stone border (if any) is treated as extra rows/cols of the world: the
	# camera scrolls over a grid `border_cells` bigger on every side, with the
	# board shifted in by that much. That way no screen space is ever reserved
	# for the border -- mid-board the whole play area shows board cells, and the
	# border only appears as the outermost row/col once the camera reaches that
	# edge. With no border art border_cells is 0 and this is the plain board.
	var border_cells: int = game._border_cells()
	var view_window: Dictionary = GridGeometry.compute_view_window(
		game.rows + border_cells * 2, game.cols + border_cells * 2, game.CELL_SIZE,
		focus_row + border_cells, focus_col + border_cells, play_width, play_height)
	var ext_row_start: int = view_window["view_row_start"]
	var ext_col_start: int = view_window["view_col_start"]
	var ext_row_end: int = ext_row_start + view_window["view_rows"]  # exclusive
	var ext_col_end: int = ext_col_start + view_window["view_cols"]  # exclusive

	# Visible range in board coordinates, including the border ring (may be
	# -1 / rows / cols) -- what _draw_border uses...
	game.border_first_row = ext_row_start - border_cells
	game.border_last_row = ext_row_end - 1 - border_cells
	game.border_first_col = ext_col_start - border_cells
	game.border_last_col = ext_col_end - 1 - border_cells
	# ...and the same range clamped to real board cells, which is what every
	# other consumer of view_* (cell drawing, minimap, banners) expects.
	game.view_row_start = maxi(0, game.border_first_row)
	game.view_col_start = maxi(0, game.border_first_col)
	game.view_rows = mini(game.rows, game.border_last_row + 1) - game.view_row_start
	game.view_cols = mini(game.cols, game.border_last_col + 1) - game.view_col_start

	# Center the (possibly smaller-than-available) visible area within the
	# leftover space, rather than pinning it to the play area's top-left.
	game.offset_x = int(view_window["extra_x"] - (ext_col_start - border_cells) * game.CELL_SIZE)
	game.offset_y = int(game.HUD_HEIGHT + view_window["extra_y"] - game.MARGIN - (ext_row_start - border_cells) * game.CELL_SIZE)

const BACKGROUND_COLOR: Color = Color("1d1c2b")  # behind the board when there's no background.png

func _draw_background() -> void:
	var viewport_size: Vector2 = game.get_viewport_rect().size
	var full_rect: Rect2 = Rect2(Vector2.ZERO, viewport_size)
	if game.background_texture != null:
		game.draw_texture_rect(game.background_texture, full_rect, false)
	else:
		game.draw_rect(full_rect, BACKGROUND_COLOR)

# ---------------------------------------------------------------------------
# Top HUD -- hamburger menu (a real Button, see GameUIManager._build_ui)
# plus an icon row for the level timer, player health, weapon, and shield.
# Health is an icon fused to a fill bar (see _draw_hud_health_bar); the
# other three are plain icons, each looking for a matching
# res://assets/icon_*.png before falling back to a simple built-in look
# (text for the timer, a drawn heart/sword/shield shape for the rest).
# ---------------------------------------------------------------------------

func _draw_hud() -> void:
	if game.my_player_index < 0 or game.my_player_index >= game.players.size():
		return
	var my_state: Dictionary = game.players[game.my_player_index]
	var remaining: float = max(0.0, game.current_level_time_limit - game.level_timer)

	var cursor_x: float = ICON_ROW_X
	cursor_x = _draw_hud_timer_bar(cursor_x, remaining, game.current_level_time_limit) + HUD_ICON_GAP
	cursor_x = _draw_hud_health_bar(cursor_x, my_state["health"], game.COMBAT_MAX_HEALTH) + HUD_ICON_GAP
	cursor_x = _draw_hud_icon_shape(cursor_x, game.icon_weapon_texture, "sword", Color(0.55, 0.55, 0.6)) + HUD_ICON_GAP
	cursor_x = _draw_hud_icon_shape(cursor_x, game.icon_shield_texture, "shield", Color(0.45, 0.55, 0.65))
	if CampaignManager.is_campaign_active:
		cursor_x = _draw_hud_gold_icon(cursor_x + HUD_ICON_GAP)
		_draw_hud_gold_count(cursor_x + HUD_GOLD_ICON_TEXT_GAP)

# Every _draw_hud_* function below takes the x position its element starts
# at (left edge) and returns the x position right after it, so _draw_hud
# above can lay them out left-to-right with a gap in between rather than
# every element needing to know its neighbors' widths up front.

func _draw_hud_icon_shape(left_x: float, texture: Texture2D, shape: String, background_color: Color) -> float:
	var center: Vector2 = Vector2(left_x + ICON_RADIUS, ICON_ROW_Y)
	game.draw_circle(center, ICON_RADIUS, background_color)
	if texture != null:
		var icon_size: float = ICON_RADIUS * 1.5
		game.draw_texture_rect(texture, Rect2(center - Vector2(icon_size, icon_size) / 2.0, Vector2(icon_size, icon_size)), false)
	elif shape == "sword":
		game.draw_line(center + Vector2(-12, 12), center + Vector2(12, -14), Color(0.9, 0.9, 0.95), 5.0)
		game.draw_line(center + Vector2(-7, -1), center + Vector2(1, 7), Color(0.75, 0.5, 0.2), 5.0)
	else:  # shield
		var pts: PackedVector2Array = PackedVector2Array([
			center + Vector2(-13, -14), center + Vector2(13, -14),
			center + Vector2(13, 2), center + Vector2(0, 16), center + Vector2(-13, 2),
		])
		game.draw_colored_polygon(pts, Color(0.8, 0.8, 0.85))
		game.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.3, 0.3, 0.35), 2.0)
	return left_x + ICON_RADIUS * 2.0

# Heart icon fused to a fill bar, matching the reference pixel-art health
# bar: the bar is drawn first and tucks in slightly under the icon (see
# HUD_BAR_ICON_OVERLAP), then the icon is drawn on top so the seam between
# the two reads as one connected piece rather than two separate shapes.
func _draw_hud_health_bar(left_x: float, health: int, max_health: int) -> float:
	var icon_center: Vector2 = Vector2(left_x + ICON_RADIUS, ICON_ROW_Y)
	var bar_rect: Rect2 = Rect2(
		icon_center.x - HUD_BAR_ICON_OVERLAP, ICON_ROW_Y - HUD_BAR_HEIGHT / 2.0,
		HUD_BAR_WIDTH, HUD_BAR_HEIGHT
	)

	game.draw_rect(bar_rect.grow(HUD_BAR_BORDER_WIDTH), HUD_BAR_BORDER_COLOR)
	game.draw_rect(bar_rect, HUD_BAR_TRACK_COLOR)

	var fraction: float = clamp(float(health) / float(max(1, max_health)), 0.0, 1.0)
	if fraction > 0.0:
		var fill_color: Color = Color(0.85, 0.2, 0.2)
		var fill_rect: Rect2 = Rect2(bar_rect.position, Vector2(bar_rect.size.x * fraction, bar_rect.size.y))
		game.draw_rect(fill_rect, fill_color)
		# glossy top-edge highlight strip, same trick the reference art uses
		var highlight_height: float = max(2.0, bar_rect.size.y * 0.22)
		var highlight_rect: Rect2 = Rect2(fill_rect.position + Vector2(2, 2), Vector2(max(0.0, fill_rect.size.x - 4.0), highlight_height))
		game.draw_rect(highlight_rect, fill_color.lightened(0.55))

	game.draw_circle(icon_center, ICON_RADIUS, Color(0.75, 0.25, 0.25))
	if game.icon_health_texture != null:
		var icon_size: float = ICON_RADIUS * 1.5
		game.draw_texture_rect(game.icon_health_texture, Rect2(icon_center - Vector2(icon_size, icon_size) / 2.0, Vector2(icon_size, icon_size)), false)
	else:
		_draw_fallback_heart(icon_center)

	var health_text: String = "%d/%d" % [health, max_health]
	var text_size: Vector2 = game.font.get_string_size(health_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	var text_center_x: float = icon_center.x + (bar_rect.size.x - HUD_BAR_ICON_OVERLAP) / 2.0
	game.draw_string(game.font, Vector2(text_center_x - text_size.x / 2.0, ICON_ROW_Y + 5), health_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)

	return bar_rect.position.x + bar_rect.size.x

func _draw_fallback_heart(center: Vector2) -> void:
	var heart_color: Color = Color(0.85, 0.15, 0.15)
	var lobe_radius: float = 8.0
	game.draw_circle(center + Vector2(-lobe_radius * 0.75, -lobe_radius * 0.4), lobe_radius, heart_color)
	game.draw_circle(center + Vector2(lobe_radius * 0.75, -lobe_radius * 0.4), lobe_radius, heart_color)
	var pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(-lobe_radius * 1.5, -lobe_radius * 0.2),
		center + Vector2(lobe_radius * 1.5, -lobe_radius * 0.2),
		center + Vector2(0, lobe_radius * 1.8),
	])
	game.draw_colored_polygon(pts, heart_color)

# Hourglass icon fused to a fill bar, same construction as the health bar
# above. The fraction is remaining-time / current_level_time_limit, and
# current_level_time_limit itself grows by LEVEL_TIMER_BONUS_SECONDS each
# time a clue bonus is granted (see PuzzleBoard._check_clue_bonuses) -- so
# a bonus adds the same amount to both halves of that fraction, which
# always nudges it up rather than down, i.e. the bar visibly jumps forward
# a bit at the moment you earn one. That's deliberate: it means the bar
# never needs to know about bonuses specifically, it just always reflects
# "how close to the current deadline", whatever that deadline currently is.
func _draw_hud_timer_bar(left_x: float, remaining: float, total: float) -> float:
	var icon_center: Vector2 = Vector2(left_x + ICON_RADIUS, ICON_ROW_Y)
	var bar_rect: Rect2 = Rect2(
		icon_center.x - HUD_BAR_ICON_OVERLAP, ICON_ROW_Y - HUD_BAR_HEIGHT / 2.0,
		HUD_BAR_WIDTH, HUD_BAR_HEIGHT
	)

	game.draw_rect(bar_rect.grow(HUD_BAR_BORDER_WIDTH), HUD_BAR_BORDER_COLOR)
	game.draw_rect(bar_rect, HUD_BAR_TRACK_COLOR)

	var fraction: float = clamp(remaining / max(0.001, total), 0.0, 1.0)
	if fraction > 0.0:
		var fill_color: Color = Color(0.85, 0.65, 0.15)  # amber/gold, matching the hourglass reference art
		var fill_rect: Rect2 = Rect2(bar_rect.position, Vector2(bar_rect.size.x * fraction, bar_rect.size.y))
		game.draw_rect(fill_rect, fill_color)
		var highlight_height: float = max(2.0, bar_rect.size.y * 0.22)
		var highlight_rect: Rect2 = Rect2(fill_rect.position + Vector2(2, 2), Vector2(max(0.0, fill_rect.size.x - 4.0), highlight_height))
		game.draw_rect(highlight_rect, fill_color.lightened(0.55))

	game.draw_circle(icon_center, ICON_RADIUS, Color(0.25, 0.45, 0.85))
	if game.icon_timer_texture != null:
		var icon_size: float = ICON_RADIUS * 1.5
		game.draw_texture_rect(game.icon_timer_texture, Rect2(icon_center - Vector2(icon_size, icon_size) / 2.0, Vector2(icon_size, icon_size)), false)
	else:
		_draw_fallback_hourglass(icon_center)

	var timer_text: String = _format_timer(remaining)
	var text_size: Vector2 = game.font.get_string_size(timer_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	var text_center_x: float = icon_center.x + (bar_rect.size.x - HUD_BAR_ICON_OVERLAP) / 2.0
	game.draw_string(game.font, Vector2(text_center_x - text_size.x / 2.0, ICON_ROW_Y + 5), timer_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)

	return bar_rect.position.x + bar_rect.size.x

func _draw_fallback_hourglass(center: Vector2) -> void:
	var glass_color: Color = Color(0.85, 0.7, 0.35)
	var frame_color: Color = Color(0.15, 0.15, 0.18)
	var half_width: float = 9.0
	var half_height: float = 11.0
	var top_pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(-half_width, -half_height), center + Vector2(half_width, -half_height), center,
	])
	var bottom_pts: PackedVector2Array = PackedVector2Array([
		center, center + Vector2(half_width, half_height), center + Vector2(-half_width, half_height),
	])
	game.draw_colored_polygon(top_pts, glass_color)
	game.draw_colored_polygon(bottom_pts, glass_color)
	game.draw_line(center + Vector2(-half_width, -half_height), center + Vector2(half_width, -half_height), frame_color, 3.0)
	game.draw_line(center + Vector2(-half_width, half_height), center + Vector2(half_width, half_height), frame_color, 3.0)

# Gold icon (campaign mode only, see _draw_hud) with the current running
# total in text immediately to its right -- unlike the other three icons,
# this one's value isn't drawn on top of the icon itself, per how it was
# asked for.
func _draw_hud_gold_icon(left_x: float) -> float:
	var center: Vector2 = Vector2(left_x + ICON_RADIUS, ICON_ROW_Y)
	game.draw_circle(center, ICON_RADIUS, Color(0.5, 0.4, 0.15))
	if game.icon_gold_texture != null:
		var icon_size: float = ICON_RADIUS * 1.5
		game.draw_texture_rect(game.icon_gold_texture, Rect2(center - Vector2(icon_size, icon_size) / 2.0, Vector2(icon_size, icon_size)), false)
	else:
		_draw_fallback_coin(center)
	return left_x + ICON_RADIUS * 2.0

func _draw_hud_gold_count(left_x: float) -> void:
	var gold_text: String = str(CampaignManager.gold)
	game.draw_string(game.font, Vector2(left_x, ICON_ROW_Y + 7), gold_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.85, 0.3))

func _draw_fallback_coin(center: Vector2) -> void:
	var coin_color: Color = Color(0.95, 0.8, 0.25)
	var rim_color: Color = Color(0.6, 0.45, 0.1)
	game.draw_circle(center, 11.0, coin_color)
	game.draw_arc(center, 11.0, 0.0, TAU, 16, rim_color, 2.0)
	game.draw_arc(center, 6.5, 0.0, TAU, 12, rim_color, 1.5)

# ---------------------------------------------------------------------------
# Minimap -- the whole puzzle at a glance, top-right of the HUD strip, in
# flat colors/numbers only (no pixel-art lookups, unlike the main board),
# with a highlight rectangle for the current scroll window and a dot per
# player so it updates live as anyone moves.
# ---------------------------------------------------------------------------

func _draw_minimap() -> void:
	var viewport_size: Vector2 = game.get_viewport_rect().size
	var max_width: float = MINIMAP_SIZE
	var max_height: float = game.HUD_HEIGHT - 16.0
	var cell_size: float = min(max_width / game.cols, max_height / game.rows)
	var map_size: Vector2 = Vector2(cell_size * game.cols, cell_size * game.rows)
	var origin: Vector2 = Vector2(viewport_size.x - map_size.x - game.MARGIN, (game.HUD_HEIGHT - map_size.y) / 2.0)

	for row in range(game.rows):
		for col in range(game.cols):
			var cell_rect: Rect2 = Rect2(origin + Vector2(col, row) * cell_size, Vector2(cell_size, cell_size))
			var cell_data: Dictionary = game.grid[row][col]
			if cell_data["type"] == game.CellType.BLACK:
				game.draw_rect(cell_rect, Color(0.13, 0.13, 0.16))
				if cell_data["number"] >= 0 and cell_size >= 8.0:
					game.draw_string(game.font, cell_rect.position + Vector2(cell_size * 0.2, cell_size * 0.8), str(cell_data["number"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(cell_size * 0.8), Color.WHITE)
			else:
				var tint: Color = Color(1, 0.93, 0.55) if game.lit[row][col] else Color(0.9, 0.9, 0.9)
				game.draw_rect(cell_rect, tint)

	game.draw_rect(Rect2(origin, map_size), Color(0, 0, 0), false, 2.0)

	var view_rect: Rect2 = Rect2(origin + Vector2(game.view_col_start, game.view_row_start) * cell_size, Vector2(game.view_cols, game.view_rows) * cell_size)
	game.draw_rect(view_rect, Color(1, 1, 1, 0.9), false, 2.0)

	for player_state: Dictionary in game.players:
		var dot_center: Vector2 = origin + Vector2(player_state["col"] + 0.5, player_state["row"] + 0.5) * cell_size
		game.draw_circle(dot_center, max(2.0, cell_size * 0.3), Color(0.2, 0.6, 1.0))

# ---------------------------------------------------------------------------
# Win animation -- a confetti burst + "SOLVED!" banner, triggered once on
# the not-solved -> solved transition (see GameUIManager._update_status).
# Runs entirely locally, so in multiplayer everyone's own screen celebrates
# independently the moment their synced board reports solved.
# ---------------------------------------------------------------------------

func _play_win_animation() -> void:
	game.win_animation_active = true
	game.win_animation_time = 0.0
	game.confetti_pieces.clear()

	var board_width: int = game.view_cols * game.CELL_SIZE
	var view_origin: Vector2 = game._tile_to_pixel(game.view_row_start, game.view_col_start)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	for confetti_index in range(CONFETTI_PIECE_COUNT):
		var confetti_piece: Dictionary = {
			"position": Vector2(view_origin.x + rng.randf() * board_width, view_origin.y - 20.0 - rng.randf() * 160.0),
			"velocity": Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(60.0, 160.0)),
			"rotation": rng.randf_range(0.0, TAU),
			"rotation_speed": rng.randf_range(-6.0, 6.0),
			"color": CONFETTI_COLORS[rng.randi_range(0, CONFETTI_COLORS.size() - 1)],
			"size": rng.randf_range(5.0, 10.0),
		}
		game.confetti_pieces.append(confetti_piece)

func _advance_win_animation(delta: float) -> void:
	game.win_animation_time += delta
	for confetti_piece: Dictionary in game.confetti_pieces:
		var velocity: Vector2 = confetti_piece["velocity"]
		velocity.y += CONFETTI_GRAVITY * delta
		confetti_piece["velocity"] = velocity
		confetti_piece["position"] += velocity * delta
		confetti_piece["rotation"] += confetti_piece["rotation_speed"] * delta
	if game.win_animation_time >= WIN_ANIMATION_DURATION:
		game.win_animation_active = false
		game.confetti_pieces.clear()

func _advance_timer_bonus_popups(delta: float) -> bool:
	var had_popups: bool = not game.timer_bonus_popups.is_empty()
	var still_active: Array[Dictionary] = []
	for popup: Dictionary in game.timer_bonus_popups:
		var age: float = popup["age"] + delta
		if age < TIMER_BONUS_POPUP_DURATION:
			popup["age"] = age
			still_active.append(popup)
	game.timer_bonus_popups = still_active
	return had_popups

# Check Answer, when the puzzle isn't solved yet, briefly blinks red over
# every cell it found wrong (an unlit white cell, or a numbered black cell
# whose bulb count doesn't match) -- see game.error_flash_cells and
# PuzzleBoard._compute_error_cells(). Bulb-sees-bulb conflicts aren't
# included; those already get a persistent tint the instant they happen.
func _draw_error_flash() -> void:
	if game.error_flash_timer <= 0.0:
		return
	var blink: float = 0.5 + 0.5 * sin(game.error_flash_timer * 18.0)
	var fade_out: float = clamp(game.error_flash_timer / 0.3, 0.0, 1.0)
	var alpha: float = blink * fade_out * 0.55
	for cell: Array in game.error_flash_cells:
		var row: int = cell[0]
		var col: int = cell[1]
		var cell_position: Vector2 = game._tile_to_pixel(row, col)
		game.draw_rect(Rect2(cell_position, Vector2(game.CELL_SIZE, game.CELL_SIZE)), Color(1, 0.15, 0.15, alpha))

func _draw_timer_bonus_popups() -> void:
	var popup_text: String = "+%ds" % int(game.LEVEL_TIMER_BONUS_SECONDS)
	var popup_font_size: int = 20
	for popup: Dictionary in game.timer_bonus_popups:
		var age: float = popup["age"]
		var progress: float = age / TIMER_BONUS_POPUP_DURATION
		var popup_position: Vector2 = popup["position"]
		var popup_center: Vector2 = game._tile_center_to_pixel(popup_position.y, popup_position.x) - Vector2(0, progress * 30.0)
		var alpha: float = 1.0 - progress
		var text_size: Vector2 = game.font.get_string_size(popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, popup_font_size)
		var text_position: Vector2 = Vector2(popup_center.x - text_size.x / 2.0, popup_center.y)
		game.draw_string(game.font, text_position + Vector2(1, 1), popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, popup_font_size, Color(0, 0, 0, alpha * 0.6))
		game.draw_string(game.font, text_position, popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, popup_font_size, Color(0.3, 0.9, 0.5, alpha))

# ---------------------------------------------------------------------------
# Tutorial hints -- short fading text bubbles anchored above the local
# player, used to teach controls the first time they're needed (movement at
# level start, attacking once the first enemy appears). Purely local/visual:
# each peer decides for itself when to show one, nothing is networked.
# ---------------------------------------------------------------------------

func _show_tutorial_hint(text: String, duration: float = 4.0) -> void:
	game.tutorial_hints.append({"text": text, "age": 0.0, "duration": duration})

func _advance_tutorial_hints(delta: float) -> bool:
	var had_hints: bool = not game.tutorial_hints.is_empty()
	var still_active: Array[Dictionary] = []
	for hint: Dictionary in game.tutorial_hints:
		var age: float = hint["age"] + delta
		if age < hint["duration"]:
			hint["age"] = age
			still_active.append(hint)
	game.tutorial_hints = still_active
	return had_hints

func _draw_tutorial_hints() -> void:
	if game.tutorial_hints.is_empty():
		return
	if game.my_player_index < 0 or game.my_player_index >= game.players.size():
		return

	var player_state: Dictionary = game.players[game.my_player_index]
	var visual_position: Vector2 = player_state["visual_position"]
	var tile_position: Vector2 = game._tile_to_pixel(visual_position.y, visual_position.x)
	var anchor_x: float = tile_position.x + game.CELL_SIZE * 0.5
	var anchor_y: float = tile_position.y

	var hint_font_size: int = 16
	var line_height: float = hint_font_size + 4.0
	var stack_offset: float = 0.0

	for hint: Dictionary in game.tutorial_hints:
		var age: float = hint["age"]
		var duration: float = hint["duration"]
		var fade_in: float = clamp(age / 0.3, 0.0, 1.0)
		var fade_out: float = clamp((duration - age) / 0.5, 0.0, 1.0)
		var alpha: float = min(fade_in, fade_out)

		var lines: PackedStringArray = String(hint["text"]).split("\n")
		var bubble_width: float = 0.0
		for line: String in lines:
			var line_size: Vector2 = game.font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_font_size)
			bubble_width = max(bubble_width, line_size.x)
		bubble_width += 24.0
		var bubble_height: float = lines.size() * line_height + 12.0

		var bubble_bottom: float = anchor_y - 14.0 - stack_offset
		var bubble_top: float = bubble_bottom - bubble_height
		var bubble_rect: Rect2 = Rect2(anchor_x - bubble_width / 2.0, bubble_top, bubble_width, bubble_height)

		game.draw_rect(bubble_rect, Color(0.05, 0.05, 0.08, 0.65 * alpha))
		game.draw_rect(bubble_rect, Color(1, 1, 1, 0.35 * alpha), false, 2.0)

		for i in range(lines.size()):
			var line_size: Vector2 = game.font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, hint_font_size)
			var line_position: Vector2 = Vector2(anchor_x - line_size.x / 2.0, bubble_top + 20.0 + i * line_height)
			game.draw_string(game.font, line_position, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, hint_font_size, Color(1, 1, 1, alpha))

		stack_offset += bubble_height + 8.0

func _draw_win_animation() -> void:
	for confetti_piece: Dictionary in game.confetti_pieces:
		var piece_position: Vector2 = confetti_piece["position"]
		var piece_rotation: float = confetti_piece["rotation"]
		game.draw_set_transform(piece_position, piece_rotation, Vector2(1, 1))
		var piece_size: float = confetti_piece["size"]
		game.draw_rect(Rect2(-piece_size / 2.0, -piece_size / 2.0, piece_size, piece_size), confetti_piece["color"])
	game.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 1))

	var banner_progress: float = clamp(game.win_animation_time / 0.5, 0.0, 1.0)
	var banner_scale: float = lerp(0.5, 1.0, ease(banner_progress, -2.0))
	var banner_font_size: int = int(48 * banner_scale)
	var banner_text: String = "SOLVED!"
	var text_size: Vector2 = game.font.get_string_size(banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, banner_font_size)
	var board_center: Vector2 = game._tile_to_pixel(game.view_row_start + game.view_rows / 2.0, game.view_col_start + game.view_cols / 2.0)
	var text_position: Vector2 = board_center + Vector2(-text_size.x / 2.0, text_size.y / 4.0)
	game.draw_string(game.font, text_position + Vector2(2, 2), banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, banner_font_size, Color(0, 0, 0, banner_progress * 0.5))
	game.draw_string(game.font, text_position, banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, banner_font_size, Color(0.2, 0.8, 0.3, banner_progress))

func _tick_level_timer_display(delta: float) -> void:
	if game.level_timer < game.current_level_time_limit:
		game.level_timer = min(game.level_timer + delta, game.current_level_time_limit)

func _format_timer(seconds_value: float) -> String:
	var total_seconds: int = int(ceil(seconds_value))
	var minutes_part: int = total_seconds / 60
	var seconds_part: int = total_seconds % 60
	return "%d:%02d" % [minutes_part, seconds_part]
