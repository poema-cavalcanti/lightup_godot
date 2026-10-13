extends MenuScreen

# ---------------------------------------------------------------------------
# Read-only summary of saved progress (see SaveManager): each campaign
# level's best (fastest) completion time, paired with how much time was
# left on that specific run's clock, plus how many of the 7 endings have
# been seen at least once. Nothing here is interactive beyond Back/F11.
#
# Headings and layout live in Stats.tscn; the labels below carry
# placeholder text in the scene and get their real values here.
# ---------------------------------------------------------------------------

@onready var levels_text: Label = %LevelsText
@onready var endings_label: Label = %EndingsLabel
@onready var endless_text: Label = %EndlessText

func _ready() -> void:
	super._ready()

	levels_text.text = _build_level_times_text()
	endings_label.text = "Endings seen: %d/%d" % [SaveManager.get_endings_seen_count(), CampaignData.ENDING_PLACEHOLDER.size()]

	var best_time_text: String = _format_time(SaveManager.endless_best_time) if SaveManager.endless_best_time >= 0.0 else "--:--"
	endless_text.text = "Longest streak: %d\nBest time survived: %s" % [SaveManager.endless_longest_streak, best_time_text]

func _build_level_times_text() -> String:
	var lines: Array[String] = []
	var total_levels: int = CampaignManager.get_total_level_count()
	for level_index in range(total_levels):
		var record: Dictionary = SaveManager.get_level_best_time(level_index)
		if record.is_empty():
			lines.append("Level %d: not yet completed" % (level_index + 1))
		else:
			lines.append("Level %d: finished in %s  (%s left on the clock)" % [
				level_index + 1, _format_time(record["elapsed"]), _format_time(record["time_left"]),
			])
	return "\n".join(lines)

func _format_time(seconds_value: float) -> String:
	var total_seconds: int = int(ceil(seconds_value))
	var minutes_part: int = total_seconds / 60
	var seconds_part: int = total_seconds % 60
	return "%d:%02d" % [minutes_part, seconds_part]
