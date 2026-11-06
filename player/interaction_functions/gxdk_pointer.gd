#-------------------------------------------------------------------------------
# gxdk_pointer.gd
#-------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2026-present Bastiaan Olij, Malcolm A Nixon and contributors
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#-------------------------------------------------------------------------------

@tool
class_name GXDKPointer
extends GXDKHandAttachment

#region Event classes
class PointerEvent:
	var pointer: GXDKPointer
	var pointing_at: Vector3
	var pressed: bool

class GainedFocusEvent extends PointerEvent:
	pass

class LostFocusEvent extends PointerEvent:
	pass

class PressedEvent extends PointerEvent:
	pass

class ReleasedEvent extends PointerEvent:
	pass

class MovedEvent extends PointerEvent:
	var was_pointing_at: Vector3
#endregion


#region Export variables
## Is our pointer enabled?
@export var enabled: bool = true:
	set(value):
		enabled = value

		if _laser:
			_laser.visible = show_laser and enabled
		if _raycast:
			_raycast.enabled = enabled
		if _interacting_pressed and not enabled:
			_released()
		if _focus_on and not enabled:
			_loose_focus()
		if not enabled:
			_action_pressed = false
			_reset_aim_smoothing()

		set_process(enabled and not Engine.is_editor_hint())

## Action in our action map that triggers our pressed state.
@export var press_action: String = "trigger"

## Our press action must go above this to press.
@export_range(0.0, 1.0, 0.01) var press_threshold: float = 0.7

## Our press action must go below this to release.
@export_range(0.0, 1.0, 0.01) var release_threshold: float = 0.3

## If true a press already held when this node starts doesn't count:
## the hand has to open first (for instance when a scene is reloaded).
@export var require_open_first: bool = false

## If true we aim with the aim pose of our tracker, if it has one, instead of
## a bone of our hand.
@export var use_aim_pose: bool = false

## The pose actions to try, in order, when using our aim pose.
@export var aim_pose_actions: Array[String] = [ "aim", "aim_pose" ]

## If true a press held while we move onto an object presses it.
## If false only a press started while pointing at it does.
@export var press_on_arrival: bool = true

## If not 0.0, smooth our aim pose: pinching moves the hand, so a raw ray
## jitters. This cutoff in Hz applies while the hand is nearly still, lower is smoother.
@export_range(0.0, 30.0, 0.1) var aim_smoothing: float = 0.0

## How much less we smooth as our aim moves faster.
@export_range(0.0, 30.0, 0.1) var aim_smoothing_speed: float = 3.0

## Color of our laser and target.
@export var color: Color = Color(1.0, 0.0, 0.0):
	set(value):
		color = value
		if is_inside_tree():
			_update_color()

## To what distance do we perform our raycast?
@export var cast_distance: float = 3.0:
	set(value):
		cast_distance = value
		if _laser:
			_update_laser()
		if _raycast:
			_update_raycast()

## What collision layers do we interact with?
@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value
		if _raycast:
			_update_raycast()

## Does our ray collide with areas? Note that our UI components use areas so this is on by default.
@export var collide_with_areas: bool = true:
	set(value):
		collide_with_areas = value
		if _raycast:
			_raycast.collide_with_areas = collide_with_areas

## Does our ray collide with bodies? 
@export var collide_with_bodies: bool = false:
	set(value):
		collide_with_bodies = value
		if _raycast:
			_raycast.collide_with_bodies = collide_with_bodies

## Show our laser?
@export var show_laser: bool = true:
	set(value):
		show_laser = value
		if _laser:
			_laser.visible = show_laser and enabled

## Show our target? We only show this when we are colliding
@export var show_target: bool = false
#endregion


#region Private variables
var _raycast: RayCast3D
var _laser: MeshInstance3D
var _target: MeshInstance3D
var _override_laser_distance: float = 0.0
var _xr_controller: XRController3D
var _has_opened: bool = false
var _action_pressed: bool = false
var _pressed_elsewhere: bool = false
var _has_aim_pose: bool = false
var _aim_origin_filter: GXDKOneEuroFilter
var _aim_direction_filter: GXDKOneEuroFilter

# Controlling our focus and interactions
var _focus_on: CollisionObject3D
var _interacting_point: Vector3 = Vector3()
var _interacting_pressed: bool = false
#endregion


#region Public functions
## Returns [code]true[/code] if we're currently pressing an object.
func is_pressed() -> bool:
	return _interacting_pressed


## Returns [code]true[/code] if our press action is pressed, pointing at something or not.
func is_action_pressed() -> bool:
	return _action_pressed


## Returns [code]true[/code] if we're pointing along our aim pose this frame.
func has_aim_pose() -> bool:
	return _has_aim_pose


