extends "res://tests/test_base.gd"


func tests() -> Array[Callable]:
	return [
		_test_poke_press,
		_test_touch_drag_rules,
	]


# Our input per frame: all the arguments of step but delta and slop.
func _touch(t: GXDKTouchDrag, depth: float, tip: Vector2, keep: bool = true, confident: bool = true, slop: float = 0.003) -> Dictionary:
	return t.step(true, depth, tip, keep, false, Vector2.ZERO, 0.0, false, false, confident, false, 1.0 / 72.0, slop)


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
