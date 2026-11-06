extends "res://tests/test_base.gd"


func tests() -> Array[Callable]:
	return [
		_test_staging_swap,
	]


func _test_staging_swap() -> void:
	var scn: PackedScene = load("res://addons/godot-xr-development-kit/staging/gxdk_staging.tscn")
	var staging: GXDKStaging = scn.instantiate()
	staging.main_scene = "res://tests/test_stage.tscn"
	staging.prompt_on_start = false
	staging.fade_time = 0.05
	var stage_script: Script = load("res://tests/test_stage.gd")
	stage_script.loaded.clear()
	stage_script.visible_with.clear()
	stage_script.exiting = 0
	var started: int = Time.get_ticks_msec()
	get_tree().root.add_child(staging)
	# GXDKStartXR reports it can't start OpenXR here, there is no runtime in these tests.
	allowed_errors += 1
	while stage_script.visible_with.is_empty() and Time.get_ticks_msec() - started < 3000:
		await get_tree().process_frame
	ok(stage_script.loaded.size() == 1, "with no prompt, the first stage loads by itself")
	ok(stage_script.visible_with.size() == 1, "and shows")
	var ms: int = Time.get_ticks_msec()
	var first: Node = staging.get_node("Scene").get_child(0)
	(first as GXDKStageBase).reset_scene("ride-b")
	while stage_script.visible_with.size() < 2 and Time.get_ticks_msec() - ms < 3000:
		await get_tree().process_frame
	ms = Time.get_ticks_msec() - ms
	ok(stage_script.exiting == 1, "reset_scene frees the old stage")
	ok(stage_script.loaded.size() == 2 and stage_script.loaded[1] == "ride-b", "and the new one gets user_data")
	ok(staging.get_node("Scene").get_child_count() == 1 and staging.get_node("Scene").get_child(0) != first, "one new stage")
	ok(ms < 1000, "fade_time applies: a swap took %d ms" % ms)
	staging.queue_free()
	await _frames(3)
