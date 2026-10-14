extends MenuScreen

# The four screens of the lobby (choice, hosting, joining, connected) are all
# laid out in Lobby.tscn as sibling views; only one is visible at a time.
# This script switches between them, fills in the dynamic text, and reacts to
# NetworkManager. Two transports are supported: Steam (when the GodotSteam
# extension is installed and Steam is running) and LAN / direct IP.

enum View { CHOICE, HOST_WAITING, JOIN_ENTRY, CLIENT_WAITING }

const MULTIPLAYER_ROWS: int = 30
const MULTIPLAYER_COLS: int = 30
const DEFAULT_JOIN_ADDRESS: String = "127.0.0.1"

var current_view: View = View.CHOICE
var use_steam: bool = false  # true = host/join through Steam; false = LAN / direct IP

@onready var back_button: Button = %BackButton
@onready var choice_view: Control = %ChoiceView
@onready var host_view: Control = %HostView
@onready var join_view: Control = %JoinView
@onready var client_view: Control = %ClientView

@onready var network_button: Button = %NetworkButton
@onready var choice_status_label: Label = %ChoiceStatusLabel
@onready var address_label: Label = %AddressLabel
@onready var hint_label: Label = %HintLabel
@onready var invite_button: Button = %InviteButton
@onready var host_player_list_label: Label = %HostPlayerListLabel
@onready var client_player_list_label: Label = %ClientPlayerListLabel
@onready var instruction_label: Label = %InstructionLabel
@onready var ip_input: LineEdit = %IpInput
@onready var status_label: Label = %StatusLabel  # the Join screen's status line

# The LAN text of these labels lives in the scene ({ip}/{port} placeholders in
# the address); keep the originals so they can be restored/re-filled each time
# a screen opens, since the Steam variants replace them.
var address_label_template: String
var hint_label_template: String
var instruction_label_template: String

func _ready() -> void:
	super._ready()
	address_label_template = address_label.text
	hint_label_template = hint_label.text
	instruction_label_template = instruction_label.text

	NetworkManager.player_list_changed.connect(_on_player_list_changed)
	NetworkManager.connected_ok.connect(_on_connected_ok)
	NetworkManager.connection_failed_signal.connect(_on_connection_failed)
	NetworkManager.kicked_from_server.connect(_on_kicked)
	NetworkManager.steam_host_ready.connect(_on_steam_host_ready)
	NetworkManager.steam_host_failed.connect(_on_steam_host_failed)
	NetworkManager.steam_join_failed.connect(_on_steam_join_failed)

	use_steam = NetworkManager.steam_available()
	_show_view(View.CHOICE)

	# A friend's invite / "Join Game" brought us here: join straight away.
	if SteamBridge.pending_join_lobby_id > 0:
		var invited_lobby_id: int = SteamBridge.pending_join_lobby_id
		SteamBridge.pending_join_lobby_id = 0
		use_steam = true
		_show_view(View.JOIN_ENTRY)
		status_label.text = "Joining through Steam..."
		if not NetworkManager.join_steam_lobby(invited_lobby_id):
			status_label.text = "Couldn't start the Steam join. Is Steam running?"

# ---------------------------------------------------------------------------
# View switching
# ---------------------------------------------------------------------------

func _show_view(view: View) -> void:
	current_view = view
	choice_view.visible = view == View.CHOICE
	host_view.visible = view == View.HOST_WAITING
	join_view.visible = view == View.JOIN_ENTRY
	client_view.visible = view == View.CLIENT_WAITING
	# Only the choice and join screens have a Back button; while hosting or
	# connected, the Cancel/Leave buttons do that job (they leave the game).
	back_button.visible = view == View.CHOICE or view == View.JOIN_ENTRY

	match view:
		View.CHOICE:
			network_button.text = "Network: Steam" if use_steam else "Network: LAN / direct IP"
			network_button.disabled = not NetworkManager.steam_available()
			if NetworkManager.steam_available():
				choice_status_label.text = ""
			else:
				choice_status_label.text = "Steam isn't available (%s)\nUsing LAN / direct IP." % SteamBridge.init_error
		View.HOST_WAITING:
			if use_steam:
				address_label.text = "Hosting through Steam (friends only).\nLobby ID: %d" % SteamBridge.lobby_id
				hint_label.text = "Click Invite Friends, or right-click a friend in Steam and choose Join Game."
			else:
				address_label.text = address_label_template.format({"ip": NetworkManager.local_ip_hint(), "port": NetworkManager.PORT})
				hint_label.text = hint_label_template
			invite_button.visible = use_steam
			_refresh_player_list_labels()
		View.JOIN_ENTRY:
			instruction_label.text = "Steam lobby ID (or accept a friend's invite):" if use_steam else instruction_label_template
			ip_input.text = "" if use_steam else DEFAULT_JOIN_ADDRESS
			ip_input.placeholder_text = "Paste lobby ID" if use_steam else ""
			status_label.text = ""
		View.CLIENT_WAITING:
			_refresh_player_list_labels()