## Returns the object we're pointing at, if any.
func get_target() -> CollisionObject3D:
	return _focus_on


## Returns the point we're pointing at.
func get_target_point() -> Vector3:
	return _interacting_point
#endregion


#region Private functions
func _update_laser() -> void:
	var length = _override_laser_distance if _override_laser_distance > 0.0 else cast_distance
	_laser.position = Vector3(0.0, 0.0, -length * 0.5)
	# We scale instead of changing our mesh size, this prevents having to update the mesh on the GPU.
	_laser.scale = Vector3(1.0, length, 1.0)


func _update_raycast() -> void:
	_raycast.target_position = Vector3(0.0, 0.0, -cast_distance)
	_raycast.collision_mask = collision_mask


func _update_color() -> void:
	if _laser:
		var material: ShaderMaterial = _laser.mesh.surface_get_material(0)
		if material:
			material.set_shader_parameter("albedo", color)

	if _target:
		var material: ShaderMaterial = _target.mesh.surface_get_material(0)
		if material:
			material.set_shader_parameter("albedo", color)


# Is our action pressed?
func _is_action_pressed() -> bool:
	var input: Variant
	if _xr_collision_hand:
		input = _xr_collision_hand.get_input(press_action)
	elif _xr_controller:
		input = _xr_controller.get_input(press_action)

	var pressed: bool = false
	var value: float = 0.0
	if typeof(input) == TYPE_BOOL:
		pressed = input
		value = 1.0 if pressed else 0.0
	elif typeof(input) == TYPE_FLOAT:
		value = input
		var threshold: float = release_threshold if _action_pressed else press_threshold
		pressed = input > threshold

	# An input we don't have, or one read with no tracking, says nothing about our hand.
	if input != null and value <= release_threshold and (_has_aim_pose or not use_aim_pose):
		_has_opened = true

	return pressed and (_has_opened or not require_open_first)


# Forget our smoothing, so we don't ease in from where we last were.
func _reset_aim_smoothing() -> void:
	_aim_origin_filter = null
	_aim_direction_filter = null


# Returns the tracker that has our aim pose.
func _get_aim_tracker() -> XRPositionalTracker:
	if _xr_collision_hand:
		return _xr_collision_hand.get_controller_tracker()
	elif _xr_controller:
		return XRServer.get_tracker(_xr_controller.tracker)

	return null


# Point along our aim pose. Returns false if we have none.
func _update_aim(delta: float) -> bool:
	var tracker: XRPositionalTracker = _get_aim_tracker()
	var origin: XROrigin3D = GXDK.get_xr_origin(self)
	if not tracker or not origin:
		_reset_aim_smoothing()
		return false

	for action in aim_pose_actions:
		var pose: XRPose = tracker.get_pose(action)
		if pose and pose.has_tracking_data:
			var aim: Transform3D = origin.global_transform * pose.get_adjusted_transform()
			if aim_smoothing > 0.0:
				if not _aim_origin_filter:
					_aim_origin_filter = GXDKOneEuroFilter.new(aim_smoothing, aim_smoothing_speed)
					_aim_direction_filter = GXDKOneEuroFilter.new(aim_smoothing, aim_smoothing_speed)
				aim.origin = _aim_origin_filter.filter(aim.origin, delta)
				var forward: Vector3 = _aim_direction_filter.filter(-aim.basis.z.normalized(), delta)
				if forward.length_squared() > 0.0001:
					var up: Vector3 = Vector3.UP if absf(forward.normalized().y) < 0.99 else Vector3.FORWARD
					aim.basis = Basis.looking_at(forward.normalized(), up)
			global_transform = aim
			return true

	_reset_aim_smoothing()
	return false


# With an aim pose, a bone of our hand doesn't position us.
func _on_skeleton_updated():
	if use_aim_pose:
		return

	super()


# Update our properties
func _validate_property(property) -> void:
	super(property)

	# We manage these so hide them.
	if property.name in [ "bone_name", "position_offset", "rotation_offset" ]:
		property.usage = PROPERTY_USAGE_NO_EDITOR


