extends Node

# ---------------------------------------------------------------------------
# Autoload (registered in project.godot). Tracks progress through the
# campaign (CampaignData.LEVELS) across the scene changes between
# Cutscene.tscn, Game.tscn, and Town.tscn. Campaign mode is singleplayer
# only -- nothing here interacts with NetworkManager.
#
# boss_summoned_history[i] is whether the boss was summoned during level
# i+1's playthrough (true/false), appended in order as each level is
# completed. Its length doubles as "how many levels have been completed",
# which is exactly the index get_cutscene_data() uses to decide which
# cutscene comes next -- 0 completed means the fixed Chapter One intro,
# 1 or 2 completed use their own specific branches, 3+ use the general
# 7-way split from CampaignData.evaluate_boss_path().
# ---------------------------------------------------------------------------

var current_level_index: int = 0
var is_campaign_active: bool = false
var boss_summoned_history: Array[bool] = []
var gold: int = 0  # campaign currency -- earned per level (see credit_level_earnings), spent in a shop
var inventory: Dictionary = {}  # item_id (see ItemData) -> quantity owned
var equipped: Dictionary = {"weapon": "", "armor": ""}  # slot name -> equipped item_id ("" = empty)

const GOLD_PER_TEN_SECONDS_LEFT: int = 1
const GOLD_PER_BOSS_KILL: int = 20
const GOLD_PER_ENEMY_KILL: int = 2

func start_campaign() -> void:
	current_level_index = 0
	is_campaign_active = true
	boss_summoned_history.clear()
	gold = 0
	inventory.clear()
	equipped = {"weapon": "", "armor": ""}
	SaveManager.clear_campaign_progress()

# Resumes a campaign saved by a previous session's progress (see
# advance_to_next_level() below). Returns false (and changes nothing) if
# there's nothing to resume, so callers can fall back to start_campaign().
func resume_campaign() -> bool:
	if not SaveManager.has_campaign_in_progress():
		return false
	current_level_index = SaveManager.saved_campaign_level_index
	boss_summoned_history.assign(SaveManager.saved_campaign_boss_history)
	gold = SaveManager.saved_campaign_gold
	inventory = SaveManager.saved_campaign_inventory.duplicate()
	equipped = SaveManager.saved_campaign_equipped.duplicate()
	if not equipped.has("weapon"):
		equipped["weapon"] = ""
	if not equipped.has("armor"):
		equipped["armor"] = ""
	is_campaign_active = true
	return true

func has_saved_progress() -> bool:
	return SaveManager.has_campaign_in_progress()

func get_current_level() -> Dictionary:
	return CampaignData.LEVELS[current_level_index]

# Picks one of the current level's interchangeable puzzle layouts at
# random (see CampaignData.LEVELS) -- called once when the level starts,
# not re-rolled on every Reset within the same playthrough of it.
func get_current_level_puzzle_rows() -> PackedStringArray:
	var options: Array = CampaignData.LEVELS[current_level_index]["puzzle_rows_options"]
	return options.pick_random()

func get_current_level_number() -> int:
	return current_level_index + 1

func get_total_level_count() -> int:
	return CampaignData.LEVELS.size()

func record_level_result(boss_was_summoned: bool) -> void:
	boss_summoned_history.append(boss_was_summoned)

# Called once, right when a level's puzzle is solved (see
# GameUIManager._update_status()), so the earnings panel shown above the
# Next Level button has something to display before the player even
# presses it. Adds the total to `gold` immediately; persisting that to disk
# still waits for advance_to_next_level() below, same as everything else
# about this level (best time, boss history) -- so, consistent with those,
# gold from a level you quit out of without pressing Next Level is lost.
# Pure calculation (no side effects) -- Endless/multiplayer use this directly
# since their gold isn't part of the campaign save.
func calculate_level_earnings(seconds_remaining: float, boss_killed: bool, enemies_killed: int) -> Dictionary:
	var time_bonus: int = int(seconds_remaining / 10.0) * GOLD_PER_TEN_SECONDS_LEFT
	var boss_bonus: int = GOLD_PER_BOSS_KILL if boss_killed else 0
	var enemy_bonus: int = enemies_killed * GOLD_PER_ENEMY_KILL
	var total: int = time_bonus + boss_bonus + enemy_bonus
	return {
		"time_bonus": time_bonus,
		"boss_bonus": boss_bonus,
		"enemy_bonus": enemy_bonus,
		"enemies_killed": enemies_killed,
		"total": total,
	}

func credit_level_earnings(seconds_remaining: float, boss_killed: bool, enemies_killed: int) -> Dictionary:
	var breakdown: Dictionary = calculate_level_earnings(seconds_remaining, boss_killed, enemies_killed)
	gold += breakdown["total"]
	return breakdown

