extends Control

# ---------------------------------------------------------------------------
# The post-level summary panel ("Congratulations, you lit the area!" with the
# earnings breakdown). Its layout and art live in EarningsPanel.tscn, which
# HUD.tscn instances inside its solve screen -- a container there centers it
# with the Next Level / Continue button under it, so nothing positions it from
# code. This script only fills in the numbers.
#
# Shown/hidden by GameUIManager._update_status() alongside that button;
# populate() is called once per level, right when it's solved (singleplayer
# campaign: from _update_status(); Endless / multiplayer: from
# Game._show_solve_summary(), on every peer).
# ---------------------------------------------------------------------------

@onready var time_value: Label = %TimeValue
@onready var enemy_label: Label = %EnemyLabel  # text includes the kill count, e.g. "Enemies Killed x3"
@onready var enemy_value: Label = %EnemyValue
@onready var boss_label: Label = %BossLabel  # this row is hidden when no boss was killed this level
@onready var boss_value: Label = %BossValue
@onready var total_value: Label = %TotalValue

# breakdown is what CampaignManager.credit_level_earnings() /
# calculate_level_earnings() returned.
func populate(breakdown: Dictionary) -> void:
	time_value.text = "+%d gold" % breakdown["time_bonus"]

	var enemies_killed: int = breakdown["enemies_killed"]
	enemy_label.text = "Enemies Killed x%d" % enemies_killed if enemies_killed > 0 else "Enemies Killed"
	enemy_value.text = "+%d gold" % breakdown["enemy_bonus"]

	var boss_bonus: int = breakdown["boss_bonus"]
	boss_label.visible = boss_bonus > 0
	boss_value.visible = boss_bonus > 0
	if boss_bonus > 0:
		boss_value.text = "+%d gold" % boss_bonus

	total_value.text = "+%d gold" % breakdown["total"]
