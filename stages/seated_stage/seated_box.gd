extends RigidBody3D

## A box that's rigid in your hand, eases into line near a slot,
## and goes into the slot when you let go with the slot helping enough.

## The slot we can go into.
@export var slot: GXDKSnapZone

## Let go with at least this much help and we go into our slot.
@export_range(0.0, 1.0, 0.01) var seat_assist: float = 0.5


# Called by GXDKPickup each frame while we're held.
func _xr_custom_pickup_process(
		_pickup: GXDKPickup,
		_delta: float,
		_controller_target: Transform3D,
		global_target: Transform3D
	) -> void:
	global_transform = slot.get_axis_assisted(global_target) if slot else global_target


# Called by GXDKPickup when we're let go.
func dropped(by: GXDKPickup) -> void:
	# A lost hand isn't a decision to put us anywhere.
	if by.get_drop_reason() != GXDKPickup.DropReason.RELEASED:
		return

	if slot and slot.get_axis_assist(global_position) >= seat_assist:
		slot.capture_node(self)
