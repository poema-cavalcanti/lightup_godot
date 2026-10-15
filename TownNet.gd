extends RefCounted

# ---------------------------------------------------------------------------
# The shared multiplayer Town (Town.tscn when NetworkManager.is_multiplayer).
# Town.gd keeps the campaign's single-player behavior untouched and hands
# everything multiplayer to this manager; Town.gd also holds the thin @rpc
# wrappers (RPCs must live on the node), exactly like Game.gd does for its
# managers.
#
# THE RULES
#   - Everyone walks the same town. The host is authoritative: a client asks to
#     step (_request_move), the host validates and broadcasts the result
#     (_sync_move), applied on every peer -- the same shape as the levels.
#   - Players can fight here (unlike in the puzzles). A hit is resolved on the
#     host (_request_attack -> _sync_hit); a player who is "killed" is simply
#     put back at the spawn tile at full health at once. Nothing is permanent.
#   - Saying Yes at a shop door hides the player: invisible to everyone and
#     impossible to hit (the host ignores hidden players as targets) until
#     they close the shop, which puts them back on the tile below the door.
#   - Walking off either end of the road "leaves" town. When every connected
#     player has left, the host starts the next board and everyone goes back
#     into Game.tscn together (NetworkManager._begin_game).
#   - Gold, items and gear are the match's SessionEconomy; shopping and the
#     inventory reuse ShopManager / LoadoutManager through the Town node, which
#     exposes the same fields those managers read from Game.
#
# Town positions are not in any save file and need no persistence: everyone
# starts at the same spawn tile, so only a late loader needs a snapshot
# (_town_ready -> _town_full_sync), mirroring Game's _client_ready.
# ---------------------------------------------------------------------------

const MAX_HEALTH: int = 100
const ATTACK_DAMAGE: int = 10  # per hit, before the victim's armor
const ATTACK_COOLDOWN: float = 0.4
const MOVE_MIN_INTERVAL: float = 0.06
const REQUEST_TIMEOUT: float = 0.3  # how long the local player waits for the host's answer to a step before trying again
const HEALTH_BAR_SIZE: Vector2 = Vector2(36, 5)

var town: Node2D
var pending_timer: float = 0.0
var job: GenerationJob = null
var transitioning: bool = false
var waiting_label: Label = null
var loading_popup: CanvasLayer = null

func _init(town_ref: Node2D) -> void:
	town = town_ref

# --- Setup / teardown --------------------------------------------------------

func setup() -> void:
	var peer_order: Array = NetworkManager.pending_peer_order
	town.my_player_index = peer_order.find(town.multiplayer.get_unique_id())
	for _player_index in range(peer_order.size()):
		town.players.append(_new_state())

	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 20
	waiting_label = Label.new()
	waiting_label.visible = false
	waiting_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	waiting_label.position.y = 24.0
	waiting_label.add_theme_color_override("font_color", Constants.STATUS_NEUTRAL_COLOR)
	waiting_label.add_theme_color_override("font_outline_color", Color.BLACK)
	waiting_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(waiting_label)
	town.add_child(layer)
	loading_popup = preload("res://LoadingPopup.tscn").instantiate()
	town.add_child(loading_popup)

	town.multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.kicked_from_server.connect(_on_host_gone)
	if town.multiplayer.is_server():
		# The next board is built while everyone shops and brawls.
		var sizes: Array[Vector2i] = preload("res://Game.gd").SUBSEQUENT_PUZZLE_SIZES
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		job = GenerationJob.new()
		job.start(sizes[rng.randi() % sizes.size()], Constants.GENERATOR_DENSITY)
	else:
		town.rpc_id(1, "_town_ready")

func cleanup() -> void:
	if town.multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		town.multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if NetworkManager.kicked_from_server.is_connected(_on_host_gone):
		NetworkManager.kicked_from_server.disconnect(_on_host_gone)
	if job != null:
		job.cancel()
		job.finish()
		job = null

func _on_host_gone() -> void:
	town.get_tree().change_scene_to_file(Constants.SCENE_MAIN_MENU)

