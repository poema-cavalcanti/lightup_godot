extends MenuScreen

# The layout lives in MainMenu.tscn. This script only applies the parts that
# depend on saved progress (Continue vs. new Campaign, Endless Mode lock) and
# handles the button presses (wired up in the scene's Node > Signals tab).

@onready var campaign_button: Button = %CampaignButton
@onready var new_campaign_button: Button = %NewCampaignButton
@onready var endless_mode_button: Button = %EndlessModeButton
@onready var lock_note_label: Label = %LockNoteLabel

func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("Light Up Puzzle")

	var can_resume_campaign: bool = CampaignManager.has_saved_progress()
	campaign_button.text = "Continue Campaign" if can_resume_campaign else "Campaign"
	new_campaign_button.visible = can_resume_campaign

	var endless_mode_unlocked: bool = SaveManager.has_completed_campaign
	endless_mode_button.disabled = not endless_mode_unlocked
	lock_note_label.visible = not endless_mode_unlocked

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://Settings.tscn")

func _on_campaign_pressed() -> void:
	NetworkManager.is_multiplayer = false
	if not CampaignManager.resume_campaign():
		CampaignManager.start_campaign()
	get_tree().change_scene_to_file("res://Cutscene.tscn")

func _on_new_campaign_pressed() -> void:
	NetworkManager.is_multiplayer = false
	CampaignManager.start_campaign()
	get_tree().change_scene_to_file("res://Cutscene.tscn")

func _on_endless_mode_pressed() -> void:
	if not SaveManager.has_completed_campaign:
		return  # defensive -- the button is disabled in this case anyway
	NetworkManager.is_multiplayer = false
	CampaignManager.is_campaign_active = false
	get_tree().change_scene_to_file("res://Game.tscn")

func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file("res://Lobby.tscn")

func _on_how_to_play_pressed() -> void:
	get_tree().change_scene_to_file("res://HowToPlay.tscn")

func _on_stats_pressed() -> void:
	get_tree().change_scene_to_file("res://Stats.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
