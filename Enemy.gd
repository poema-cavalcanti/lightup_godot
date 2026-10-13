extends RefCounted
# Enemy + boss logic: AI movement/attacks, spawning, boss escalation, network sync, drawing.
# Split out of Game.gd -- operates on shared board/combat state via the `game` back-reference.

var game: Node2D

func _init(game_ref: Node2D) -> void:
	game = game_ref

const ENEMY_MAX_HEALTH: int = 10
const ENEMY_ATTACK_DAMAGE: int = 5
const ENEMY_MOVE_INTERVAL: float = 0.7
const ENEMY_ATTACK_INTERVAL: float = 1.0
const MOVE_DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const BOSS_MAX_HEALTH: int = 50
const BOSS_MELEE_DAMAGE: int = 10
const BOSS_RANGED_DAMAGE: int = 5
const BOSS_RANGED_ATTACK_INTERVAL: float = 1.2
const SPAWN_ANIMATION_DURATION: float = 0.4  # scale/fade-in when an enemy first appears

# --- Animation definitions ---------------------------------------------------
# Sheets are grids: frames run left-to-right, one row per facing (enemy sheets:
# down, up, left, right; boss sheets are single-row). Per animation: "frames"
# (0 = infer from width/height, single-row sheets only), "rows", and either
# "frame_time" (loops) or "duration" (one-shot: frames are stretched to fit it,
# so the gameplay timers below always match the art whatever the frame count).
# Missing sheets fall back to the static texture / shape. See assets/README.md.
const ATTACK_ANIMATION_DURATION: float = 0.25  # keep equal to CombatManager.ATTACK_FLASH_DURATION
const RANGED_ANIMATION_DURATION: float = 0.3  # boss ranged wind-up/release pose, boss-only
const HURT_ANIMATION_DURATION: float = 0.25
const DEATH_ANIMATION_DURATION: float = 0.5  # also how long the corpse blocks re-targeting before it's removed
const ANIMS: Dictionary = {
	"enemy": {
		"idle": {"frames": 6, "rows": 4, "frame_time": 0.15},
		"move": {"frames": 8, "rows": 4, "frame_time": 0.05},
		"attack": {"frames": 9, "rows": 4, "duration": ATTACK_ANIMATION_DURATION},
		"hurt": {"frames": 5, "rows": 4, "duration": HURT_ANIMATION_DURATION},
		"death": {"frames": 10, "rows": 4, "duration": DEATH_ANIMATION_DURATION},
	},
	"boss": {  # tier sheets, boss_tier_<n>_<anim>_sheet.png
		"idle": {"frames": 4, "rows": 4, "frame_time": 0.15},
		"move": {"frames": 6, "rows": 4, "frame_time": 0.07},
		"attack": {"frames": 12, "rows": 4, "duration": ATTACK_ANIMATION_DURATION},
		"hurt": {"frames": 4, "rows": 4, "duration": HURT_ANIMATION_DURATION},
		"death": {"frames": 11, "rows": 4, "duration": DEATH_ANIMATION_DURATION},
	},
}

func _create_enemy_state(enemy_id: int, spawn_row: int, spawn_col: int, health: int, max_health: int, is_boss: bool) -> Dictionary:
	var spawn_visual_position: Vector2 = Vector2(spawn_col, spawn_row)
	return {
		"id": enemy_id,
		"row": spawn_row,
		"col": spawn_col,
		"health": health,
		"max_health": max_health,
		"is_boss": is_boss,
		"visual_position": spawn_visual_position,
		"animation_from": spawn_visual_position,
		"animation_to": spawn_visual_position,
		"animation_progress": 1.0,
		"spawn_progress": 0.0,
		"attack_flash_timer": 0.0,
		"move_cooldown_timer": 0.0,
		"attack_cooldown_timer": 0.0,
		"action_anim": "",  # "" (move/static) | "attack" | "ranged" (boss only) -- one-shot pose overlay
		"action_progress": 1.0,
		"is_dying": false,
		"anim_name": "",  # current sheet key (see ANIMS), "" = static fallback
		"anim_time": 0.0,
		"facing": 0,  # sheet row: 0 down, 1 up, 2 left, 3 right
		"hurt_timer": 0.0,
		"death_progress": 0.0,
		"death_timer": 0.0,  # host-only countdown before actual removal from game.enemies
	}