func _new_state() -> Dictionary:
	var start: Vector2 = Vector2(town.SPAWN_COL, town.SPAWN_ROW)
	return {
		"row": town.SPAWN_ROW, "col": town.SPAWN_COL, "facing": "up",
		"visual_position": start, "from": start, "to": start, "progress": 1.0,
		"anim_timer": 0.0, "frame": 0, "idle_timer": 0.0, "idle_frame": 0,
		"health": MAX_HEALTH, "hidden": false, "departed": false,
		"cooldown": 0.0, "swing": 0.0, "hurt": 0.0,
	}

func _me() -> Dictionary:
	if town.my_player_index < 0 or town.my_player_index >= town.players.size():
		return {}
	return town.players[town.my_player_index]

func _is_host() -> bool:
	return town.multiplayer.is_server()

# --- Per-frame ---------------------------------------------------------------

func advance(delta: float) -> void:
	pending_timer = maxf(0.0, pending_timer - delta)
	for state: Dictionary in town.players:
		state["cooldown"] = maxf(0.0, state["cooldown"] - delta)
		state["swing"] = maxf(0.0, state["swing"] - delta)
		state["hurt"] = maxf(0.0, state["hurt"] - delta)
		if state["progress"] < 1.0:
			state["progress"] = minf(state["progress"] + delta / Constants.MOVE_ANIMATION_DURATION, 1.0)
			state["visual_position"] = state["from"].lerp(state["to"], ease(state["progress"], -2.0))
			state["anim_timer"] += delta
			if state["anim_timer"] >= Constants.PLAYER_ANIMATION_FRAME_DURATION:
				state["anim_timer"] = 0.0
				state["frame"] = (state["frame"] + 1) % Constants.PLAYER_RUN_SHEET_FRAME_COUNT
		else:
			state["anim_timer"] = 0.0
			state["frame"] = 0
			state["idle_timer"] += delta
			if state["idle_timer"] >= Constants.PLAYER_IDLE_FRAME_DURATION:
				state["idle_timer"] = 0.0
				state["idle_frame"] = (state["idle_frame"] + 1) % Constants.PLAYER_IDLE_SHEET_FRAME_COUNT

# The hold-to-move repeater waits while this is true: mid-hop, or still waiting on the host's reply.
func local_busy() -> bool:
	var me: Dictionary = _me()
	return pending_timer > 0.0 or (not me.is_empty() and me["progress"] < 1.0)

func local_can_act() -> bool:
	var me: Dictionary = _me()
	return not me.is_empty() and not me["hidden"] and not me["departed"]

# --- Walking -------------------------------------------------------------------

func request_move(delta_row: int, delta_col: int) -> void:
	if not local_can_act() or local_busy():
		return
	var me: Dictionary = _me()
	var next_row: int = me["row"] + delta_row
	var next_col: int = me["col"] + delta_col
	# The same checks the host makes, done up front so a bump into a wall costs no round trip.
	if next_col >= 0 and next_col < town.grid_cols:
		if next_row < 0 or next_row >= town.grid_rows or town.TOWN_GRID[next_row][next_col] == town.WALL_CHAR:
			return
	pending_timer = REQUEST_TIMEOUT
	if _is_host():
		_request_move(town.my_player_index, delta_row, delta_col)
	else:
		town.rpc_id(1, "_town_request_move", town.my_player_index, delta_row, delta_col)

func _request_move(player_index: int, delta_row: int, delta_col: int) -> void:
	if not _is_host():
		return
	if not NetworkManager.validate_request(player_index, town.players.size(), "town_move", MOVE_MIN_INTERVAL):
		return
	if abs(delta_row) + abs(delta_col) != 1:
		return
	var state: Dictionary = town.players[player_index]
	if state["hidden"] or state["departed"] or state["progress"] < 0.5:
		return  # not here / still mid-hop (a little slack, since peers' timing differs by a frame or two)
	var next_row: int = state["row"] + delta_row
	var next_col: int = state["col"] + delta_col
	if next_col < 0 or next_col >= town.grid_cols:
		town.rpc("_town_sync_departed", player_index)  # off either end of the road: leaves town
		return
	if next_row < 0 or next_row >= town.grid_rows or town.TOWN_GRID[next_row][next_col] == town.WALL_CHAR:
		return
	town.rpc("_town_sync_move", player_index, next_row, next_col, _facing_for(delta_row, delta_col))

