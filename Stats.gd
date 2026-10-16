extends MenuScreen

# ---------------------------------------------------------------------------
# Read-only summary of saved progress (see SaveManager): each campaign
# level's best (fastest) completion time, paired with how much time was
# left on that specific run's clock, plus how many of the 7 endings have
# been seen at least once. Nothing here is interactive beyond Back/F11.
#
# Headings and layout live in Stats.tscn. The two tables (GridContainers) are
# empty there and get their header row, divider and data rows built here.
# ---------------------------------------------------------------------------

const TABLE_FONT_SIZE: int = 16
const HEADER_COLOR: Color = Color(1.0, 0.85, 0.3)
const DIVIDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.25)
const NOT_DONE_COLOR: Color = Color(0.6, 0.6, 0.66)
const NO_TIME_TEXT: String = "--:--"
const LEVEL_COLUMN_WIDTHS: Array[int] = [90, 120, 190]  # Level | Best Time | Time left on Clock
const ENDLESS_COLUMN_WIDTHS: Array[int] = [90, 120]     # Streak | Time

@onready var levels_table: GridContainer = %LevelsTable
@onready var endings_label: Label = %EndingsLabel
@onready var endless_table: GridContainer = %EndlessTable

func _ready() -> void:
	super._ready()

	_build_level_times_table()
	endings_label.text = "Endings seen: %d/%d" % [SaveManager.get_endings_seen_count(), CampaignData.ENDING_PLACEHOLDER.size()]

	var has_endless_time: bool = SaveManager.endless_best_time >= 0.0
	_fill_table(endless_table, ["Longest Streak", "Time"], ENDLESS_COLUMN_WIDTHS, [{
		"cells": [str(SaveManager.endless_longest_streak), _format_time(SaveManager.endless_best_time) if has_endless_time else NO_TIME_TEXT],
		"dim": not has_endless_time and SaveManager.endless_longest_streak <= 0,
	}])

# One row per campaign level; levels you haven't finished show dashes, dimmed.
func _build_level_times_table() -> void:
	var rows: Array[Dictionary] = []
	for level_index in range(CampaignManager.get_total_level_count()):
		var record: Dictionary = SaveManager.get_level_best_time(level_index)
		var level_name: String = "Level %d" % (level_index + 1)
		if record.is_empty():
			rows.append({"cells": [level_name, NO_TIME_TEXT, NO_TIME_TEXT], "dim": true})
		else:
			rows.append({"cells": [level_name, _format_time(record["elapsed"]), _format_time(record["time_left"])], "dim": false})
	_fill_table(levels_table, ["Level", "Best Time", "Time left on Clock"], LEVEL_COLUMN_WIDTHS, rows)

# Rebuilds a table: header row, a thin divider under it, then the data rows ({"cells": [String], "dim": bool}).
# Everything is left aligned; column_widths keeps the columns lined up between rows.
func _fill_table(table: GridContainer, headers: Array[String], column_widths: Array[int], rows: Array[Dictionary]) -> void:
	for child: Node in table.get_children():
		child.queue_free()
		table.remove_child(child)
	for column_index in range(headers.size()):
		table.add_child(_make_cell(headers[column_index], column_widths[column_index], HEADER_COLOR))
	for column_index in range(headers.size()):
		var divider: ColorRect = ColorRect.new()
		divider.custom_minimum_size = Vector2(column_widths[column_index], 2)
		divider.color = DIVIDER_COLOR
		table.add_child(divider)
	for row: Dictionary in rows:
		var cells: Array = row["cells"]
		for column_index in range(cells.size()):
			var cell_color: Color = NOT_DONE_COLOR if row["dim"] and column_index > 0 else Color.WHITE
			table.add_child(_make_cell(cells[column_index], column_widths[column_index], cell_color))

func _make_cell(cell_text: String, column_width: int, text_color: Color) -> Label:
	var cell: Label = Label.new()
	cell.text = cell_text
	cell.custom_minimum_size = Vector2(column_width, 0)
	cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cell.add_theme_font_size_override("font_size", TABLE_FONT_SIZE)
	cell.add_theme_color_override("font_color", text_color)
	return cell

func _format_time(seconds_value: float) -> String:
	var total_seconds: int = int(ceil(seconds_value))
	var minutes_part: int = total_seconds / 60
	var seconds_part: int = total_seconds % 60
	return "%d:%02d" % [minutes_part, seconds_part]
