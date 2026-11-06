extends SceneTree
## Headless tests for GXDK additions, driven by fake XR trackers (no XR runtime).
##   godot --headless --xr-mode off --path . --script res://tests/run_tests.gd
## Exit code 0 when every check passes.

const MASK := 2


# Counts engine and script errors, so a script error fails a test.
class ErrorCounter extends Logger:
	var count: int = 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1


var errors: ErrorCounter = ErrorCounter.new()

var checks: int = 0
var failures: int = 0
var lh: XRHandTracker
var lc: XRControllerTracker
var scene: Node3D
var origin: XROrigin3D
var hand: GXDKCollisionHand
var pickup: GXDKPickup
var hxf: Transform3D = Transform3D(Basis(), Vector3(0.0, 1.0, 0.0))
var sides: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.add_logger(errors)
	Engine.physics_ticks_per_second = 72
	_trackers()
	for t: Callable in _tests():
		lc.set_input("trigger", 0.0)
		lc.set_input("grip", 0.0)
		print("TEST ", t.get_method())
		var before: int = errors.count
		await t.call()
		await _clear()
		ok(errors.count == before, "no script or engine errors in %s" % t.get_method())
	print("PASS %d checks" % checks if failures == 0 else "FAIL %d of %d checks" % [failures, checks])
	quit(0 if failures == 0 else 1)


func _tests() -> Array[Callable]:
	return [
		_test_no_player_body,
		_test_poke_press,
		_test_touch_drag_rules,
		_test_display_rate_visual_only,
		_test_display_rate_free,
		_test_display_rate_held_back,
		_test_display_rate_override,
		_test_staging_swap,
		_test_pointer_defaults,
		_test_pointer_aim,
		_test_pointer_smoothing,
		_test_pointer_open_first,
		_test_all_scripts_load,
		_test_snap_defaults,
		_test_axis_assist,
		_test_axis_manual_capture,
		_test_menu_pressed,
		_test_menu_settle_and_repeat,
		_test_menu_button,
		_test_system_flags,
		_test_palm_angle,
		_test_loss_recovers,
		_test_loss_releases,
		_test_unsure_open_isnt_release,
		_test_unsure_pinch_carries_on,
		_test_loss_off_by_default,
		_test_grab_window,
		_test_unsure_wait,
		_test_open_first,
		_test_no_retake_after_drop,
		_test_observe_window,
		_test_process_hook,
		_test_palm_side_default,
		_test_pinch_point,
		_test_keep_grip,
		_test_two_grab_actions,
		_test_observe_only,
	]


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL ", what)


func _trackers() -> void:
	lh = XRHandTracker.new()
	lh.name = "/user/hand_tracker/left"
	lh.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	lc = XRControllerTracker.new()
	lc.name = "left_hand"
	lc.type = XRServer.TRACKER_CONTROLLER
	lc.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	XRServer.add_tracker(lh)
	XRServer.add_tracker(lc)
	_joints(hxf)


func _joints(xf: Transform3D, tracked: bool = true) -> void:
	var flags: int = XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID
	if tracked:
		flags |= XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED
	for j in XRHandTracker.HAND_JOINT_MAX:
		lh.set_hand_joint_flags(j, flags)
		lh.set_hand_joint_transform(j, xf)