func _get_sheet(is_boss: bool, anim: String) -> Texture2D:
	var key: String = ("boss_tier_%d_" % _get_boss_tier() if is_boss else "enemy_") + anim
	return game.enemy_sheets.get(key) as Texture2D

func _frame_count(sheet: Texture2D, def: Dictionary) -> int:
	var frames: int = def["frames"]
	if frames > 0:
		return frames
	return maxi(1, roundi(float(sheet.get_width()) / (float(sheet.get_height()) / float(def["rows"]))))

func _anim_frame(sheet: Texture2D, def: Dictionary, anim_time: float) -> int:
	var frames: int = _frame_count(sheet, def)
	if def.has("duration"):
		var duration: float = def["duration"]
		return mini(int(anim_time / duration * frames), frames - 1)
	var frame_time: float = def["frame_time"]
	return int(anim_time / frame_time) % frames

# Priority: death > hurt > attack/ranged > move > idle, skipping any whose
# sheet is missing. Stateless, so finishing a hurt/attack just falls back.
func _select_animation(enemy_state: Dictionary) -> String:
	var is_boss: bool = enemy_state["is_boss"]
	if enemy_state["is_dying"]:
		return "death" if _get_sheet(is_boss, "death") != null else ""
	var candidates: Array[String] = []
	if enemy_state["hurt_timer"] > 0.0:
		candidates.append("hurt")
	if enemy_state["action_anim"] != "":
		candidates.append(enemy_state["action_anim"])
		if enemy_state["action_anim"] == "ranged":
			candidates.append("attack")  # no dedicated ranged sheet: reuse attack
	if enemy_state["animation_progress"] < 1.0:
		candidates.append("move")
	candidates.append("idle")
	for candidate: String in candidates:
		if _get_sheet(is_boss, candidate) != null:
			return candidate
	return ""

# Host calls this on damage; clients detect it from a health drop in the snapshot.
func _trigger_hurt(enemy_state: Dictionary) -> void:
	enemy_state["hurt_timer"] = HURT_ANIMATION_DURATION
	if enemy_state["anim_name"] == "hurt":
		enemy_state["anim_time"] = 0.0

# Called from CombatManager whenever a melee or ranged attack actually
# lands/fires, both of which already broadcast that event to every peer the
# same way, so this only ever needs to run locally in response to it.
func _trigger_action_animation(enemy_id: int, action_name: String) -> void:
	for enemy_state: Dictionary in game.enemies:
		if enemy_state["id"] == enemy_id:
			enemy_state["action_anim"] = action_name
			enemy_state["action_progress"] = 0.0
			return

func _get_boss_tier() -> int:
	if not CampaignManager.is_campaign_active:
		return 1
	var level_number: int = CampaignManager.get_current_level_number()
	if level_number <= 3:
		return 1
	elif level_number <= 6:
		return 2
	elif level_number <= 9:
		return 3
	else:
		return 4

func _get_boss_texture() -> Texture2D:
	var tier: int = _get_boss_tier()
	if game.boss_tier_textures.has(tier):
		return game.boss_tier_textures[tier]
	return game.boss_texture  # generic fallback, itself possibly null

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _find_boss_spawn_position() -> Array:
	var unlit_positions: Array = []
	for row in range(game.rows):
		for col in range(game.cols):
			if game.grid[row][col]["type"] == game.CellType.WHITE and not game.lit[row][col]:
				unlit_positions.append([row, col])
	if unlit_positions.is_empty():
		# shouldn't happen since callers only reach here after
		# _any_unlit_white_cell() returned true, but fail safe
		return [game.rows / 2, game.cols / 2]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	return unlit_positions[rng.randi_range(0, unlit_positions.size() - 1)]

