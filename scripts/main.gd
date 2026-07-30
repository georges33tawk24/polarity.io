extends Node3D
## Root node. Owns the UI and swaps the arena in and out.

var ui: Ui
var arena: Arena
var rig: CameraRig
var _loading: LoadingScreen = null


func _ready() -> void:
	ui = Ui.new()
	add_child(ui)
	# Dev-only. A release export never runs this branch, so the cheat calls are
	# not reachable in a shipped binary.
	if OS.is_debug_build():
		var overlay := DebugOverlay.new()
		overlay.main = self
		add_child(overlay)

	ui.play_pressed.connect(start_match)
	# Printed once so "did the authored art actually load?" is never a guess.
	call_deferred("_report_assets")
	ui.menu_pressed.connect(to_menu)
	to_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause") and arena != null:
		to_menu()


func _report_assets() -> void:
	print("[polarity] ", AssetLibrary.source_report())


func to_menu() -> void:
	_clear()
	ui.show_screen("menu")


func start_match() -> void:
	if _loading != null:
		return   # already building; ignore a double tap on PLAY
	_clear()

	_loading = LoadingScreen.new()
	add_child(_loading)
	# One frame so the loader is actually on screen before the heavy work
	# starts — otherwise it is constructed and torn down within one blocked
	# frame and the player still sees a freeze.
	await get_tree().process_frame

	rig = CameraRig.new()
	add_child(rig)
	arena = Arena.new()
	add_child(arena)

	var stages := arena.setup_staged(Game.tuning, rig)
	# Music synthesis is ~200k samples per track; building it here hides the
	# cost behind the loader instead of hitching the first frame of play.
	stages.append(func() -> void:
		Audio.ensure_music("game")
		Audio.ensure_music("intensity"))
	for i in stages.size():
		stages[i].call()
		_loading.set_progress(float(i + 1) / stages.size())
		await get_tree().process_frame

	# The loader dismisses itself and nothing waits on it, so it can never block
	# the match starting. The handle is kept so _clear() can reap it if the match
	# is torn down before its minimum display time elapses.
	_loading.complete()

	ui.show_screen("hud")
	ui.attach_minimap(arena)
	ui.start_ftue(arena)


func _clear() -> void:
	Engine.time_scale = 1.0
	if _loading != null and is_instance_valid(_loading):
		_loading.queue_free()
		_loading = null
	Audio.set_hum(0.0)
	if ui != null:
		ui.stop_ftue()
	if arena != null:
		arena.queue_free()
		arena = null
	if rig != null:
		rig.queue_free()
		rig = null
