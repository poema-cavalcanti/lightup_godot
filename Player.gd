extends RefCounted
# Player character logic: movement, bulb input triggers, health, attack input, respawn, drawing.
# Split out of Game.gd -- operates on shared board/combat state via the `game` back-reference.

var game: Node2D

func _init(game_ref: Node2D) -> void:
	game = game_ref

const PLAYER_COLORS: Array[Color] = [
	Color(0.15, 0.65, 0.95),  # P1 blue
	Color(0.90, 0.25, 0.55),  # P2 pink
	Color(0.25, 0.80, 0.35),  # P3 green
	Color(0.95, 0.60, 0.10),  # P4 orange
]
const PLAYER_OFFSETS: Array[Vector2] = [
	Vector2(-6, -6), Vector2(6, -6), Vector2(-6, 6), Vector2(6, 6),
]
const PLAYER_SHEET_FRAME_WIDTH: int = 32
const PLAYER_SHEET_FRAME_HEIGHT: int = 32
const PLAYER_SHEET_FRAME_COUNT: int = 4
const PLAYER_SHEET_DIRECTION_ROWS: Dictionary = {
	"down": 0, "right": 2, "up": 4,
	# "left" isn't a row of its own -- the sheet only has one side view
	# (row 2, "right"); facing left reuses that same row and gets flipped
	# horizontally at draw time instead (see _draw_players below).
}
const PLAYER_ANIMATION_FRAME_DURATION: float = 0.12
const SPAWN_ANIMATION_DURATION: float = 0.4  # fade/scale-in on first spawn and on respawn
const MELEE_BLOCK_DAMAGE_MULTIPLIER: float = 0.75  # 25% reduction while blocking; ranged is fully negated
const OWN_AVATAR_RING_ALPHA: float = 0.55  # the "this one's you" ring, kept translucent so it doesn't overpower the sprite

# --- Attack / interact sheets: same 32x32, down/right/up (+mirrored left) --
# --- row layout as the walk sheet above, just with a different column    --
# --- count each, so they reuse PLAYER_SHEET_DIRECTION_ROWS and the same  --
# --- left-facing source-rect flip trick.                                 --
const PLAYER_ATTACK_SHEET_FRAME_COUNT: int = 7
const PLAYER_INTERACT_SHEET_FRAME_COUNT: int = 4
const INTERACT_ANIMATION_DURATION: float = 0.3  # one-shot pose played on bulb place/remove
const BLOCK_LOOP_FRAME_DURATION: float = 0.15  # frame pace of the continuous held-guard pose
const PLAYER_IDLE_SHEET_FRAME_COUNT: int = 4
const PLAYER_RUN_SHEET_FRAME_COUNT: int = 6
const PLAYER_IDLE_FRAME_DURATION: float = 0.25  # slower, restful pace for standing still

# Equipped-armor overlay placement (see _draw_equipped_armor_overlay). How
# many *source* pixels above the body frame's own top edge the overlay art's
# (0, 0) pixel lands depends on which body sheet is showing, since each
# sheet poses the head at a slightly different height. Attack is 0 for when
# its own art exists; for now it borrows run's art (see ItemData's
# OVERLAY_ART_FALLBACK) but keeps this 0. Body frame counts are here so an
# overlay strip with a different count (attack's 7 body frames vs run's 6
# hat frames) can be mapped proportionally instead of running off its end.
const OVERLAY_TOP_OFFSET_PIXELS: Dictionary = {"walk": 1, "idle": 2, "interact": 0, "run": 2, "attack": 0}
const OVERLAY_BODY_FRAME_COUNTS: Dictionary = {"walk": 4, "idle": 4, "interact": 4, "run": 6, "attack": 7}

# --- Hold-to-move: local input state only (not synced -- each peer tracks --
# --- only its own keyboard), so this lives as a single instance on the    --
# --- singleton player_mgr rather than in any per-player Dictionary. See   --
# --- MoveRepeater.gd for the timing itself (shared with Town.gd).        --
var move_repeater: MoveRepeater = MoveRepeater.new()

