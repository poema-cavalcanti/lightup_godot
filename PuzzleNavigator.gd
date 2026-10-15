class_name PuzzleNavigator
extends RefCounted

# ---------------------------------------------------------------------------
# Connects the open (white) cells of a finished, uniquely solvable puzzle so a
# player can walk to every one of them -- while keeping the puzzle uniquely
# solvable. A GDScript port of make_navigable.py (which used an integer-program
# solver; this one uses LightUpSolver), run by LightUpGenerator on a worker
# thread. It replaces "throw away every random layout whose white cells aren't
# one connected region and try again", which on big boards rejects nearly
# every layout.
#
# Puzzles here are arrays of row strings: '#' black cell, '0'-'4' numbered
# black cell, '.' white cell. Cells are Vector2i(row, col).
#
# ALGORITHM (one "round" per bridge, until a single white region remains)
#   A "bridge candidate" is an unnumbered '#' that touches two or more
#   different white regions; opening it (turning it into '.') joins them. A
#   move only counts if the result is verified to have exactly ONE solution.
#     Stage A  keep the solution S exactly: open a bridge only if the new white
#              cell is already lit by exactly one bulb in each direction at
#              most, or can hold its own bulb without touching a clue.
#     Stage B  open the bridge and let the solution shift: take the new
#              solution closest to S.
#     Stage C  as B, but also turn one nearby (<= 3 cells) numbered black cell
#              into a plain '#' ("relaxing a clue").
#   If opening leaves a second solution, it is repaired by numbering an
#   unnumbered black cell next to where the two solutions differ (_fix_unique).
#   Candidates are ranked: most regions joined first, then least disturbance.
#
# make_navigable() returns an empty array when it gets "stuck" (no bridge can be
# opened while staying unique, a check couldn't finish inside its node budget,
# or TIME_BUDGET_MSEC ran out) -- the caller then generates a new board.
# ---------------------------------------------------------------------------

const SOLVE_NODE_BUDGET: int = 60000     # per solver call; a call that runs out is treated as "can't verify" (a rejection)
const SHIFT_SOLUTION_LIMIT: int = 10      # stage B/C: how many solutions to look at when picking the closest to S
const MAX_FIX_ADDITIONS: int = 30        # clues _fix_unique may add to one bridge before giving up
const STAGE_A_TRIES: int = 10            # candidates fully checked per round in stage A...
const STAGE_B_CANDIDATES: int = 8        # ...and considered per round in stages B and C
const RELAX_CLUES_PER_CANDIDATE: int = 6 # nearest clues tried as the stage C relaxation, per candidate
const CLUE_RELAX_DISTANCE: int = 3
const TIME_BUDGET_MSEC: int = 40000      # whole conversion

static func make_navigable(puzzle_rows: PackedStringArray) -> PackedStringArray:
	var deadline_msec: int = Time.get_ticks_msec() + TIME_BUDGET_MSEC
	var g: Array = Array(puzzle_rows)
	var start: LightUpSolver.Result = _solve(g, 2)
	if start.exhausted or start.count != 1:
		return PackedStringArray()  # input must have exactly one (verified) solution
	var bulbs: Dictionary = _solution_set(start.solution)

	while true:
		var regions: Dictionary = _components(g)
		if regions["count"] == 1:
			break
		if Time.get_ticks_msec() > deadline_msec:
			return PackedStringArray()
		var candidates: Array = _bridge_candidates(g, regions["ids"])
		if candidates.is_empty():
			return PackedStringArray()

		var move: Dictionary = _stage_a(g, bulbs, candidates, deadline_msec)
		if move.is_empty():
			move = _stage_b_and_c(g, bulbs, candidates, deadline_msec)
		if move.is_empty():
			return PackedStringArray()  # stuck
		g = move["grid"]
		bulbs = move["bulbs"]

	# Final verification: exactly one solution, exactly one white region.
	var final_check: LightUpSolver.Result = _solve(g, 2)
	if final_check.exhausted or final_check.count != 1 or _components(g)["count"] != 1:
		return PackedStringArray()
	return PackedStringArray(g)

# --- Stage A: keep the solution untouched ---------------------------------------

