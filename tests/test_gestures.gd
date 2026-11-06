extends "res://tests/test_base.gd"


func tests() -> Array[Callable]:
	return [
		_test_menu_pressed,
		_test_menu_settle_and_repeat,
		_test_menu_button,
		_test_system_flags,
		_test_palm_angle,
	]


func _aim(hand_name: String) -> XRPositionalTracker:
	var aim: XRPositionalTracker = XRPositionalTracker.new()
	aim.name = "/user/fbhandaim/" + hand_name
	aim.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(aim)
	return aim


func _gestures(which: int = 0, settle: float = 0.0, repeat: float = 0.0) -> GXDKHandGestures:
	var g: GXDKHandGestures = GXDKHandGestures.new()
	g.hand = which
	g.settle_time = settle
	g.repeat_time = repeat
	origin.add_child(g)
	return g


func _test_menu_pressed() -> void:
	await _rig()
	var g: GXDKHandGestures = _gestures()
	var aim: XRPositionalTracker = _aim("left")
	var seen: Array = []
	g.menu_pressed.connect(func(source: String) -> void: seen.append(source))
	await _frames(2)
	aim.set_input("menu_gesture", true)
	await _frames(2)
	ok(seen.is_empty(), "menu_gesture alone, the palm facing the head, isn't the menu")
	aim.set_input("menu_pressed", true)
	aim.set_input("menu_pressed", false)
	await _frames(2)
	ok(seen == ["gesture"], "menu_pressed for a moment between frames is caught, on a tracker that appeared late")
	XRServer.remove_tracker(aim)


func _test_menu_settle_and_repeat() -> void:
	await _rig()
	var aim: XRPositionalTracker = _aim("left")
	var g: GXDKHandGestures = _gestures(0, 0.2, 0.2)
	var seen: Array = []
	g.menu_pressed.connect(func(source: String) -> void: seen.append(source))
	await _frames(2)
	aim.set_input("menu_pressed", true)
	aim.set_input("menu_pressed", false)
	await _frames(2)
	ok(seen.is_empty(), "the pulse at launch doesn't count")
	await get_tree().create_timer(0.3).timeout
	ok(seen.is_empty(), "and isn't kept for later")
	aim.set_input("menu_pressed", true)
	aim.set_input("menu_pressed", false)
	await _frames(2)
	aim.set_input("menu_pressed", true)
	aim.set_input("menu_pressed", false)
	await _frames(2)
	ok(seen.size() == 1, "two in quick succession count once")
	await get_tree().create_timer(0.3).timeout
	aim.set_input("menu_pressed", true)
	aim.set_input("menu_pressed", false)
	await _frames(2)
	ok(seen.size() == 2, "a later one counts")
	XRServer.remove_tracker(aim)


func _test_menu_button() -> void:
	await _rig()
	var g: GXDKHandGestures = _gestures()
	var seen: Array = []
	g.menu_pressed.connect(func(source: String) -> void: seen.append(source))
	await _frames(2)
	lc.set_input("menu_button", true)
	await _frames(2)
	lc.set_input("menu_button", false)
	await _frames(2)
	ok(seen == ["button"], "a controller's menu button works too")


func _test_system_flags() -> void:
	await _rig()
	var left_aim: XRPositionalTracker = _aim("left")
	var right_aim: XRPositionalTracker = _aim("right")
	var left: GXDKHandGestures = _gestures(0)
	var right: GXDKHandGestures = _gestures(1)
	await _frames(2)
	ok(not left.is_system_gesture() and not right.is_system_gesture(), "nothing to start with")
	left_aim.set_input("system_gesture", true)
	right_aim.set_input("menu_gesture", true)
	await _frames(2)
	ok(not left.is_system_gesture() and not right.is_system_gesture(), "the other hand's flag means nothing")
	left_aim.set_input("menu_gesture", true)
	right_aim.set_input("system_gesture", true)
	await _frames(2)
	ok(left.is_system_gesture() and right.is_system_gesture(), "each hand's own flag counts")
	ok(left.get_system_gesture_source() == "flag", "and says so")
	XRServer.remove_tracker(left_aim)
	XRServer.remove_tracker(right_aim)


func _test_palm_angle() -> void:
	await _rig()
	var cam: XRCamera3D = XRCamera3D.new()
	origin.add_child(cam)
	cam.position = Vector3(0.0, 1.0, 0.3)
	var g: GXDKHandGestures = _gestures()
	# The palm faces -Y of the joint: turn it to face the head, which is along +Z here.
	var facing: Basis = Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	lh.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(facing, Vector3(0.0, 1.0, 0.0)))
	await _frames(2)
	ok(g.is_system_gesture() and g.get_system_gesture_source() == "palm angle", "a palm facing a near head counts")
	lh.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0 + 35.0)), Vector3(0.0, 1.0, 0.0)))
	await _frames(2)
	ok(g.is_system_gesture(), "35 degrees off still counts once it's started")
	lh.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0 + 50.0)), Vector3(0.0, 1.0, 0.0)))
	await _frames(2)
	ok(not g.is_system_gesture(), "50 degrees off doesn't")
	lh.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0 + 35.0)), Vector3(0.0, 1.0, 0.0)))
	await _frames(2)
	ok(not g.is_system_gesture(), "nor does 35 until it's started again")
	lh.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(facing, Vector3(0.0, 1.0, 0.9)))
	await _frames(2)
	ok(not g.is_system_gesture(), "nor a palm far from the head")
