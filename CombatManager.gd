extends RefCounted
# Combat resolution: attack requests, damage application, cooldowns, conflict timer, projectiles.
# Split out of Game.gd -- operates on shared board/combat state via the `game` back-reference.

var game: Node2D

func _init(game_ref: Node2D) -> void:
	game = game_ref

const PLAYER_ATTACK_DAMAGE: int = 5
const PLAYER_ATTACK_COOLDOWN: float = 0.4
const PROJECTILE_SPEED_CELLS_PER_SECOND: float = 10.0
# projectile.png is a horizontal strip of PROJECTILE_FRAME_WIDTH_PIXELS-wide
# frames (32x16 each, 9 frames). The first PROJECTILE_FLIGHT_FRAME_COUNT frames
# play once across the flight (art faces right, so it just rotates to the
# travel direction); the remaining frames are an impact burst that plays once,
# upright, at the target after arrival. Purely visual -- damage lands at fire time.
const PROJECTILE_FRAME_WIDTH_PIXELS: int = 32
const PROJECTILE_FLIGHT_FRAME_COUNT: int = 5
const PROJECTILE_IMPACT_FRAME_DURATION: float = 0.07  # seconds per impact frame
const PROJECTILE_SPRITE_SCALE: float = 2.0  # multiple of native pixels (2.0 = a 32px-wide frame spans one 64px cell)
const ATTACK_FLASH_DURATION: float = 0.25  # purely cosmetic swing/hit flash, both player and enemy

func _tick_combat_simulation(delta: float) -> void:
	var party_wiped: bool = game.player_mgr._all_players_defeated()
	_tick_player_attack_cooldowns(delta)
	game.enemy_mgr._tick_enemy_death_timers(delta)
	if not party_wiped:
		_tick_conflict_timer(delta)
		game.enemy_mgr._tick_enemy_ai(delta)
		game.enemy_mgr._tick_boss_spawn_check()
	game.player_mgr._tick_player_respawns(party_wiped)

func _tick_player_attack_cooldowns(delta: float) -> void:
	for player_state: Dictionary in game.players:
		if player_state["attack_cooldown_timer"] > 0.0:
			player_state["attack_cooldown_timer"] = max(0.0, player_state["attack_cooldown_timer"] - delta)

func _tick_conflict_timer(delta: float) -> void:
	if game.conflicting_bulbs.is_empty():
		game.conflict_timer = 0.0
		game.next_enemy_spawn_threshold = game.CONFLICT_SPAWN_INTERVAL
		return
	game.conflict_timer += delta
	if game.conflict_timer >= game.next_enemy_spawn_threshold:
		game.next_enemy_spawn_threshold += game.CONFLICT_SPAWN_INTERVAL
		game.enemy_mgr._spawn_enemy_from_conflict()

@rpc("any_peer", "call_remote", "reliable")
func _request_attack(player_index: int) -> void:
	if NetworkManager.is_multiplayer and not game.multiplayer.is_server():
		return
	if not NetworkManager.validate_request(player_index, game.players.size(), "attack", 0.05):
		return
	var player_state: Dictionary = game.players[player_index]
	if player_state["is_defeated"]:
		return
	if player_state["is_blocking"]:
		return  # guard's up -- can't swing (authoritative check; input is also blocked client-side)
	if player_state["attack_cooldown_timer"] > 0.0:
		return
	var target_enemy_id: int = _find_adjacent_enemy_id(player_state)
	if target_enemy_id < 0:
		return
	player_state["attack_cooldown_timer"] = PLAYER_ATTACK_COOLDOWN
	_flash_player_attack(player_index)
	_damage_enemy_by_id(target_enemy_id, PLAYER_ATTACK_DAMAGE)

func _find_adjacent_enemy_id(player_state: Dictionary) -> int:
	var player_row: int = player_state["row"]
	var player_col: int = player_state["col"]
	for enemy_state: Dictionary in game.enemies:
		if enemy_state["is_dying"]:
			continue  # already resolved -- just playing out its death pose, not a valid target
		var distance: int = abs(enemy_state["row"] - player_row) + abs(enemy_state["col"] - player_col)
		if distance <= 1:
			return enemy_state["id"]
	return -1

