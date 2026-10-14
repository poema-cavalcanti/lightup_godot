extends MenuScreen

# ---------------------------------------------------------------------------
# Full-window cutscene: a "Stage" fills the whole screen, with the chapter
# title overlaid top-left and a slim dialog bar along the bottom showing one
# line at a time, advanced with a Continue button (or Enter/Space).
#
# What fills the Stage, for a given scene_key:
#   1. res://cutscenes/<scene_key>.tscn if it exists -- a hand-built scene
#      animated with its own AnimationPlayer (see CutsceneStage.gd for how to
#      author one). Cutscene.gd calls its play_line() each time a line shows.
#   2. otherwise res://assets/cutscenes/<scene_key>.png as a static picture,
#   3. otherwise just the plain background color.
#
# The layout (stage, title, dialog bar, button) lives in Cutscene.tscn.
# Content comes entirely from CampaignManager.get_cutscene_data() -- this
# script has no narrative logic of its own, it just presents whatever
# {"title", "scene_key", "lines"} it's handed. When the lines run out,
# Continue either starts the next level (if the campaign is still active)
# or returns to the Main Menu (if that was the ending).
# ---------------------------------------------------------------------------

const ASSET_DIRECTORY: String = "res://assets/cutscenes/"
const STAGE_DIRECTORY: String = "res://cutscenes/"

var lines: Array[String] = []
var current_line_index: int = 0
var stage_scene: CutsceneStage = null  # null when this cutscene has no scene of its own

@onready var stage: Control = %Stage
@onready var scene_image: TextureRect = %SceneImage
@onready var scene_title_label: Label = %SceneTitleLabel
@onready var dialog_label: Label = %DialogLabel
@onready var continue_button: Button = %ContinueButton

func _ready() -> void:
	super._ready()

	var cutscene_data: Dictionary = CampaignManager.get_cutscene_data()
	lines = cutscene_data["lines"]
	var scene_key: String = cutscene_data["scene_key"]
	var scene_title: String = cutscene_data["title"]
	current_line_index = 0

	if scene_key.begins_with("ending_"):
		SaveManager.record_ending_seen(int(scene_key.trim_prefix("ending_")))

	_load_stage(scene_key)

	scene_title_label.text = scene_title
	scene_title_label.visible = scene_title != ""

	_refresh_dialog()
	_play_stage_line()

# Fills the Stage for this cutscene (see the header comment for the order).
func _load_stage(scene_key: String) -> void:
	var stage_path: String = STAGE_DIRECTORY + scene_key + ".tscn"
	if ResourceLoader.exists(stage_path):
		scene_image.texture = null
		var stage_node: Node = (load(stage_path) as PackedScene).instantiate()
		stage.add_child(stage_node)
		if stage_node is Control:
			(stage_node as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stage_scene = stage_node as CutsceneStage
		return
	# Optional art: with no matching file the image stays empty and the plain
	# background behind it shows through.
	scene_image.texture = AssetLoader.load_optional_texture(ASSET_DIRECTORY + scene_key + ".png")

# Tells the stage scene (if any) which dialogue line is now showing, so its
# AnimationPlayer can play that line's beat.
func _play_stage_line() -> void:
	if stage_scene != null:
		stage_scene.play_line(current_line_index)

func _refresh_dialog() -> void:
	dialog_label.text = lines[current_line_index]
	if current_line_index == lines.size() - 1:
		continue_button.text = "Start Level" if CampaignManager.is_campaign_active else "Return to Main Menu"
	else:
		continue_button.text = "Continue"

func _on_continue_pressed() -> void:
	current_line_index += 1
	if current_line_index >= lines.size():
		_finish_cutscene()
	else:
		_refresh_dialog()
		_play_stage_line()

func _finish_cutscene() -> void:
	if CampaignManager.is_campaign_active:
		get_tree().change_scene_to_file("res://Game.tscn")
	else:
		get_tree().change_scene_to_file("res://MainMenu.tscn")

func _input(event: InputEvent) -> void:
	super._input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_on_continue_pressed()