func _pose(xf: Transform3D, confidence: int = XRPose.XR_TRACKING_CONFIDENCE_HIGH) -> void:
	lh.has_tracking_data = true
	lh.set_pose("default", xf, Vector3.ZERO, Vector3.ZERO, confidence)
	lc.set_pose("palm_pose", xf, Vector3.ZERO, Vector3.ZERO, confidence)
	_joints(xf, confidence == XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _lost() -> void:
	lh.has_tracking_data = false
	lh.invalidate_pose("default")
	lc.invalidate_pose("palm_pose")


# Build a hand and pickup. A seated rig has no body unless with_body is set.
func _rig(with_body: bool = true) -> void:
	scene = Node3D.new()
	root.add_child(scene)
	var parent: Node3D = scene
	if with_body:
		var body: StaticBody3D = StaticBody3D.new()
		body.collision_layer = 0
		body.collision_mask = 0
		scene.add_child(body)
		parent = body
	origin = XROrigin3D.new()
	parent.add_child(origin)
	hand = GXDKCollisionHand.new()
	hand.hand = 0
	hand.mode = GXDKCollisionHand.CollisionHandMode.TELEPORT
	hand.enable_ghost_hand = false
	pickup = GXDKPickup.new()
	pickup.grab_action = "trigger"
	pickup.collision_mask = MASK
	pickup.detection_radius = 0.045
	pickup.detection_offset = Vector3.ZERO
	hand.add_child(pickup)
	origin.add_child(hand)
	_pose(hxf)
	await _frames(5)


func _clear() -> void:
	if scene:
		scene.queue_free()
		scene = null
	await physics_frame
	await physics_frame


func _cart(at: Vector3, frozen: bool = false, script: Script = null) -> RigidBody3D:
	var c: RigidBody3D = RigidBody3D.new()
	if script:
		c.set_script(script)
	c.collision_layer = MASK
	c.collision_mask = 0
	c.gravity_scale = 0.0
	c.mass = 0.1
	c.freeze = frozen
	var s: CollisionShape3D = CollisionShape3D.new()
	var b: BoxShape3D = BoxShape3D.new()
	b.size = Vector3(0.068, 0.060, 0.014)
	s.shape = b
	c.add_child(s)
	scene.add_child(c)
	c.global_position = at
	return c


# Beside the pickup, on the side the palm-facing check allows.
func _beside() -> Vector3:
	return pickup.global_position + pickup.global_basis * Vector3(0.05, 0.0, 0.0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _test_no_player_body() -> void:
	await _rig(false)
	var c: RigidBody3D = _cart(_beside())
	var got: Array = []
	pickup.picked_up.connect(func(_by: GXDKPickup, what: PhysicsBody3D) -> void: got.append(what))
	await _frames(5)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	ok(pickup.has_picked_up(), "a seated rig with no body picks up")
	ok(got.size() == 1 and got[0] == c, "picked_up fires with no body: the function ran to its end")
	lc.set_input("trigger", 0.0)
	await _frames(3)
	ok(not pickup.has_picked_up(), "and drops")


func _test_observe_only() -> void:
	await _rig()
	pickup.observe_only = true
	var seen: Array = []
	pickup.observed_grab.connect(func(_by: GXDKPickup, what: PhysicsBody3D) -> void: seen.append(what))
	lc.set_input("trigger", 1.0)
	await _frames(3)
	lc.set_input("trigger", 0.0)
	await _frames(3)
	ok(seen.size() == 1 and seen[0] == null, "a press with nothing in reach reports null")
	var at: Vector3 = _beside()
	var c: RigidBody3D = _cart(at)
	var m: MeshInstance3D = MeshInstance3D.new()
	m.mesh = BoxMesh.new()
	c.add_child(m)
	await _frames(5)
	ok(pickup.get_closest_body() == c, "it knows the candidate")
	ok(m.material_overlay == null, "no highlight on the candidate")
	lc.set_input("trigger", 1.0)
	await _frames(5)
	ok(seen.size() == 2 and seen[1] == c, "a press in reach reports the body")
	ok(not pickup.has_picked_up(), "and takes nothing")
	ok(c.global_position.distance_to(at) < 0.0001, "the body doesn't move")
	_pose(Transform3D(Basis(), hxf.origin + Vector3(0.1, 0.0, 0.0)))
	await _frames(5)
	ok(c.global_position.distance_to(at) < 0.0001, "nor when the hand moves")
	lc.set_input("trigger", 0.0)
	await _frames(2)
	pickup.observe_only = false
	_pose(hxf)
	await _frames(5)
	ok(m.material_overlay != null, "turned off, highlights come back")


func _test_two_grab_actions() -> void:
	await _rig()
	pickup.secondary_grab_action = "grip"
	pickup.grab_threshold = 0.75
	pickup.release_threshold = 0.4
	_cart(_beside())
	await _frames(5)
	lc.set_input("grip", 0.7)
	await _frames(2)
	ok(not pickup.has_picked_up(), "below the threshold takes nothing")
	lc.set_input("grip", 1.0)
	await _frames(2)
	ok(pickup.has_picked_up(), "the second action grabs")
	lc.set_input("trigger", 1.0)
	await _frames(2)
	lc.set_input("grip", 0.0)
	await _frames(2)
	ok(pickup.has_picked_up(), "going from palm to pinch doesn't drop")
	lc.set_input("grip", 1.0)
	await _frames(2)
	lc.set_input("trigger", 0.0)
	await _frames(2)
	ok(pickup.has_picked_up(), "nor from pinch to palm")
	lc.set_input("grip", 0.5)
	await _frames(2)
	ok(pickup.has_picked_up(), "holds above the release threshold")
	lc.set_input("grip", 0.3)
	await _frames(2)
	ok(not pickup.has_picked_up(), "lets go below it")


func _test_palm_side_default() -> void:
	await _rig()
	var at: Vector3 = pickup.global_position + pickup.global_basis * Vector3(-0.05, 0.0, 0.0)
	_cart(at)
	await _frames(5)
	ok(pickup.get_closest_body() == null, "by default the back of the hand is refused")
	pickup.require_palm_facing = false
	await _frames(3)
	ok(pickup.get_closest_body() != null, "the check can be turned off")


func _test_pinch_point() -> void:
	await _rig()
	pickup.require_palm_facing = false
	pickup.detect_from_pinch_point = true
	var tip: Vector3 = Vector3(0.0, 0.0, -0.15)
	lh.set_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP, Transform3D(Basis(), hxf.origin + tip))
	lh.set_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, Transform3D(Basis(), hxf.origin + tip))
	var c: RigidBody3D = _cart(hxf.origin + tip + Vector3(0.0, 0.0, -0.03))
	await _frames(5)
	ok(pickup.get_closest_body() == c, "a cartridge at the fingertips is found, 150 mm from the bone")
	pickup.detect_from_pinch_point = false
	await _frames(3)
	ok(pickup.get_closest_body() == null, "and not found from the bone")


