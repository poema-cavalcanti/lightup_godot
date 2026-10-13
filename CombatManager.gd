extends RefCounted
# Combat resolution: attack requests, damage application, cooldowns, conflict timer, projectiles.
# Split out of Game.gd -- operates on shared board/combat state via the `game` back-reference.

var game: Node2D

func _init(game_ref: Node2D) -> void:
	game = game_ref

const PLAYER_ATTACK_DAMAGE: int = 5
const PLAYER_ATTACK_COOLDOWN: float = 0.4
const PROJECTILE_SPEED_CELLS_PER_SECOND: float = 10.0
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
	})
	game.enemy_mgr._trigger_action_animation(shooter_enemy_id, "ranged")

func _advance_projectiles(delta: float) -> bool:
	var had_projectiles: bool = not game.projectiles.is_empty()
	var still_active: Array[Dictionary] = []
	for projectile: Dictionary in game.projectiles:
		var duration: float = projectile["duration"]
		var progress: float = projectile["progress"] + delta / duration
		if progress < 1.0:
			projectile["progress"] = progress
			still_active.append(projectile)
	game.projectiles = still_active
	return had_projectiles

func _draw_projectiles() -> void:
	for projectile: Dictionary in game.projectiles:
		var from_position: Vector2 = projectile["from_position"]
		var to_position: Vector2 = projectile["to_position"]
		var progress: float = projectile["progress"]
		var current_position: Vector2 = from_position.lerp(to_position, progress)
		var center: Vector2 = game._tile_center_to_pixel(current_position.y, current_position.x)

		if game.projectile_texture != null:
			var sprite_size: float = game.CELL_SIZE * 0.35
			var travel_direction: Vector2 = to_position - from_position
			var travel_angle: float = travel_direction.angle() if travel_direction.length() > 0.0 else 0.0
			game.draw_set_transform(center, travel_angle, Vector2(1, 1))
			game.draw_texture_rect(game.projectile_texture, Rect2(-sprite_size / 2.0, -sprite_size / 2.0, sprite_size, sprite_size), false)
			game.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 1))
		else:
			game.draw_circle(center, game.CELL_SIZE * 0.09, game.BOSS_COLOR)
			game.draw_arc(center, game.CELL_SIZE * 0.09, 0.0, TAU, 10, Color.WHITE, 1.5)

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
