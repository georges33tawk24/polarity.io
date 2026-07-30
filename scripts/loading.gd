class_name LoadingScreen
extends CanvasLayer
## Branded loader shown while a match builds.
##
## Exists because arena setup is not free — 420 scrap instances, 15 magnets,
## hazards and power-ups — and on a mid-range phone that is a visible hitch
## between tapping PLAY and the countdown. Without a loader the player taps and
## the screen freezes, which reads as a crash (spec §8, §9).

const MIN_SECONDS := 0.35   # below this the loader itself is the flicker

var _bar: ProgressBar
var _label: Label
var _pulse := 0.0
var _shown_at := 0.0
var _progress := 0.0
var _done := false


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shown_at = Time.get_ticks_msec() / 1000.0

	add_child(UiKit.backdrop())

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	add_child(box)

	box.add_child(UiKit.lbl("POLARITY", UiKit.T_DISPLAY, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	_label = UiKit.lbl(tr("UI_TAGLINE"), 32, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_label)
	box.add_child(UiKit.spacer(40))

	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 160)
	wrap.add_theme_constant_override("margin_right", 160)
	_bar = UiKit.bar(0.0, UiKit.ACCENT, 20)
	wrap.add_child(_bar)
	box.add_child(wrap)


func _process(delta: float) -> void:
	_pulse += delta * 2.0
	# Ease toward the reported progress so the bar never jumps or stalls dead.
	_bar.value = lerpf(float(_bar.value), _progress, clampf(delta * 8.0, 0.0, 1.0))
	_label.modulate.a = 0.55 + 0.25 * sin(_pulse)

	# Self-dismissing. An earlier version had start_match() await a `finished`
	# signal that this node emitted immediately before freeing itself, which
	# could strand the awaiting coroutine and hang the whole match start.
	if _done:
		var elapsed := Time.get_ticks_msec() / 1000.0 - _shown_at
		if elapsed >= MIN_SECONDS:
			queue_free()


func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)


func complete() -> void:
	_progress = 1.0
	_done = true
