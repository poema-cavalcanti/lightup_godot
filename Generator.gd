class_name LightUpGenerator
extends RefCounted

# ---------------------------------------------------------------------------
# Generates a Light Up puzzle that is guaranteed solvable, and (whenever the
# trimming pass succeeds) has a UNIQUE solution.
#
# Standard technique:
#   1. Scatter black cells randomly.
#   1.5. Reject the layout if its white cells aren't all one connected,
#        walkable region -- a bulb can shine into a pocket the player can
#        never walk into, but they still need to be able to reach it to
#        place a bulb there when the solution calls for one.
#   2. Ask the solver whether ANY valid, non-conflicting full illumination
#      exists for that layout (ignoring numbers). If not, the layout is
#      unusable -- try another.
#   3. Turn that found solution into number clues on every black cell.
#   4. Confirm the fully-clued puzzle has EXACTLY one solution.
#   5. Try removing each clue (random order); keep it removed only if the
#      puzzle still has exactly one solution -- so not every black cell
#      ends up numbered, like a real puzzle.
#
# WHITE/BLACK must stay numerically in sync with Game.gd's CellType enum
# and Solver.gd's constants (WHITE=0, BLACK=1).
# ---------------------------------------------------------------------------

const MAX_LAYOUT_ATTEMPTS: int = 1000
const BASE_NODE_BUDGET: int = 200000   # for "does a solution exist" / "is it unique"
const TRIM_NODE_BUDGET: int = 30000    # smaller budget per clue-removal check (runs many times)

# Returns {"success": bool, "rows": PackedStringArray}. Capped at
# MAX_LAYOUT_ATTEMPTS -- fine for callers that can't wait (see GenerationJob
# for the keep-trying-until-found version used by Endless Mode).
static func generate(rows: int, cols: int, black_density: float, rng: RandomNumberGenerator) -> Dictionary:
	for attempt in range(MAX_LAYOUT_ATTEMPTS):
		var rows_found: PackedStringArray = try_generate(rows, cols, black_density, rng)
		if not rows_found.is_empty():
			return {"success": true, "rows": rows_found}
	return {"success": false, "rows": PackedStringArray()}

# A single layout attempt. Returns the puzzle rows, or an empty array if this
# layout didn't pan out.
#
# require_connected = true (the original behavior) throws away any layout whose
# white cells aren't one connected region -- which on a big board is nearly
# every layout. false skips that check and instead, once the puzzle is finished
# and trimmed, connects the white cells afterwards with PuzzleNavigator (the
# result is still uniquely solvable); that returns an empty array when the
# conversion gets stuck, and the caller simply tries a new layout.
static func try_generate(rows: int, cols: int, black_density: float, rng: RandomNumberGenerator, require_connected: bool = true) -> PackedStringArray:
	var grid: Array = _random_black_layout(rows, cols, black_density, rng)

	var white_count: int = 0
	for row in range(rows):
		for col in range(cols):
			if grid[row][col]["type"] == Constants.CELL_WHITE:
				white_count += 1
	if white_count < rows * cols / 2:
		return PackedStringArray()  # too many black cells to be an interesting puzzle

	if require_connected and not _is_fully_connected(grid, rows, cols):
		return PackedStringArray()  # some white cell(s) are walled off -- unreachable by the player

	# Step 1-2: find ANY valid bulb placement for this layout.
	var base_result: LightUpSolver.Result = LightUpSolver.solve(grid, rows, cols, 1, BASE_NODE_BUDGET)
	if base_result.exhausted or base_result.count == 0:
		return PackedStringArray()

	# Step 3: derive clues from that solution.
	_assign_all_clues(grid, rows, cols, base_result.solution)

	# Step 4: fully-clued puzzle must have exactly one solution.
	var uniqueness_check: LightUpSolver.Result = LightUpSolver.solve(grid, rows, cols, 2, BASE_NODE_BUDGET)
	if uniqueness_check.exhausted or uniqueness_check.count != 1:
		return PackedStringArray()

	# Step 5: trim clues while uniqueness holds.
	_trim_clues(grid, rows, cols, rng)

	var puzzle_rows: PackedStringArray = _grid_to_rows(grid, rows, cols)
	if not require_connected:
		return PuzzleNavigator.make_navigable(puzzle_rows)
	return puzzle_rows

static func _random_black_layout(rows: int, cols: int, density: float, rng: RandomNumberGenerator) -> Array:
	var grid: Array = []
	for row in range(rows):
		var grid_row: Array = []
		for col in range(cols):
			if rng.randf() < density:
				grid_row.append({"type": Constants.CELL_BLACK, "number": -1})
			else:
				grid_row.append({"type": Constants.CELL_WHITE, "number": -1})
		grid.append(grid_row)
	return grid

