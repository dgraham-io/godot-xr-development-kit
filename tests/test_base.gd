extends Node
## What our tests share: fake XR trackers, so no XR runtime is needed, and a hand to drive.

const MASK := 2

static var checks: int = 0
static var failures: int = 0
static var allowed_errors: int = 0
static var lh: XRHandTracker
static var lc: XRControllerTracker

var scene: Node3D
var origin: XROrigin3D
var hand: GXDKCollisionHand
var pickup: GXDKPickup
var hxf: Transform3D = Transform3D(Basis(), Vector3(0.0, 1.0, 0.0))


## Set up our fake trackers, once.
static func trackers() -> void:
	lh = XRHandTracker.new()
	lh.name = "/user/hand_tracker/left"
	lh.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	lc = XRControllerTracker.new()
	lc.name = "left_hand"
	lc.type = XRServer.TRACKER_CONTROLLER
	lc.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	XRServer.add_tracker(lh)
	XRServer.add_tracker(lc)


## The tests in this file.
func tests() -> Array[Callable]:
	return []


## Runs after each test.
func clear() -> void:
	await _clear()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL ", what)


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
	get_tree().root.add_child(scene)
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
	await get_tree().physics_frame
	await get_tree().physics_frame


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
		await get_tree().process_frame
