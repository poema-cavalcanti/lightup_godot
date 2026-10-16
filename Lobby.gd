extends MenuScreen

# The four screens of the lobby (choice, hosting, joining, connected) are all
# laid out in Lobby.tscn as sibling views; only one is visible at a time. The
# hosting and connected screens also show the four player slots (LobbySlots.gd).
# This script switches between them, fills in the dynamic text, and reacts to
# NetworkManager. Two transports are supported: Steam (when the GodotSteam
# extension is installed and Steam is running) and LAN / direct IP.

enum View { CHOICE, HOST_WAITING, JOIN_ENTRY, CLIENT_WAITING }

const MULTIPLAYER_ROWS: int = 30
const MULTIPLAYER_COLS: int = 30

# The first board of every multiplayer match: always this one (a navigable 30x30 puzzle), so
# Start Game is instant. The later boards are generated in the background while it's played
# (Game._start_pregeneration, handed on to the Town -- see TownNet).
const MULTIPLAYER_STARTING_LEVEL: Array[String] = [
	".2##.....0......0......11..#..",
	".....10......11.#..2#1#......1",
	"#...#.2.1.#....#....##.#.1...#",
	"..........1.0#.#...#.........#",
	"..#.1##.......##..#..#..10....",
	"#...0#.#.#01...2..1..0..###.1.",
	"#.#.....#..#......#.#....#.2#.",
	".1........#####2..1.1#..2.....",
	".##.##.3.2........#...#2.3.3..",
	".#1...1#.....#.#..##.0.......#",
	".#.#.....#....2..2......1.##..",
	"....1##2#0....#.#.....###.....",
	"..........1..#1.#.....1...2...",
	"##.........#...#.#..1.1...#.#.",
	"..###0.#.1...#...#2#..#..2..2.",
	".#..1..1..1###..1...1.#.101#..",
	".0.#...#.#..1.2#..#.........##",
	"...1...1.......#2..0..........",
	".....###.....2.#....##1#1#....",
	"..#2...#....#..2....#.....0.0.",
	"#....#..#.21..#.#.....0#...##.",
	"..0...2#...#........4.#.##.1#.",
	".....1..2#.#..##1###.#......#.",
	".1#.#....#.#......#..#.....#.#",
	".1.2##..#..#..#...01....1#...#",
	"....#1..0..2..##.....2.0##.2..",
	"1.........#...1.#1.#....#.....",
	"0...2.2.#0....#....#.3.#.#...1",
	"1......#00#..#.20......#......",
	"..#..#0......#......#.....1#2."
]
const DEFAULT_JOIN_ADDRESS: String = "127.0.0.1"

var current_view: View = View.CHOICE
var use_steam: bool = false  # true = host/join through Steam; false = LAN / direct IP

@onready var choice_view: Control = %ChoiceView
@onready var host_view: Control = %HostView
@onready var join_view: Control = %JoinView
@onready var client_view: Control = %ClientView

@onready var network_button: Button = %NetworkButton
@onready var choice_status_label: Label = %ChoiceStatusLabel
@onready var address_label: Label = %AddressLabel
@onready var hint_label: Label = %HintLabel
@onready var invite_button: Button = %InviteButton
@onready var slots: LobbySlots = %Slots
@onready var name_input: LineEdit = %NameInput
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

	name_input.max_length = NetworkManager.MAX_NAME_LENGTH
	name_input.text = SettingsManager.player_name if SettingsManager.player_name != "" else NetworkManager.local_player_name()
	name_input.focus_exited.connect(_commit_name)
	name_input.text_submitted.connect(func(_submitted: String) -> void: _commit_name())

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
	slots.visible = view == View.HOST_WAITING or view == View.CLIENT_WAITING
	if slots.visible:
		slots.reset()  # so everyone drops in fresh each time the screen opens

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
			_refresh_slots()
		View.JOIN_ENTRY:
			instruction_label.text = "Steam lobby ID (or accept a friend's invite):" if use_steam else instruction_label_template
			ip_input.text = "" if use_steam else DEFAULT_JOIN_ADDRESS
			ip_input.placeholder_text = "Paste lobby ID" if use_steam else ""
			status_label.text = ""
		View.CLIENT_WAITING:
			_refresh_slots()

# Hands the roster to the slots row: one entry per connected player, in player-index order.
# The names come from the host with the list (NetworkManager.player_names).
func _refresh_slots() -> void:
	var my_peer_id: int = multiplayer.get_unique_id()
	var entries: Array = []
	for player_index in range(NetworkManager.connected_peer_ids.size()):
		var player_name: String = NetworkManager.player_names[player_index] if player_index < NetworkManager.player_names.size() else "Player %d" % (player_index + 1)
		entries.append({
			"name": player_name,
			"is_host": player_index == 0,
			"is_you": NetworkManager.connected_peer_ids[player_index] == my_peer_id,
		})
	slots.set_entries(entries)

# Saves what's in the name box (called when it loses focus / Enter, and right before hosting or joining).
func _commit_name() -> void:
	SettingsManager.set_player_name(NetworkManager.sanitize_name(name_input.text))

# ---------------------------------------------------------------------------
# NetworkManager signal handlers
# ---------------------------------------------------------------------------

func _on_player_list_changed() -> void:
	_refresh_slots()

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
	_commit_name()
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
	_commit_name()
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
	NetworkManager.start_game(PackedStringArray(MULTIPLAYER_STARTING_LEVEL))

func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	_show_view(View.CHOICE)

# Back always means "previous screen": from the Multiplayer menu that's the main
# menu; from Join, Hosting or Connected it's the Multiplayer menu, after leaving
# whatever session or join attempt was open.
func _on_back_pressed() -> void:
	if current_view == View.CHOICE:
		super._on_back_pressed()
	else:
		_on_leave_pressed()