func _spawn_boss() -> void:
	var spawn_position: Array = _find_boss_spawn_position()
	game.enemies.append(_create_enemy_state(game.next_enemy_id, spawn_position[0], spawn_position[1], BOSS_MAX_HEALTH, BOSS_MAX_HEALTH, true))
	game.next_enemy_id += 1
	game.boss_was_summoned_this_level = true
	_broadcast_enemy_snapshot()

func _tick_boss_spawn_check() -> void:
	if game.boss_spawn_evaluated:
		return
	if game.level_timer < game.current_level_time_limit:
		return
	game.boss_spawn_evaluated = true
	if _any_unlit_white_cell():
		_spawn_boss()

# Does a straight, unbroken line (same row or same column, no wall cell in
# between) connect these two cells? Same rule a bulb's light already
# follows -- used so the boss's ranged attack "cannot go through walls".

func _has_line_of_sight(from_row: int, from_col: int, to_row: int, to_col: int) -> bool:
	if from_row == to_row:
		var low_col: int = min(from_col, to_col)
		var high_col: int = max(from_col, to_col)
		for col in range(low_col + 1, high_col):
			if game.puzzle_mgr.is_black(from_row, col):
				return false
		return true
	if from_col == to_col:
		var low_row: int = min(from_row, to_row)
		var high_row: int = max(from_row, to_row)
		for row in range(low_row + 1, high_row):
			if game.puzzle_mgr.is_black(row, from_col):
				return false
		return true
	return false

func _tick_enemy_ai(delta: float) -> void:
	var living_player_indices: Array[int] = []
	for player_index in range(game.players.size()):
		if not game.players[player_index]["is_defeated"]:
			living_player_indices.append(player_index)
	if living_player_indices.is_empty() or game.enemies.is_empty():
		return

	var enemy_snapshot_changed: bool = false

	for enemy_state: Dictionary in game.enemies:
		if enemy_state["is_dying"]:
			continue  # already resolved -- just playing out its death pose, no AI while that finishes

		# Cooldowns tick every frame regardless of what the enemy is doing, so
		# they don't freeze mid-countdown while it walks around.
		enemy_state["attack_cooldown_timer"] = maxf(0.0, enemy_state["attack_cooldown_timer"] - delta)
		enemy_state["move_cooldown_timer"] = maxf(0.0, enemy_state["move_cooldown_timer"] - delta)

		var is_boss: bool = enemy_state["is_boss"]

		# 1. Anyone adjacent? Melee wins over everything.
		var target_index: int = _find_melee_target(enemy_state, living_player_indices)
		if target_index != -1:
			_tick_enemy_melee_attack(enemy_state, game.players[target_index], target_index, is_boss)
			continue

		# 2. Boss: anyone in line of sight? Shoot them.
		if is_boss:
			target_index = _find_ranged_target(enemy_state, living_player_indices)
			if target_index != -1:
				_tick_boss_ranged_attack(enemy_state, game.players[target_index], target_index)
				continue

		# 3. Otherwise walk toward the nearest player by path.
		if enemy_state["move_cooldown_timer"] <= 0.0:
			enemy_state["move_cooldown_timer"] = ENEMY_MOVE_INTERVAL
			if _step_enemy_toward(enemy_state, living_player_indices):
				enemy_snapshot_changed = true

	if enemy_snapshot_changed:
		_broadcast_enemy_snapshot()

func _tick_enemy_melee_attack(enemy_state: Dictionary, target_player_state: Dictionary, target_player_index: int, is_boss: bool) -> void:
	if enemy_state["attack_cooldown_timer"] > 0.0:
		return
	enemy_state["attack_cooldown_timer"] = ENEMY_ATTACK_INTERVAL
	var damage: int = BOSS_MELEE_DAMAGE if is_boss else ENEMY_ATTACK_DAMAGE
	game.player_mgr._damage_player(target_player_state, target_player_index, damage)
	game.combat_mgr._flash_enemy_attack(enemy_state["id"])

