extends Node

# ---------------------------------------------------------------------------
# Autoload (registered in project.godot). Persists whether the campaign has
# ever been completed (gates Endless Mode on the Main Menu), in-progress
# campaign position (current level, boss-summon history, gold, and
# inventory so far) so quitting to the Main Menu mid-campaign and coming
# back resumes instead of restarting from Level 1, each level's best
# completion time (for the Stats screen), and which of the 7 endings have
# been seen at least once. Uses Godot's built-in ConfigFile format -- a
# simple, human-readable key-value save file, no need to hand-roll JSON.
# ---------------------------------------------------------------------------

const SAVE_PATH: String = "user://savegame.cfg"
const SAVE_SECTION: String = "progress"
const COMPLETED_CAMPAIGN_KEY: String = "completed_campaign"
const CAMPAIGN_LEVEL_INDEX_KEY: String = "campaign_level_index"
const CAMPAIGN_BOSS_HISTORY_KEY: String = "campaign_boss_history"
const CAMPAIGN_GOLD_KEY: String = "campaign_gold"
const CAMPAIGN_INVENTORY_KEY: String = "campaign_inventory"
const CAMPAIGN_EQUIPPED_KEY: String = "campaign_equipped"
const LEVEL_BEST_TIMES_KEY: String = "level_best_times"
const ENDINGS_SEEN_KEY: String = "endings_seen"
const ENDLESS_LONGEST_STREAK_KEY: String = "endless_longest_streak"
const ENDLESS_BEST_TIME_KEY: String = "endless_best_time"

var has_completed_campaign: bool = false
var saved_campaign_level_index: int = -1  # -1 means no in-progress campaign saved
var saved_campaign_boss_history: Array = []
var saved_campaign_gold: int = 0
var saved_campaign_inventory: Dictionary = {}  # item_id -> quantity owned
var saved_campaign_equipped: Dictionary = {}  # slot name -> equipped item_id (or "")
var level_best_times: Dictionary = {}  # level_index (int, 0-based) -> {"elapsed": float, "time_left": float}
var endings_seen: Array = []  # unique ending numbers (1-based) the player has reached at least once
var endless_longest_streak: int = 0  # most puzzles solved in a row in one Endless Mode run, ever
var endless_best_time: float = -1.0  # longest a single Endless Mode run has lasted, in seconds; -1 = none yet

func _ready() -> void:
	_load_save_data()

func _load_save_data() -> void:
	var save_file: ConfigFile = ConfigFile.new()
	var load_result: int = save_file.load(SAVE_PATH)
	if load_result == OK:
		has_completed_campaign = save_file.get_value(SAVE_SECTION, COMPLETED_CAMPAIGN_KEY, false)
		saved_campaign_level_index = save_file.get_value(SAVE_SECTION, CAMPAIGN_LEVEL_INDEX_KEY, -1)
		saved_campaign_boss_history = save_file.get_value(SAVE_SECTION, CAMPAIGN_BOSS_HISTORY_KEY, [])
		saved_campaign_gold = save_file.get_value(SAVE_SECTION, CAMPAIGN_GOLD_KEY, 0)
		saved_campaign_inventory = save_file.get_value(SAVE_SECTION, CAMPAIGN_INVENTORY_KEY, {})
		saved_campaign_equipped = save_file.get_value(SAVE_SECTION, CAMPAIGN_EQUIPPED_KEY, {})
		level_best_times = save_file.get_value(SAVE_SECTION, LEVEL_BEST_TIMES_KEY, {})
		endings_seen = save_file.get_value(SAVE_SECTION, ENDINGS_SEEN_KEY, [])
		endless_longest_streak = save_file.get_value(SAVE_SECTION, ENDLESS_LONGEST_STREAK_KEY, 0)
		endless_best_time = save_file.get_value(SAVE_SECTION, ENDLESS_BEST_TIME_KEY, -1.0)

func mark_campaign_completed() -> void:
	clear_campaign_progress()  # a finished campaign has nothing left to resume
	if has_completed_campaign:
		return  # already saved, avoid a redundant disk write
	has_completed_campaign = true
	_write_save_data()