func _create_player_state(starting_row: int, starting_col: int) -> Dictionary:
	var starting_visual_position: Vector2 = Vector2(starting_col, starting_row)
	return {
		"row": starting_row,
		"col": starting_col,
		"visual_position": starting_visual_position,
		"animation_from": starting_visual_position,
		"animation_to": starting_visual_position,
		"animation_progress": 1.0,
		"facing_direction": "down",
		"animation_frame_index": 0,
		"animation_timer": 0.0,
		"idle_frame_index": 0,
		"idle_timer": 0.0,
		"health": game.COMBAT_MAX_HEALTH,
		"is_defeated": false,
		"respawn_timer": 0.0,
		"attack_cooldown_timer": 0.0,
		"attack_flash_timer": 0.0,
		"spawn_progress": 0.0,
		"is_blocking": false,
		"action_anim": "",  # "" (walk sheet) | "attack" | "interact" -- one-shot pose overlay
		"action_progress": 1.0,
		"action_frame_index": 0,
		"block_anim_timer": 0.0,
		"block_anim_frame_index": 0,
	}

# Starts (or restarts) a one-shot attack/interact pose for a player; called
# from CombatManager (on attack) and PuzzleBoard (on bulb place/remove),
# both of which already broadcast the triggering event to every peer the
# same way, so this only ever needs to run locally in response to that.
func _trigger_action_animation(player_index: int, action_name: String) -> void:
	if player_index < 0 or player_index >= game.players.size():
		return
	var player_state: Dictionary = game.players[player_index]
	player_state["action_anim"] = action_name
	player_state["action_progress"] = 0.0
	player_state["action_frame_index"] = 0

func _handle_move_input(delta_row: int, delta_col: int) -> void:
	if NetworkManager.is_multiplayer and not game.multiplayer.is_server():
		game.rpc_id(1, "_request_move", game.my_player_index, delta_row, delta_col)
	else:
		_request_move(game.my_player_index, delta_row, delta_col)

# --- Hold-to-move -----------------------------------------------------------
# The timing itself lives in MoveRepeater (shared with Town.gd); this is
# just the glue to this scene's specific "what does a move actually do"
# (an RPC-aware request, see _handle_move_input) and "is a move even
# allowed right now" (the local player's hop animation).

func _is_move_keycode(keycode: int) -> bool:
	return MoveRepeater.is_move_keycode(keycode)

# Called from Game._input for every non-echo press/release of a movement
# key. A press moves immediately (so a quick tap still feels instant).
func _handle_move_key_event(keycode: int, is_pressed: bool) -> void:
	var delta: Array = move_repeater.handle_key_event(keycode, is_pressed)
	if not delta.is_empty():
		_handle_move_input(delta[0], delta[1])

# Called every frame from Game._process.
func _tick_move_repeat(delta_time: float) -> void:
	var is_hop_in_progress: bool = false
	if game.my_player_index >= 0 and game.my_player_index < game.players.size():
		is_hop_in_progress = game.players[game.my_player_index]["animation_progress"] < 1.0
	var delta: Array = move_repeater.tick(delta_time, is_hop_in_progress, game.MOVE_ANIMATION_DURATION)
	if not delta.is_empty():
		_handle_move_input(delta[0], delta[1])

# Safety net for anything that should stop a held direction from repeating
# without a matching key-release event reaching _input -- opening the pause
# menu, and the window losing OS focus entirely (alt-tab etc., where the
# key-up can happen while this game never sees it).
func _clear_held_move_keys() -> void:
	move_repeater.clear()

@rpc("any_peer", "call_remote", "reliable")
func _request_move(player_index: int, delta_row: int, delta_col: int) -> void:
	if NetworkManager.is_multiplayer and not game.multiplayer.is_server():
		return  # only the host may apply moves
	if not NetworkManager.validate_request(player_index, game.players.size(), "move", 0.08):
		return
	if abs(delta_row) + abs(delta_col) != 1:
		return  # exactly one orthogonal step; anything else is a teleport attempt
	var player_state: Dictionary = game.players[player_index]
	if player_state["is_defeated"]:
		return
	var next_row: int = player_state["row"] + delta_row
	var next_col: int = player_state["col"] + delta_col
	if next_row < 0 or next_row >= game.rows or next_col < 0 or next_col >= game.cols or game.puzzle_mgr.is_black(next_row, next_col):
		return
	if NetworkManager.is_multiplayer:
		game.rpc("_sync_player_position", player_index, next_row, next_col)
	else:
		_sync_player_position(player_index, next_row, next_col)

