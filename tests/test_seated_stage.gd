extends "res://tests/test_base.gd"


func tests() -> Array[Callable]:
	return [
		_test_take_carry_insert,
		_test_lost_hand_doesnt_insert,
		_test_menu_toggles_label,
	]


func _load_stage() -> Node3D:
	scene = Node3D.new()
	get_tree().root.add_child(scene)
	var packed: PackedScene = load("res://stages/seated_stage/seated_stage.tscn")
	var stage: Node3D = packed.instantiate()
	scene.add_child(stage)
	_pose(hxf)
	await _frames(5)
	return stage


func _reach(at: Vector3) -> void:
	_pose(Transform3D(Basis(), at))
	await get_tree().physics_frame
	await _frames(3)


func _take(box: Node3D) -> void:
	lc.set_input("trigger", 0.0)
	await _frames(2)
	await _reach(box.global_position)
	lc.set_input("trigger", 1.0)
	await _frames(3)


func _test_take_carry_insert() -> void:
	var stage: Node3D = await _load_stage()
	var box: RigidBody3D = stage.get_node("BoxB")
	var slot: GXDKSnapZone = stage.get_node("Slot")
	var pickup_node: GXDKPickup = stage.get_node("Seat/XROrigin3D/LeftCollisionHand/Pickup")
	var at: Vector3 = box.global_position
	await _take(box)
	ok(pickup_node.get_picked_up() == box, "a pinch takes the box")
	ok(box.global_position.distance_to(at) < 0.001, "and it doesn't jump")
	await _reach(at + Vector3(0.1, 0.0, 0.0))
	ok(box.global_position.distance_to(at + Vector3(0.1, 0.0, 0.0)) < 0.001, "it's rigid in the hand")
	await _reach(slot.global_position + Vector3(0.0, 0.03, 0.0))
	ok(slot.get_axis_assist(box.global_position) > 0.5, "near the slot it's helped")
	lc.set_input("trigger", 0.0)
	await _frames(3)
	ok(GXDKSnapZone.captured_by(box) == slot, "letting go there seats it")
	ok(box.global_position.distance_to(slot.global_position) < 0.001, "at the slot")
	await _take(box)
	ok(pickup_node.get_picked_up() == box, "it can be taken out again")
	ok(GXDKSnapZone.captured_by(box) == null, "which frees the slot")


func _test_lost_hand_doesnt_insert() -> void:
	var stage: Node3D = await _load_stage()
	var box: RigidBody3D = stage.get_node("BoxA")
	var slot: GXDKSnapZone = stage.get_node("Slot")
	var pickup_node: GXDKPickup = stage.get_node("Seat/XROrigin3D/LeftCollisionHand/Pickup")
	await _take(box)
	await _reach(slot.global_position + Vector3(0.0, 0.03, 0.0))
	_lost()
	await get_tree().create_timer(0.6).timeout
	ok(not pickup_node.has_picked_up(), "lost for a while, it lets go")
	ok(GXDKSnapZone.captured_by(box) == null, "and a lost hand doesn't put it in the slot")


func _test_menu_toggles_label() -> void:
	var stage: Node3D = await _load_stage()
	var gestures: GXDKHandGestures = stage.get_node("Seat/XROrigin3D/LeftGestures")
	var label: Label3D = stage.get_node("Label")
	gestures.settle_time = 0.0
	gestures._settle_left = 0.0
	var seen: bool = label.visible
	gestures.menu_pressed.emit("gesture")
	await _frames(2)
	ok(label.visible != seen, "the menu gesture toggles the label")
