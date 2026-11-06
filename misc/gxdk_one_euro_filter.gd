#-------------------------------------------------------------------------------
# gxdk_one_euro_filter.gd
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

class_name GXDKOneEuroFilter
extends RefCounted

## GXDK One Euro Filter
##
## Smooths a position or direction: heavily while it's nearly still, to hide
## tracking jitter, and hardly at all while it's moving, so it doesn't lag.
## See https://gery.casiez.net/1euro/


#region Private variables
var _min_cutoff: float
var _beta: float
var _has_value: bool = false
var _value: Vector3
var _derivative: Vector3
#endregion


#region Public functions
func _init(p_min_cutoff: float = 1.0, p_beta: float = 0.0):
	_min_cutoff = p_min_cutoff
	_beta = p_beta


## Start again from this value.
func reset(value: Vector3) -> void:
	_value = value
	_derivative = Vector3()
	_has_value = true


## Add a new value and return the smoothed one.
func filter(value: Vector3, delta: float) -> Vector3:
	if not _has_value or delta <= 0.0:
		reset(value)
		return value

	var derivative: Vector3 = (value - _value) / delta
	_derivative = _derivative.lerp(derivative, _alpha(1.0, delta))
	_value = _value.lerp(value, _alpha(_min_cutoff + _beta * _derivative.length(), delta))
	return _value
#endregion


#region Private functions
func _alpha(cutoff: float, delta: float) -> float:
	var tau: float = 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + tau / delta)
#endregion