@rpc("authority", "call_local", "reliable")
func _sync_player_position(player_index: int, row: int, col: int) -> void:
	var player_state: Dictionary = game.players[player_index]
	var delta_row: int = row - player_state["row"]
	var delta_col: int = col - player_state["col"]
	if delta_row < 0:
		player_state["facing_direction"] = "up"
	elif delta_row > 0:
		player_state["facing_direction"] = "down"
	elif delta_col < 0:
		player_state["facing_direction"] = "left"
	elif delta_col > 0:
		player_state["facing_direction"] = "right"
	player_state["animation_from"] = player_state["visual_position"]
	player_state["row"] = row
	player_state["col"] = col
	player_state["animation_to"] = Vector2(col, row)
	player_state["animation_progress"] = 0.0
	# no game.queue_redraw() here -- game._process() drives redraws while this hop animates

func _damage_player(player_state: Dictionary, player_index: int, amount: int, is_ranged: bool = false) -> void:
	if player_state["is_defeated"]:
		return
	var effective_amount: int = amount
	if player_state["is_blocking"]:
		effective_amount = 0 if is_ranged else int(round(amount * MELEE_BLOCK_DAMAGE_MULTIPLIER))
	if not is_ranged and effective_amount > 0:
		effective_amount = int(round(effective_amount * _get_melee_damage_multiplier()))
	var new_health: int = max(0, player_state["health"] - effective_amount)
	var new_is_defeated: bool = new_health <= 0
	if NetworkManager.is_multiplayer:
		game.rpc("_sync_player_health", player_index, new_health, new_is_defeated)
	else:
		_apply_player_health_update(player_state, player_index, new_health, new_is_defeated)

# Passive melee damage reduction from whatever's equipped in the "armor"
# slot (see ItemData's "melee_damage_reduction" field) -- 1.0 = no
# reduction. Stacks multiplicatively with the blocking reduction above
# (applied after it, in _damage_player); never applies to ranged damage,
# since armor here doesn't claim to stop that.
func _get_melee_damage_multiplier() -> float:
	if not CampaignManager.is_campaign_active:
		return 1.0
	var armor_item_id: String = CampaignManager.get_equipped_item_id("armor")
	if armor_item_id == "":
		return 1.0
	var item: Dictionary = ItemData.get_item(armor_item_id)
	return 1.0 - float(item.get("melee_damage_reduction", 0.0))

@rpc("authority", "call_local", "reliable")
func _sync_player_health(player_index: int, health: int, is_defeated: bool) -> void:
	_apply_player_health_update(game.players[player_index], player_index, health, is_defeated)

func _apply_player_health_update(player_state: Dictionary, player_index: int, new_health: int, new_is_defeated: bool) -> void:
	var was_defeated: bool = player_state["is_defeated"]
	player_state["health"] = new_health
	player_state["is_defeated"] = new_is_defeated
	if new_is_defeated and not was_defeated:
		player_state["respawn_timer"] = 0.0
		# Dying closes the inventory overlay (it only exists in a campaign, so
		# it's null otherwise). Only for the local player, so a teammate going
		# down in multiplayer can't yank it shut.
		if player_index == game.my_player_index and game.inventory_panel != null:
			game.inventory_panel.close()
	game.queue_redraw()

func _respawn_player(player_index: int) -> void:
	var spawn_positions: Array = BoardUtil.corner_positions(game.current_puzzle_rows, game.players.size())
	var spawn_position: Array = spawn_positions[player_index]
	if NetworkManager.is_multiplayer:
		game.rpc("_sync_player_respawn", player_index, spawn_position[0], spawn_position[1])
	else:
		_apply_player_respawn(player_index, spawn_position[0], spawn_position[1])

@rpc("authority", "call_local", "reliable")
func _sync_player_respawn(player_index: int, row: int, col: int) -> void:
	_apply_player_respawn(player_index, row, col)

func _apply_player_respawn(player_index: int, row: int, col: int) -> void:
	game.players[player_index] = _create_player_state(row, col)
	game.queue_redraw()

