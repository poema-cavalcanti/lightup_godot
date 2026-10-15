extends Node

# ---------------------------------------------------------------------------
# Autoload (registered in project.godot). Persists across scene changes, so
# it's the natural home for connection state and for handing puzzle/spawn
# data from the Lobby across the transition into Game.tscn.
#
# Model: client-server via Godot's high-level ENet multiplayer API. The host
# is always peer id 1. connected_peer_ids[i] == the peer id of player i, and
# is mirrored identically to every peer (host is the single source of truth,
# broadcasting the canonical list on every join/leave) so nobody has to
# infer indices independently.
#
# Two transports share that model: ENet (LAN / direct IP -- handy for local
# testing) and Steam (SteamMultiplayerPeer via the GodotSteam extension, which
# connects through Steam so nobody types or shares an IP address). Everything
# above the transport -- RPCs, the roster, request validation -- is identical.
# ---------------------------------------------------------------------------

const PORT: int = 8910
const MAX_PLAYERS: int = 4

signal player_list_changed
signal connected_ok
signal connection_failed_signal
signal kicked_from_server
signal steam_host_ready
signal steam_host_failed(reason: String)
signal steam_join_failed(reason: String)

# How long a Steam client may sit in "connecting" before we give up.
const STEAM_JOIN_TIMEOUT_SEC: float = 15.0

# True while the current session runs over Steam rather than ENet.
var using_steam: bool = false
var _steam_signals_connected: bool = false

var is_multiplayer: bool = false
var is_host: bool = false

var connected_peer_ids: Array = []

# True from the moment the host starts a match until the session ends.
# While set, the host refuses new connections (the players array is fixed at
# match start, so a late joiner would have no valid player index).
var match_in_progress: bool = false

# Host-side request throttling: "<peer_id>:<action>" -> last accepted time (ms).
var _last_request_msec: Dictionary = {}

# Set by _begin_game() right before the scene change; Game.gd's _ready()
# reads these immediately after.
var pending_puzzle_rows: PackedStringArray = []
var pending_start_positions: Array = []
var pending_peer_order: Array = []

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- Hosting / joining -------------------------------------------------

func host_game() -> bool:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var connection_error: int = peer.create_server(PORT, MAX_PLAYERS - 1)
	if connection_error != OK:
		return false
	multiplayer.multiplayer_peer = peer
	using_steam = false
	is_multiplayer = true
	is_host = true
	connected_peer_ids = [1]  # host is always peer id 1 -> player_index 0
	player_list_changed.emit()
	return true

func join_game(ip_address: String) -> bool:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var connection_error: int = peer.create_client(ip_address, PORT)
	if connection_error != OK:
		return false
	multiplayer.multiplayer_peer = peer
	using_steam = false
	is_multiplayer = true
	is_host = false
	return true

func leave_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	SteamBridge.leave_lobby()
	using_steam = false
	is_multiplayer = false
	is_host = false
	match_in_progress = false
	SessionEconomy.carry = false
	_last_request_msec.clear()
	connected_peer_ids.clear()

func local_ip_hint() -> String:
	for local_address: String in IP.get_local_addresses():
		if local_address.begins_with("192.") or local_address.begins_with("10.") or local_address.begins_with("172."):
			return local_address
	return "(couldn't auto-detect a LAN address -- check your OS network settings)"