func _facing_for(delta_row: int, delta_col: int) -> String:
	if delta_row < 0:
		return "up"
	if delta_row > 0:
		return "down"
	return "left" if delta_col < 0 else "right"

func _sync_move(player_index: int, row: int, col: int, facing: String) -> void:
	if player_index < 0 or player_index >= town.players.size():
		return
	_hop_to(town.players[player_index], row, col, facing)
	if player_index != town.my_player_index:
		return
	pending_timer = 0.0
	town.player_row = row
	town.player_col = col
	if town.TOWN_GRID[row][col] == town.DOOR_CHAR:
		var shop_index: int = town._shop_index_at(row, col)
		if shop_index != -1:
			town.active_shop_index = shop_index
			town._open_confirm_panel(shop_index)

func _hop_to(state: Dictionary, row: int, col: int, facing: String) -> void:
	state["row"] = row
	state["col"] = col
	state["facing"] = facing
	state["from"] = state["visual_position"]
	state["to"] = Vector2(col, row)
	state["progress"] = 0.0

# --- Shop doors: hidden while shopping -------------------------------------------

func request_hidden(should_hide: bool) -> void:
	if _me().is_empty():
		return
	if _is_host():
		_request_hidden(town.my_player_index, should_hide)
	else:
		town.rpc_id(1, "_town_request_hidden", town.my_player_index, should_hide)

func _request_hidden(player_index: int, should_hide: bool) -> void:
	if not _is_host():
		return
	if not NetworkManager.validate_request(player_index, town.players.size(), "town_hide", 0.1):
		return
	var state: Dictionary = town.players[player_index]
	if state["departed"] or state["hidden"] == should_hide:
		return
	if should_hide:
		if town.TOWN_GRID[state["row"]][state["col"]] != town.DOOR_CHAR:
			return  # only from a shop door
		town.rpc("_town_sync_hidden", player_index, true, state["row"], state["col"], state["facing"])
	else:
		# Back out onto the tile below the door.
		town.rpc("_town_sync_hidden", player_index, false, state["row"] + 1, state["col"], "down")

func _sync_hidden(player_index: int, should_hide: bool, row: int, col: int, facing: String) -> void:
	if player_index < 0 or player_index >= town.players.size():
		return
	var state: Dictionary = town.players[player_index]
	state["hidden"] = should_hide
	if not should_hide:
		_hop_to(state, row, col, facing)
	if player_index != town.my_player_index:
		return
	if should_hide:
		town.open_shop_panel_for_multiplayer()
	else:
		town.player_row = row
		town.player_col = col

# The shop window closed (X button): come back out.
func on_shop_closed() -> void:
	var me: Dictionary = _me()
	if not me.is_empty() and me["hidden"]:
		request_hidden(false)

# --- Fighting ---------------------------------------------------------------------

func request_attack() -> void:
	if not local_can_act():
		return
	if _is_host():
		_request_attack(town.my_player_index)
	else:
		town.rpc_id(1, "_town_request_attack", town.my_player_index)