# Whether the local player is up and about -- the inventory's can_open gate
# (see GameUIManager._build_ui()). True if the local player can't be found.
func _is_local_player_alive() -> bool:
	if game.my_player_index < 0 or game.my_player_index >= game.players.size():
		return true
	return not game.players[game.my_player_index]["is_defeated"]

func _all_players_defeated() -> bool:
	for player_state: Dictionary in game.players:
		if not player_state["is_defeated"]:
			return false
	return true

# --- Reset / New Puzzle: host (or singleplayer) only, buttons don't exist --
# --- for anyone else, so no request/host-routing layer is needed here.   --

func _tick_player_respawns(party_wiped: bool) -> void:
	if party_wiped:
		return  # nobody auto-respawns during a full wipe -- only Reset recovers
	for player_index in range(game.players.size()):
		var player_state: Dictionary = game.players[player_index]
		if player_state["is_defeated"] and player_state["respawn_timer"] >= game.RESPAWN_DURATION:
			_respawn_player(player_index)

func _tick_respawn_display_timers(delta: float) -> void:
	if _all_players_defeated():
		return  # frozen during a full wipe -- nothing is actually counting down
	for player_state: Dictionary in game.players:
		if player_state["is_defeated"] and player_state["respawn_timer"] < game.RESPAWN_DURATION:
			player_state["respawn_timer"] = min(player_state["respawn_timer"] + delta, game.RESPAWN_DURATION)

func _advance_player_animations(delta: float) -> bool:
	var any_animating: bool = false
	for player_state: Dictionary in game.players:
		var animation_progress: float = player_state["animation_progress"]
		if animation_progress < 1.0:
			animation_progress = min(animation_progress + delta / game.MOVE_ANIMATION_DURATION, 1.0)
			player_state["animation_progress"] = animation_progress
			var eased_progress: float = ease(animation_progress, -2.0)
			var from_position: Vector2 = player_state["animation_from"]
			var to_position: Vector2 = player_state["animation_to"]
			player_state["visual_position"] = from_position.lerp(to_position, eased_progress)
			any_animating = true

			var run_frame_count: int = PLAYER_RUN_SHEET_FRAME_COUNT
			var animation_timer: float = player_state["animation_timer"] + delta
			if animation_timer >= PLAYER_ANIMATION_FRAME_DURATION:
				animation_timer = 0.0
				var frame_index: int = player_state["animation_frame_index"]
				player_state["animation_frame_index"] = (frame_index + 1) % run_frame_count
			player_state["animation_timer"] = animation_timer
		else:
			player_state["animation_timer"] = 0.0
			player_state["animation_frame_index"] = 0

			# Idle loops continuously (not just reset-and-wait) for as long
			# as the player stands still, independent of animation_progress
			# above -- that one only exists while a hop is actually playing.
			var idle_timer: float = player_state["idle_timer"] + delta
			if idle_timer >= PLAYER_IDLE_FRAME_DURATION:
				idle_timer = 0.0
				var idle_frame_index: int = player_state["idle_frame_index"]
				player_state["idle_frame_index"] = (idle_frame_index + 1) % PLAYER_IDLE_SHEET_FRAME_COUNT
			player_state["idle_timer"] = idle_timer
			any_animating = true

		var spawn_progress: float = player_state["spawn_progress"]
		if spawn_progress < 1.0:
			player_state["spawn_progress"] = min(spawn_progress + delta / SPAWN_ANIMATION_DURATION, 1.0)
			any_animating = true

		var attack_flash_timer: float = player_state["attack_flash_timer"]
		if attack_flash_timer > 0.0:
			player_state["attack_flash_timer"] = max(0.0, attack_flash_timer - delta)
			any_animating = true

		var action_anim: String = player_state["action_anim"]
		if action_anim != "":
			var action_duration: float = game.combat_mgr.ATTACK_FLASH_DURATION if action_anim == "attack" else INTERACT_ANIMATION_DURATION
			var action_frame_count: int = PLAYER_ATTACK_SHEET_FRAME_COUNT if action_anim == "attack" else PLAYER_INTERACT_SHEET_FRAME_COUNT
			var action_progress: float = min(player_state["action_progress"] + delta / action_duration, 1.0)
			player_state["action_progress"] = action_progress
			player_state["action_frame_index"] = min(int(action_progress * action_frame_count), action_frame_count - 1)
			any_animating = true
			if action_progress >= 1.0:
				player_state["action_anim"] = ""

		# Continuous held-guard pose -- ticks only while blocking is actually
		# down, independent of the one-shot action_anim above (blocking can
		# be held right through an attack/interact pose finishing).
		if player_state["is_blocking"]:
			var block_anim_timer: float = player_state["block_anim_timer"] + delta
			if block_anim_timer >= BLOCK_LOOP_FRAME_DURATION:
				block_anim_timer = 0.0
				player_state["block_anim_frame_index"] = (player_state["block_anim_frame_index"] + 1) % PLAYER_INTERACT_SHEET_FRAME_COUNT
			player_state["block_anim_timer"] = block_anim_timer
			any_animating = true
		else:
			player_state["block_anim_timer"] = 0.0
			player_state["block_anim_frame_index"] = 0
	return any_animating

