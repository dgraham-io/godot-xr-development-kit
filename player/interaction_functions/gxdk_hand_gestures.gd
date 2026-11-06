#-------------------------------------------------------------------------------
# gxdk_hand_gestures.gd
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
class_name GXDKHandGestures
extends Node3D

## GXDK Hand Gestures Script
##
## This script reports the system gestures of a tracked hand, as given by the
## XR_FB_hand_tracking_aim extension through the Godot OpenXR Vendors plugin:
## the menu gesture that the runtime draws on the upturned left palm, and
## whether this hand is making a gesture that belongs to the system.
## Without that extension we only have the menu button and the palm angle.


#region Signals
## The menu gesture completed, or the menu button was pressed.
## [param source] says which of the two.
signal menu_pressed(source: String)
#endregion


#region Export variables
## Which hand are we watching?
@export_enum("Left","Right") var hand : int = 0:
	set(value):
		hand = value
		if is_inside_tree() and not Engine.is_editor_hint():
			_update_trackers()

## Ignore the menu gesture for this long after starting.
## Note: runtimes can report one as the application starts, with no hand there.
@export_range(0.0, 10.0, 0.1) var settle_time : float = 2.0

## A second menu gesture within this time is the same gesture.
@export_range(0.0, 5.0, 0.01) var repeat_time : float = 0.6

## Our palm counts as facing the head if the dot product with the direction to
## the head goes above this...
@export_range(0.0, 1.0, 0.01) var palm_enter_dot : float = 0.88

## ...and stays that way until it goes below this.
@export_range(0.0, 1.0, 0.01) var palm_exit_dot : float = 0.75

## Our palm only counts within this distance of the head.
@export_range(0.0, 2.0, 0.01) var palm_distance : float = 0.5
#endregion


#region Private variables
var _xr_origin : XROrigin3D
var _xr_camera : XRCamera3D

# Note: the aim tracker is a plain XRPositionalTracker, not an XRControllerTracker!
# Godot warns once that get_input is deprecated there, but it's what the plugin gives us.
var _aim_tracker : XRPositionalTracker
var _controller_tracker : XRPositionalTracker
var _hand_tracker : XRHandTracker

var _settle_left : float = 0.0
var _repeat_left : float = 0.0
var _system_gesture : bool = false
var _system_gesture_source : String = ""

# These inputs may only last a frame, so we catch them by their signals.
var _pending_source : String = ""
#endregion


#region Public functions
## Returns [code]true[/code] if this hand is making a gesture that belongs to
## the system, so it should press nothing.
func is_system_gesture() -> bool:
	return _system_gesture


## Returns what told us about the system gesture.
func get_system_gesture_source() -> String:
	return _system_gesture_source
#endregion


#region Private functions
func _enter_tree() -> void:
	_xr_origin = GXDK.get_xr_origin(self)

	if not Engine.is_editor_hint():
		_settle_left = settle_time
		_update_trackers()
		XRServer.tracker_added.connect(_on_tracker_signal)
		XRServer.tracker_removed.connect(_on_tracker_signal)
		XRServer.tracker_updated.connect(_on_tracker_signal)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		XRServer.tracker_added.disconnect(_on_tracker_signal)
		XRServer.tracker_removed.disconnect(_on_tracker_signal)
		XRServer.tracker_updated.disconnect(_on_tracker_signal)
		_set_aim_tracker(null)
		_set_controller_tracker(null)

	_xr_origin = null
	_xr_camera = null


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()

	if not GXDK.get_xr_origin(self):
		warnings.push_back("This node must be a child of an XROrigin3D node.")

	return warnings


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_settle_left = max(_settle_left - delta, 0.0)
	_repeat_left = max(_repeat_left - delta, 0.0)

	var source : String = _pending_source
	_pending_source = ""
	if not source.is_empty() and _settle_left <= 0.0 and _repeat_left <= 0.0:
		_repeat_left = repeat_time
		menu_pressed.emit(source)

	_update_system_gesture()


# The flags are menu_gesture on our left hand, and system_gesture on our right hand.
func _update_system_gesture() -> void:
	var flag : bool = _aim_tracker != null and \
		_aim_tracker.get_input("menu_gesture" if hand == 0 else "system_gesture") == true

	var palm : bool = _palm_faces_head()
	_system_gesture = flag or palm
	_system_gesture_source = "flag" if flag else ("palm angle" if palm else "")


func _palm_faces_head() -> bool:
	if not _xr_origin or not _hand_tracker or not _hand_tracker.has_tracking_data:
		return false

	if not is_instance_valid(_xr_camera):
		var cameras : Array[Node] = _xr_origin.find_children("*", "XRCamera3D", true, false)
		if cameras.is_empty():
			return false
		_xr_camera = cameras[0]

	var palm_joint : int = XRHandTracker.HAND_JOINT_PALM
	var palm_transform : Transform3D = \
		_xr_origin.global_transform * _hand_tracker.get_hand_joint_transform(palm_joint)
	var to_head : Vector3 = _xr_camera.global_position - palm_transform.origin
	if to_head.length() > palm_distance:
		return false

	# Our palm joints Y axis points out of the back of our hand.
	var threshold : float = palm_exit_dot if _system_gesture else palm_enter_dot
	return (-palm_transform.basis.y.normalized()).dot(to_head.normalized()) > threshold


func _update_trackers() -> void:
	var hand_name : String = "left" if hand == 0 else "right"
	_set_aim_tracker(XRServer.get_tracker("/user/fbhandaim/" + hand_name))
	_set_controller_tracker(XRServer.get_tracker(hand_name + "_hand"))
	_hand_tracker = XRServer.get_tracker("/user/hand_tracker/" + hand_name)


func _set_aim_tracker(tracker : XRPositionalTracker) -> void:
	if tracker == _aim_tracker:
		return

	if _aim_tracker:
		_aim_tracker.button_pressed.disconnect(_on_aim_button_pressed)

	_aim_tracker = tracker
	if _aim_tracker:
		_aim_tracker.button_pressed.connect(_on_aim_button_pressed)


func _set_controller_tracker(tracker : XRPositionalTracker) -> void:
	if tracker == _controller_tracker:
		return

	if _controller_tracker:
		_controller_tracker.button_pressed.disconnect(_on_controller_button_pressed)

	_controller_tracker = tracker
	if _controller_tracker:
		_controller_tracker.button_pressed.connect(_on_controller_button_pressed)


func _on_tracker_signal(_tracker_name : StringName, _type : int) -> void:
	_update_trackers()


func _on_aim_button_pressed(action_name : String) -> void:
	if action_name == "menu_pressed":
		_pending_source = "gesture"


func _on_controller_button_pressed(action_name : String) -> void:
	if action_name == "menu_button":
		_pending_source = "button"
#endregion
