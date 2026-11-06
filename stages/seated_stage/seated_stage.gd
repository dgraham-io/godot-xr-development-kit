@tool
extends GXDKStageBase

## This is our seated, hands only demo stage.
## Pinch a box to take it, carrying it rigidly in your hand, and push it into the slot.
## The menu gesture on your upturned left palm shows and hides the label.

@onready var _label: Label3D = $Label


func _on_left_gestures_menu_pressed(_source: String) -> void:
	_label.visible = not _label.visible