# --- Connection lifecycle -----------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	if is_host:
		if match_in_progress:
			# Mid-match joins aren't supported (fixed player slots), so don't
			# let strangers sit connected to a running game.
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)
			return
		if connected_peer_ids.size() >= MAX_PLAYERS:
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)
			return  # ENet's max_clients should already prevent this
		connected_peer_ids.append(peer_id)
		rpc("_update_player_list", connected_peer_ids)
		if using_steam:
			_verify_steam_peer(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if is_host:
		connected_peer_ids.erase(peer_id)
		for key: String in _last_request_msec.keys():
			if key.begins_with("%d:" % peer_id):
				_last_request_msec.erase(key)
		rpc("_update_player_list", connected_peer_ids)

func _on_connected_to_server() -> void:
	connected_ok.emit()

func _on_connection_failed() -> void:
	if using_steam:
		leave_game()
	is_multiplayer = false
	connection_failed_signal.emit()

func _on_server_disconnected() -> void:
	SteamBridge.leave_lobby()
	using_steam = false
	is_multiplayer = false
	is_host = false
	match_in_progress = false
	connected_peer_ids.clear()
	kicked_from_server.emit()

@rpc("authority", "call_local", "reliable")
func _update_player_list(peer_ids: Array) -> void:
	connected_peer_ids = peer_ids
	player_list_changed.emit()

# --- Steam transport -----------------------------------------------------
# Flow (per the GodotSteam lobby + MultiplayerPeer tutorials):
#   host:   create lobby -> on lobby_created, create the host peer
#   joiner: join lobby   -> on lobby_joined, create a client peer aimed at the
#           lobby owner's Steam ID
# The host also receives lobby_joined for its own lobby; we skip that one.

func steam_available() -> bool:
	return SteamBridge.initialized and ClassDB.class_exists("SteamMultiplayerPeer")

func _ensure_steam_signals() -> void:
	if _steam_signals_connected:
		return
	_steam_signals_connected = true
	SteamBridge.lobby_created.connect(_on_steam_lobby_created)
	SteamBridge.lobby_create_failed.connect(_on_steam_lobby_create_failed)
	SteamBridge.lobby_entered.connect(_on_steam_lobby_entered)
	SteamBridge.lobby_enter_failed.connect(_on_steam_lobby_enter_failed)

# Asks Steam for a lobby; the result arrives via steam_host_ready /
# steam_host_failed. Returns false if the request couldn't even be sent.
func host_steam_game() -> bool:
	if not steam_available():
		return false
	_ensure_steam_signals()
	leave_game()  # clear out any leftover session first
	using_steam = true
	return SteamBridge.create_lobby(MAX_PLAYERS)

# Asks Steam to join a lobby; success continues in _on_steam_lobby_entered.
func join_steam_lobby(target_lobby_id: int) -> bool:
	if not steam_available():
		return false
	_ensure_steam_signals()
	leave_game()
	using_steam = true
	return SteamBridge.join_lobby(target_lobby_id)

func _new_steam_peer() -> Variant:
	var peer: Variant = ClassDB.instantiate("SteamMultiplayerPeer")
	# Route client-to-client traffic through the host, like ENet's topology.
	# (Only set if this peer exposes the property; it's the default otherwise.)
	if peer != null and "server_relay" in peer:
		peer.server_relay = true
	return peer

func _on_steam_lobby_created(_new_lobby_id: int) -> void:
	if not using_steam:
		return
	var peer: Variant = _new_steam_peer()
	var create_error: int = peer.create_host(0)
	if create_error != OK:
		leave_game()
		steam_host_failed.emit("Couldn't start the Steam host (error %d)." % create_error)
		return
	multiplayer.multiplayer_peer = peer
	is_multiplayer = true
	is_host = true
	connected_peer_ids = [1]  # host is always peer id 1 -> player_index 0
	player_list_changed.emit()
	steam_host_ready.emit()

func _on_steam_lobby_create_failed(reason: String) -> void:
	if not using_steam:
		return
	using_steam = false
	steam_host_failed.emit(reason)

func _on_steam_lobby_entered(_entered_lobby_id: int, owner_steam_id: int) -> void:
	if not using_steam or is_multiplayer:
		return  # not a Steam session, or we already have a peer (e.g. we're the host)
	if owner_steam_id == SteamBridge.my_steam_id:
		return  # we own this lobby; the host peer is created in _on_steam_lobby_created
	var peer: Variant = _new_steam_peer()
	var create_error: int = peer.create_client(owner_steam_id, 0)
	if create_error != OK:
		leave_game()
		steam_join_failed.emit("Couldn't connect to the host through Steam (error %d)." % create_error)
		return
	multiplayer.multiplayer_peer = peer
	is_multiplayer = true
	is_host = false
	_watch_steam_connection()

func _on_steam_lobby_enter_failed(reason: String) -> void:
	if not using_steam:
		return
	using_steam = false
	steam_join_failed.emit(reason)

# The lobby is friends-only, but a Steam connection itself is addressed by Steam
# ID, so make sure every connected peer really is a member of OUR lobby and
# drop anyone who isn't. Needs the peer to expose get_steam64_from_peer_id();
# if it doesn't, we can't check and say so (see STEAM_SETUP.md).
func _verify_steam_peer(peer_id: int) -> void:
	var steam_peer: Variant = multiplayer.multiplayer_peer
	if steam_peer == null or not steam_peer.has_method("get_steam64_from_peer_id"):
		push_warning("Can't verify Steam peer %d: peer has no get_steam64_from_peer_id()." % peer_id)
		return
	var peer_steam_id: int = int(steam_peer.get_steam64_from_peer_id(peer_id))
	# Membership can lag the connection by a moment, so allow a few re-checks.
	for _attempt in range(4):
		if SteamBridge.is_lobby_member(peer_steam_id):
			return
		await get_tree().create_timer(0.5).timeout
		if not using_steam or not is_host or not multiplayer.get_peers().has(peer_id):
			return  # session ended or that peer already left
	push_warning("Dropping peer %d: not a member of our Steam lobby." % peer_id)
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)

