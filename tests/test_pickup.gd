extends "res://tests/test_base.gd"


func tests() -> Array[Callable]:
	return [
		_test_unsure_open_with_curl,
		_test_pinch_takes_over,
		_test_secondary_only_hold,
		_test_no_retake_with_curled_hand,
		_test_pinch_owns_hold,
		_test_pinch_on_grip_open_first,
		_test_pinch_on_grip,
		_test_open_first_wobble,
		_test_no_player_body,
		_test_drop_on_exit,
		_test_observe_only,
		_test_two_grab_actions,
		_test_palm_side_default,
		_test_pinch_point,
		_test_keep_grip,
		_test_process_hook,
		_test_grab_window,
		_test_unsure_wait,
		_test_open_first,
		_test_no_retake_after_drop,
		_test_observe_window,
		_test_loss_recovers,
		_test_loss_releases,
		_test_unsure_open_isnt_release,
		_test_unsure_pinch_carries_on,
		_test_loss_off_by_default,
	]


func _hold_rigid() -> GDScript:
	var src: GDScript = GDScript.new()
	src.source_code = "extends RigidBody3D\nfunc _xr_custom_pickup_process(_p, _d, _ct, gt):\n\tglobal_transform = gt\n"
	src.reload()
	return src


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
		await get_tree().process_frame
		worst = maxf(worst, c.global_position.distance_to((xf * grip).origin))
	ok(worst < 0.0005, "rigid in the hand each frame: worst %.2f mm" % (worst * 1000.0))
	ok(c.in_process > 30, "the process hook runs")
	ok(c.in_physics == 0, "and the physics hook doesn't")


func _test_grab_window() -> void:
	await _rig()
	pickup.grab_window = 0.35
	lc.set_input("trigger", 1.0)
	await _frames(2)
	await get_tree().create_timer(0.1).timeout
	var c: RigidBody3D = _cart(_beside())
	await _frames(5)
	ok(pickup.has_picked_up() and pickup.get_picked_up() == c, "closed 0.1 s before arriving takes it")
	lc.set_input("trigger", 0.0)
	await _frames(3)
	c.queue_free()
	await _frames(3)
	lc.set_input("trigger", 1.0)
	await _frames(2)
	await get_tree().create_timer(0.5).timeout
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
	await get_tree().create_timer(0.15).timeout
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
	await get_tree().create_timer(0.3).timeout
	ok(seen.size() == 2 and seen[1] == null, "and null once the window's gone")
	ok(not pickup.has_picked_up(), "taking nothing")


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
	await get_tree().create_timer(0.2).timeout
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
	await get_tree().create_timer(0.6).timeout
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
	await get_tree().create_timer(0.4).timeout
	ok(pickup.has_picked_up(), "still pinching on unsure frames holds past the loss time")


func _test_loss_off_by_default() -> void:
	await _rig()
	_cart(_beside())
	await _frames(5)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	_lost()
	lc.set_input("trigger", 0.0)
	await get_tree().create_timer(0.5).timeout
	ok(pickup.has_picked_up(), "by default a lost hand holds on, as upstream")


func _test_drop_on_exit() -> void:
	await _rig()
	var c: RigidBody3D = _cart(_beside())
	var reasons: Array = []
	pickup.dropped.connect(func(by: GXDKPickup, _what: PhysicsBody3D) -> void: reasons.append(by.get_drop_reason()))
	await _frames(5)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	ok(pickup.get_picked_up() == c, "taken")
	hand.remove_child(pickup)
	ok(reasons == [GXDKPickup.DropReason.EXITING], "leaving the tree isn't a release")
	pickup.free()


func _test_open_first_wobble() -> void:
	lc.set_input("trigger", 1.0)
	await _rig()
	pickup.require_open_first = true
	pickup.grab_threshold = 0.75
	pickup.release_threshold = 0.4
	pickup.grab_window = 0.35
	_cart(_beside())
	await _frames(5)
	lc.set_input("trigger", 0.6)
	await _frames(3)
	lc.set_input("trigger", 1.0)
	await _frames(5)
	ok(not pickup.has_picked_up(), "a closed pinch wobbling to 0.6 hasn't opened")
	lc.set_input("trigger", 0.4)
	await _frames(3)
	lc.set_input("trigger", 1.0)
	await _frames(5)
	ok(pickup.has_picked_up(), "at the release threshold it has")


func _test_pinch_on_grip() -> void:
	await _rig()
	_grab_values()
	lc.set_input("grip", 1.0)
	await _frames(2)
	await get_tree().create_timer(0.3).timeout
	var c: RigidBody3D = _cart(_beside())
	await _frames(5)
	ok(not pickup.has_picked_up(), "a grip held past the window takes nothing")
	lc.set_input("trigger", 0.6)
	await _frames(3)
	ok(not pickup.has_picked_up(), "a pinch below the threshold isn't a press")
	lc.set_input("trigger", 1.0)
	await _frames(3)
	ok(pickup.get_picked_up() == c, "a fresh pinch on a closed grip takes it")
	lc.set_input("grip", 0.0)
	await _frames(3)
	ok(pickup.has_picked_up(), "the grip going while the pinch holds doesn't drop it")
	lc.set_input("trigger", 0.0)
	await _frames(3)
	ok(not pickup.has_picked_up(), "the pinch opening ends the hold")
	c.queue_free()
	await _frames(3)
	lc.set_input("grip", 1.0)
	await _frames(2)
	await get_tree().create_timer(0.3).timeout
	lc.set_input("trigger", 1.0)
	await _frames(2)
	lc.set_input("trigger", 0.6)
	await _frames(2)
	lc.set_input("trigger", 1.0)
	await get_tree().create_timer(0.3).timeout
	_cart(_beside())
	await _frames(5)
	ok(not pickup.has_picked_up(), "a wobble isn't a new press, and arriving past the window takes nothing")