# Marks the enemy dying rather than removing it outright -- it stays in
# game.enemies (un-targetable, see _find_adjacent_enemy_id and
# EnemyManager._tick_enemy_ai) so its death pose can play out; the actual
# removal + snapshot broadcast happens once that finishes, in
# EnemyManager._tick_enemy_death_timers. Also where a kill is credited
# toward this level's gold earnings (see Game.boss_killed_this_level /
# enemies_killed_this_level, tallied up in CampaignManager.credit_level_earnings
# once the level is solved) -- campaign mode is always singleplayer, so
# there's no risk of double-crediting a kill across peers here.
func _damage_enemy_by_id(enemy_id: int, amount: int) -> void:
	for enemy_index in range(game.enemies.size()):
		var enemy_state: Dictionary = game.enemies[enemy_index]
		if enemy_state["id"] == enemy_id:
			if enemy_state["is_dying"]:
				break  # already resolved, ignore any further hits
			var new_health: int = enemy_state["health"] - amount
			if new_health <= 0:
				enemy_state["health"] = 0
				enemy_state["is_dying"] = true
				enemy_state["death_progress"] = 0.0
				enemy_state["death_timer"] = game.enemy_mgr.DEATH_ANIMATION_DURATION
				if enemy_state["is_boss"]:
					game.boss_killed_this_level = true
				else:
					game.enemies_killed_this_level += 1
			else:
				enemy_state["health"] = new_health
				game.enemy_mgr._trigger_hurt(enemy_state)
			break
	game.enemy_mgr._broadcast_enemy_snapshot()

# Purely cosmetic swing/hit flashes -- broadcast the same way projectiles
# are below, since the enemy AI (and player-attack resolution) only ever
# runs on the host/singleplayer, but everyone should see the flash.

func _flash_player_attack(player_index: int) -> void:
	if NetworkManager.is_multiplayer:
		game.rpc("_sync_player_attack_flash", player_index)
	else:
		_sync_player_attack_flash(player_index)

@rpc("authority", "call_local", "reliable")
func _sync_player_attack_flash(player_index: int) -> void:
	game.players[player_index]["attack_flash_timer"] = ATTACK_FLASH_DURATION
	game.player_mgr._trigger_action_animation(player_index, "attack")

func _flash_enemy_attack(enemy_id: int) -> void:
	if NetworkManager.is_multiplayer:
		game.rpc("_sync_enemy_attack_flash", enemy_id)
	else:
		_sync_enemy_attack_flash(enemy_id)

@rpc("authority", "call_local", "reliable")
func _sync_enemy_attack_flash(enemy_id: int) -> void:
	for enemy_state: Dictionary in game.enemies:
		if enemy_state["id"] == enemy_id:
			enemy_state["attack_flash_timer"] = ATTACK_FLASH_DURATION
			game.enemy_mgr._trigger_action_animation(enemy_id, "attack")
			return

func _spawn_projectile(from_row: int, from_col: int, to_row: int, to_col: int, shooter_enemy_id: int) -> void:
	if NetworkManager.is_multiplayer:
		game.rpc("_sync_spawn_projectile", from_row, from_col, to_row, to_col, shooter_enemy_id)
	else:
		_sync_spawn_projectile(from_row, from_col, to_row, to_col, shooter_enemy_id)

@rpc("authority", "call_local", "reliable")
func _sync_spawn_projectile(from_row: int, from_col: int, to_row: int, to_col: int, shooter_enemy_id: int) -> void:
	var from_position: Vector2 = Vector2(from_col, from_row)
	var to_position: Vector2 = Vector2(to_col, to_row)
	var travel_distance: float = from_position.distance_to(to_position)
	var flight_duration: float = max(0.05, travel_distance / PROJECTILE_SPEED_CELLS_PER_SECOND)
	game.projectiles.append({
		"from_position": from_position,
		"to_position": to_position,
		"progress": 0.0,
		"duration": flight_duration,
		"impact_time": -1.0,  # < 0 while in flight; counts up from 0 once it has arrived
	})
	game.enemy_mgr._trigger_action_animation(shooter_enemy_id, "ranged")

