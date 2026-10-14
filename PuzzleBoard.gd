extends RefCounted
# Light Up puzzle-solving logic: parsing the level string into a grid,
# bulb placement (incl. its RPC request/sync pair), computing lit
# cells and bulb conflicts, clue-satisfaction bonuses, and the solved
# check. Split out of Game.gd -- operates on shared board state (rows,
# cols, grid, bulbs, lit, ...) via the `game` back-reference.

var game: Node2D

func _init(game_ref: Node2D) -> void:
	game = game_ref

func parse_puzzle() -> void:
	game.rows = game.current_puzzle_rows.size()
	game.cols = game.current_puzzle_rows[0].length()
	game.grid.clear()
	game.floor_seed = hash(game.current_puzzle_rows)
	game.bulbs.clear()
	for row in range(game.rows):
		var grid_row: Array = []
		var bulb_row: Array = []
		var row_string: String = game.current_puzzle_rows[row]
		for col in range(game.cols):
			var cell_character: String = row_string[col]
			if cell_character == ".":
				grid_row.append({"type": Constants.CellType.WHITE, "number": -1})
			elif cell_character == "#":
				grid_row.append({"type": Constants.CellType.BLACK, "number": -1})
			else:
				grid_row.append({"type": Constants.CellType.BLACK, "number": int(cell_character)})
			bulb_row.append(false)
		game.grid.append(grid_row)
		game.bulbs.append(bulb_row)
	_reset_clue_bonus_tracking()

func _reset_clue_bonus_tracking() -> void:
	game.clue_bonus_granted.clear()
	for row in range(game.rows):
		var bonus_row: Array = []
		for col in range(game.cols):
			bonus_row.append(false)
		game.clue_bonus_granted.append(bonus_row)

func is_black(row: int, col: int) -> bool:
	return game.grid[row][col]["type"] == Constants.CellType.BLACK

# --- Movement: any player, any peer, routed to the host ---------------------

func _compute_lit() -> void:
	game.lit.clear()
	game.wall_lit.clear()
	for row in range(game.rows):
		var lit_row: Array = []
		var wall_lit_row: Array = []
		for col in range(game.cols):
			lit_row.append(false)
			wall_lit_row.append(false)
		game.lit.append(lit_row)
		game.wall_lit.append(wall_lit_row)

	# Each bulb lights its own cell and the white cells in its row/column up to
	# the first wall in each direction. That first wall is itself "seen" by the
	# bulb, so it's flagged in wall_lit (used by the clue-0 and blank walls).
	for row in range(game.rows):
		for col in range(game.cols):
			if not game.bulbs[row][col]:
				continue
			game.lit[row][col] = true
			for scan_row in range(row - 1, -1, -1):
				if is_black(scan_row, col):
					game.wall_lit[scan_row][col] = true
					break
				game.lit[scan_row][col] = true
			for scan_row in range(row + 1, game.rows):
				if is_black(scan_row, col):
					game.wall_lit[scan_row][col] = true
					break
				game.lit[scan_row][col] = true
			for scan_col in range(col - 1, -1, -1):
				if is_black(row, scan_col):
					game.wall_lit[row][scan_col] = true
					break
				game.lit[row][scan_col] = true
			for scan_col in range(col + 1, game.cols):
				if is_black(row, scan_col):
					game.wall_lit[row][scan_col] = true
					break
				game.lit[row][scan_col] = true

func _compute_conflicts() -> void:
	game.conflicting_bulbs.clear()
	for row in range(game.rows):
		for col in range(game.cols):
			if not game.bulbs[row][col]:
				continue
			for scan_col in range(col + 1, game.cols):
				if is_black(row, scan_col):
					break
				if game.bulbs[row][scan_col]:
					game.conflicting_bulbs[[row, col]] = true
					game.conflicting_bulbs[[row, scan_col]] = true
			for scan_row in range(row + 1, game.rows):
				if is_black(scan_row, col):
					break
				if game.bulbs[scan_row][col]:
					game.conflicting_bulbs[[row, col]] = true
					game.conflicting_bulbs[[scan_row, col]] = true

func _bulb_neighbor_count(row: int, col: int) -> int:
	var count: int = 0
	var neighbor_offsets: Array = [[-1, 0], [1, 0], [0, -1], [0, 1]]
	for offset: Array in neighbor_offsets:
		var neighbor_row: int = row + offset[0]
		var neighbor_col: int = col + offset[1]
		if neighbor_row >= 0 and neighbor_row < game.rows and neighbor_col >= 0 and neighbor_col < game.cols:
			if game.bulbs[neighbor_row][neighbor_col]:
				count += 1
	return count

