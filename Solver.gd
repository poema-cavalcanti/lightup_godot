class_name LightUpSolver
extends RefCounted

# ---------------------------------------------------------------------------
# Solves/verifies Light Up puzzles.
#
# IMPORTANT: WHITE/BLACK here must stay numerically in sync with Game.gd's
# `enum CellType { WHITE, BLACK }` (WHITE=0, BLACK=1) since grid cells are
# passed around as plain {"type": int, "number": int} dictionaries.
# ---------------------------------------------------------------------------

const WHITE: int = 0
const BLACK: int = 1
const NEIGHBOR_OFFSETS: Array = [[-1, 0], [1, 0], [0, -1], [0, 1]]

enum State { UNKNOWN, BULB, EMPTY }

class Result:
	extends RefCounted
	var count: int = 0
	var solution: Array = []  # first solution found, as a 2D Array[bool]; empty until found
	var nodes: int = 0
	var exhausted: bool = false  # true if max_nodes was hit before the search
	                               # finished -- count/solution are then INCONCLUSIVE,
	                               # not ground truth, and must be treated as "unknown"

# Finds up to `max_solutions` solutions for the given grid (numbers included).
# Used two ways:
#   - max_solutions=1 : "does at least one valid layout exist?" (generation)
#   - max_solutions=2 : "is the solution unique?" (uniqueness verification)
#
# max_nodes caps how many search-tree nodes are explored (-1 = unlimited).
# On large/lightly-constrained grids the search can blow up combinatorially;
# a node budget bounds worst-case work deterministically. If the budget is
# hit, result.exhausted is true and count must NOT be trusted as final.
static func solve(grid: Array, rows: int, cols: int, max_solutions: int = 2, max_nodes: int = -1) -> Result:
	var state: Array = []
	for row in range(rows):
		var state_row: Array = []
		for col in range(cols):
			if grid[row][col]["type"] == WHITE:
				state_row.append(State.UNKNOWN)
			else:
				state_row.append(State.EMPTY)
		state.append(state_row)

	var result: Result = Result.new()
	_depth_first_search(grid, rows, cols, state, result, max_solutions, max_nodes)
	return result

# Direct verification of an already-placed board (no searching at all).
# This is the single source of truth for "is this board a correct,
# complete answer?" -- both the live game UI and the generator's
# uniqueness check ultimately agree with this function.
static func verify_answer(grid: Array, rows: int, cols: int, bulbs: Array) -> bool:
	var state: Array = []
	for row in range(rows):
		var state_row: Array = []
		for col in range(cols):
			if grid[row][col]["type"] == BLACK:
				state_row.append(State.EMPTY)
			elif bulbs[row][col]:
				state_row.append(State.BULB)
			else:
				state_row.append(State.EMPTY)
		state.append(state_row)
	return _verify_complete(grid, rows, cols, state)

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _depth_first_search(grid: Array, rows: int, cols: int, state: Array, result: Result, max_solutions: int, max_nodes: int) -> void:
	if max_nodes >= 0 and result.nodes >= max_nodes:
		result.exhausted = true
		return
	result.nodes += 1

	if result.count >= max_solutions:
		return

	var working_state: Array = _deep_copy(state)
	if not _propagate(grid, rows, cols, working_state):
		return
	if not _all_can_be_lit(grid, rows, cols, working_state):
		return

	var next_unknown: Array = _find_unknown(rows, cols, working_state)
	if next_unknown.is_empty():
		if _verify_complete(grid, rows, cols, working_state):
			result.count += 1
			if result.solution.is_empty():
				result.solution = _extract_bulbs(working_state, rows, cols)
		return

	var branch_row: int = next_unknown[0]
	var branch_col: int = next_unknown[1]

	var branch_with_bulb: Array = _deep_copy(working_state)
	branch_with_bulb[branch_row][branch_col] = State.BULB
	_depth_first_search(grid, rows, cols, branch_with_bulb, result, max_solutions, max_nodes)
	if result.count >= max_solutions or result.exhausted:
		return

	var branch_without_bulb: Array = _deep_copy(working_state)
	branch_without_bulb[branch_row][branch_col] = State.EMPTY
	_depth_first_search(grid, rows, cols, branch_without_bulb, result, max_solutions, max_nodes)

