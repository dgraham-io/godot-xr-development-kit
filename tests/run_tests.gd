extends SceneTree
## Headless tests of this plugin, driven by fake XR trackers.
##   godot --headless --xr-mode off --script res://tests/run_tests.gd
## Prints PASS or FAIL. Godot also exits with 0 if this script fails to load, so read the output.

const TEST_FILES: Array[String] = [
	"res://tests/test_scripts.gd",
	"res://tests/test_pickup.gd",
	"res://tests/test_pointer.gd",
	"res://tests/test_gestures.gd",
	"res://tests/test_snap.gd",
	"res://tests/test_hands.gd",
	"res://tests/test_touch.gd",
	"res://tests/test_seated_stage.gd",
]


# Counts engine and script errors, so an error fails its test.
class ErrorCounter extends Logger:
	var count: int = 0

	func _log_error(
			_function: String,
			_file: String,
			_line: int,
			_code: String,
			_rationale: String,
			_editor_notify: bool,
			error_type: int,
			_script_backtrace: Array[ScriptBacktrace]
		) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1


var errors: ErrorCounter = ErrorCounter.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.add_logger(errors)
	Engine.physics_ticks_per_second = 72
	var base: GDScript = load("res://tests/test_base.gd")
	base.trackers()
	for path: String in TEST_FILES:
		var group: Node = (load(path) as GDScript).new()
		root.add_child(group)
		for test: Callable in group.tests():
			base.lc.set_input("trigger", 0.0)
			base.lc.set_input("grip", 0.0)
			print("TEST ", test.get_method())
			var before: int = errors.count
			await test.call()
			await group.clear()
			group.ok(errors.count - base.allowed_errors == before, "no errors in %s" % test.get_method())
			errors.count -= base.allowed_errors
			base.allowed_errors = 0
		group.queue_free()

	if base.failures == 0:
		print("PASS %d checks" % base.checks)
	else:
		print("FAIL %d of %d checks" % [base.failures, base.checks])
	quit(0 if base.failures == 0 else 1)