func _tick_boss_ranged_attack(enemy_state: Dictionary, target_player_state: Dictionary, target_player_index: int) -> void:
	if enemy_state["attack_cooldown_timer"] > 0.0:
		return
	enemy_state["attack_cooldown_timer"] = BOSS_RANGED_ATTACK_INTERVAL
	game.combat_mgr._spawn_projectile(enemy_state["row"], enemy_state["col"], target_player_state["row"], target_player_state["col"], enemy_state["id"])
	game.player_mgr._damage_player(target_player_state, target_player_index, BOSS_RANGED_DAMAGE, true)

# Purely cosmetic -- damage above is already applied the instant the shot
# fires, this just gives it something to look at. Broadcast to all peers
# (fire-and-forget, no id/reconciliation needed since it's transient and
# self-expiring).

# Nearest adjacent (or same-cell) player, or -1.
func _find_melee_target(enemy_state: Dictionary, living_player_indices: Array[int]) -> int:
	var best_index: int = -1
	var best_distance: int = 999999
	for player_index: int in living_player_indices:
		var player_state: Dictionary = game.players[player_index]
		var distance: int = abs(enemy_state["row"] - player_state["row"]) + abs(enemy_state["col"] - player_state["col"])
		if distance <= 1 and distance < best_distance:
			best_distance = distance
			best_index = player_index
	return best_index

# Nearest player with a clear straight line to the boss, or -1.
func _find_ranged_target(enemy_state: Dictionary, living_player_indices: Array[int]) -> int:
	var best_index: int = -1
	var best_distance: int = 999999
	for player_index: int in living_player_indices:
		var player_state: Dictionary = game.players[player_index]
		if not _has_line_of_sight(enemy_state["row"], enemy_state["col"], player_state["row"], player_state["col"]):
			continue
		var distance: int = abs(enemy_state["row"] - player_state["row"]) + abs(enemy_state["col"] - player_state["col"])
		if distance < best_distance:
			best_distance = distance
			best_index = player_index
	return best_index

# Moves one grid step along the shortest walkable route to the nearest living
# player (BFS, so it routes around walls instead of getting stuck on them),
# treating cells held by other living enemies as blocked so enemies don't
# stack. Returns true if it actually moved.
func _step_enemy_toward(enemy_state: Dictionary, living_player_indices: Array[int]) -> bool:
	var start := Vector2i(enemy_state["col"], enemy_state["row"])

	var player_cells: Dictionary = {}
	for player_index: int in living_player_indices:
		var player_state: Dictionary = game.players[player_index]
		player_cells[Vector2i(player_state["col"], player_state["row"])] = true

	# Cells held by other living enemies. Read live, so an enemy that already
	# moved earlier this same tick is accounted for. Dying enemies don't block.
	var occupied: Dictionary = {}
	for other: Dictionary in game.enemies:
		if other["id"] != enemy_state["id"] and not other["is_dying"]:
			occupied[Vector2i(other["col"], other["row"])] = true

	var step: Vector2i = _bfs_first_step(start, player_cells, occupied)
	if step == start:
		# Crowd is blocking every route. Path through them, but only advance
		# if the next cell is actually free; otherwise wait in line.
		step = _bfs_first_step(start, player_cells, {})
		if step == start or occupied.has(step):
			return false

	enemy_state["animation_from"] = enemy_state["visual_position"]
	enemy_state["row"] = step.y
	enemy_state["col"] = step.x
	enemy_state["animation_to"] = Vector2(step.x, step.y)
	enemy_state["animation_progress"] = 0.0
	return true

# Returns the first cell to step into on the shortest route from `start` to any
# cell in `goals`, or `start` itself if there's no route. Cells in `blocked`
# can't be entered (unless they're also a goal).
func _bfs_first_step(start: Vector2i, goals: Dictionary, blocked: Dictionary) -> Vector2i:
	var came_from: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	var goal: Vector2i = start

	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if goals.has(current):
			goal = current
			break
		for direction: Vector2i in MOVE_DIRECTIONS:
			var next: Vector2i = current + direction
			if came_from.has(next):
				continue
			if next.y < 0 or next.y >= game.rows or next.x < 0 or next.x >= game.cols:
				continue
			if game.puzzle_mgr.is_black(next.y, next.x):
				continue
			if blocked.has(next) and not goals.has(next):
				continue
			came_from[next] = current
			queue.append(next)

	if goal == start:
		return start
	var step: Vector2i = goal
	while came_from[step] != start:
		step = came_from[step]
	return step

