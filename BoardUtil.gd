class_name BoardUtil
extends RefCounted

# ---------------------------------------------------------------------------
# Turns a puzzle's string-row encoding into player spawn positions, without
# needing a live Game.gd instance. NetworkManager calls this to compute
# spawns BEFORE the game scene exists (so it can hand them to clients
# alongside the puzzle itself); Game.gd calls it again after Reset / New
# Puzzle to re-spawn everyone.
# ---------------------------------------------------------------------------

const NEIGHBOR_OFFSETS: Array = [[-1, 0], [1, 0], [0, -1], [0, 1]]

static func _is_black(rows_array: PackedStringArray, row: int, col: int) -> bool:
	return rows_array[row][col] != "."

static func find_nearest_white(rows_array: PackedStringArray, row_count: int, col_count: int, start_row: int, start_col: int) -> Array:
	if not _is_black(rows_array, start_row, start_col):
		return [start_row, start_col]
	var visited: Dictionary = {}
	var frontier: Array = [[start_row, start_col]]
	visited["%d,%d" % [start_row, start_col]] = true
	while frontier.size() > 0:
		var next_frontier: Array = []
		for frontier_position: Array in frontier:
			for neighbor_offset: Array in Constants.GRID_NEIGHBOR_OFFSETS:
				var next_row: int = frontier_position[0] + neighbor_offset[0]
				var next_col: int = frontier_position[1] + neighbor_offset[1]
				if next_row < 0 or next_row >= row_count or next_col < 0 or next_col >= col_count:
					continue
				var visited_key: String = "%d,%d" % [next_row, next_col]
				if visited.has(visited_key):
					continue
				visited[visited_key] = true
				if not _is_black(rows_array, next_row, next_col):
					return [next_row, next_col]
				next_frontier.append([next_row, next_col])
		frontier = next_frontier
	return [0, 0]  # unreachable on any real (fully-lightable) puzzle

# Returns up to 4 [row, col] starting positions, one per player, in the
# order top-left, top-right, bottom-left, bottom-right -- snapped to the
# nearest white cell if the exact corner happens to be black.
static func corner_positions(rows_array: PackedStringArray, player_count: int) -> Array:
	var row_count: int = rows_array.size()
	var col_count: int = rows_array[0].length()
	var raw_corners: Array = [
		[0, 0],
		[0, col_count - 1],
		[row_count - 1, 0],
		[row_count - 1, col_count - 1],
	]
	var corner_position_list: Array = []
	for player_index in range(player_count):
		var corner: Array = raw_corners[player_index]
		corner_position_list.append(find_nearest_white(rows_array, row_count, col_count, corner[0], corner[1]))
	return corner_position_list