# Returns {"grid", "bulbs"} for the first bridge (best first) that opens cleanly
# and verifies unique, or {} if none does.
static func _stage_a(g: Array, bulbs: Dictionary, candidates: Array, deadline_msec: int) -> Dictionary:
	var options: Array = []
	for candidate: Dictionary in candidates:
		var opened: Dictionary = _try_open_keep_solution(g, bulbs, candidate["cell"])
		if not opened.is_empty():
			opened["merged"] = candidate["merged"]
			opened["added"] = opened["bulbs"].size() - bulbs.size()
			opened["cell"] = candidate["cell"]
			options.append(opened)
	options.sort_custom(_compare_options)

	var tries: int = 0
	for option: Dictionary in options:
		if tries >= STAGE_A_TRIES or Time.get_ticks_msec() > deadline_msec:
			break
		tries += 1
		var repaired: Variant = _fix_unique(option["grid"], option["bulbs"])
		if repaired != null:
			return {"grid": repaired, "bulbs": option["bulbs"]}
	return {}

# Most regions merged first, then fewest new bulbs, then position (for a stable order).
static func _compare_options(a: Dictionary, b: Dictionary) -> bool:
	if a["merged"] != b["merged"]:
		return a["merged"] > b["merged"]
	if a["added"] != b["added"]:
		return a["added"] < b["added"]
	return _cell_less(a["cell"], b["cell"])

static func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)

# Opens bridge b without disturbing S. {} if two bulbs would then see each other,
# or the new cell needs a bulb of its own but touches a clue.
static func _try_open_keep_solution(g: Array, bulbs: Dictionary, b: Vector2i) -> Dictionary:
	var g2: Array = _set_cell(g, b, ".")
	var is_lit: bool = false
	for direction: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		var count: int = 0
		for cell: Vector2i in _run_through(g2, b, direction):
			if bulbs.has(cell):
				count += 1
		if count > 1:
			return {}  # two bulbs would see each other
		if count == 1:
			is_lit = true
	var new_bulbs: Dictionary = bulbs.duplicate()
	if not is_lit:
		for offset: Array in Constants.GRID_NEIGHBOR_OFFSETS:
			var neighbor: Vector2i = Vector2i(b.x + offset[0], b.y + offset[1])
			if _in_bounds(g, neighbor) and _char_at(g, neighbor) >= "0" and _char_at(g, neighbor) <= "9":
				return {}  # a bulb here would break that clue
		new_bulbs[b] = true
	return {"grid": g2, "bulbs": new_bulbs}

# --- Stages B and C: let the solution shift ---------------------------------------

static func _stage_b_and_c(g: Array, bulbs: Dictionary, candidates: Array, deadline_msec: int) -> Dictionary:
	var ranked: Array = candidates.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["merged"] != b["merged"]:
			return a["merged"] > b["merged"]
		return _cell_less(a["cell"], b["cell"]))
	if ranked.size() > STAGE_B_CANDIDATES:
		ranked.resize(STAGE_B_CANDIDATES)

	# Stage B for every considered bridge first, then C -- like the original ranking, "no clue relaxed" always beats "one relaxed".
	for relax_clues in [false, true]:
		var options: Array = []
		for candidate: Dictionary in ranked:
			if Time.get_ticks_msec() > deadline_msec:
				return {}
			var cell: Vector2i = candidate["cell"]
			var relaxations: Array = [Vector2i(-1, -1)]
			if relax_clues:
				relaxations = _nearby_clues(g, cell)
			for relaxed: Vector2i in relaxations:
				var g2: Array = _set_cell(g, cell, ".")
				if relaxed.x >= 0:
					g2 = _set_cell(g2, relaxed, "#")
				var closest: Dictionary = _closest_solution(g2, bulbs)
				if not closest.is_empty():
					options.append({"grid": g2, "bulbs": closest["bulbs"], "shift": closest["shift"], "merged": candidate["merged"], "cell": cell})
		options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["shift"] != b["shift"]:
				return a["shift"] < b["shift"]
			if a["merged"] != b["merged"]:
				return a["merged"] > b["merged"]
			return _cell_less(a["cell"], b["cell"]))
		var tries: int = 0
		for option: Dictionary in options:
			if tries >= STAGE_A_TRIES or Time.get_ticks_msec() > deadline_msec:
				break
			tries += 1
			var repaired: Variant = _fix_unique(option["grid"], option["bulbs"])
			if repaired != null:
				return {"grid": repaired, "bulbs": option["bulbs"]}
	return {}

