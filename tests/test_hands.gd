extends "res://tests/test_base.gd"


func tests() -> Array[Callable]:
	return [
		_test_untracked_joint,
		_test_display_rate_visual_only,
		_test_display_rate_free,
		_test_display_rate_held_back,
		_test_display_rate_override,
	]


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


func _test_untracked_joint() -> void:
	await _rig()
	var skeleton: Skeleton3D = hand._hand_skeleton
	var bone: int = skeleton.find_bone("LeftIndexTip")
	lh.set_hand_joint_flags(XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL, 0)
	lh.set_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, hxf * Transform3D(Basis(Vector3.RIGHT, 1.0), Vector3(0.0, 0.0, -0.1)))
	await _frames(5)
	var with_gap: Basis = skeleton.get_bone_global_pose(bone).basis
	lh.set_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, hxf * Transform3D(Basis(Vector3.RIGHT, -1.0), Vector3(0.0, 0.0, -0.1)))
	await _frames(5)
	var moved: float = (with_gap * skeleton.get_bone_global_pose(bone).basis.inverse()).get_rotation_quaternion().get_angle()
	ok(moved > 0.5, "a joint with no data doesn't stop the fingers after it: moved %.2f rad" % moved)


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
		await get_tree().physics_frame
	await _frames(30)
	ok(hand.global_position.x < 0.2, "the body stops at the wall: x %.3f" % hand.global_position.x)
	ok(absf(mesh.global_position.x - hand.global_position.x) < 0.01, "and the hand stays with it: %.3f" % mesh.global_position.x)
	while x > 0.0:
		x -= 0.5 / 72.0
		_pose(Transform3D(Basis(), Vector3(x, 1.0, 0.0)))
		await get_tree().physics_frame
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