# Advances to the next level if there is one (returns true). If the current
# level was the last one, marks the campaign complete (unlocking Endless
# Mode) and returns false. Call record_level_result() first so the history
# (and therefore get_cutscene_data()'s decision) already reflects the level
# that was just finished.
func advance_to_next_level() -> bool:
	if current_level_index + 1 < CampaignData.LEVELS.size():
		current_level_index += 1
		_persist_progress()
		return true
	is_campaign_active = false
	SaveManager.mark_campaign_completed()
	return false

# Adds an ItemData item to the inventory (called by Town.gd right after a
# successful purchase, alongside deducting `gold` there). Persists right
# away -- unlike gold earned from a level (which waits for
# advance_to_next_level() to actually write to disk), a Town purchase
# happens *after* that write already occurred for this level, so without
# its own save here, quitting mid-Town would silently lose both the gold
# spent and the item bought.
func add_item(item_id: String, quantity: int = 1) -> void:
	inventory[item_id] = get_item_quantity(item_id) + quantity
	_persist_progress()

func get_item_quantity(item_id: String) -> int:
	return inventory.get(item_id, 0)

# Equips an owned item into whichever slot its ItemData entry names (does
# nothing if the item has no "slot" or isn't owned) -- replaces whatever
# was already in that slot, if anything. Doesn't consume the item from
# `inventory`; equipping just marks which owned copy is "worn", it doesn't
# use it up.
func equip_item(item_id: String) -> void:
	var item: Dictionary = ItemData.get_item(item_id)
	var slot: String = item.get("slot", "")
	if slot == "" or get_item_quantity(item_id) <= 0:
		return
	equipped[slot] = item_id
	_persist_progress()

func unequip_slot(slot: String) -> void:
	equipped[slot] = ""
	_persist_progress()

func get_equipped_item_id(slot: String) -> String:
	return equipped.get(slot, "")

func _persist_progress() -> void:
	SaveManager.save_campaign_progress(current_level_index, boss_summoned_history, gold, inventory, equipped)

# Returns {"title": String, "scene_key": String, "lines": Array[String]}
# for whichever cutscene comes next, purely as a function of how many
# levels have been completed so far (and, for the first two specific
# branches, exactly what happened in them).
func get_cutscene_data() -> Dictionary:
	var levels_completed: int = boss_summoned_history.size()

	if levels_completed == 0:
		return {
			"title": "Chapter One: Life of the Dead",
			"scene_key": "chapter_1_intro",
			"lines": CampaignData.CHAPTER_ONE_INTRO,
		}

	if levels_completed == 1:
		var lines: Array[String] = CampaignData.AFTER_LEVEL_1_BOSS if boss_summoned_history[0] else CampaignData.AFTER_LEVEL_1_CLEAN
		return {"title": "Chapter Two", "scene_key": "after_level_1", "lines": lines}

	if levels_completed == 2:
		return _get_after_level_2_data()

	return _get_general_cutscene_data(levels_completed)

func _get_after_level_2_data() -> Dictionary:
	var level_one_summoned: bool = boss_summoned_history[0]
	var level_two_summoned: bool = boss_summoned_history[1]
	var lines: Array[String]
	if not level_one_summoned and not level_two_summoned:
		lines = CampaignData.AFTER_LEVEL_2_NEVER
	elif level_one_summoned and not level_two_summoned:
		lines = CampaignData.AFTER_LEVEL_2_IMPROVED
	else:
		lines = CampaignData.AFTER_LEVEL_2_STRUGGLED
	return {"title": "Chapter Three", "scene_key": "after_level_2", "lines": lines}

func _get_general_cutscene_data(levels_completed: int) -> Dictionary:
	var path: int = CampaignData.evaluate_boss_path(boss_summoned_history)
	var is_ending: bool = levels_completed >= CampaignData.LEVELS.size()
	if is_ending:
		var ending_lines: Array[String] = Array(CampaignData.ENDING_PLACEHOLDER[path], TYPE_STRING, "", null)
		return {"title": "Epilogue", "scene_key": "ending_%d" % path, "lines": ending_lines}
	var upcoming_level_number: int = levels_completed + 1
	var chapter_title: String = "Chapter %s" % CampaignData.CHAPTER_ORDINALS[upcoming_level_number - 1]
	var path_lines: Array[String] = Array(CampaignData.BOSS_PATH_PLACEHOLDER[path], TYPE_STRING, "", null)
	return {"title": chapter_title, "scene_key": "boss_path_%d" % path, "lines": path_lines}