func _draw_players() -> void:
	for player_index in range(game.players.size()):
		var player_state: Dictionary = game.players[player_index]
		var player_color: Color = PLAYER_COLORS[player_index % PLAYER_COLORS.size()]
		if player_state["is_defeated"]:
			player_color = player_color.darkened(0.6)
			player_color.a = 0.5
		var visual_position: Vector2 = player_state["visual_position"]
		var top_left: Vector2 = game._tile_to_pixel(visual_position.y, visual_position.x)

		var spawn_progress: float = player_state["spawn_progress"]
		var spawn_eased: float = ease(spawn_progress, -2.0)
		var spawn_scale: float = lerp(0.3, 1.0, spawn_eased)
		var is_blocking: bool = player_state["is_blocking"]
		var outline_color: Color = player_color
		if is_blocking:
			outline_color = outline_color.lerp(Color(0.35, 0.75, 1.0), 0.85)
		outline_color.a *= spawn_eased
		var outline_inset: float = (game.CELL_SIZE - 4) * (1.0 - spawn_scale) * 0.5
		game.draw_rect(Rect2(top_left.x + 2 + outline_inset, top_left.y + 2 + outline_inset, (game.CELL_SIZE - 4) * spawn_scale, (game.CELL_SIZE - 4) * spawn_scale), outline_color, false, 4.0)

		var health_fraction: float = float(player_state["health"]) / float(game.COMBAT_MAX_HEALTH)
		var bar_width: float = game.CELL_SIZE * 0.5
		var bar_height: float = 4.0
		var bar_position: Vector2 = Vector2(top_left.x + game.CELL_SIZE * 0.5 - bar_width / 2.0, top_left.y - 2.0)
		game.draw_rect(Rect2(bar_position, Vector2(bar_width, bar_height)), Color(0.2, 0.2, 0.2, spawn_eased))
		game.draw_rect(Rect2(bar_position, Vector2(bar_width * health_fraction, bar_height)), Color(0.3, 0.85, 0.3, spawn_eased))

		var sprite_offset: Vector2 = PLAYER_OFFSETS[player_index % PLAYER_OFFSETS.size()]
		var body_center: Vector2 = game._tile_center_to_pixel(visual_position.y, visual_position.x) + sprite_offset
		# Only meaningful with more than one player sharing the board --
		# skip the ring entirely in singleplayer, where there's nothing to
		# tell yourself apart from.
		var is_own_avatar: bool = player_index == game.my_player_index and game.players.size() > 1

		# Sheet priority: an in-progress one-shot attack/interact pose wins,
		# then a continuous held-guard pose while blocking, then run (while
		# a hop is in progress) or idle (while standing still).
		var active_texture: Texture2D
		var active_frame_index: int
		# Which sheet kind is showing, for picking the matching equipped-armor
		# overlay art and offset (see _draw_equipped_armor_overlay).
		var overlay_kind: String
		var action_anim: String = player_state["action_anim"]
		var is_moving: bool = player_state["animation_progress"] < 1.0
		if action_anim == "attack":
			active_texture = game.player_attack_sheet_texture
			active_frame_index = player_state["action_frame_index"]
			overlay_kind = "attack"
		elif action_anim == "interact":
			active_texture = game.player_interact_sheet_texture
			active_frame_index = player_state["action_frame_index"]
			overlay_kind = "interact"
		elif is_blocking:
			active_texture = game.player_interact_sheet_texture
			active_frame_index = player_state["block_anim_frame_index"]
			overlay_kind = "interact"
		elif is_moving:
			active_texture = game.player_run_sheet_texture
			active_frame_index = player_state["animation_frame_index"]
			overlay_kind = "run"
		else:
			active_texture = game.player_idle_sheet_texture
			active_frame_index = player_state["idle_frame_index"]
			overlay_kind = "idle"

		var facing_direction: String = player_state["facing_direction"]
		var source_direction: String = "right" if facing_direction == "left" else facing_direction
		var direction_row: int = PLAYER_SHEET_DIRECTION_ROWS.get(source_direction, 0)
		var frame_index: int = active_frame_index
		var source_rectangle: Rect2 = Rect2(
			frame_index * PLAYER_SHEET_FRAME_WIDTH,
			direction_row * PLAYER_SHEET_FRAME_HEIGHT,
			PLAYER_SHEET_FRAME_WIDTH,
			PLAYER_SHEET_FRAME_HEIGHT
		)
		var sprite_size: float = game.CELL_SIZE * 0.6 * spawn_scale
		var destination_rectangle: Rect2 = Rect2(
			body_center.x - sprite_size / 2.0, body_center.y - sprite_size / 2.0,
			sprite_size, sprite_size
		)
		if is_own_avatar:
			game.draw_circle(body_center, sprite_size * 0.5 + 3.0, Color(1, 1, 1, spawn_eased * OWN_AVATAR_RING_ALPHA))
		var flip_horizontally: bool = facing_direction == "left"
		if flip_horizontally:
			# Mirror the whole draw about the body's center with a canvas
			# transform, so the source rect is always the plain, in-bounds
			# frame. (The old approach -- a negative-width source rect
			# shifted by one frame -- can end up sampling the *next*
			# frame's region, which for a row's last frame is off the
			# edge of the sheet and draws nothing.) The rects drawn below
			# are relative to body_center while the mirror is active.
			game.draw_set_transform(body_center, 0.0, Vector2(-1.0, 1.0))
			destination_rectangle.position -= body_center
		game.draw_texture_rect_region(active_texture, destination_rectangle, source_rectangle, Color(player_color, player_color.a * spawn_eased))
		_draw_equipped_armor_overlay(player_index, overlay_kind, frame_index, destination_rectangle, spawn_eased)
		if flip_horizontally:
			game.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		var attack_flash: float = player_state["attack_flash_timer"] / game.combat_mgr.ATTACK_FLASH_DURATION
		if attack_flash > 0.0:
			var flash_radius: float = game.CELL_SIZE * 0.32 * (1.0 + 0.5 * (1.0 - attack_flash))
			game.draw_arc(body_center, flash_radius, 0.0, TAU, 16, Color(1, 1, 0.6, attack_flash), 3.0)

		# Persistent (not timed) visual cue while guard is up -- a soft
		# pulsing barrier, so it's obvious at a glance who's currently
		# eating reduced/no damage instead of only finding out afterward.
		if is_blocking:
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			var shield_radius: float = game.CELL_SIZE * 0.4 * spawn_scale + pulse * 3.0
			game.draw_circle(body_center, shield_radius, Color(0.35, 0.75, 1.0, 0.15 * spawn_eased))
			game.draw_arc(body_center, shield_radius, 0.0, TAU, 24, Color(0.45, 0.85, 1.0, (0.65 + 0.25 * pulse) * spawn_eased), 3.0)