func _test_keep_grip() -> void:
	await _rig()
	pickup.keep_grip_on_grab = true
	var at: Vector3 = _beside()
	var c: RigidBody3D = _cart(at)
	c.global_basis = Basis(Vector3.UP, 0.7)
	var b: Basis = c.global_basis
	await _frames(5)
	lc.set_input("trigger", 1.0)
	await _frames(10)
	ok(pickup.has_picked_up(), "taken")
	ok(c.global_position.distance_to(at) < 0.001, "it stays where it was: %.2f mm" % (c.global_position.distance_to(at) * 1000.0))
	ok((b * c.global_basis.inverse()).get_rotation_quaternion().get_angle() < deg_to_rad(0.5), "and doesn't turn")


func _test_process_hook() -> void:
	var src: GDScript = GDScript.new()
	src.source_code = "extends RigidBody3D\nvar in_process: int = 0\nvar in_physics: int = 0\nfunc _xr_custom_pickup_process(_p, _d, _ct, gt):\n\tin_process += 1\n\tglobal_transform = gt\nfunc _xr_custom_pickup_handler(_p, _d, _ct, _gt):\n\tin_physics += 1\n\treturn true\n"
	src.reload()
	await _rig()
	pickup.keep_grip_on_grab = true
	var c: RigidBody3D = _cart(_beside(), true, src)
	await _frames(5)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	ok(pickup.has_picked_up(), "a frozen body is taken")
	var grip: Transform3D = hxf.affine_inverse() * c.global_transform
	var worst: float = 0.0
	for i in 40:
		var xf: Transform3D = Transform3D(Basis(Vector3.UP, sin(i * 0.1)), hxf.origin + Vector3(sin(i * 0.1) * 0.2, 0.0, 0.0))
		_pose(xf)
		await process_frame
		worst = maxf(worst, c.global_position.distance_to((xf * grip).origin))
	ok(worst < 0.0005, "rigid in the hand each frame: worst %.2f mm" % (worst * 1000.0))
	ok(c.in_process > 30, "the process hook runs")
	ok(c.in_physics == 0, "and the physics hook doesn't")