@rpc("authority", "call_local", "reliable")
func _sync_enemies(snapshot: Array) -> void:
	_apply_enemy_snapshot(snapshot)

func _apply_enemy_snapshot(snapshot: Array) -> void:
	var existing_by_id: Dictionary = {}
	for enemy_state: Dictionary in game.enemies:
		existing_by_id[enemy_state["id"]] = enemy_state

	var reconciled_enemies: Array[Dictionary] = []
	for entry: Dictionary in snapshot:
		var enemy_id: int = entry["id"]
		var new_row: int = entry["row"]
		var new_col: int = entry["col"]
		var new_health: int = entry["health"]
		var new_max_health: int = entry["max_health"]
		var new_is_boss: bool = entry["is_boss"]
		var new_is_dying: bool = entry.get("is_dying", false)

		if existing_by_id.has(enemy_id):
			var enemy_state: Dictionary = existing_by_id[enemy_id]
			if new_health < enemy_state["health"] and not new_is_dying:
				_trigger_hurt(enemy_state)
			enemy_state["health"] = new_health
			enemy_state["max_health"] = new_max_health
			enemy_state["is_boss"] = new_is_boss
			if new_is_dying and not enemy_state["is_dying"]:
				enemy_state["is_dying"] = true
				enemy_state["death_progress"] = 0.0
			if enemy_state["row"] != new_row or enemy_state["col"] != new_col:
				enemy_state["animation_from"] = enemy_state["visual_position"]
				enemy_state["row"] = new_row
				enemy_state["col"] = new_col
				enemy_state["animation_to"] = Vector2(new_col, new_row)
				enemy_state["animation_progress"] = 0.0
			reconciled_enemies.append(enemy_state)
		else:
			var created_state: Dictionary = _create_enemy_state(enemy_id, new_row, new_col, new_health, new_max_health, new_is_boss)
			created_state["is_dying"] = new_is_dying  # rare (e.g. a client joining mid-death-animation) but shouldn't resurrect it visually
			reconciled_enemies.append(created_state)

	game.enemies = reconciled_enemies

# ---------------------------------------------------------------------------
# Combat simulation -- host-only (or singleplayer, which is trivially its
# own host). Conflict timer -> enemy spawns; enemy AI movement/attacks;
# player respawn timing. Never runs on non-host clients, who only ever
# render state the host has broadcast.
# ---------------------------------------------------------------------------

func _build_enemy_snapshot() -> Array:
	var snapshot: Array = []
	for enemy_state: Dictionary in game.enemies:
		snapshot.append({
			"id": enemy_state["id"],
			"row": enemy_state["row"],
			"col": enemy_state["col"],
			"health": enemy_state["health"],
			"max_health": enemy_state["max_health"],
			"is_boss": enemy_state["is_boss"],
			"is_dying": enemy_state["is_dying"],
		})
	return snapshot

func _broadcast_enemy_snapshot() -> void:
	var snapshot: Array = _build_enemy_snapshot()
	if NetworkManager.is_multiplayer:
		game.rpc("_sync_enemies", snapshot)
	else:
		_apply_enemy_snapshot(snapshot)

# Host-only (see _tick_combat_simulation): counts down the death pose for
# any enemy marked is_dying, and once it's finished actually drops that
# enemy from game.enemies and broadcasts the resulting snapshot -- which,
# lacking that id, is what makes it disappear on every peer. Kept separate
# from the instant-remove that used to happen in
# CombatManager._damage_enemy_by_id so the death animation has time to play
# out first instead of the enemy just vanishing the instant it hits 0 hp.
func _tick_enemy_death_timers(delta: float) -> void:
	var any_removed: bool = false
	var remaining: Array[Dictionary] = []
	for enemy_state: Dictionary in game.enemies:
		if enemy_state["is_dying"]:
			var death_timer: float = enemy_state["death_timer"] - delta
			if death_timer <= 0.0:
				any_removed = true
				continue
			enemy_state["death_timer"] = death_timer
		remaining.append(enemy_state)
	if any_removed:
		game.enemies = remaining
		_broadcast_enemy_snapshot()

