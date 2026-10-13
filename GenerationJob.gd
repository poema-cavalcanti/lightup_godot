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
		var rows_found: PackedStringArray = LightUpGenerator.try_generate(size.x, size.y, density, rng)
		if not rows_found.is_empty():
			result_rows = rows_found
			break
	done = true

# Stops after the current attempt (each is bounded by the solver node budgets).
func cancel() -> void:
	cancelled = true

# Joins the thread; blocks only for the tail of an in-flight attempt.
func finish() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