func _request_attack(player_index: int) -> void:
	if not _is_host():
		return
	if not NetworkManager.validate_request(player_index, town.players.size(), "town_attack", 0.05):
		return
	var attacker: Dictionary = town.players[player_index]
	if attacker["hidden"] or attacker["departed"] or attacker["cooldown"] > 0.0:
		return
	var target_index: int = -1
	var best_distance: int = 2
	for other_index in range(town.players.size()):
		var other: Dictionary = town.players[other_index]
		if other_index == player_index or other["hidden"] or other["departed"]:
			continue  # hidden (shopping) and departed players can't be hit
		var distance: int = abs(other["row"] - attacker["row"]) + abs(other["col"] - attacker["col"])
		if distance < best_distance:
			best_distance = distance
			target_index = other_index
	if target_index < 0:
		return
	attacker["cooldown"] = ATTACK_COOLDOWN
	var damage: int = maxi(1, int(round(ATTACK_DAMAGE * _melee_multiplier(target_index))))
	var new_health: int = maxi(0, town.players[target_index]["health"] - damage)
	town.rpc("_town_sync_hit", player_index, target_index, new_health, new_health <= 0)

# The same armor reduction the levels use (see Player._get_melee_damage_multiplier).
func _melee_multiplier(player_index: int) -> float:
	var armor_item_id: String = _armor_of(player_index)
	if armor_item_id == "":
		return 1.0
	return 1.0 - float(ItemData.get_item(armor_item_id).get("melee_damage_reduction", 0.0))

func _armor_of(player_index: int) -> String:
	if player_index < 0 or player_index >= town.player_equipped.size():
		return ""
	return town.player_equipped[player_index].get("armor", "")

func _sync_hit(attacker_index: int, target_index: int, new_health: int, died: bool) -> void:
	if attacker_index < 0 or attacker_index >= town.players.size() or target_index < 0 or target_index >= town.players.size():
		return
	var attacker: Dictionary = town.players[attacker_index]
	var target: Dictionary = town.players[target_index]
	attacker["swing"] = Constants.ATTACK_FLASH_DURATION
	target["hurt"] = Constants.ATTACK_FLASH_DURATION
	if not died:
		target["health"] = new_health
		return
	# "Killed": straight back to the spawn tile at full health. No penalty of any kind.
	target["health"] = MAX_HEALTH
	var spawn: Vector2 = Vector2(town.SPAWN_COL, town.SPAWN_ROW)
	target["row"] = town.SPAWN_ROW
	target["col"] = town.SPAWN_COL
	target["visual_position"] = spawn
	target["from"] = spawn
	target["to"] = spawn
	target["progress"] = 1.0
	if target_index == town.my_player_index:
		pending_timer = 0.0
		town.player_row = town.SPAWN_ROW
		town.player_col = town.SPAWN_COL
		town.confirm_canvas.visible = false  # was standing on a shop door with the prompt up

# --- Leaving town -------------------------------------------------------------------

func _sync_departed(player_index: int) -> void:
	if player_index < 0 or player_index >= town.players.size():
		return
	var state: Dictionary = town.players[player_index]
	state["departed"] = true
	state["hidden"] = true
	if player_index == town.my_player_index:
		pending_timer = 0.0
		waiting_label.text = "Waiting for the other players to leave town..."
		waiting_label.visible = true
	if _is_host():
		_check_everyone_left()

func _on_peer_disconnected(_peer_id: int) -> void:
	if _is_host():
		_check_everyone_left.call_deferred()  # after the peer list has updated

func _check_everyone_left() -> void:
	if transitioning:
		return
	var roster: Array = NetworkManager.pending_peer_order
	for player_index in range(town.players.size()):
		var peer_id: int = roster[player_index]
		var still_here: bool = peer_id == 1 or town.multiplayer.get_peers().has(peer_id)
		if still_here and not town.players[player_index]["departed"]:
			return
	transitioning = true
	_start_next_level()

func _start_next_level() -> void:
	if job != null and not job.done:
		town.rpc("_town_sync_loading")  # the board isn't ready yet: everyone sees the loading popup
	while job != null and not job.done:
		await town.get_tree().process_frame
		if job == null or job.cancelled:
			return
	if job == null:
		return
	job.finish()
	var rows: PackedStringArray = job.result_rows
	job = null
	var positions: Array = BoardUtil.corner_positions(rows, town.players.size())
	NetworkManager.rpc("_begin_game", rows, positions, NetworkManager.pending_peer_order, true)

# Every peer: the host is still building the next board.
func _sync_loading() -> void:
	waiting_label.visible = false
	loading_popup.show_popup()