# True only if every white cell is reachable from every other white cell by
# walking (4-directional, through white cells only) -- i.e. there's a
# single connected white region, not several pockets sealed off from each
# other by walls. A layout can have a perfectly valid bulb placement and
# still fail this (a cell can be lit by a bulb down its row/column without
# a walking path to it), which would leave the player unable to actually
# reach a cell that needs a bulb placed on it.
static func _is_fully_connected(grid: Array, rows: int, cols: int) -> bool:
	var total_white: int = 0
	var start_row: int = -1
	var start_col: int = -1
	for row in range(rows):
		for col in range(cols):
			if grid[row][col]["type"] == Constants.CELL_WHITE:
				total_white += 1
				if start_row == -1:
					start_row = row
					start_col = col
	if total_white == 0:
		return false

	var visited: Array = []
	for row in range(rows):
		var visited_row: Array = []
		visited_row.resize(cols)
		visited_row.fill(false)
		visited.append(visited_row)

	var reached: int = 1
	visited[start_row][start_col] = true
	var queue: Array = [[start_row, start_col]]
	while not queue.is_empty():
		var current: Array = queue.pop_back()
		for neighbor_offset: Array in Constants.GRID_NEIGHBOR_OFFSETS:
			var next_row: int = current[0] + neighbor_offset[0]
			var next_col: int = current[1] + neighbor_offset[1]
			if next_row < 0 or next_row >= rows or next_col < 0 or next_col >= cols:
				continue
			if visited[next_row][next_col] or grid[next_row][next_col]["type"] != Constants.CELL_WHITE:
				continue
			visited[next_row][next_col] = true
			reached += 1
			queue.append([next_row, next_col])

	return reached == total_white

static func _assign_all_clues(grid: Array, rows: int, cols: int, solution: Array) -> void:
	for row in range(rows):
		for col in range(cols):
			if grid[row][col]["type"] != Constants.CELL_BLACK:
				continue
			var bulb_neighbor_count: int = 0
			for neighbor_offset: Array in Constants.GRID_NEIGHBOR_OFFSETS:
				var next_row: int = row + neighbor_offset[0]
				var next_col: int = col + neighbor_offset[1]
				if next_row >= 0 and next_row < rows and next_col >= 0 and next_col < cols and solution[next_row][next_col]:
					bulb_neighbor_count += 1
			grid[row][col]["number"] = bulb_neighbor_count

static func _trim_clues(grid: Array, rows: int, cols: int, rng: RandomNumberGenerator) -> void:
	var black_cell_positions: Array = []
	for row in range(rows):
		for col in range(cols):
			if grid[row][col]["type"] == Constants.CELL_BLACK:
				black_cell_positions.append([row, col])
	black_cell_positions = _shuffled(black_cell_positions, rng)

	for black_cell_position: Array in black_cell_positions:
		var row: int = black_cell_position[0]
		var col: int = black_cell_position[1]
		var saved_number: int = grid[row][col]["number"]
		grid[row][col]["number"] = -1
		var uniqueness_check: LightUpSolver.Result = LightUpSolver.solve(grid, rows, cols, 2, TRIM_NODE_BUDGET)
		# If the check couldn't finish within budget, we genuinely don't know
		# whether removing this clue keeps the puzzle unique -- keep the
		# clue rather than gamble on an unverified removal.
		if uniqueness_check.exhausted or uniqueness_check.count != 1:
			grid[row][col]["number"] = saved_number

static func _shuffled(input_array: Array, rng: RandomNumberGenerator) -> Array:
	var shuffled_array: Array = input_array.duplicate()
	for current_index in range(shuffled_array.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, current_index)
		var swapped_value: Array = shuffled_array[current_index]
		shuffled_array[current_index] = shuffled_array[swap_index]
		shuffled_array[swap_index] = swapped_value
	return shuffled_array

static func _grid_to_rows(grid: Array, rows: int, cols: int) -> PackedStringArray:
	var puzzle_rows: PackedStringArray = PackedStringArray()
	for row in range(rows):
		var row_string: String = ""
		for col in range(cols):
			var cell_data: Dictionary = grid[row][col]
			if cell_data["type"] == Constants.CELL_WHITE:
				row_string += "."
			elif cell_data["number"] < 0:
				row_string += "#"
			else:
				row_string += str(cell_data["number"])
		puzzle_rows.append(row_string)
	return puzzle_rows