# If the host never answers, don't leave the joiner staring at "Connecting...".
func _watch_steam_connection() -> void:
	await get_tree().create_timer(STEAM_JOIN_TIMEOUT_SEC).timeout
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if using_steam and not is_host and peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		leave_game()
		connection_failed_signal.emit()

# --- Host-side request validation -----------------------------------------
# Every any_peer RPC carries a client-supplied player_index. Never trust it:
# check it against the peer that actually sent the packet, and throttle it.

# Returns true if the request should be processed. Call at the top of every
# "_request_*" handler, on the host.
#   player_index  -- the index the caller claims to be acting as
#   player_count  -- size of game.players
#   action        -- short key for throttling ("move", "bulb", ...)
#   min_interval  -- minimum seconds between accepted requests of this action
func validate_request(player_index: int, player_count: int, action: String, min_interval: float) -> bool:
	if player_index < 0 or player_index >= player_count:
		return false
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		return true  # direct local call (host's own input, or single-player)
	if player_roster().find(sender) != player_index:
		return false  # peer is trying to act as someone else
	return rate_limit_ok(sender, action, min_interval)

# Player index -> peer id. During a match this is the order frozen at start
# (pending_peer_order, which is also what each client uses for its own
# my_player_index), NOT the live connected list: that list shifts when
# someone disconnects mid-match, which would otherwise remap everyone.
func player_roster() -> Array:
	return pending_peer_order if match_in_progress else connected_peer_ids

func rate_limit_ok(peer_id: int, action: String, min_interval: float) -> bool:
	var key: String = "%d:%s" % [peer_id, action]
	var now_msec: int = Time.get_ticks_msec()
	var last_msec: int = _last_request_msec.get(key, -1000000)
	if now_msec - last_msec < int(min_interval * 1000.0):
		return false
	_last_request_msec[key] = now_msec
	return true

# --- Starting the match ---------------------------------------------------

# Host only. Generates the puzzle, works out everyone's starting corner,
# and tells every peer (itself included, via call_local) to load Game.tscn.
func start_game(rows: int, cols: int, density: float) -> void:
	if not is_host:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var generation_result: Dictionary = LightUpGenerator.generate(rows, cols, density, rng)
	var puzzle_rows: PackedStringArray
	if generation_result["success"]:
		puzzle_rows = generation_result["rows"]
	else:
		# exceedingly unlikely given how reliably the generator succeeds in
		# testing, but fail safe rather than leave everyone hanging
		puzzle_rows = PackedStringArray()
		for row in range(rows):
			puzzle_rows.append(".".repeat(cols))

	var start_positions: Array = BoardUtil.corner_positions(puzzle_rows, connected_peer_ids.size())
	match_in_progress = true
	if using_steam:
		SteamBridge.set_lobby_joinable(false)  # nobody new can join a running match
	rpc("_begin_game", puzzle_rows, start_positions, connected_peer_ids, false)

@rpc("authority", "call_local", "reliable")
# keep_economy: true when coming back from the Town between levels (the match's gold/items carry on,
# see SessionEconomy.gd); false for a fresh match from the lobby.
func _begin_game(puzzle_rows: PackedStringArray, start_positions: Array, peer_order: Array, keep_economy: bool) -> void:
	SessionEconomy.carry = keep_economy
	pending_puzzle_rows = puzzle_rows
	pending_start_positions = start_positions
	pending_peer_order = peer_order
	get_tree().change_scene_to_file(Constants.SCENE_GAME)