# --- Late loaders ------------------------------------------------------------------

func _request_ready() -> void:
	if not _is_host():
		return
	var peer_id: int = town.multiplayer.get_remote_sender_id()
	if peer_id == 0 or not NetworkManager.player_roster().has(peer_id):
		return
	if not NetworkManager.rate_limit_ok(peer_id, "town_ready", 1.0):
		return
	var snapshot: Array = []
	for state: Dictionary in town.players:
		snapshot.append({
			"row": state["row"], "col": state["col"], "facing": state["facing"],
			"health": state["health"], "hidden": state["hidden"], "departed": state["departed"],
		})
	town.rpc_id(peer_id, "_town_full_sync", snapshot)

func _full_sync(snapshot: Array) -> void:
	for player_index in range(mini(snapshot.size(), town.players.size())):
		var entry: Dictionary = snapshot[player_index]
		var state: Dictionary = _new_state()
		state["row"] = entry["row"]
		state["col"] = entry["col"]
		state["facing"] = entry["facing"]
		state["health"] = entry["health"]
		state["hidden"] = entry["hidden"]
		state["departed"] = entry["departed"]
		var tile: Vector2 = Vector2(entry["col"], entry["row"])
		state["visual_position"] = tile
		state["from"] = tile
		state["to"] = tile
		town.players[player_index] = state
	var me: Dictionary = _me()
	if not me.is_empty():
		town.player_row = me["row"]
		town.player_col = me["col"]
		if me["departed"]:
			waiting_label.text = "Waiting for the other players to leave town..."
			waiting_label.visible = true

# --- Drawing -----------------------------------------------------------------------

# Called from Town._draw(): every visible player, the local one last so it's on top.
func draw(grid_origin: Vector2) -> void:
	var order: Array[int] = []
	for player_index in range(town.players.size()):
		if player_index != town.my_player_index:
			order.append(player_index)
	order.append(town.my_player_index)
	for player_index in order:
		if player_index < 0 or player_index >= town.players.size():
			continue
		var state: Dictionary = town.players[player_index]
		if state["hidden"] or state["departed"]:
			continue
		var offset: Vector2 = Constants.PLAYER_OFFSETS[player_index % Constants.PLAYER_OFFSETS.size()]
		var color: Color = Constants.PLAYER_COLORS[player_index % Constants.PLAYER_COLORS.size()]
		if state["hurt"] > 0.0:
			color = color.lerp(Color(1, 0.3, 0.3), 0.6)
		var is_moving: bool = state["progress"] < 1.0
		var body_center: Vector2 = GridGeometry.tile_center_to_pixel(state["visual_position"].y, state["visual_position"].x, grid_origin, Constants.CELL_SIZE) + offset
		town._draw_character(body_center, is_moving, state["frame"] if is_moving else state["idle_frame"], state["facing"], color, _armor_of(player_index))
		if player_index == town.my_player_index and town.players.size() > 1:
			town.draw_arc(body_center, Constants.CELL_SIZE * 0.42, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0)  # same white ring the levels use for "this is you"
		if state["swing"] > 0.0:
			var flash: float = state["swing"] / Constants.ATTACK_FLASH_DURATION
			town.draw_arc(body_center, Constants.CELL_SIZE * 0.32 * (1.0 + 0.5 * (1.0 - flash)), 0.0, TAU, 16, Color(1, 1, 0.6, flash), 3.0)
		if state["health"] < MAX_HEALTH:
			var bar_origin: Vector2 = body_center + Vector2(-HEALTH_BAR_SIZE.x / 2.0, -Constants.CELL_SIZE * 0.5)
			town.draw_rect(Rect2(bar_origin, HEALTH_BAR_SIZE), Color(0, 0, 0, 0.6))
			town.draw_rect(Rect2(bar_origin, Vector2(HEALTH_BAR_SIZE.x * float(state["health"]) / MAX_HEALTH, HEALTH_BAR_SIZE.y)), Color(0.3, 0.85, 0.3))