# Called every time the player advances to a new level, or buys/equips
# something in a Town shop or the inventory panel, so quitting to the Main
# Menu any time after any of those always resumes with the right level,
# gold, inventory, and equipped items.
func save_campaign_progress(level_index: int, boss_history: Array, gold: int, inventory: Dictionary, equipped: Dictionary) -> void:
	saved_campaign_level_index = level_index
	saved_campaign_boss_history = boss_history.duplicate()
	saved_campaign_gold = gold
	saved_campaign_inventory = inventory.duplicate()
	saved_campaign_equipped = equipped.duplicate()
	_write_save_data()

func has_campaign_in_progress() -> bool:
	# Just the level index, deliberately not gated on has_completed_campaign
	# too: that flag stays true forever once you finish the campaign once
	# (it also permanently unlocks Endless Mode), but a *later* fresh
	# playthrough still needs its own progress to resume correctly. Right
	# after actually completing the campaign, saved_campaign_level_index is
	# already reset to -1 by clear_campaign_progress() below, so this alone
	# already returns false at the moment that matters.
	return saved_campaign_level_index > 0

func clear_campaign_progress() -> void:
	saved_campaign_level_index = -1
	saved_campaign_boss_history = []
	saved_campaign_gold = 0
	saved_campaign_inventory = {}
	saved_campaign_equipped = {}
	_write_save_data()

# Only overwrites the stored record for this level if there wasn't one yet,
# or this run beat it (lower elapsed time). time_left is whatever was left
# on that specific run's clock (which can itself vary, since clue bonuses
# grow it), stored alongside rather than derived, so the Stats screen can
# show both without assuming a fixed level time limit.
func record_level_best_time(level_index: int, elapsed: float, time_left: float) -> void:
	var key: String = str(level_index)
	var existing: Dictionary = level_best_times.get(key, {})
	if not existing.is_empty() and existing["elapsed"] <= elapsed:
		return
	level_best_times[key] = {"elapsed": elapsed, "time_left": time_left}
	_write_save_data()

# Returns {} if this level has never been completed, else {"elapsed":
# float, "time_left": float}.
func get_level_best_time(level_index: int) -> Dictionary:
	return level_best_times.get(str(level_index), {})

func record_ending_seen(ending_number: int) -> void:
	if ending_number in endings_seen:
		return
	endings_seen.append(ending_number)
	_write_save_data()

func get_endings_seen_count() -> int:
	return endings_seen.size()

# Called once an Endless Mode run ends (quitting to the Main Menu, or the
# whole party being defeated) with how many puzzles were solved in a row
# and how long the run lasted. Each is kept independently -- a run doesn't
# have to beat both records to improve one of them.
func record_endless_run(streak: int, elapsed_seconds: float) -> void:
	var changed: bool = false
	if streak > endless_longest_streak:
		endless_longest_streak = streak
		changed = true
	if elapsed_seconds > endless_best_time:
		endless_best_time = elapsed_seconds
		changed = true
	if changed:
		_write_save_data()

func _write_save_data() -> void:
	var save_file: ConfigFile = ConfigFile.new()
	save_file.set_value(SAVE_SECTION, COMPLETED_CAMPAIGN_KEY, has_completed_campaign)
	save_file.set_value(SAVE_SECTION, CAMPAIGN_LEVEL_INDEX_KEY, saved_campaign_level_index)
	save_file.set_value(SAVE_SECTION, CAMPAIGN_BOSS_HISTORY_KEY, saved_campaign_boss_history)
	save_file.set_value(SAVE_SECTION, CAMPAIGN_GOLD_KEY, saved_campaign_gold)
	save_file.set_value(SAVE_SECTION, CAMPAIGN_INVENTORY_KEY, saved_campaign_inventory)
	save_file.set_value(SAVE_SECTION, CAMPAIGN_EQUIPPED_KEY, saved_campaign_equipped)
	save_file.set_value(SAVE_SECTION, LEVEL_BEST_TIMES_KEY, level_best_times)
	save_file.set_value(SAVE_SECTION, ENDINGS_SEEN_KEY, endings_seen)
	save_file.set_value(SAVE_SECTION, ENDLESS_LONGEST_STREAK_KEY, endless_longest_streak)
	save_file.set_value(SAVE_SECTION, ENDLESS_BEST_TIME_KEY, endless_best_time)
	var save_result: Error = save_file.save(SAVE_PATH)
	if save_result != OK:
		push_error("Failed to save game data: %s" % error_string(save_result))
