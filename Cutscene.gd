extends MenuScreen

# ---------------------------------------------------------------------------
# Split-view cutscene: a "scene" panel on top (optionally showing art from
# res://assets/cutscenes/<scene_key>.png, falling back to a plain colored
# panel with the chapter title) and a dialog box on the bottom showing one
# line at a time, advanced with a Continue button (or Enter/Space).
#
# The layout (panels, colors, label and button positions) lives in
# Cutscene.tscn. Content comes entirely from CampaignManager.get_cutscene_data()
# -- this script has no narrative logic of its own, it just presents whatever
# {"title", "scene_key", "lines"} it's handed. When the lines run out,
# Continue either starts the next level (if the campaign is still active)
# or returns to the Main Menu (if that was the ending).
# ---------------------------------------------------------------------------

const ASSET_DIRECTORY: String = "res://assets/cutscenes/"

var lines: Array[String] = []
var current_line_index: int = 0

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

	# Optional art: with no matching file the image stays empty and the
	# plain background panel behind it shows through.
	scene_image.texture = AssetLoader.load_optional_texture(ASSET_DIRECTORY + scene_key + ".png")

	scene_title_label.text = scene_title
	scene_title_label.visible = scene_title != ""

	_refresh_dialog()

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