static func _deep_copy(state: Array) -> Array:
	var copied_state: Array = []
	for state_row: Array in state:
		copied_state.append(state_row.duplicate())
	return copied_state

static func _is_black(grid: Array, row: int, col: int) -> bool:
	return grid[row][col]["type"] == BLACK

static func _white_neighbors(grid: Array, rows: int, cols: int, row: int, col: int) -> Array:
	var neighbor_positions: Array = []
	for neighbor_offset: Array in NEIGHBOR_OFFSETS:
		var next_row: int = row + neighbor_offset[0]
		var next_col: int = col + neighbor_offset[1]
		if next_row >= 0 and next_row < rows and next_col >= 0 and next_col < cols and not _is_black(grid, next_row, next_col):
			neighbor_positions.append([next_row, next_col])
	return neighbor_positions

# Propagates two deductions to a fixpoint (or returns false on contradiction):
#   A. A numbered black cell's unknown neighbors are forced to BULB/EMPTY
#      once enough of its neighbors are already decided.
#   B. A confirmed bulb forces the rest of its row/column segment to EMPTY
#      (this is just "no two bulbs may see each other").
static func _propagate(grid: Array, rows: int, cols: int, state: Array) -> bool:
	var changed: bool = true
	while changed:
		changed = false

		for row in range(rows):
			for col in range(cols):
				var cell_data: Dictionary = grid[row][col]
				if cell_data["type"] != BLACK or cell_data["number"] < 0:
					continue
				var neighbor_positions: Array = _white_neighbors(grid, rows, cols, row, col)
				var known_bulb_count: int = 0
				var unknown_positions: Array = []
				for neighbor_position: Array in neighbor_positions:
					var neighbor_state: int = state[neighbor_position[0]][neighbor_position[1]]
					if neighbor_state == State.BULB:
						known_bulb_count += 1
					elif neighbor_state == State.UNKNOWN:
						unknown_positions.append(neighbor_position)
				var clue_number: int = cell_data["number"]
				if known_bulb_count > clue_number:
					return false
				if known_bulb_count + unknown_positions.size() < clue_number:
					return false
				if unknown_positions.size() > 0:
					if known_bulb_count == clue_number:
						for unknown_position: Array in unknown_positions:
							state[unknown_position[0]][unknown_position[1]] = State.EMPTY
						changed = true
					elif known_bulb_count + unknown_positions.size() == clue_number:
						for unknown_position: Array in unknown_positions:
							state[unknown_position[0]][unknown_position[1]] = State.BULB
						changed = true

		for row in range(rows):
			for col in range(cols):
				if state[row][col] != State.BULB:
					continue
				for scan_col in range(col - 1, -1, -1):
					if _is_black(grid, row, scan_col):
						break
					if state[row][scan_col] == State.BULB:
						return false
					if state[row][scan_col] == State.UNKNOWN:
						state[row][scan_col] = State.EMPTY
						changed = true
				for scan_col in range(col + 1, cols):
					if _is_black(grid, row, scan_col):
						break
					if state[row][scan_col] == State.BULB:
						return false
					if state[row][scan_col] == State.UNKNOWN:
						state[row][scan_col] = State.EMPTY
						changed = true
				for scan_row in range(row - 1, -1, -1):
					if _is_black(grid, scan_row, col):
						break
					if state[scan_row][col] == State.BULB:
						return false
					if state[scan_row][col] == State.UNKNOWN:
						state[scan_row][col] = State.EMPTY
						changed = true
				for scan_row in range(row + 1, rows):
					if _is_black(grid, scan_row, col):
						break
					if state[scan_row][col] == State.BULB:
						return false
					if state[scan_row][col] == State.UNKNOWN:
						state[scan_row][col] = State.EMPTY
						changed = true
	return true