func _test_grab_window() -> void:
	await _rig()
	pickup.grab_window = 0.35
	lc.set_input("trigger", 1.0)
	await _frames(2)
	await create_timer(0.1).timeout
	var c: RigidBody3D = _cart(_beside())
	await _frames(5)
	ok(pickup.has_picked_up() and pickup.get_picked_up() == c, "closed 0.1 s before arriving takes it")
	lc.set_input("trigger", 0.0)
	await _frames(3)
	c.queue_free()
	await _frames(3)
	lc.set_input("trigger", 1.0)
	await _frames(2)
	await create_timer(0.5).timeout
	_cart(_beside())
	await _frames(5)
	ok(not pickup.has_picked_up(), "closed 0.5 s before arriving doesn't")


func _test_unsure_wait() -> void:
	await _rig()
	pickup.grab_window = 0.35
	pickup.unsure_wait = 0.1
	_cart(_beside())
	await _frames(5)
	_pose(hxf, XRPose.XR_TRACKING_CONFIDENCE_LOW)
	lc.set_input("trigger", 1.0)
	await _frames(2)
	ok(not pickup.has_picked_up(), "an unsure hand waits")
	await create_timer(0.15).timeout
	ok(pickup.has_picked_up(), "then takes it anyway")
	lc.set_input("trigger", 0.0)
	await _frames(3)
	_pose(hxf)
	await _frames(3)
	lc.set_input("trigger", 1.0)
	await _frames(2)
	ok(pickup.has_picked_up(), "a sure hand takes it at once")


func _test_open_first() -> void:
	lc.set_input("trigger", 1.0)
	await _rig()
	pickup.require_open_first = true
	pickup.grab_window = 0.35
	_cart(_beside())
	await _frames(10)
	ok(not pickup.has_picked_up(), "a pinch already held takes nothing")
	lc.set_input("trigger", 0.0)
	await _frames(3)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	ok(pickup.has_picked_up(), "once opened, a pinch takes it")


func _test_no_retake_after_drop() -> void:
	await _rig()
	pickup.grab_window = 0.35
	pickup.keep_grip_on_grab = true
	var c: RigidBody3D = _cart(_beside())
	await _frames(5)
	lc.set_input("trigger", 1.0)
	await _frames(2)
	ok(pickup.has_picked_up(), "taken")
	pickup.drop_held_object()
	await _frames(5)
	ok(not pickup.has_picked_up(), "a hand still closed after a drop takes nothing back")
	ok(pickup.get_closest_body() == c, "it's still in reach")
	lc.set_input("trigger", 0.0)
	await _frames(3)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	ok(pickup.has_picked_up(), "until it opens")


func _test_observe_window() -> void:
	await _rig()
	pickup.observe_only = true
	pickup.grab_window = 0.2
	var seen: Array = []
	pickup.observed_grab.connect(func(_by: GXDKPickup, what: PhysicsBody3D) -> void: seen.append(what))
	lc.set_input("trigger", 1.0)
	await _frames(2)
	var c: RigidBody3D = _cart(_beside())
	await _frames(5)
	ok(seen.size() == 1 and seen[0] == c, "observing reports a late arrival in the window")
	lc.set_input("trigger", 0.0)
	await _frames(2)
	c.queue_free()
	await _frames(2)
	lc.set_input("trigger", 1.0)
	await create_timer(0.3).timeout
	ok(seen.size() == 2 and seen[1] == null, "and null once the window's gone")
	ok(not pickup.has_picked_up(), "taking nothing")


func _hold_rigid() -> GDScript:
	var src: GDScript = GDScript.new()
	src.source_code = "extends RigidBody3D\nfunc _xr_custom_pickup_process(_p, _d, _ct, gt):\n\tglobal_transform = gt\n"
	src.reload()
	return src


