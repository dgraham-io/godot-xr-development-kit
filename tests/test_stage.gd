extends GXDKStageBase
## A small stage for the staging tests.

static var loaded: Array = []
static var visible_with: Array = []
static var exiting: int = 0


func scene_loaded(user_data = null) -> void:
	super(user_data)
	loaded.append(user_data)


func scene_visible(user_data = null) -> void:
	visible_with.append(user_data)


func scene_exiting(_user_data = null) -> void:
	exiting += 1
