extends "res://tests/test_base.gd"


func tests() -> Array[Callable]:
	return [
		_test_all_scripts_load,
	]


func _test_all_scripts_load() -> void:
	var bad: int = 0
	var count: int = 0
	var dirs: Array[String] = ["res://addons/godot-xr-development-kit"]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for sub: String in DirAccess.get_directories_at(dir):
			dirs.push_back(dir.path_join(sub))
		for f: String in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				count += 1
				var script: Script = load(dir.path_join(f))
				if script == null or not script.can_instantiate():
					bad += 1
					print("FAIL didn't load ", f)
	ok(count >= 40, "found the addon's scripts: %d" % count)
	ok(bad == 0, "every script loads")