func _refresh_player_list_labels() -> void:
	var player_lines: Array = []
	for player_index in range(NetworkManager.connected_peer_ids.size()):
		var host_tag_suffix: String = " (Host)" if player_index == 0 else ""
		var you_suffix: String = "  <- you" if NetworkManager.connected_peer_ids[player_index] == multiplayer.get_unique_id() else ""
		player_lines.append("Player %d%s%s" % [player_index + 1, host_tag_suffix, you_suffix])
	var list_text: String = "Connected (%d/%d):\n%s" % [
		NetworkManager.connected_peer_ids.size(), NetworkManager.MAX_PLAYERS, "\n".join(player_lines)
	]
	host_player_list_label.text = list_text
	client_player_list_label.text = list_text

# ---------------------------------------------------------------------------
# NetworkManager signal handlers
# ---------------------------------------------------------------------------

func _on_player_list_changed() -> void:
	_refresh_player_list_labels()

func _on_connected_ok() -> void:
	if current_view == View.JOIN_ENTRY:
		_show_view(View.CLIENT_WAITING)

func _on_connection_failed() -> void:
	_show_view(View.JOIN_ENTRY)
	if use_steam:
		status_label.text = "Couldn't connect through Steam. Make sure the host is still in the lobby and try again."
	else:
		status_label.text = "Connection failed. Double-check the address, and that the host has clicked \"Host Game\"."

func _on_kicked() -> void:
	_show_view(View.CHOICE)

func _on_steam_host_ready() -> void:
	_show_view(View.HOST_WAITING)

func _on_steam_host_failed(reason: String) -> void:
	_show_view(View.CHOICE)
	choice_status_label.text = reason

func _on_steam_join_failed(reason: String) -> void:
	_show_view(View.JOIN_ENTRY)
	status_label.text = reason

# ---------------------------------------------------------------------------
# Button handlers (connected in Lobby.tscn)
# ---------------------------------------------------------------------------

func _on_host_pressed() -> void:
	if use_steam:
		# The result arrives via steam_host_ready / steam_host_failed.
		choice_status_label.text = "Creating Steam lobby..."
		if not NetworkManager.host_steam_game():
			choice_status_label.text = "Couldn't start a Steam lobby. Is Steam running?"
		return
	if NetworkManager.host_game():
		_show_view(View.HOST_WAITING)
	else:
		_show_view(View.CHOICE)

func _on_network_toggle_pressed() -> void:
	use_steam = not use_steam
	_show_view(View.CHOICE)

func _on_invite_pressed() -> void:
	SteamBridge.invite_friends()

func _on_join_pressed() -> void:
	_show_view(View.JOIN_ENTRY)

func _on_connect_pressed() -> void:
	if use_steam:
		var typed_lobby_id: int = ip_input.text.strip_edges().to_int()
		if typed_lobby_id <= 0:
			status_label.text = "Enter a valid lobby ID, or accept an invite from a friend."
			return
		status_label.text = "Joining through Steam..."
		if not NetworkManager.join_steam_lobby(typed_lobby_id):
			status_label.text = "Couldn't start the Steam join. Is Steam running?"
		return
	var ip_address: String = ip_input.text.strip_edges()
	if ip_address == "":
		ip_address = DEFAULT_JOIN_ADDRESS
	status_label.text = "Connecting..."
	if not NetworkManager.join_game(ip_address):
		status_label.text = "Couldn't start connecting -- check the address and try again."
	# view transitions on the connected_ok / connection_failed_signal callbacks above

func _on_start_pressed() -> void:
	NetworkManager.start_game(MULTIPLAYER_ROWS, MULTIPLAYER_COLS, Constants.GENERATOR_DENSITY)

func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	_show_view(View.CHOICE)

# Overrides MenuScreen's default: don't leave a half-open session or Steam
# lobby behind when backing out to the main menu.
func _on_back_pressed() -> void:
	NetworkManager.leave_game()
	super._on_back_pressed()
