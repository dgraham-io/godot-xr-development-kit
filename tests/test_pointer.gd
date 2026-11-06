extends "res://tests/test_base.gd"


func tests() -> Array[Callable]:
	return [
		_test_pointer_defaults,
		_test_pointer_aim,
		_test_pointer_smoothing,
		_test_pointer_open_first,
	]


func _pointer(aim: bool) -> GXDKPointer:
	var ptr: GXDKPointer = GXDKPointer.new()
	ptr.collision_mask = MASK
	ptr.use_aim_pose = aim
	ptr.show_laser = false
	hand.add_child(ptr)
	return ptr


func _target(at: Vector3) -> Area3D:
	var src: GDScript = GDScript.new()
	src.source_code = "extends Area3D\nvar events: Array = []\nfunc _xr_pointer_input(event):\n\tevents.append(event)\n"
	src.reload()
	var a: Area3D = Area3D.new()
	a.set_script(src)
	a.collision_layer = MASK
	a.collision_mask = 0
	var s: CollisionShape3D = CollisionShape3D.new()
	var b: BoxShape3D = BoxShape3D.new()
	b.size = Vector3(0.2, 0.2, 0.01)
	s.shape = b
	a.add_child(s)
	scene.add_child(a)
	a.global_position = at
	return a


func _aim_pose(xf: Transform3D) -> void:
	lc.set_pose("aim", xf, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _test_pointer_defaults() -> void:
	await _rig()
	var ptr: GXDKPointer = _pointer(false)
	await _frames(3)
	ok(not ptr.use_aim_pose and ptr.press_threshold == 0.7 and ptr.release_threshold == 0.3, "defaults as upstream")
	ok(ptr.get_target() == null and not ptr.is_pressed(), "nothing targeted or pressed")


func _test_pointer_aim() -> void:
	await _rig()
	var ptr: GXDKPointer = _pointer(true)
	var a: Area3D = _target(Vector3(0.5, 1.5, -1.0))
	var aim_at: Transform3D = Transform3D(Basis.looking_at(Vector3(0.5, 0.5, -1.0).normalized(), Vector3.UP), Vector3(0.0, 1.0, 0.0))
	_aim_pose(aim_at)
	await get_tree().physics_frame
	await _frames(3)
	ok(ptr.global_position.distance_to(aim_at.origin) < 0.0001, "it sits at the aim pose, not the hand bone")
	ok(ptr.get_target() == a, "and hits what the aim pose points at")
	lc.set_input("trigger", 0.5)
	await _frames(2)
	ok(not ptr.is_pressed(), "below the threshold doesn't press")
	lc.set_input("trigger", 1.0)
	await _frames(2)
	ok(ptr.is_pressed(), "a press")
	lc.set_input("trigger", 0.5)
	await _frames(2)
	ok(ptr.is_pressed(), "holds above release")
	lc.set_input("trigger", 0.0)
	await _frames(2)
	ok(not ptr.is_pressed(), "and releases")
	var kinds: Array = a.events.map(func(e: GXDKPointer.PointerEvent) -> String: return "press" if e is GXDKPointer.PressedEvent else ("release" if e is GXDKPointer.ReleasedEvent else ""))
	ok(kinds.count("press") == 1 and kinds.count("release") == 1, "the target gets one press and one release")
	lc.invalidate_pose("aim")


func _test_pointer_smoothing() -> void:
	await _rig()
	var ptr: GXDKPointer = _pointer(true)
	ptr.aim_smoothing = 1.2
	var spread_in: float = 0.0
	var seen: Array[Vector3] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i in 90:
		var n: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 0.0) * 0.003
		_aim_pose(Transform3D(Basis(), Vector3(0.0, 1.0, 0.0) + n))
		await get_tree().process_frame
		spread_in = maxf(spread_in, n.length())
		if i > 30:
			seen.append(ptr.global_position)
	var spread_out: float = 0.0
	for p: Vector3 in seen:
		spread_out = maxf(spread_out, p.distance_to(Vector3(0.0, 1.0, 0.0)))
	ok(spread_out < spread_in * 0.5, "jitter while still is cut: %.2f mm to %.2f mm" % [spread_in * 1000.0, spread_out * 1000.0])
	for i in 60:
		_aim_pose(Transform3D(Basis(), Vector3(i * 0.02, 1.0, 0.0)))
		await get_tree().process_frame
	var lag: float = ptr.global_position.distance_to(Vector3(59 * 0.02, 1.0, 0.0))
	ok(lag < 0.1, "a fast sweep hardly lags: %.0f mm" % (lag * 1000.0))
	lc.invalidate_pose("aim")


func _test_pointer_open_first() -> void:
	lc.set_input("trigger", 1.0)
	await _rig()
	var ptr: GXDKPointer = _pointer(true)
	ptr.require_open_first = true
	_target(Vector3(0.0, 1.0, -1.0))
	_aim_pose(Transform3D(Basis(), Vector3(0.0, 1.0, 0.0)))
	await get_tree().physics_frame
	await _frames(3)
	ok(not ptr.is_pressed(), "a press already held counts for nothing")
	lc.set_input("trigger", 0.0)
	await _frames(2)
	lc.set_input("trigger", 1.0)
	await _frames(2)
	ok(ptr.is_pressed(), "once open, a press counts")
	lc.set_input("trigger", 0.0)
	lc.invalidate_pose("aim")
