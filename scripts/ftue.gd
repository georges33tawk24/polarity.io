class_name Ftue
extends Control
## First-time user experience: a guided first match.
##
## Runs *inside* a normal match rather than a scripted sandbox — the player is
## in a real arena with real bots from the first second (spec §4.7, §16: never
## block the first play session). It only adds a prompt and a highlight ring,
## and every step has a timeout so it can never soft-lock a real match.

signal finished

enum Step { HOLD, RELEASE, LAUNCH, DONE }

## Seconds of holding that counts as "understood the verb".
const HOLD_TARGET := 0.8
## Per-step ceiling. If a player is struggling, the tutorial gets out of the way
## rather than trapping them behind an instruction they cannot satisfy.
const STEP_TIMEOUT := 22.0

var arena: Arena

var _step := Step.HOLD
var _held := 0.0
var _timer := 0.0
var _pulse := 0.0
var _prompt: Label
var _flash: Label
var _ring: Control
var _screen_pos := Vector2.ZERO


func setup(a: Arena) -> void:
	arena = a


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_ring = Control.new()
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	add_child(_ring)

	_prompt = UiKit.lbl("", 72, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.offset_top = 260
	add_child(_prompt)

	_flash = UiKit.lbl("", 88, UiKit.SIGNAL_GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_flash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_flash.grow_vertical = Control.GROW_DIRECTION_BOTH
	_flash.modulate.a = 0.0
	add_child(_flash)

	var skip := UiKit.btn(tr("UI_SKIP"), Color.TRANSPARENT, 90)
	# Top LEFT: the leaderboard owns the top-right corner, and the skip button was
	# sitting on top of it.
	skip.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	skip.grow_horizontal = Control.GROW_DIRECTION_END
	skip.offset_top = 120
	skip.custom_minimum_size.x = 220
	skip.add_theme_font_size_override("font_size", 32)
	skip.pressed.connect(_complete)
	add_child(skip)

	Bus.repel_fired.connect(_on_repel)
	Bus.magnet_eliminated.connect(_on_eliminated)
	_set_step(Step.HOLD)


func _process(delta: float) -> void:
	if _step == Step.DONE or arena == null or not is_instance_valid(arena):
		return
	var player: Magnet = arena.player
	if player == null or not player.alive:
		# Dying mid-tutorial is a legitimate outcome; do not re-run it.
		_complete()
		return

	_pulse += delta * 3.0
	_timer += delta
	if arena.rig != null:
		_screen_pos = arena.rig.screen_point(player.global_position)
	_ring.queue_redraw()

	if _step == Step.HOLD:
		if player.holding:
			_held += delta
			if _held >= HOLD_TARGET:
				_praise()
				_set_step(Step.RELEASE)
	if _timer > STEP_TIMEOUT:
		# Move on rather than nag. The next step may be easier to satisfy.
		_set_step(Step.RELEASE if _step == Step.HOLD else Step.DONE)


func _on_repel(_pos: Vector3, _radius: float, _power: float) -> void:
	if _step == Step.RELEASE:
		_praise()
		_set_step(Step.LAUNCH)


func _on_eliminated(_victim: String, _killer: String, by_player: bool) -> void:
	if _step == Step.LAUNCH and by_player:
		_praise()
		_complete()


func _set_step(step: Step) -> void:
	_step = step
	_timer = 0.0
	match step:
		Step.HOLD: _prompt.text = tr("FTUE_HOLD")
		Step.RELEASE: _prompt.text = tr("FTUE_RELEASE")
		Step.LAUNCH: _prompt.text = tr("FTUE_LAUNCH")
		Step.DONE:
			_complete()
			return
	_prompt.modulate.a = 1.0


func _praise() -> void:
	_flash.text = tr("FTUE_NICE")
	_flash.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(_flash, "modulate:a", 0.0, 0.4)
	Audio.play("size_up", 1.1, -8.0)


func _complete() -> void:
	if _step == Step.DONE and not visible:
		return
	_step = Step.DONE
	Game.set_value("seen_tutorial", true)
	visible = false
	finished.emit()
	queue_free()


## Pulsing ring around the player. This is the "highlight" half of the
## zero-text guidance — the word alone does not say *where* to act.
func _draw_ring() -> void:
	if _step == Step.DONE or _screen_pos == Vector2.ZERO:
		return
	if Game.profile.get("reduced_motion", false):
		_ring.draw_arc(_screen_pos, 130.0, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 5.0, true)
		return
	var t: float = 0.5 + 0.5 * sin(_pulse)
	var radius: float = lerpf(110.0, 165.0, t)
	var alpha: float = lerpf(0.75, 0.15, t)
	_ring.draw_arc(_screen_pos, radius, 0.0, TAU, 48, Color(1, 1, 1, alpha), 6.0, true)
