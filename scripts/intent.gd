class_name Intent
extends RefCounted
## Input abstraction. Gameplay reads `dir` and `held` — never a device event.
##
## Touch: press anywhere to attract and steer toward your thumb, release to repel.
## Mouse: identical, with the left button.
## Keyboard: WASD/arrows to steer, space/shift to attract.

var dir := Vector2.ZERO
var held := false
## Screen position of the active pointer, for drawing the steer indicator.
var pointer_pos := Vector2.ZERO
var pointer_down := false

var _touch_index := -1


func handle_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			pointer_down = true
			pointer_pos = event.position
		elif not event.pressed and event.index == _touch_index:
			# Extra fingers are ignored; only the one that started the hold ends it.
			_touch_index = -1
			pointer_down = false
			if String(Game.get_value("control_scheme", "drag")) == "toggle":
				toggle_active = not toggle_active
	elif event is InputEventScreenDrag and event.index == _touch_index:
		pointer_pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# emulate_mouse_from_touch is ON, because Control/Button only listen for
		# mouse events and the UI is otherwise completely dead on a phone. The cost
		# is that every touch ALSO arrives here as a synthetic mouse event, so
		# ignore those: the ScreenTouch branch above already owns the gesture, and
		# it handles multi-finger cases a single emulated pointer cannot express.
		if _touch_index == -1:
			pointer_down = event.pressed
			pointer_pos = event.position
	elif event is InputEventMouseMotion:
		if _touch_index == -1:
			pointer_pos = event.position


## `toggle` scheme: a tap flips attract on/off instead of requiring a held
## finger. Requested by the spec for accessibility — sustained holding is
## painful for some players and impossible for others.
var toggle_active := false


## `player_screen` is where the magnet currently is on screen; `vp` the viewport size.
func update(player_screen: Vector2, vp: Vector2) -> void:
	var scheme := String(Game.get_value("control_scheme", "drag"))
	var kb := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if kb.length_squared() > 0.01:
		dir = kb.limit_length(1.0)
		held = Input.is_action_pressed("magnet_hold") or pointer_down
		return

	if pointer_down:
		var delta := pointer_pos - player_screen
		# Reach is a fraction of viewport height so the same physical gesture
		# gives the same input on a phone and a 4K monitor.
		var reach := maxf(vp.y * 0.16, 1.0)
		if delta.length() < vp.y * 0.015:
			dir = Vector2.ZERO   # dead zone directly under the thumb
		else:
			dir = (delta / reach).limit_length(1.0)
		held = true if scheme != "toggle" else toggle_active
		return

	dir = Vector2.ZERO
	held = Input.is_action_pressed("magnet_hold") or (scheme == "toggle" and toggle_active)


func release() -> void:
	pointer_down = false
	_touch_index = -1
	dir = Vector2.ZERO
	held = false
