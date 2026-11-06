#-------------------------------------------------------------------------------
# gxdk_touch_drag.gd
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

class_name GXDKTouchDrag
extends RefCounted

## GXDK Touch Drag
##
## The rules for one hand on a control you touch: with the index finger, or
## with a pinch. As plain inputs, so they can be used and tested without a headset.
##
## The finger is armed in front of the control and inside its outline, and takes
## the control past its plane with the hand open. A touch that moves less than
## the slop is a tap when it ends; past that it moves, and never taps.
## The control keeps our hand until it lets go: the finger retracts or leaves
## the keep region, or a pinch opens. Losing tracking holds, carries on with no
## jump if tracking returns, and otherwise lets go.


#region Constants
## Not touching.
const NONE: int = 0

## Touching with our index finger.
const INDEX: int = 1

## Touching with a pinch.
const PINCH: int = 2
#endregion


#region Public variables
## How far past the plane our fingertip must go to touch.
var press_depth: float = 0.007

## How far it must come back before the touch ends.
var retract_distance: float = 0.010

## Above this pinch value the hand counts as pinching, and the finger doesn't touch.
var max_pinch: float = 0.3

## We tap at most once per this many seconds.
var cooldown: float = 0.25

## After losing tracking for this long, we let go.
var loss_release_time: float = 0.4

## Smooths our position while moving, in Hz.
var filter_rate: float = 12.0

## How we're touching: [constant NONE], [constant INDEX] or [constant PINCH].
var mode: int = NONE

## We've moved past the slop.
var moved: bool = false

## Our fingertip has been in front of the plane, inside the outline.
var armed: bool = false

## Our current velocity, for a glide after letting go.
var velocity: Vector2 = Vector2.ZERO
#endregion


#region Private variables
var _start: Vector2 = Vector2.ZERO
var _position: Vector2 = Vector2.ZERO
var _anchored: bool = false
var _lost: float = 0.0
var _last_tap: float = -1000.0
var _now: float = 0.0
#endregion


#region Public functions
## Advance our touch by a frame. Positions are in the plane of the control.
## Returns an empty dictionary, or any of:
## [code]started[/code] (position),
## [code]pos[/code] and [code]delta[/code] (smoothed position and how far it moved, past the slop),
## [code]ended[/code] (true) with [code]tap[/code] (bool) and [code]fling[/code] (velocity).
##
## [param tip_inside] our fingertip is within the control's outline.
## [param depth] how far our fingertip is past the plane, negative is in front.
## [param tip] our fingertip's position.
## [param tip_keep] our fingertip is within the region that keeps a touch going.
## [param pinch_inside] our pinch point is where it can take the control.
## [param pinch_position] our pinch point's position.
## [param pinch] our pinch value.
## [param pinch_started] our pinch closed this frame.
## [param pinch_held] our pinch is closed.
## [param confident] our hand is reliably tracked this frame.
## [param other_holds] our other hand has this control.
## [param delta] the time since our last step.
## [param slop] how far we must move before it's a move and not a tap.
func step(
		tip_inside: bool,
		depth: float,
		tip: Vector2,
		tip_keep: bool,
		pinch_inside: bool,
		pinch_position: Vector2,
		pinch: float,
		pinch_started: bool,
		pinch_held: bool,
		confident: bool,
		other_holds: bool,
		delta: float,
		slop: float
	) -> Dictionary:
	_now += delta

	if mode == NONE:
		if not tip_inside:
			armed = false
		elif depth < 0.0:
			armed = true

		if other_holds or not confident:
			return {}

		if pinch_started and pinch_inside:
			return _begin(PINCH, pinch_position)

		if armed and tip_inside and depth >= press_depth and pinch < max_pinch:
			armed = false
			return _begin(INDEX, tip)

		return {}

	if not confident:
		_anchored = false
		_lost += delta
		return _end(false) if _lost >= loss_release_time else {}

	_lost = 0.0

	var ending: bool
	if mode == PINCH:
		ending = not pinch_held
	else:
		ending = depth < press_depth - retract_distance or not tip_keep

	if ending:
		return _end(not moved and (mode == PINCH or tip_keep) and _now - _last_tap >= cooldown)

	var current: Vector2 = pinch_position if mode == PINCH else tip
	if not _anchored:
		# Tracking is back, carry on from here with no jump.
		_position = current
		_anchored = true
		return {}

	var before: Vector2 = _position
	_position += (current - _position) * (1.0 - exp(-delta * TAU * filter_rate))

	if not moved:
		if _position.distance_to(_start) < slop:
			return {}

		# We move from here, so nothing jumps by the slop.
		moved = true
		return { "pos": _position, "delta": Vector2.ZERO }

	var moved_by: Vector2 = _position - before
	velocity = velocity.lerp(moved_by / max(delta, 0.0001), clamp(delta * 12.0, 0.0, 1.0))
	return { "pos": _position, "delta": moved_by }
#endregion


#region Private functions
func _begin(p_mode: int, at: Vector2) -> Dictionary:
	mode = p_mode
	moved = false
	velocity = Vector2.ZERO
	_start = at
	_position = at
	_anchored = true
	_lost = 0.0
	return { "started": at }


func _end(tap: bool) -> Dictionary:
	var fling: Vector2 = velocity if moved and _lost == 0.0 else Vector2.ZERO
	mode = NONE
	moved = false
	armed = false
	velocity = Vector2.ZERO
	if tap:
		_last_tap = _now

	return { "ended": true, "tap": tap, "fling": fling }
#endregion