# Rewards correctly satisfying a numbered clue (not a blank '#' cell, and
# not a "0" clue -- there's nothing to place there) with extra time before
# the boss check, once per cell per level. Runs identically on every peer
# since it's purely derived from already-synced game.bulbs/game.grid state -- no RPC
# needed, same as the win-animation/game.enemies-clear-on-solve logic.

func _check_clue_bonuses() -> void:
	for row in range(game.rows):
		for col in range(game.cols):
			var cell_data: Dictionary = game.grid[row][col]
			if cell_data["type"] != Constants.CellType.BLACK:
				continue
			var clue_number: int = cell_data["number"]
			if clue_number <= 0:
				continue
			if game.clue_bonus_granted[row][col]:
				continue
			if _bulb_neighbor_count(row, col) == clue_number:
				game.clue_bonus_granted[row][col] = true
				game.current_level_time_limit += game.LEVEL_TIMER_BONUS_SECONDS
				game.timer_bonus_popups.append({"position": Vector2(col, row), "age": 0.0})

# Late-join catch-up: game.marks every clue that's ALREADY satisfied as granted
# without adding bonus time (that time is already folded into the
# game.current_level_time_limit value the host sent along), so a joining client
# doesn't re-grant bonuses for progress made before they connected.

func _mark_currently_satisfied_clues_as_granted() -> void:
	for row in range(game.rows):
		for col in range(game.cols):
			var cell_data: Dictionary = game.grid[row][col]
			if cell_data["type"] != Constants.CellType.BLACK:
				continue
			var clue_number: int = cell_data["number"]
			if clue_number <= 0:
				continue
			if _bulb_neighbor_count(row, col) == clue_number:
				game.clue_bonus_granted[row][col] = true

func _is_solved() -> bool:
	return LightUpSolver.verify_answer(game.grid, game.rows, game.cols, game.bulbs)

# Everything Check Answer should flag when the puzzle ISN'T solved yet: any
# white cell that's neither a bulb nor lit by one, and any numbered black
# cell whose adjacent bulb count doesn't match its clue. Bulb-sees-bulb
# conflicts aren't included here -- those already get a persistent red tint
# the instant they happen (see game.conflicting_bulbs), so re-flagging them
# on Check would just be noise.
func _compute_error_cells() -> Array:
	var error_cells: Array = []
	for row in range(game.rows):
		for col in range(game.cols):
			var cell_data: Dictionary = game.grid[row][col]
			if cell_data["type"] == Constants.CellType.WHITE:
				if not game.bulbs[row][col] and not game.lit[row][col]:
					error_cells.append([row, col])
			elif cell_data["number"] >= 0:
				if _bulb_neighbor_count(row, col) != cell_data["number"]:
					error_cells.append([row, col])
	return error_cells

func recompute_state() -> void:
	_compute_lit()
	_compute_conflicts()
	_check_clue_bonuses()
	game.ui_mgr._update_status()
	game.queue_redraw()

func _empty_bool_grid() -> Array:
	var empty_grid: Array = []
	for row in range(game.rows):
		var empty_row: Array = []
		for col in range(game.cols):
			empty_row.append(false)
		empty_grid.append(empty_row)
	return empty_grid

func _handle_bulb_input() -> void:
	if NetworkManager.is_multiplayer and not game.multiplayer.is_server():
		game.rpc_id(1, "_request_toggle_bulb", game.my_player_index)
	else:
		_request_toggle_bulb(game.my_player_index)

@rpc("any_peer", "call_remote", "reliable")
func _request_toggle_bulb(player_index: int) -> void:
	if NetworkManager.is_multiplayer and not game.multiplayer.is_server():
		return
	if not NetworkManager.validate_request(player_index, game.players.size(), "bulb", 0.08):
		return
	var player_state: Dictionary = game.players[player_index]
	if player_state["is_defeated"]:
		return
	var player_row: int = player_state["row"]
	var player_col: int = player_state["col"]
	if is_black(player_row, player_col):
		return
	var new_bulb_value: bool = not game.bulbs[player_row][player_col]
	if NetworkManager.is_multiplayer:
		game.rpc("_sync_bulb", player_index, player_row, player_col, new_bulb_value)
	else:
		_sync_bulb(player_index, player_row, player_col, new_bulb_value)

@rpc("authority", "call_local", "reliable")
func _sync_bulb(player_index: int, row: int, col: int, bulb_value: bool) -> void:
	game.bulbs[row][col] = bulb_value
	game.player_mgr._trigger_action_animation(player_index, "interact")
	recompute_state()

# --- Combat: attacking, taking damage, dying, respawning -------------------