# Numbered black cells within CLUE_RELAX_DISTANCE of cell, nearest first (at most RELAX_CLUES_PER_CANDIDATE).
static func _nearby_clues(g: Array, cell: Vector2i) -> Array:
	var found: Array = []
	for row in range(g.size()):
		for col in range(g[0].length()):
			var ch: String = g[row][col]
			var distance: int = abs(row - cell.x) + abs(col - cell.y)
			if ch >= "0" and ch <= "9" and distance <= CLUE_RELAX_DISTANCE:
				found.append({"cell": Vector2i(row, col), "distance": distance})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["distance"] != b["distance"]:
			return a["distance"] < b["distance"]
		return _cell_less(a["cell"], b["cell"]))
	var cells: Array = []
	for entry: Dictionary in found:
		cells.append(entry["cell"])
		if cells.size() >= RELAX_CLUES_PER_CANDIDATE:
			break
	return cells

# Of up to SHIFT_SOLUTION_LIMIT solutions of g, the one sharing the most bulbs with `prefer`.
# {} if there is none (or the search ran out before finding any).
static func _closest_solution(g: Array, prefer: Dictionary) -> Dictionary:
	var result: LightUpSolver.Result = _solve(g, SHIFT_SOLUTION_LIMIT)
	if result.count == 0:
		return {}
	var best: Dictionary = {}
	for solution: Array in result.solutions:
		var cells_set: Dictionary = _solution_set(solution)
		var shift: int = _symmetric_difference_size(cells_set, prefer)
		if best.is_empty() or shift < best["shift"]:
			best = {"bulbs": cells_set, "shift": shift}
	return best

# --- Uniqueness repair -------------------------------------------------------------

# Makes `bulbs` the unique solution of g by numbering unnumbered black cells that
# tell it apart from a rival solution. Returns the repaired grid, or null.
static func _fix_unique(g: Array, bulbs: Dictionary) -> Variant:
	for _attempt in range(MAX_FIX_ADDITIONS):
		var result: LightUpSolver.Result = _solve(g, 2)
		if result.exhausted or result.count == 0:
			return null
		if result.count == 1:
			return g if _same_set(_solution_set(result.solution), bulbs) else null
		var rival: Dictionary = {}
		for solution: Array in result.solutions:
			var cells_set: Dictionary = _solution_set(solution)
			if not _same_set(cells_set, bulbs):
				rival = cells_set
				break
		if rival.is_empty():
			return g

		var votes: Dictionary = {}  # black cell -> how many differing cells it touches
		for cell: Vector2i in _symmetric_difference(bulbs, rival):
			for offset: Array in Constants.GRID_NEIGHBOR_OFFSETS:
				var neighbor: Vector2i = Vector2i(cell.x + offset[0], cell.y + offset[1])
				if _in_bounds(g, neighbor) and _char_at(g, neighbor) == "#":
					votes[neighbor] = votes.get(neighbor, 0) + 1
		var best_cell: Vector2i = Vector2i(-1, -1)
		var best_votes: int = 0
		for neighbor: Vector2i in votes:
			if _adjacent_bulbs(bulbs, neighbor) == _adjacent_bulbs(rival, neighbor):
				continue  # numbering it wouldn't rule the rival out
			if votes[neighbor] > best_votes or (votes[neighbor] == best_votes and _cell_less(neighbor, best_cell)):
				best_cell = neighbor
				best_votes = votes[neighbor]
		if best_votes == 0:
			return null
		g = _set_cell(g, best_cell, str(_adjacent_bulbs(bulbs, best_cell)))
	return null

static func _adjacent_bulbs(bulbs: Dictionary, cell: Vector2i) -> int:
	var count: int = 0
	for offset: Array in Constants.GRID_NEIGHBOR_OFFSETS:
		if bulbs.has(Vector2i(cell.x + offset[0], cell.y + offset[1])):
			count += 1
	return count

# --- White regions ---------------------------------------------------------------------