func _test_loss_recovers() -> void:
	await _rig()
	pickup.loss_release_time = 0.4
	pickup.keep_grip_on_grab = true
	var c: RigidBody3D = _cart(_beside(), true, _hold_rigid())
	await _frames(5)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	var at: Vector3 = c.global_position
	_lost()
	await create_timer(0.2).timeout
	ok(pickup.has_picked_up(), "lost 0.2 s: still held")
	ok(c.global_position.distance_to(at) < 0.0001, "and it stays where it is")
	_pose(Transform3D(Basis(), hxf.origin + Vector3(0.3, 0.0, 0.0)))
	await _frames(2)
	ok(pickup.has_picked_up(), "back: still held")
	ok(c.global_position.distance_to(at) < 0.0001, "back 300 mm away: no jump")
	_pose(Transform3D(Basis(), hxf.origin + Vector3(0.35, 0.0, 0.0)))
	await _frames(2)
	ok(absf(c.global_position.distance_to(at) - 0.05) < 0.001, "and carries on from there")
	lc.set_input("trigger", 0.0)
	await _frames(2)
	ok(not pickup.has_picked_up() and pickup.get_drop_reason() == GXDKPickup.DropReason.RELEASED, "opening then is a release")


func _test_loss_releases() -> void:
	await _rig()
	pickup.loss_release_time = 0.4
	var got: Array = []
	pickup.dropped.connect(func(by: GXDKPickup, _what: PhysicsBody3D) -> void: got.append(by.get_drop_reason()))
	_cart(_beside())
	await _frames(5)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	_lost()
	lc.set_input("trigger", 0.0)
	await create_timer(0.6).timeout
	ok(not pickup.has_picked_up(), "lost 0.6 s: let go")
	ok(got.size() == 1 and got[0] == GXDKPickup.DropReason.TRACKING_LOST, "and dropped says tracking was lost")
	_pose(hxf)
	await _frames(3)
	ok(not pickup.has_picked_up(), "back with an open hand takes nothing")


func _test_unsure_open_isnt_release() -> void:
	await _rig()
	pickup.loss_release_time = 0.4
	_cart(_beside())
	await _frames(5)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	_pose(hxf, XRPose.XR_TRACKING_CONFIDENCE_LOW)
	lc.set_input("trigger", 0.0)
	await _frames(3)
	ok(pickup.has_picked_up(), "opening on an unsure frame isn't a release")
	lc.set_input("trigger", 1.0)
	_pose(hxf)
	await _frames(3)
	ok(pickup.has_picked_up(), "pinching again carries on")


func _test_unsure_pinch_carries_on() -> void:
	await _rig()
	pickup.loss_release_time = 0.2
	_cart(_beside())
	await _frames(5)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	_pose(hxf, XRPose.XR_TRACKING_CONFIDENCE_LOW)
	await create_timer(0.4).timeout
	ok(pickup.has_picked_up(), "still pinching on unsure frames holds past the loss time")