# Called when we enter the scene tree.
func _enter_tree() -> void:
	super()

	if _xr_collision_hand:
		bone_name = "LeftMiddleMetacarpal" if _xr_collision_hand.hand == 0 else "RightMiddleMetacarpal"
		position_offset = Vector3(0.03 if _xr_collision_hand.hand == 0 else -0.03, 0.0, -0.06)
	else:
		_xr_controller = GXDK.get_xr_controller(self)

		# We should position our node based on the pose used for the controller.
		# We can use our position offset and rotation offset for this
		position_offset = Vector3(0.0, 0.0, 0.0)


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_laser = MeshInstance3D.new()
	_laser.mesh = load("res://addons/godot-xr-development-kit/player/interaction_functions/laser_mesh.tres").duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL)
	add_child(_laser, false, Node.INTERNAL_MODE_BACK)
	_laser.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_laser.visible = show_laser and enabled
	_update_laser()

	_target = MeshInstance3D.new()
	_target.mesh = load("res://addons/godot-xr-development-kit/player/interaction_functions/target_mesh.tres").duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL)
	add_child(_target, false, Node.INTERNAL_MODE_BACK)
	_target.top_level = true
	_target.visible = false

	_update_color()

	# In editor we don't need the rest.
	if Engine.is_editor_hint():
		set_process(false)
		return

	_raycast = RayCast3D.new()
	_raycast.collide_with_areas = collide_with_areas
	_raycast.collide_with_bodies = collide_with_bodies
	add_child(_raycast, false, Node.INTERNAL_MODE_BACK)
	_update_raycast()

	set_process(enabled)


func _exit_tree():
	_xr_controller = null
	super()


func _process(delta: float) -> void:
	# In editor we don't do this
	if Engine.is_editor_hint():
		return

	# If not enabled, do nothing
	if not enabled:
		_target.visible = false
		return

	_has_aim_pose = use_aim_pose and _update_aim(delta)
	if _has_aim_pose:
		# Our ray doesn't wait for the next physics step
		_raycast.force_raycast_update()

	var pressed: bool = _is_action_pressed()
	if pressed and not _action_pressed:
		_pressed_elsewhere = not _raycast.is_colliding()
	_action_pressed = pressed

	if _interacting_pressed and _interacting_pressed != pressed:
		_released()

	if _raycast.is_colliding():
		var point = _raycast.get_collision_point()
		var obj = _raycast.get_collider()
		_override_laser_distance = (point - global_position).length()
		_update_laser()

		_target.visible = show_target
		_target.global_position = point

		# Ensure focus on this object, if it already is, nothing changes.
		_focus(obj, point)

		if _interacting_point != point:
			_moved(point)

		if pressed and _interacting_pressed != pressed and (press_on_arrival or not _pressed_elsewhere):
			_pressed()
	else:
		_target.visible = false

		_loose_focus()

		_interacting_point = Vector3()

		if _override_laser_distance > 0.0:
			_override_laser_distance = 0.0
			_update_laser()


func _focus(on: CollisionObject3D, at: Vector3) -> void:
	if _focus_on == on:
		return
	if _focus_on:
		_loose_focus()

	_focus_on = on
	_interacting_point = at

	var event = GainedFocusEvent.new()
	event.pointer = self
	event.pointing_at = _interacting_point
	event.pressed = _interacting_pressed

	# As we don't have traits yet, good old fashioned duck typing
	if _focus_on.has_method("_xr_pointer_input"):
		_focus_on._xr_pointer_input(event)


func _loose_focus() -> void:
	if not _focus_on:
		return

	var event = LostFocusEvent.new()
	event.pointer = self
	event.pointing_at = _interacting_point
	event.pressed = _interacting_pressed

	# As we don't have traits yet, good old fashioned duck typing
	if _focus_on.has_method("_xr_pointer_input"):
		_focus_on._xr_pointer_input(event)

	_focus_on = null


func _pressed():
	if _interacting_pressed:
		return

	_interacting_pressed = true

	if not _focus_on:
		return

	var event = PressedEvent.new()
	event.pointer = self
	event.pointing_at = _interacting_point
	event.pressed = _interacting_pressed

	# As we don't have traits yet, good old fashioned duck typing
	if _focus_on.has_method("_xr_pointer_input"):
		_focus_on._xr_pointer_input(event)

	# Q: Possibly recording this so we always sent our release here?
	# Or do we add some sort of capture state for this?


func _released() -> void:
	if not _interacting_pressed:
		return

	_interacting_pressed = false

	if not _focus_on:
		return

	var event = ReleasedEvent.new()
	event.pointer = self
	event.pointing_at = _interacting_point
	event.pressed = _interacting_pressed

	# As we don't have traits yet, good old fashioned duck typing
	if _focus_on.has_method("_xr_pointer_input"):
		_focus_on._xr_pointer_input(event)


func _moved(to: Vector3):
	if not _focus_on:
		_interacting_point = to
		return

	var event = MovedEvent.new()
	event.pointer = self
	event.was_pointing_at = _interacting_point
	event.pointing_at = to
	event.pressed = _interacting_pressed
	_interacting_point = to

	# As we don't have traits yet, good old fashioned duck typing
	if _focus_on.has_method("_xr_pointer_input"):
		_focus_on._xr_pointer_input(event)

#endregion