# {"ids": Vector2i -> region number for every white cell, "count": number of regions}
static func _components(g: Array) -> Dictionary:
	var ids: Dictionary = {}
	var count: int = 0
	for row in range(g.size()):
		for col in range(g[0].length()):
			var start: Vector2i = Vector2i(row, col)
			if g[row][col] != "." or ids.has(start):
				continue
			ids[start] = count
			var queue: Array = [start]
			while not queue.is_empty():
				var current: Vector2i = queue.pop_back()
				for offset: Array in Constants.GRID_NEIGHBOR_OFFSETS:
					var next: Vector2i = Vector2i(current.x + offset[0], current.y + offset[1])
					if _in_bounds(g, next) and _char_at(g, next) == "." and not ids.has(next):
						ids[next] = count
						queue.append(next)
			count += 1
	return {"ids": ids, "count": count}

# Unnumbered '#' cells that touch two or more different regions: [{"cell", "merged": regions joined - 1}].
static func _bridge_candidates(g: Array, ids: Dictionary) -> Array:
	var found: Array = []
	for row in range(g.size()):
		for col in range(g[0].length()):
			if g[row][col] != "#":
				continue
			var touching: Dictionary = {}
			for offset: Array in Constants.GRID_NEIGHBOR_OFFSETS:
				var neighbor: Vector2i = Vector2i(row + offset[0], col + offset[1])
				if ids.has(neighbor):
					touching[ids[neighbor]] = true
			if touching.size() >= 2:
				found.append({"cell": Vector2i(row, col), "merged": touching.size() - 1})
	return found

# The white cells in the straight run through `cell` along `direction` (cell itself included).
static func _run_through(g: Array, cell: Vector2i, direction: Vector2i) -> Array:
	var run: Array = [cell]
	for step in [1, -1]:
		var next: Vector2i = cell + direction * step
		while _in_bounds(g, next) and _char_at(g, next) == ".":
			run.append(next)
			next += direction * step
	return run

# --- Small helpers -------------------------------------------------------------------------

static func _in_bounds(g: Array, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < g.size() and cell.y >= 0 and cell.y < g[0].length()

static func _char_at(g: Array, cell: Vector2i) -> String:
	return g[cell.x][cell.y]

static func _set_cell(g: Array, cell: Vector2i, ch: String) -> Array:
	var copy: Array = g.duplicate()
	var row: String = copy[cell.x]
	copy[cell.x] = row.substr(0, cell.y) + ch + row.substr(cell.y + 1)
	return copy

# LightUpSolver on a row-string puzzle.
static func _solve(g: Array, max_solutions: int) -> LightUpSolver.Result:
	var rows: int = g.size()
	var cols: int = g[0].length()
	var grid: Array = []
	for row in range(rows):
		var grid_row: Array = []
		for col in range(cols):
			var ch: String = g[row][col]
			if ch == ".":
				grid_row.append({"type": Constants.CELL_WHITE, "number": -1})
			elif ch == "#":
				grid_row.append({"type": Constants.CELL_BLACK, "number": -1})
			else:
				grid_row.append({"type": Constants.CELL_BLACK, "number": int(ch)})
		grid.append(grid_row)
	return LightUpSolver.solve(grid, rows, cols, max_solutions, SOLVE_NODE_BUDGET)

# A solver solution (2D bool array) as a set of bulb cells.
static func _solution_set(solution: Array) -> Dictionary:
	var cells_set: Dictionary = {}
	for row in range(solution.size()):
		for col in range(solution[row].size()):
			if solution[row][col]:
				cells_set[Vector2i(row, col)] = true
	return cells_set

static func _same_set(a: Dictionary, b: Dictionary) -> bool:
	return a.size() == b.size() and _symmetric_difference_size(a, b) == 0

static func _symmetric_difference(a: Dictionary, b: Dictionary) -> Array:
	var cells: Array = []
	for cell: Vector2i in a:
		if not b.has(cell):
			cells.append(cell)
	for cell: Vector2i in b:
		if not a.has(cell):
			cells.append(cell)
	return cells

static func _symmetric_difference_size(a: Dictionary, b: Dictionary) -> int:
	return _symmetric_difference(a, b).size()
