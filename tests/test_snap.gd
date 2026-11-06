extends "res://tests/test_base.gd"


func tests() -> Array[Callable]:
	return [
		_test_snap_defaults,
		_test_axis_assist,
		_test_axis_manual_capture,
	]


func _test_snap_defaults() -> void:
	await _rig()
	var zone: GXDKSnapZone = GXDKSnapZone.new()
	zone.radius = 0.07
	zone.detection_mask = MASK
	scene.add_child(zone)
	zone.global_position = Vector3(0.0, 1.5, 0.0)
	ok(zone.get_axis_assist(zone.global_position) == 0.0, "no axis assist by default")
	var c: RigidBody3D = _cart(zone.global_position + Vector3(0.0, 0.03, 0.0))
	await _frames(10)
	ok(GXDKSnapZone.captured_by(c) == zone, "an object let go in range is captured, as upstream")
	ok(c.freeze, "and frozen")


func _test_axis_assist() -> void:
	await _rig()
	var zone: GXDKSnapZone = GXDKSnapZone.new()
	zone.axis_length = 0.12
	scene.add_child(zone)
	zone.global_position = Vector3(0.0, 1.5, 0.0)
	zone.global_basis = Basis(Vector3.RIGHT, 0.5)
	var up: Vector3 = zone.global_basis.y
	var side: Vector3 = zone.global_basis.x
	var o: Vector3 = zone.global_position
	ok(is_equal_approx(zone.get_axis_assist(o), 1.0), "full help at the seat")
	ok(zone.get_axis_assist(o + up * 0.13) == 0.0, "none past its length")
	ok(zone.get_axis_assist(o + side * 0.08) == 0.0, "none past its radius")
	var mid: float = zone.get_axis_assist(o + up * 0.03 + side * 0.035)
	ok(mid > 0.3 and mid < 0.7, "partial between: %.2f" % mid)
	var t: Transform3D = Transform3D(Basis(), o + up * 0.03 + side * 0.02)
	var eased: Transform3D = zone.get_axis_assisted(t)
	ok(eased.origin.distance_to(zone.get_on_axis(t.origin).origin) < t.origin.distance_to(zone.get_on_axis(t.origin).origin), "eases towards the axis")
	var low: Transform3D = zone.get_on_axis(o - up * 0.02)
	ok(low.origin.distance_to(o) < 0.0001, "never below the zone")
	ok(zone.is_home(o + up * 0.01 + side * 0.01), "home when pushed in and in line")
	ok(not zone.is_home(o + up * 0.03), "not when above")
	ok(not zone.is_home(o + side * 0.04), "not when off line")
	var lateral: Vector3 = side * 0.04
	var at_seat: float = zone.get_axis_assist(o + lateral)
	ok(is_equal_approx(zone.get_axis_assist(o + lateral - up * 0.03), at_seat), "full strength down to 30 mm below the seat")
	ok(zone.get_axis_assist(o + lateral - up * 0.05) == 0.0, "gone by 50 mm below it")
	var worst_step: float = 0.0
	var last: float = at_seat
	for mm in range(0, 60):
		var now: float = zone.get_axis_assist(o + lateral - up * (mm * 0.001))
		worst_step = maxf(worst_step, absf(now - last))
		last = now
	ok(worst_step < at_seat * 0.1, "it eases out, with no sudden edge: worst %.3f per mm" % worst_step)


func _test_axis_manual_capture() -> void:
	await _rig()
	var zone: GXDKSnapZone = GXDKSnapZone.new()
	zone.radius = 0.07
	zone.axis_length = 0.12
	zone.auto_capture = false
	zone.detection_mask = MASK
	scene.add_child(zone)
	zone.global_position = Vector3(0.0, 1.5, 0.0)
	var c: RigidBody3D = _cart(zone.global_position + Vector3(0.0, 0.03, 0.0), true)
	await _frames(10)
	ok(GXDKSnapZone.captured_by(c) == null, "with auto capture off nothing is captured")
	zone.capture_node(c)
	ok(GXDKSnapZone.captured_by(c) == zone, "capture_node works on a frozen body")
	ok(zone.get_axis_assist(zone.global_position) == 0.0, "a taken slot gives no help")
	zone.release_captured_body()
	ok(c.freeze, "and it stays frozen on release, as it was")