func _advance_enemy_animations(delta: float) -> bool:
	var any_animating: bool = false
	for enemy_state: Dictionary in game.enemies:
		var animation_progress: float = enemy_state["animation_progress"]
		if animation_progress < 1.0:
			animation_progress = min(animation_progress + delta / game.MOVE_ANIMATION_DURATION, 1.0)
			enemy_state["animation_progress"] = animation_progress
			var eased_progress: float = ease(animation_progress, -2.0)
			var from_position: Vector2 = enemy_state["animation_from"]
			var to_position: Vector2 = enemy_state["animation_to"]
			enemy_state["visual_position"] = from_position.lerp(to_position, eased_progress)
			var step: Vector2 = to_position - from_position
			if step != Vector2.ZERO:
				if abs(step.x) > abs(step.y):
					enemy_state["facing"] = 3 if step.x > 0.0 else 2
				else:
					enemy_state["facing"] = 0 if step.y > 0.0 else 1
			any_animating = true

		var spawn_progress: float = enemy_state["spawn_progress"]
		if spawn_progress < 1.0:
			enemy_state["spawn_progress"] = min(spawn_progress + delta / SPAWN_ANIMATION_DURATION, 1.0)
			any_animating = true

		var attack_flash_timer: float = enemy_state["attack_flash_timer"]
		if attack_flash_timer > 0.0:
			enemy_state["attack_flash_timer"] = max(0.0, attack_flash_timer - delta)
			any_animating = true

		var hurt_timer: float = enemy_state["hurt_timer"]
		if hurt_timer > 0.0:
			enemy_state["hurt_timer"] = max(0.0, hurt_timer - delta)

		var action_anim: String = enemy_state["action_anim"]
		if action_anim != "":
			var action_duration: float = RANGED_ANIMATION_DURATION if action_anim == "ranged" else ATTACK_ANIMATION_DURATION
			var action_progress: float = min(enemy_state["action_progress"] + delta / action_duration, 1.0)
			enemy_state["action_progress"] = action_progress
			any_animating = true
			if action_progress >= 1.0:
				enemy_state["action_anim"] = ""

		if enemy_state["is_dying"]:
			var death_progress: float = enemy_state["death_progress"]
			if death_progress < 1.0:
				enemy_state["death_progress"] = min(death_progress + delta / DEATH_ANIMATION_DURATION, 1.0)
				any_animating = true

		var anim_name: String = _select_animation(enemy_state)
		if anim_name != enemy_state["anim_name"]:
			enemy_state["anim_name"] = anim_name
			enemy_state["anim_time"] = 0.0
		else:
			enemy_state["anim_time"] += delta
		if anim_name != "":
			any_animating = true  # idle/move loop, so keep redrawing
	return any_animating

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _draw_enemies() -> void:
	for enemy_state: Dictionary in game.enemies:
		var visual_position: Vector2 = enemy_state["visual_position"]
		var top_left: Vector2 = game._tile_to_pixel(visual_position.y, visual_position.x)
		var body_center: Vector2 = game._tile_center_to_pixel(visual_position.y, visual_position.x)
		var is_boss: bool = enemy_state["is_boss"]
		var is_dying: bool = enemy_state["is_dying"]

		var spawn_progress: float = enemy_state["spawn_progress"]
		var spawn_eased: float = ease(spawn_progress, -2.0)
		var spawn_scale: float = lerp(0.25, 1.0, spawn_eased)
		var spawn_alpha: float = spawn_eased
		var attack_flash: float = enemy_state["attack_flash_timer"] / game.combat_mgr.ATTACK_FLASH_DURATION

		# Dying shrinks and fades the whole thing out over DEATH_ANIMATION_DURATION,
		# on top of whatever art is drawn below (dedicated death sheet, plain
		# static texture, or the fallback shape) -- so even a project with no
		# death art at all still gets a readable "this one's finished" cue.
		var death_eased: float = ease(enemy_state["death_progress"], -2.0) if is_dying else 0.0
		var render_alpha: float = spawn_alpha * (1.0 - death_eased)
		var render_scale: float = spawn_scale * lerp(1.0, 0.35, death_eased)

		var anim_name: String = enemy_state["anim_name"]
		var active_sheet: Texture2D = _get_sheet(is_boss, anim_name) if anim_name != "" else null

		var sprite_size: float = game.CELL_SIZE * (0.85 if is_boss else 0.55) * render_scale
		var destination_rectangle: Rect2 = Rect2(
			body_center.x - sprite_size / 2.0, body_center.y - sprite_size / 2.0,
			sprite_size, sprite_size
		)

		if active_sheet != null:
			var def: Dictionary = ANIMS["boss" if is_boss else "enemy"][anim_name]
			var frames: int = _frame_count(active_sheet, def)
			var rows: int = def["rows"]
			var frame_size: Vector2 = Vector2(float(active_sheet.get_width()) / frames, float(active_sheet.get_height()) / rows)
			var frame_index: int = _anim_frame(active_sheet, def, enemy_state["anim_time"])
			var row: int = mini(enemy_state["facing"], rows - 1)
			var source_rectangle: Rect2 = Rect2(Vector2(frame_index * frame_size.x, row * frame_size.y), frame_size)
			game.draw_texture_rect_region(active_sheet, destination_rectangle, source_rectangle, Color(1, 1, 1, render_alpha))
		else:
			# Only a boss can get here (boss tier 4 has no art yet): static image,
			# then a plain drawn shape. Regular enemies always have their sheets.
			var static_texture: Texture2D = _get_boss_texture()
			if static_texture != null:
				game.draw_texture_rect(static_texture, destination_rectangle, false, Color(1, 1, 1, render_alpha))
			else:
				var body_radius: float = game.CELL_SIZE * 0.35 * render_scale
				var body_color: Color = game.BOSS_COLOR
				body_color.a = render_alpha
				game.draw_circle(body_center, body_radius, body_color)
				game.draw_arc(body_center, body_radius, 0.0, TAU, 16, Color(body_color.darkened(0.5), render_alpha), 3.0)

		if attack_flash > 0.0 and not is_dying:
			var flash_radius: float = game.CELL_SIZE * (0.5 if is_boss else 0.35) * (1.0 + 0.5 * (1.0 - attack_flash))
			game.draw_arc(body_center, flash_radius, 0.0, TAU, 16, Color(1, 0.9, 0.4, attack_flash), 3.0)

		if not is_dying:
			var max_health: int = enemy_state["max_health"]
			var health_fraction: float = float(enemy_state["health"]) / float(max_health)
			var bar_width: float = game.CELL_SIZE * (0.7 if is_boss else 0.5)
			var bar_height: float = 5.0
			var bar_y_offset: float = -8.0 if is_boss else 4.0
			var bar_position: Vector2 = Vector2(body_center.x - bar_width / 2.0, top_left.y + bar_y_offset)
			game.draw_rect(Rect2(bar_position, Vector2(bar_width, bar_height)), Color(0.2, 0.2, 0.2, spawn_alpha))
			game.draw_rect(Rect2(bar_position, Vector2(bar_width * health_fraction, bar_height)), Color(0.9, 0.2, 0.2, spawn_alpha))

func _spawn_enemy_from_conflict() -> void:
	var conflict_positions: Array = game.conflicting_bulbs.keys()
	if conflict_positions.is_empty():
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var spawn_position: Array = conflict_positions[rng.randi_range(0, conflict_positions.size() - 1)]
	game.enemies.append(_create_enemy_state(game.next_enemy_id, spawn_position[0], spawn_position[1], ENEMY_MAX_HEALTH, ENEMY_MAX_HEALTH, false))
	game.next_enemy_id += 1
	_broadcast_enemy_snapshot()

func _any_unlit_white_cell() -> bool:
	for row in range(game.rows):
		for col in range(game.cols):
			if game.grid[row][col]["type"] == game.CellType.WHITE and not game.lit[row][col]:
				return true
	return false