# Equipped armor's visual (e.g. a hat), drawn over the just-drawn body
# sprite -- campaign-only (equipping doesn't exist elsewhere), and only
# for the local player, since CampaignManager.equipped is a single global
# slot map, not per-player (campaign is always singleplayer, so there's
# only ever one player to apply it to anyway).
func _draw_equipped_armor_overlay(player_index: int, sheet_kind: String, frame_index: int, body_destination_rectangle: Rect2, alpha: float) -> void:
	if not CampaignManager.is_campaign_active or player_index != game.my_player_index:
		return
	var armor_item_id: String = CampaignManager.get_equipped_item_id("armor")
	if armor_item_id == "":
		return
	# Left-facing reuses the "right" art -- the caller has already mirrored
	# the canvas (see _draw_players) when facing left, so this just needs to
	# pick the right-facing frame.
	var facing_direction: String = game.players[player_index]["facing_direction"]
	var overlay_direction: String = "right" if facing_direction == "left" else facing_direction
	var overlay_texture: Texture2D = ItemData.get_item_overlay_texture(armor_item_id, sheet_kind, overlay_direction)
	if overlay_texture == null:
		return

	# The strip's frame count comes from the art itself (32px per frame);
	# when it differs from the body sheet's (attack's 7 body frames vs the
	# 6-frame run art it borrows), spread the hat's frames evenly across the
	# body's instead of indexing past the end of the strip.
	var overlay_frame_width: int = PLAYER_SHEET_FRAME_WIDTH
	var overlay_frame_count: int = maxi(1, overlay_texture.get_width() / overlay_frame_width)
	var body_frame_count: int = OVERLAY_BODY_FRAME_COUNTS.get(sheet_kind, overlay_frame_count)
	var overlay_frame_index: int = frame_index
	if overlay_frame_count != body_frame_count:
		overlay_frame_index = int(float(frame_index) * overlay_frame_count / body_frame_count)
	overlay_frame_index = clampi(overlay_frame_index, 0, overlay_frame_count - 1)

	var overlay_source_rectangle: Rect2 = Rect2(
		overlay_frame_index * overlay_frame_width, 0,
		overlay_frame_width, overlay_texture.get_height()
	)
	# The art's own (0, 0) pixel lands OVERLAY_TOP_OFFSET_PIXELS[sheet_kind]
	# source pixels above the body frame's top edge -- scaled by the same
	# factor the body itself was scaled by.
	var scale_factor: float = body_destination_rectangle.size.x / float(PLAYER_SHEET_FRAME_WIDTH)
	var top_offset: float = float(OVERLAY_TOP_OFFSET_PIXELS.get(sheet_kind, 0)) * scale_factor
	var overlay_destination_rectangle: Rect2 = Rect2(
		body_destination_rectangle.position.x,
		body_destination_rectangle.position.y - top_offset,
		overlay_frame_width * scale_factor,
		overlay_texture.get_height() * scale_factor
	)
	game.draw_texture_rect_region(overlay_texture, overlay_destination_rectangle, overlay_source_rectangle, Color(1, 1, 1, alpha))