# Pruning: a white cell already fixed to EMPTY must still have some hope of
# being lit -- some cell in its row-segment or column-segment must be a
# BULB or still UNKNOWN. If not, this whole branch is a dead end.
static func _all_can_be_lit(grid: Array, rows: int, cols: int, state: Array) -> bool:
	for row in range(rows):
		for col in range(cols):
			if _is_black(grid, row, col) or state[row][col] != State.EMPTY:
				continue
			var can_be_lit: bool = false
			for scan_col in range(col - 1, -1, -1):
				if _is_black(grid, row, scan_col):
					break
				if state[row][scan_col] != State.EMPTY:
					can_be_lit = true
					break
			if not can_be_lit:
				for scan_col in range(col + 1, cols):
					if _is_black(grid, row, scan_col):
						break
					if state[row][scan_col] != State.EMPTY:
						can_be_lit = true
						break
			if not can_be_lit:
				for scan_row in range(row - 1, -1, -1):
					if _is_black(grid, scan_row, col):
						break
					if state[scan_row][col] != State.EMPTY:
						can_be_lit = true
						break
			if not can_be_lit:
				for scan_row in range(row + 1, rows):
					if _is_black(grid, scan_row, col):
						break
					if state[scan_row][col] != State.EMPTY:
						can_be_lit = true
						break
			if not can_be_lit:
				return false
	return true

static func _find_unknown(rows: int, cols: int, state: Array) -> Array:
	for row in range(rows):
		for col in range(cols):
			if state[row][col] == State.UNKNOWN:
				return [row, col]
	return []

static func _extract_bulbs(state: Array, rows: int, cols: int) -> Array:
	var bulbs: Array = []
	for row in range(rows):
		var bulb_row: Array = []
		for col in range(cols):
			bulb_row.append(state[row][col] == State.BULB)
		bulbs.append(bulb_row)
	return bulbs

# From-scratch validity check of a fully-assigned state (no UNKNOWNs left,
# or in verify_answer's case, every white cell already decided BULB/EMPTY).
static func _verify_complete(grid: Array, rows: int, cols: int, state: Array) -> bool:
	for row in range(rows):
		for col in range(cols):
			if _is_black(grid, row, col) or state[row][col] == State.BULB:
				continue
			var is_lit: bool = false
			for scan_col in range(col - 1, -1, -1):
				if _is_black(grid, row, scan_col):
					break
				if state[row][scan_col] == State.BULB:
					is_lit = true
					break
			if not is_lit:
				for scan_col in range(col + 1, cols):
					if _is_black(grid, row, scan_col):
						break
					if state[row][scan_col] == State.BULB:
						is_lit = true
						break
			if not is_lit:
				for scan_row in range(row - 1, -1, -1):
					if _is_black(grid, scan_row, col):
						break
					if state[scan_row][col] == State.BULB:
						is_lit = true
						break
			if not is_lit:
				for scan_row in range(row + 1, rows):
					if _is_black(grid, scan_row, col):
						break
					if state[scan_row][col] == State.BULB:
						is_lit = true
						break
			if not is_lit:
				return false

	for row in range(rows):
		for col in range(cols):
			var cell_data: Dictionary = grid[row][col]
			if cell_data["type"] == BLACK and cell_data["number"] >= 0:
				var bulb_neighbor_count: int = 0
				for neighbor_offset: Array in NEIGHBOR_OFFSETS:
					var next_row: int = row + neighbor_offset[0]
					var next_col: int = col + neighbor_offset[1]
					if next_row >= 0 and next_row < rows and next_col >= 0 and next_col < cols:
						if state[next_row][next_col] == State.BULB:
							bulb_neighbor_count += 1
				if bulb_neighbor_count != cell_data["number"]:
					return false
	return true