func _test_pinch_on_grip_open_first() -> void:
	lc.set_input("grip", 1.0)
	lc.set_input("trigger", 1.0)
	await _rig()
	_grab_values()
	pickup.require_open_first = true
	var c: RigidBody3D = _cart(_beside())
	await _frames(5)
	lc.set_input("trigger", 0.6)
	await _frames(2)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	ok(not pickup.has_picked_up(), "held through a start, a wobble in the pinch doesn't take")
	lc.set_input("trigger", 0.0)
	await _frames(2)
	lc.set_input("trigger", 1.0)
	await _frames(3)
	ok(pickup.get_picked_up() == c, "a pinch that really opened counts, with the grip still closed")


func _test_pinch_owns_hold() -> void:
	var c: RigidBody3D = await _curled_hand_rig()
	lc.set_input("trigger", 1.0)
	lc.set_input("grip", 1.0)
	await _frames(3)
	ok(pickup.get_picked_up() == c, "pinch and curl take it")
	lc.set_input("trigger", 0.07)
	await _frames(3)
	ok(not pickup.has_picked_up(), "opening the pinch lets go, with the grip still at 1.0")
	ok(pickup.get_drop_reason() == GXDKPickup.DropReason.RELEASED, "as a release")


func _test_no_retake_with_curled_hand() -> void:
	var c: RigidBody3D = await _curled_hand_rig()
	lc.set_input("trigger", 1.0)
	lc.set_input("grip", 1.0)
	await _frames(3)
	lc.set_input("trigger", 0.0)
	await _frames(10)
	ok(not pickup.has_picked_up(), "still curled after a release, it stays let go")
	lc.set_input("trigger", 1.0)
	await _frames(3)
	ok(pickup.get_picked_up() == c, "a new pinch takes it again")
	lc.set_input("trigger", 0.0)
	await _frames(3)
	lc.set_input("grip", 0.0)
	await _frames(3)
	lc.set_input("grip", 1.0)
	await _frames(3)
	ok(pickup.get_picked_up() == c, "and so does the grip opening and rising")


func _test_secondary_only_hold() -> void:
	var c: RigidBody3D = await _curled_hand_rig()
	lc.set_input("grip", 1.0)
	await _frames(3)
	ok(pickup.get_picked_up() == c, "a palm grab takes it")
	lc.set_input("trigger", 0.6)
	await _frames(2)
	ok(pickup.has_picked_up(), "a half pinch changes nothing")
	lc.set_input("grip", 0.0)
	await _frames(3)
	ok(not pickup.has_picked_up(), "the grip opening ends it, with the pinch never closed")


func _test_pinch_takes_over() -> void:
	var c: RigidBody3D = await _curled_hand_rig()
	lc.set_input("grip", 1.0)
	await _frames(3)
	ok(pickup.get_picked_up() == c, "the grip gets there first")
	lc.set_input("trigger", 1.0)
	await _frames(3)
	lc.set_input("grip", 0.0)
	await _frames(3)
	ok(pickup.has_picked_up(), "the pinch closing a moment later owns it, the grip going changes nothing")
	lc.set_input("grip", 1.0)
	await _frames(2)
	lc.set_input("trigger", 0.0)
	await _frames(3)
	ok(not pickup.has_picked_up(), "and its opening ends it")


func _test_unsure_open_with_curl() -> void:
	var c: RigidBody3D = await _curled_hand_rig()
	pickup.loss_release_time = 0.4
	lc.set_input("trigger", 1.0)
	lc.set_input("grip", 1.0)
	await _frames(3)
	ok(pickup.get_picked_up() == c, "taken")
	_pose(hxf, XRPose.XR_TRACKING_CONFIDENCE_LOW)
	lc.set_input("trigger", 0.0)
	await _frames(3)
	ok(pickup.has_picked_up(), "opening the pinch on an unsure frame isn't a release, curled or not")
	lc.set_input("trigger", 1.0)
	_pose(hxf)
	await _frames(3)
	ok(pickup.has_picked_up(), "pinching again carries on")


func _grab_values() -> void:
	pickup.secondary_grab_action = "grip"
	pickup.grab_threshold = 0.75
	pickup.release_threshold = 0.4
	pickup.grab_window = 0.2
	pickup.keep_grip_on_grab = true


# David's log: a natural curl reads grip 1.00 with the pinch at 0.00 and 0.07.
func _curled_hand_rig() -> RigidBody3D:
	await _rig()
	pickup.secondary_grab_action = "grip"
	pickup.grab_threshold = 0.75
	pickup.release_threshold = 0.4
	pickup.grab_window = 0.35
	pickup.keep_grip_on_grab = true
	var c: RigidBody3D = _cart(_beside(), true)
	await _frames(5)
	return c