func _test_loss_off_by_default() -> void:
	await _rig()
	_cart(_beside())
	await _frames(5)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	_lost()
	lc.set_input("trigger", 0.0)
	await create_timer(0.5).timeout
	ok(pickup.has_picked_up(), "by default a lost hand holds on, as upstream")


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
	await create_timer(0.3).timeout
	ok(seen.is_empty(), "and isn't kept for later")
	aim.set_input("menu_pressed", true)
	aim.set_input("menu_pressed", false)
	await _frames(2)
	aim.set_input("menu_pressed", true)
	aim.set_input("menu_pressed", false)
	await _frames(2)
	ok(seen.size() == 1, "two in quick succession count once")
	await create_timer(0.3).timeout
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
	await physics_frame
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
		await process_frame
		spread_in = maxf(spread_in, n.length())
		if i > 30:
			seen.append(ptr.global_position)
	var spread_out: float = 0.0
	for p: Vector3 in seen:
		spread_out = maxf(spread_out, p.distance_to(Vector3(0.0, 1.0, 0.0)))
	ok(spread_out < spread_in * 0.5, "jitter while still is cut: %.2f mm to %.2f mm" % [spread_in * 1000.0, spread_out * 1000.0])
	for i in 60:
		_aim_pose(Transform3D(Basis(), Vector3(i * 0.02, 1.0, 0.0)))
		await process_frame
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
	await physics_frame
	await _frames(3)
	ok(not ptr.is_pressed(), "a press already held counts for nothing")
	lc.set_input("trigger", 0.0)
	await _frames(2)
	lc.set_input("trigger", 1.0)
	await _frames(2)
	ok(ptr.is_pressed(), "once open, a press counts")
	lc.set_input("trigger", 0.0)
	lc.invalidate_pose("aim")


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
	root.add_child(staging)
	# GXDKStartXR reports it can't start OpenXR here, there is no runtime in these tests.
	errors.count -= 1
	while stage_script.visible_with.is_empty() and Time.get_ticks_msec() - started < 3000:
		await process_frame
	ok(stage_script.loaded.size() == 1, "with no prompt, the first stage loads by itself")
	ok(stage_script.visible_with.size() == 1, "and shows")
	var ms: int = Time.get_ticks_msec()
	var first: Node = staging.get_node("Scene").get_child(0)
	(first as GXDKStageBase).reset_scene("ride-b")
	while stage_script.visible_with.size() < 2 and Time.get_ticks_msec() - ms < 3000:
		await process_frame
	ms = Time.get_ticks_msec() - ms
	ok(stage_script.exiting == 1, "reset_scene frees the old stage")
	ok(stage_script.loaded.size() == 2 and stage_script.loaded[1] == "ride-b", "and the new one gets user_data")
	ok(staging.get_node("Scene").get_child_count() == 1 and staging.get_node("Scene").get_child(0) != first, "one new stage")
	ok(ms < 1000, "fade_time applies: a swap took %d ms" % ms)
	staging.queue_free()
	await _frames(3)


func _mesh_rig(mode: int) -> Node3D:
	await _rig()
	hand.mode = mode
	hand.collision_mask = 1 if mode == GXDKCollisionHand.CollisionHandMode.COLLIDE else 0
	hand.collision_layer = 0
	hand.follow_at_display_rate = true
	await _frames(10)
	return hand._hand_mesh


func _wall(x: float) -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	var s: CollisionShape3D = CollisionShape3D.new()
	var b: BoxShape3D = BoxShape3D.new()
	b.size = Vector3(0.02, 1.0, 1.0)
	s.shape = b
	wall.add_child(s)
	scene.add_child(wall)
	wall.global_position = Vector3(x, 1.0, 0.0)


# Runs after all other nodes each frame: what we see there is what's drawn.
func _end_of_frame() -> Node:
	var src: GDScript = GDScript.new()
	src.source_code = "extends Node\nsignal frame_done\nfunc _process(_d):\n\tframe_done.emit()\n"
	src.reload()
	var probe: Node = Node.new()
	probe.set_script(src)
	probe.process_priority = 1000
	scene.add_child(probe)
	return probe


func _worst_while_moving(mesh: Node3D) -> float:
	var worst: float = 0.0
	var probe: Node = _end_of_frame()
	for i in 120:
		var xf: Transform3D = Transform3D(Basis(Vector3.UP, sin(i * 0.05)), hxf.origin + Vector3(sin(i * 0.05) * 0.2, 0.0, 0.0))
		_pose(xf)
		await probe.frame_done
		if i > 20:
			worst = maxf(worst, mesh.global_position.distance_to(xf.origin))
	return worst