func _advance_projectiles(delta: float) -> bool:
	var had_projectiles: bool = not game.projectiles.is_empty()
	var impact_frame_count: int = _projectile_impact_frame_count()
	var impact_duration: float = impact_frame_count * PROJECTILE_IMPACT_FRAME_DURATION
	var still_active: Array[Dictionary] = []
	for projectile: Dictionary in game.projectiles:
		if projectile["impact_time"] >= 0.0:
			projectile["impact_time"] += delta
			if projectile["impact_time"] < impact_duration:
				still_active.append(projectile)
			continue
		var duration: float = projectile["duration"]
		var progress: float = projectile["progress"] + delta / duration
		if progress < 1.0:
			projectile["progress"] = progress
		else:
			# Arrived: switch to the impact burst (dropped right away if the
			# strip has no impact frames).
			projectile["progress"] = 1.0
			projectile["impact_time"] = 0.0
			if impact_frame_count == 0:
				continue
		still_active.append(projectile)
	game.projectiles = still_active
	return had_projectiles

func _projectile_total_frame_count() -> int:
	return maxi(1, roundi(float(game.projectile_texture.get_width()) / float(PROJECTILE_FRAME_WIDTH_PIXELS)))

func _projectile_impact_frame_count() -> int:
	return maxi(0, _projectile_total_frame_count() - PROJECTILE_FLIGHT_FRAME_COUNT)

func _draw_projectiles() -> void:
	var texture: Texture2D = game.projectile_texture
	var frame_size: Vector2 = Vector2(PROJECTILE_FRAME_WIDTH_PIXELS, texture.get_height())
	var draw_size: Vector2 = frame_size * PROJECTILE_SPRITE_SCALE
	var impact_frame_count: int = _projectile_impact_frame_count()
	for projectile: Dictionary in game.projectiles:
		var from_position: Vector2 = projectile["from_position"]
		var to_position: Vector2 = projectile["to_position"]
		var current_position: Vector2 = from_position.lerp(to_position, projectile["progress"])
		var center: Vector2 = game._tile_center_to_pixel(current_position.y, current_position.x)

		var frame_index: int
		var rotation_angle: float = 0.0
		if projectile["impact_time"] >= 0.0:
			# Impact burst: upright, not rotated with the shot.
			var impact_frame: int = mini(int(projectile["impact_time"] / PROJECTILE_IMPACT_FRAME_DURATION), impact_frame_count - 1)
			frame_index = PROJECTILE_FLIGHT_FRAME_COUNT + impact_frame
		else:
			# Flight: play the flight frames once, stretched over the whole trip.
			frame_index = mini(int(projectile["progress"] * PROJECTILE_FLIGHT_FRAME_COUNT), PROJECTILE_FLIGHT_FRAME_COUNT - 1)
			var travel_direction: Vector2 = to_position - from_position
			rotation_angle = travel_direction.angle() if travel_direction.length() > 0.0 else 0.0

		var source_rectangle: Rect2 = Rect2(Vector2(frame_index * frame_size.x, 0.0), frame_size)
		game.draw_set_transform(center, rotation_angle, Vector2(1, 1))
		game.draw_texture_rect_region(texture, Rect2(-draw_size / 2.0, draw_size), source_rectangle)
		game.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 1))

func _update_combat_status_label() -> void:
	if game.combat_status_label == null:
		return
	var status_lines: Array[String] = []
	if NetworkManager.is_multiplayer:
		status_lines.append("You are Player %d of %d" % [game.my_player_index + 1, game.players.size()])

	var my_state: Dictionary = game.players[game.my_player_index]
	var party_wiped: bool = game.player_mgr._all_players_defeated()
	if game.try_again_button != null:
		game.try_again_button.visible = party_wiped
	if my_state["is_defeated"]:
		if party_wiped:
			if NetworkManager.is_multiplayer:
				status_lines.append("All players defeated! Ask the host to Reset.")
			else:
				status_lines.append("Defeated! Press Reset to continue.")
		else:
			var seconds_left: int = int(ceil(max(0.0, game.RESPAWN_DURATION - my_state["respawn_timer"])))
			status_lines.append("Defeated -- respawning in %ds" % seconds_left)
	else:
		if not game.enemies.is_empty():
			status_lines.append("Enemies: %d" % game.enemies.size())

	game.combat_status_label.text = "\n".join(status_lines)

# ---------------------------------------------------------------------------
# Rules engine (unchanged from singleplayer -- shared board, same rules)
# ---------------------------------------------------------------------------