func _handle_attack_input() -> void:
	if game.my_player_index < 0 or game.my_player_index >= game.players.size():
		return
	if game.players[game.my_player_index]["is_blocking"]:
		return  # can't swing while your guard is up
	if NetworkManager.is_multiplayer and not game.multiplayer.is_server():
		game.rpc_id(1, "_request_attack", game.my_player_index)
	else:
		game.combat_mgr._request_attack(game.my_player_index)

# --- Blocking: held key, not a one-shot request -- broadcasts its current
# on/off state (rather than a single event) so a peer who joins or whose
# packet arrives late still ends up with the right state, not a stuck one.

func _handle_block_input(is_pressed: bool) -> void:
	if game.my_player_index < 0 or game.my_player_index >= game.players.size():
		return
	if NetworkManager.is_multiplayer and not game.multiplayer.is_server():
		game.rpc_id(1, "_request_block", game.my_player_index, is_pressed)
	else:
		_request_block(game.my_player_index, is_pressed)

@rpc("any_peer", "call_remote", "reliable")
func _request_block(player_index: int, is_blocking: bool) -> void:
	if NetworkManager.is_multiplayer and not game.multiplayer.is_server():
		return  # only the host may apply state that affects damage
	if not NetworkManager.validate_request(player_index, game.players.size(), "block", 0.05 if is_blocking else 0.0):
		return
	if NetworkManager.is_multiplayer:
		game.rpc("_sync_block_state", player_index, is_blocking)
	else:
		_sync_block_state(player_index, is_blocking)

@rpc("authority", "call_local", "reliable")
func _sync_block_state(player_index: int, is_blocking: bool) -> void:
	game.players[player_index]["is_blocking"] = is_blocking
	game.queue_redraw()