# The visual-only setup: no contacts, physics at 60 against any display rate.
func _test_display_rate_visual_only() -> void:
	Engine.physics_ticks_per_second = 60
	var mesh: Node3D = await _mesh_rig(GXDKCollisionHand.CollisionHandMode.TELEPORT)
	var worst: float = await _worst_while_moving(mesh)
	hand.follow_at_display_rate = false
	var stepping: float = await _worst_while_moving(mesh)
	Engine.physics_ticks_per_second = 72
	ok(worst < 0.001, "visual only, on the tracked hand each frame: worst %.2f mm" % (worst * 1000.0))
	ok(stepping > 0.003, "without the option it steps with physics: worst %.2f mm" % (stepping * 1000.0))
	print("TEST display rate %.2f mm, stepping %.2f mm" % [worst * 1000.0, stepping * 1000.0])


func _test_display_rate_free() -> void:
	Engine.physics_ticks_per_second = 60
	var mesh: Node3D = await _mesh_rig(GXDKCollisionHand.CollisionHandMode.COLLIDE)
	var worst: float = await _worst_while_moving(mesh)
	Engine.physics_ticks_per_second = 72
	ok(worst < 0.002, "colliding but free, on the tracked hand each frame: worst %.2f mm" % (worst * 1000.0))


func _test_display_rate_held_back() -> void:
	var mesh: Node3D = await _mesh_rig(GXDKCollisionHand.CollisionHandMode.COLLIDE)
	_wall(0.2)
	var x: float = 0.0
	while x < 0.5:
		x += 0.5 / 72.0
		_pose(Transform3D(Basis(), Vector3(x, 1.0, 0.0)))
		await physics_frame
	await _frames(30)
	ok(hand.global_position.x < 0.2, "the body stops at the wall: x %.3f" % hand.global_position.x)
	ok(absf(mesh.global_position.x - hand.global_position.x) < 0.01, "and the hand stays with it: %.3f" % mesh.global_position.x)
	while x > 0.0:
		x -= 0.5 / 72.0
		_pose(Transform3D(Basis(), Vector3(x, 1.0, 0.0)))
		await physics_frame
	await _frames(40)
	var off: float = mesh.global_position.distance_to(Vector3(x, 1.0, 0.0))
	ok(off < 0.002, "back in the open it's on the tracked hand again: %.2f mm" % (off * 1000.0))


func _test_display_rate_override() -> void:
	var mesh: Node3D = await _mesh_rig(GXDKCollisionHand.CollisionHandMode.TELEPORT)
	pickup.keep_grip_on_grab = true
	_cart(_beside(), true)
	await _frames(5)
	hand.add_target_override(scene.get_child(scene.get_child_count() - 1), 1, Transform3D())
	hand.follow_at_display_rate = false
	await _frames(3)
	ok(mesh.transform.is_equal_approx(Transform3D()), "turned off, the mesh is back on the body")


func _test_poke_press() -> void:
	var p: GXDKPokePress = GXDKPokePress.new()
	ok(not p.step(0.01, true, 0.0, 10.0), "in from behind doesn't press")
	p = GXDKPokePress.new()
	ok(not p.step(-0.01, false, 0.0, 10.0) and not p.armed, "in front but outside doesn't arm")
	ok(not p.step(0.01, true, 0.0, 10.0), "in from the side doesn't press")
	ok(not p.step(-0.01, true, 0.0, 10.0) and p.armed, "in front and inside arms")
	ok(not p.step(0.005, true, 0.0, 10.0), "not deep enough yet")
	ok(not p.step(0.01, true, 0.9, 10.0), "a pinching hand doesn't press")
	ok(p.step(0.01, true, 0.0, 10.0), "presses")
	ok(not p.step(0.02, true, 0.0, 10.0), "once")
	p.step(-0.01, true, 0.0, 10.1)
	ok(not p.down and p.armed, "retracted, it re-arms")
	ok(not p.step(0.01, true, 0.0, 10.1), "the cooldown holds it")
	p.step(-0.01, true, 0.0, 10.2)
	ok(p.step(0.01, true, 0.0, 10.5), "after that it presses again")


# Our input per frame: all the arguments of step but delta and slop.
func _touch(t: GXDKTouchDrag, depth: float, tip: Vector2, keep: bool = true, confident: bool = true, slop: float = 0.003) -> Dictionary:
	return t.step(true, depth, tip, keep, false, Vector2.ZERO, 0.0, false, false, confident, false, 1.0 / 72.0, slop)


