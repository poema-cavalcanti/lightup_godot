extends MenuScreen

# The static layout lives in Settings.tscn. The size-preset and key-binding
# rows are generated here, because how many there are comes from
# SettingsManager (SIZE_PRESETS / KEY_BINDING_ACTIONS). The scene holds one
# placeholder button in each list so the layout is visible in the editor;
# _ready() swaps those for the real ones.

@onready var fullscreen_button: Button = %FullscreenButton
@onready var size_button_list: VBoxContainer = %SizeButtons
@onready var rebind_button_list: VBoxContainer = %RebindButtons

var size_buttons: Array[Button] = []
var rebind_buttons: Dictionary = {}  # action -> Button
var listening_action: String = ""  # "" when not capturing a key press

func _ready() -> void:
	super._ready()
	_build_dynamic_buttons()
	_refresh_labels()

func _build_dynamic_buttons() -> void:
	# Clone the placeholder in each list as the template, then drop it.
	var size_template: Button = size_button_list.get_child(0)
	var rebind_template: Button = rebind_button_list.get_child(0)

	size_buttons.clear()
	for preset: Vector2i in SettingsManager.SIZE_PRESETS:
		var size_button: Button = size_template.duplicate()
		size_button.pressed.connect(_on_size_selected.bind(preset))
		size_button_list.add_child(size_button)
		size_buttons.append(size_button)

	rebind_buttons.clear()
	for action: String in SettingsManager.KEY_BINDING_ACTIONS:
		var rebind_button: Button = rebind_template.duplicate()
		rebind_button.pressed.connect(_on_rebind_pressed.bind(action))
		rebind_button_list.add_child(rebind_button)
		rebind_buttons[action] = rebind_button

	size_template.queue_free()
	rebind_template.queue_free()

func _refresh_labels() -> void:
	fullscreen_button.text = "Fullscreen: ON" if SettingsManager.is_fullscreen else "Fullscreen: OFF"
	for button_index in range(size_buttons.size()):
		var preset: Vector2i = SettingsManager.SIZE_PRESETS[button_index]
		var label_text: String = "%dx%d" % [preset.x, preset.y]
		if preset == SettingsManager.window_size:
			label_text = "[%s]" % label_text
		size_buttons[button_index].text = label_text
	for action: String in SettingsManager.KEY_BINDING_ACTIONS:
		if action == listening_action:
			rebind_buttons[action].text = "%s: press a key…" % SettingsManager.KEY_BINDING_LABELS[action]
		else:
			rebind_buttons[action].text = "%s: %s" % [SettingsManager.KEY_BINDING_LABELS[action], SettingsManager.get_key_label(action)]

func _on_fullscreen_pressed() -> void:
	SettingsManager.toggle_fullscreen()
	_refresh_labels()

func _on_size_selected(preset: Vector2i) -> void:
	SettingsManager.set_window_size(preset)
	_refresh_labels()

func _on_rebind_pressed(action: String) -> void:
	listening_action = action
	_refresh_labels()

func _on_reset_controls_pressed() -> void:
	SettingsManager.reset_key_bindings_to_default()
	_refresh_labels()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if listening_action != "":
		if event.keycode != KEY_ESCAPE and event.keycode != KEY_F11:
			SettingsManager.set_key_binding(listening_action, event.keycode)
		listening_action = ""
		_refresh_labels()
		return

	if event.keycode == KEY_F11:
		SettingsManager.toggle_fullscreen()
		_refresh_labels()
