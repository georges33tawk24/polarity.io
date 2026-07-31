class_name Intent
extends RefCounted
## Input abstraction. Gameplay reads `dir` and `held` — never a device event.
##
## Touch: press anywhere; that spot becomes a floating stick. Push away from it to
## steer. Holding attracts, releasing repels, so one thumb does both — that is the
## whole game and the control must not split it across two fingers.
## Mouse: identical, with the left button.
## Keyboard: WASD/arrows to steer, space/shift to attract.
##
## ## Why the stick floats instead of pointing at the thumb
##
## This used to steer toward wherever the thumb WAS on screen: `dir` was the vector
## from the magnet's on-screen position to the finger. Two things made that awful on
## a phone, and both got reported as "i move in slowmotion".
##
## The camera follows the magnet, so the magnet is always near the middle of the
## screen. Full input needed the thumb a full `reach` away from the CENTRE of the
## display — and the moment you started moving, the magnet slid toward your thumb
## and shrank the very vector that was driving it. Steady-state was a fraction of
## full tilt: you accelerate, the input decays, you settle at a crawl. To keep
## moving you had to keep dragging further out, which is exactly what the player
## described as having to drag their thumb across the whole screen.
##
## Anchoring at the touch-down point instead makes the gesture relative: a short
## push in a direction is full tilt in that direction, forever, and the magnet
## catching up changes nothing because the anchor does not move with it.

var dir := Vector2.ZERO
var held := false
## Screen position of the active pointer.
var pointer_pos := Vector2.ZERO
## Where the stick is centred — the point the thumb landed on, re-centred as it
## travels. Read by the HUD to draw the stick.
var anchor := Vector2.ZERO
var pointer_down := false

## Stick throw, as a fraction of the shorter viewport axis. At 1080x1920 this is
## ~162px, about 1cm of thumb travel for full speed. A fraction rather than a
## constant so a tablet and a phone ask for the same physical gesture.
const REACH_FRACTION := 0.15
## Inside this fraction of the throw, the stick reads as centred. Stops a tap
## meant purely as an attract-and-release from also nudging the magnet.
const DEAD_FRACTION := 0.12

var _touch_index := -1


func handle_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_begin(event.position)
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
			if event.pressed:
				_begin(event.position)
			else:
				pointer_down = false
	elif event is InputEventMouseMotion:
		if _touch_index == -1:
			pointer_pos = event.position


## A new hold. The stick is born under the finger, so the first frame of any press
## is dead centre and the magnet does not lurch toward wherever the thumb happens
## to have landed.
func _begin(pos: Vector2) -> void:
	pointer_down = true
	pointer_pos = pos
	anchor = pos


## `toggle` scheme: a tap flips attract on/off instead of requiring a held
## finger. Requested by the spec for accessibility — sustained holding is
## painful for some players and impossible for others.
var toggle_active := false


## `vp` is the viewport size. The magnet's own screen position is deliberately not
## an input any more — see the note at the top of the file.
func update(vp: Vector2) -> void:
	var scheme := String(Game.get_value("control_scheme", "drag"))
	var kb := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if kb.length_squared() > 0.01:
		dir = kb.limit_length(1.0)
		held = Input.is_action_pressed("magnet_hold") or pointer_down
		return

	if pointer_down:
		var reach := maxf(minf(vp.x, vp.y) * REACH_FRACTION, 1.0)
		var delta := pointer_pos - anchor
		var dist := delta.length()
		if dist > reach:
			# Drag the anchor along behind the thumb. Without this the stick pins at
			# the rim and a reversal costs a full screen of travel to unwind; with
			# it, one throw-length in the new direction is always enough. It is also
			# what keeps a long swipe from walking the thumb off the display.
			anchor += delta * ((dist - reach) / dist)
			delta = pointer_pos - anchor
			dist = reach
		dir = Vector2.ZERO if dist < reach * DEAD_FRACTION else delta / reach
		held = true if scheme != "toggle" else toggle_active
		return

	dir = Vector2.ZERO
	held = Input.is_action_pressed("magnet_hold") or (scheme == "toggle" and toggle_active)


## Stick deflection, 0..1 from the anchor. For drawing only.
func throw() -> Vector2:
	return dir.limit_length(1.0)


func release() -> void:
	pointer_down = false
	_touch_index = -1
	dir = Vector2.ZERO
	held = false