func _test_touch_drag_rules() -> void:
	var t: GXDKTouchDrag = GXDKTouchDrag.new()
	var r: Dictionary = _touch(t, 0.01, Vector2.ZERO)
	ok(r.is_empty() and t.mode == GXDKTouchDrag.NONE, "in from behind doesn't take it")
	_touch(t, -0.01, Vector2.ZERO)
	r = _touch(t, 0.01, Vector2.ZERO)
	ok(r.has("started") and t.mode == GXDKTouchDrag.INDEX, "from the front it does")
	r = _touch(t, 0.01, Vector2(0.001, 0.0))
	ok(r.is_empty(), "under the slop there's no move")
	var first: Dictionary = {}
	var moved_x: float = 0.0
	for i in 20:
		r = _touch(t, 0.01, Vector2(0.02, 0.0))
		if r.has("delta"):
			moved_x += r.delta.x
			if first.is_empty():
				first = r
	ok(first.delta == Vector2.ZERO, "the first move reports no delta, so nothing jumps by the slop")
	ok(moved_x > 0.0, "then moves")
	r = _touch(t, -0.01, Vector2(0.02, 0.0))
	ok(r.get("ended", false) and not r.tap, "ends on retract, not a tap once moved")
	ok(r.fling.x >= 0.0, "with a fling")

	t = GXDKTouchDrag.new()
	_touch(t, -0.01, Vector2.ZERO)
	_touch(t, 0.01, Vector2.ZERO)
	r = _touch(t, -0.01, Vector2.ZERO)
	ok(r.get("tap", false), "a touch with no move is a tap")

	t = GXDKTouchDrag.new()
	_touch(t, -0.01, Vector2.ZERO)
	_touch(t, 0.01, Vector2.ZERO)
	r = _touch(t, 0.01, Vector2.ZERO, false)
	ok(r.get("ended", false) and not r.tap, "leaving the keep region ends it, not a tap")

	t = GXDKTouchDrag.new()
	_touch(t, -0.01, Vector2.ZERO)
	_touch(t, 0.01, Vector2.ZERO)
	for i in 10:
		r = _touch(t, 0.01, Vector2(i, i), true, false)
		ok(r.is_empty(), "unsure holds, with no moves")
	r = _touch(t, 0.01, Vector2(5.0, 5.0))
	ok(r.is_empty(), "back: it re-anchors with no jump")
	r = _touch(t, 0.01, Vector2(5.0, 5.0))
	ok(not r.has("delta") or r.delta.length() < 0.001, "and doesn't move from that")
	for i in 40:
		r = _touch(t, 0.01, Vector2.ZERO, true, false)
		if r.has("ended"):
			break
	ok(r.get("ended", false) and not r.tap and r.fling == Vector2.ZERO, "lost past the time it lets go: no tap, no fling")

	t = GXDKTouchDrag.new()
	r = t.step(false, -1.0, Vector2.ZERO, false, true, Vector2(0.1, 0.0), 1.0, true, true, true, false, 1.0 / 72.0, 0.0)
	ok(r.has("started") and t.mode == GXDKTouchDrag.PINCH, "a pinch takes it")
	r = t.step(false, -1.0, Vector2.ZERO, false, true, Vector2(0.1, 0.0), 0.0, false, false, true, false, 1.0 / 72.0, 0.0)
	ok(r.get("ended", false) and r.tap, "and opening ends it, a tap")

	t = GXDKTouchDrag.new()
	r = t.step(false, -1.0, Vector2.ZERO, false, true, Vector2.ZERO, 1.0, true, true, true, true, 1.0 / 72.0, 0.0)
	ok(r.is_empty(), "a control the other hand holds isn't available")
	r = t.step(false, -1.0, Vector2.ZERO, false, true, Vector2.ZERO, 1.0, true, true, false, false, 1.0 / 72.0, 0.0)
	ok(r.is_empty(), "an unsure hand starts nothing")
