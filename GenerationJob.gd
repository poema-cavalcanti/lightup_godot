class_name GenerationJob
extends RefCounted

# Runs LightUpGenerator on a worker thread, retrying until it finds a valid
# puzzle (or is cancelled). Poll `done` from the main thread, then call
# finish() before reading `result_rows`.

var size: Vector2i
var result_rows: PackedStringArray = PackedStringArray()
var attempts: int = 0
var done: bool = false
var cancelled: bool = false
var started_ms: int = 0
var _thread: Thread = null

# The first NAVIGABLE_ATTEMPTS layouts are made walkable by PuzzleNavigator
# (cheap: the layout is kept and its white regions are bridged, and only a layout
# that gets "stuck" is replaced by a new one). If all of those are spent, it falls
# back to the original method -- only accepting layouts that are connected as
# generated -- which is slower but doesn't depend on the conversion succeeding.
const NAVIGABLE_ATTEMPTS: int = 12

func start(puzzle_size: Vector2i, density: float) -> void:
	size = puzzle_size
	started_ms = Time.get_ticks_msec()
	_thread = Thread.new()
	_thread.start(_run.bind(density))

func _run(density: float) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	while not cancelled:
		attempts += 1
		var rows_found: PackedStringArray = LightUpGenerator.try_generate(size.x, size.y, density, rng, attempts > NAVIGABLE_ATTEMPTS)
		if not rows_found.is_empty():
			result_rows = rows_found
			break
	done = true

# Stops after the current attempt (each is bounded by the solver node budgets).
func cancel() -> void:
	cancelled = true

# Cancel and walk away WITHOUT waiting: for scenes that are being closed. An attempt that is
# still running can take many seconds now (see PuzzleNavigator), and finish() would freeze the
# game for all of it. The thread is parked here and joined later by reap(), which
# NetworkManager (an autoload, so it outlives every scene) calls each frame.
func abandon() -> void:
	cancelled = true
	if done or _thread == null:
		finish()  # nothing running, so this returns at once
		return
	_abandoned.append(self)

static var _abandoned: Array[GenerationJob] = []

static func reap() -> void:
	for index in range(_abandoned.size() - 1, -1, -1):
		if _abandoned[index].done:
			_abandoned[index].finish()
			_abandoned.remove_at(index)

# Joins the thread; blocks only for the tail of an in-flight attempt.
func finish() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
