#-------------------------------------------------------------------------------
# gxdk_poke_press.gd
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

class_name GXDKPokePress
extends RefCounted

## GXDK Poke Press
##
## The rules for pressing a button with an index fingertip, as plain inputs so
## they can be used and tested without a headset.
## A press needs the fingertip to have been in front of the button's face,
## inside its outline, and then go past the face with the hand open. Sweeping
## in from behind or from the side never presses.


#region Public variables
## How far past the face our fingertip must go to press.
var press_depth: float = 0.007

## How far it must come back before it can press again.
var retract_distance: float = 0.010

## Above this pinch value the hand counts as pinching, and doesn't press.
var max_pinch: float = 0.3

## We press at most once per this many seconds.
var cooldown: float = 0.25

## Our fingertip has been in front of the face, inside the outline.
var armed: bool = false

## We've pressed and haven't retracted yet.
var down: bool = false
#endregion


#region Private variables
var _last_press: float = -1000.0
#endregion


#region Public functions
## Returns [code]true[/code] on the frame of a press.
## [param depth] is how far our fingertip is past the face, negative is in front.
## [param inside] is whether it's within the button's outline.
## [param now] is the current time in seconds.
func step(depth: float, inside: bool, pinch: float, now: float) -> bool:
	if down:
		if depth < press_depth - retract_distance or not inside:
			down = false
			armed = inside and depth < 0.0
		return false

	if not inside:
		armed = false
		return false

	if depth < 0.0:
		armed = true
		return false

	if armed and depth >= press_depth and pinch < max_pinch and now - _last_press >= cooldown:
		down = true
		armed = false
		_last_press = now
		return true

	return false
#endregion
