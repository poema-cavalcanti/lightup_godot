extends Node

# ---------------------------------------------------------------------------
# Autoload (registered in project.godot, ahead of NetworkManager).
#
# A thin wrapper around the GodotSteam extension: initialises Steam, creates /
# joins / leaves lobbies, and turns Steam's callbacks into plain signals that
# NetworkManager listens to. It owns NO game or networking logic.
#
# Everything touching Steam goes through the `steam` variable, looked up at
# runtime with Engine.get_singleton("Steam") rather than by writing `Steam.`
# directly. That's deliberate: if the GodotSteam extension isn't installed, a
# literal `Steam` identifier would be a parse error and break the whole
# project; this way the game still runs, and the lobby simply offers LAN play.
#
# Written against GodotSteam 4.17.x docs; see STEAM_SETUP.md for what to
# verify first when you test it.
# ---------------------------------------------------------------------------

# 480 is Valve's shared "Spacewar" test app, fine for development. Replace it
# with your real app ID once Steam assigns you one.
const APP_ID: int = 480

# Who can join the lobby:  0 = private (invite only)   1 = friends only
#                          2 = public (don't)          3 = invisible
# Friends-only means only people on the host's Steam friends list can join,
# either from an invite or from "Join Game" in the friends list.
const LOBBY_TYPE: int = 1

# Steam result / enum values used below (so we don't need `Steam.` constants)
const RESULT_OK: int = 1
const ENTER_RESPONSE_SUCCESS: int = 1
const INIT_STATUS_OK: int = 0

const JOIN_FAILURE_MESSAGES: Dictionary = {
	2: "That lobby no longer exists.",
	3: "You don't have permission to join that lobby.",
	4: "That lobby is full.",
	5: "Something unexpected went wrong joining the lobby.",
	6: "You're banned from that lobby.",
	7: "Your Steam account is limited, so it can't join lobbies.",
	8: "That lobby is locked or disabled.",
	9: "That lobby is community locked.",
	10: "A player in that lobby has blocked you.",
	11: "You've blocked a player in that lobby.",
	15: "Too many join attempts. Wait a moment and try again.",
}

signal lobby_created(new_lobby_id: int)
signal lobby_create_failed(reason: String)
signal lobby_entered(entered_lobby_id: int, owner_steam_id: int)
signal lobby_enter_failed(reason: String)

var available: bool = false     # the GodotSteam extension is installed
var initialized: bool = false   # ...and Steam is running and initialised OK
var init_error: String = ""
var steam: Variant = null
var my_steam_id: int = 0
var lobby_id: int = 0           # the lobby we're currently in (0 = none)

# Set when a friend's invite / "Join Game" arrives (or the game was launched
# from one). Lobby.gd picks it up on load and starts the join.
var pending_join_lobby_id: int = 0

func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		init_error = "The GodotSteam extension isn't installed."
		return
	available = true
	steam = Engine.get_singleton("Steam")

	# Second argument = let GodotSteam run Steam's callbacks itself every
	# frame, so we don't need our own _process().
	var init_result: Dictionary = steam.steamInitEx(APP_ID, true)
	if int(init_result.get("status", 1)) != INIT_STATUS_OK:
		init_error = str(init_result.get("verbal", "Steam didn't start. Is the Steam client running and logged in?"))
		push_warning("Steam init failed: %s" % init_error)
		return

	initialized = true
	my_steam_id = int(steam.getSteamID())
	steam.lobby_created.connect(_on_lobby_created)
	steam.lobby_joined.connect(_on_lobby_joined)
	steam.join_requested.connect(_on_join_requested)
	call_deferred("_check_command_line")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave_lobby()

# --- Public API -------------------------------------------------------------

func create_lobby(max_members: int) -> bool:
	if not initialized:
		return false
	steam.createLobby(LOBBY_TYPE, max_members)
	return true

func join_lobby(target_lobby_id: int) -> bool:
	if not initialized or target_lobby_id <= 0:
		return false
	steam.joinLobby(target_lobby_id)
	return true

func leave_lobby() -> void:
	if initialized and lobby_id != 0:
		steam.leaveLobby(lobby_id)
	lobby_id = 0

# Stops anyone new from joining (called when the match starts).
func set_lobby_joinable(joinable: bool) -> void:
	if initialized and lobby_id != 0:
		steam.setLobbyJoinable(lobby_id, joinable)

# True if this Steam ID is currently a member of our lobby.
func is_lobby_member(member_steam_id: int) -> bool:
	if not initialized or lobby_id == 0:
		return false
	var member_count: int = int(steam.getNumLobbyMembers(lobby_id))
	for member_index in range(member_count):
		if int(steam.getLobbyMemberByIndex(lobby_id, member_index)) == member_steam_id:
			return true
	return false

# Opens the Steam overlay's "invite friends" dialog for the current lobby.
func invite_friends() -> void:
	if initialized and lobby_id != 0:
		steam.activateGameOverlayInviteDialog(lobby_id)

# --- Steam callbacks --------------------------------------------------------

func _on_lobby_created(connect_status: int, new_lobby_id: int) -> void:
	if connect_status != RESULT_OK:
		lobby_create_failed.emit("Steam couldn't create a lobby (code %d)." % connect_status)
		return
	lobby_id = new_lobby_id
	lobby_created.emit(new_lobby_id)

# Fires for BOTH joiners and the host (the host auto-joins the lobby it just
# created); NetworkManager tells them apart by comparing the lobby owner to
# our own Steam ID.
func _on_lobby_joined(joined_lobby_id: int, _permissions: Variant, _locked: Variant, response: int) -> void:
	if response != ENTER_RESPONSE_SUCCESS:
		lobby_id = 0
		lobby_enter_failed.emit(str(JOIN_FAILURE_MESSAGES.get(response, "Couldn't join the lobby (code %d)." % response)))
		return
	lobby_id = joined_lobby_id
	lobby_entered.emit(joined_lobby_id, int(steam.getLobbyOwner(joined_lobby_id)))

# A friend invited us / we clicked "Join Game" while the game is running.
func _on_join_requested(requested_lobby_id: int, _friend_id: int) -> void:
	_request_join(requested_lobby_id)

# The game was launched by an invite: Steam adds "+connect_lobby <id>".
func _check_command_line() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	var flag_index: int = args.find("+connect_lobby")
	if flag_index == -1 or flag_index + 1 >= args.size():
		return
	var requested_lobby_id: int = int(args[flag_index + 1])
	if requested_lobby_id > 0:
		_request_join(requested_lobby_id)

func _request_join(requested_lobby_id: int) -> void:
	if NetworkManager.is_multiplayer or NetworkManager.match_in_progress:
		push_warning("Ignoring a Steam join request: already in a multiplayer session.")
		return
	pending_join_lobby_id = requested_lobby_id
	get_tree().change_scene_to_file(Constants.SCENE_LOBBY)
