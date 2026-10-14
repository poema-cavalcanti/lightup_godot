extends RefCounted
# In-play HUD overlays: the scrolling-viewport math, the minimap, the
# Check Answer error flash, timer-bonus popups,
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
	var play_width: float = max(Constants.CELL_SIZE, viewport_size.x - game.MARGIN * 2)
	var play_height: float = max(Constants.CELL_SIZE, viewport_size.y - game.HUD_HEIGHT - game.MARGIN)

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
		game.rows + border_cells * 2, game.cols + border_cells * 2, Constants.CELL_SIZE,
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
	game.offset_x = int(view_window["extra_x"] - (ext_col_start - border_cells) * Constants.CELL_SIZE)
	game.offset_y = int(game.HUD_HEIGHT + view_window["extra_y"] - game.MARGIN - (ext_row_start - border_cells) * Constants.CELL_SIZE)

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
			if cell_data["type"] == Constants.CellType.BLACK:
				game.draw_rect(cell_rect, Color(0.13, 0.13, 0.16))
				if cell_data["number"] >= 0 and cell_size >= 8.0:
					game.draw_string(game.font, cell_rect.position + Vector2(cell_size * 0.2, cell_size * 0.8), str(cell_data["number"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(cell_size * 0.8), Color.WHITE)
			else:
				var tint: Color = Color(1, 0.93, 0.55) if game.lit[row][col] else Color(0.9, 0.9, 0.9)
				game.draw_rect(cell_rect, tint)

	game.draw_rect(Rect2(origin, map_size), Color(0.114, 0.11, 0.169, 1.0), false, 2.0)

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

	var board_width: int = game.view_cols * Constants.CELL_SIZE
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
		game.draw_rect(Rect2(cell_position, Vector2(Constants.CELL_SIZE, Constants.CELL_SIZE)), Color(1, 0.15, 0.15, alpha))

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
	var anchor_x: float = tile_position.x + Constants.CELL_SIZE * 0.5
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
