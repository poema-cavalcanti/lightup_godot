class_name GridGeometry
extends RefCounted

# ---------------------------------------------------------------------------
# Pure grid-position math shared between the level's puzzle board
# (Game.gd/HUDManager.gd/Player.gd/Enemy.gd/CombatManager.gd) and Town's
# walkable grid (Town.gd) -- both ultimately convert a (row, col) tile into
# a pixel position with the same "origin + tile * cell_size" formula, and
# the level's camera (which follows the focus player and clamps to the
# board's bounds, since a puzzle can be bigger than one screen) is generic
# camera-window math, not anything puzzle-specific.
#
# No per-scene state lives here, just the math -- callers own their own
# origin/cell_size (the level's scrolls and can differ from the full board
# size; Town's is static and always shows its whole grid, which just means
# its view window ends up covering everything with no scroll offset,
# rather than needing a separate "don't scroll" code path).
# ---------------------------------------------------------------------------

static func tile_to_pixel(row: float, col: float, origin: Vector2, cell_size: float) -> Vector2:
	return origin + Vector2(col, row) * cell_size

static func tile_center_to_pixel(row: float, col: float, origin: Vector2, cell_size: float) -> Vector2:
	return tile_to_pixel(row, col, origin, cell_size) + Vector2(cell_size, cell_size) * 0.5

# Camera that follows (focus_row, focus_col), clamped so it never scrolls
# past the grid's own edges, and centers a (possibly smaller-than-available)
# visible window within whatever leftover space there is. Returns a
# Dictionary with view_cols/view_rows (how many tiles are visible),
# view_col_start/view_row_start (the top-left visible tile), and
# extra_x/extra_y (leftover space to center the window within, for callers
# that draw a background/border around it) -- HUDManager._compute_view_window()
# is exactly this, parameterized.
static func compute_view_window(grid_rows: int, grid_cols: int, cell_size: float, focus_row: int, focus_col: int, play_width: float, play_height: float) -> Dictionary:
	var view_cols: int = clampi(int(play_width / cell_size), 1, grid_cols)
	var view_rows: int = clampi(int(play_height / cell_size), 1, grid_rows)
	var view_col_start: int = clampi(focus_col - view_cols / 2, 0, maxi(0, grid_cols - view_cols))
	var view_row_start: int = clampi(focus_row - view_rows / 2, 0, maxi(0, grid_rows - view_rows))
	return {
		"view_cols": view_cols,
		"view_rows": view_rows,
		"view_col_start": view_col_start,
		"view_row_start": view_row_start,
		"extra_x": (play_width - view_cols * cell_size) / 2.0,
		"extra_y": (play_height - view_rows * cell_size) / 2.0,
	}
