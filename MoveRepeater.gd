class_name MoveRepeater
extends RefCounted

# ---------------------------------------------------------------------------
# Hold-to-move input timing, shared between Player.gd (in-level movement)
# and Town.gd -- previously two near-identical copies of this exact state
# machine (and its two rounds of bug fixes: the live-key-recheck race and
# the quick-tap-fires-an-extra-step timing issue both had to be fixed in
# both files by hand). One instance per local player; Player.gd keeps a
# single one since movement input only ever drives the local player
# regardless of how many are in game.players.
#
# Two-phase repeat: a direction must stay held for INITIAL_REPEAT_DELAY
# (comfortably longer than a normal tap) before the *first* repeat fires;
# once it has, repeats switch to whatever repeat_interval tick() is given
# for smooth continuous movement (normally the move-hop animation's own
# duration, so repeats chain with no visible gap).
#
# Pure input-timing state machine -- knows nothing about what a "move"
# actually does (grid walkability, RPC requests, animation) or whether a
# popup/pause currently blocks it; the caller decides that by what it does
# with the delta this returns, and by whether it calls tick() at all this
# frame. keycode_to_delta() is the one piece of domain knowledge this does
# own, since the four cardinal directions and their key bindings really are
# universal across every host.
# ---------------------------------------------------------------------------

const INITIAL_REPEAT_DELAY: float = 0.3  # a normal keyboard tap easily lasts 100-250ms, so this has to clear that comfortably or a single press can sneak in an extra step

var held_move_keycodes: Array[int] = []  # press order, most recent last
var move_repeat_timer: float = 0.0
var is_repeating: bool = false  # false = still in the initial-hold grace period, true = auto-repeating continuously

static func keycode_to_delta(keycode: int) -> Array:
	if keycode == SettingsManager.get_key_binding("move_up"):
		return [-1, 0]
	if keycode == SettingsManager.get_key_binding("move_down"):
		return [1, 0]
	if keycode == SettingsManager.get_key_binding("move_left"):
		return [0, -1]
	if keycode == SettingsManager.get_key_binding("move_right"):
		return [0, 1]
	return []

static func is_move_keycode(keycode: int) -> bool:
	return not keycode_to_delta(keycode).is_empty()

# Call from the host's _input() for every non-echo press/release of a
# movement key. Returns [delta_row, delta_col] to act on immediately for a
# recognized press, or [] for a release/unrecognized key (the host should
# just do nothing with an empty result).
func handle_key_event(keycode: int, is_pressed: bool) -> Array:
	var delta: Array = keycode_to_delta(keycode)
	if delta.is_empty():
		return []
	if is_pressed:
		if not held_move_keycodes.has(keycode):
			held_move_keycodes.append(keycode)
		move_repeat_timer = 0.0
		is_repeating = false
		return delta
	held_move_keycodes.erase(keycode)
	move_repeat_timer = 0.0
	is_repeating = false
	return []

# Call every frame. is_hop_in_progress holds off a repeat until the current
# hop has visually landed, even once enough time has passed (see
# Player.gd/Town.gd's _try_move -- firing a repeat mid-hop is how the
# quick-tap and race-condition bugs happened). Returns [delta_row, delta_col]
# to act on, or [] if nothing should fire this frame.
func tick(delta_time: float, is_hop_in_progress: bool, repeat_interval: float) -> Array:
	if held_move_keycodes.is_empty():
		return []

	move_repeat_timer += delta_time
	var threshold: float = repeat_interval if is_repeating else INITIAL_REPEAT_DELAY
	if move_repeat_timer < threshold:
		return []
	if is_hop_in_progress:
		return []

	move_repeat_timer = 0.0
	var active_keycode: int = held_move_keycodes[-1]
	if not Input.is_key_pressed(active_keycode):
		# The key-up for this one hasn't reached handle_key_event yet this
		# frame -- _input() and _process() can each only run once per frame,
		# so a release that happens in between is invisible to
		# held_move_keycodes until next frame. Trust the OS's live key state
		# here instead of that possibly-one-frame-stale cache, so a release
		# never lets one more already-scheduled move slip through after the
		# player's actually let go.
		held_move_keycodes.erase(active_keycode)
		return []

	is_repeating = true
	return keycode_to_delta(active_keycode)

# Safety net for anything that should stop a held direction from repeating
# without a matching key-release event reaching _input -- opening a popup
# or the pause menu, and the window losing OS focus entirely (alt-tab etc.,
# where the key-up can happen while the game never sees it).
func clear() -> void:
	held_move_keycodes.clear()
	move_repeat_timer = 0.0
	is_repeating = false
