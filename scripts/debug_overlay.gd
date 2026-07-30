class_name DebugOverlay
extends CanvasLayer
## FPS / memory / entity counts, and a cheat panel — dev builds only.
##
## Gated on `OS.is_debug_build()` so it cannot ship: an exported release build
## never constructs it, and the cheat calls are unreachable from a release
## binary rather than merely hidden behind a flag.

const KEY_TOGGLE := KEY_F3

var _label: Label
var _panel: VBoxContainer
var _samples: Array[float] = []
var main: Node


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.offset_left = 20
	root.offset_top = 20
	add_child(root)

	_label = UiKit.lbl("", 26, Color(0.6, 1.0, 0.7))
	root.add_child(_label)

	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 6)
	root.add_child(_panel)

	for entry: Array in [
		["+10k coins", func() -> void: Game.add_currency("coins", 10000, "cheat")],
		["+1k gems", func() -> void: Game.add_currency("gems", 1000, "cheat")],
		["unlock all", _unlock_all],
		["+500 trophies", func() -> void: Meta.add_trophies(500)],
		["reset profile", func() -> void: Backend.delete_account()],
		["reset tutorial", func() -> void: Game.set_value("seen_tutorial", false)],
		["roll day", _roll_day],
	]:
		var b := UiKit.btn(String(entry[0]), Color.TRANSPARENT, 64)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(entry[1])
		_panel.add_child(b)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TOGGLE:
		visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	_samples.append(Engine.get_frames_per_second())
	if _samples.size() > 60:
		_samples.pop_front()
	var lowest := 999.0
	for f in _samples:
		lowest = minf(lowest, f)

	var arena: Node = main.arena if main != null and "arena" in main else null
	var magnets := 0
	var scrap := 0
	if arena != null and is_instance_valid(arena):
		magnets = arena.magnets.size()
		scrap = arena.scrap.alive_count()

	# Worst-frame FPS matters more than the average — the average hides the
	# stutter players actually feel.
	_label.text = "FPS %d (low %d)\nmem %d MB\nmagnets %d  scrap %d\nnodes %d\nqueue %d  seg %s" % [
		Engine.get_frames_per_second(), int(lowest),
		int(OS.get_static_memory_usage() / 1048576),
		magnets, scrap,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Analytics.queue_size(), Config.segment(),
	]


func _unlock_all() -> void:
	for kind: String in Cosmetics.KINDS:
		for item: Dictionary in Cosmetics.all_of(kind):
			Cosmetics.grant(String(item["id"]))


## Shifts the stored day stamps back so daily/weekly rollover can be tested
## without waiting or changing the system clock.
func _roll_day() -> void:
	var daily: Dictionary = Game.get_value("daily", {})
	daily["last_day"] = Meta.today() - 1
	Game.set_value("daily", daily)
	Game.set_value("missions", {})
	Game.set_value("rewarded_day", -1)
