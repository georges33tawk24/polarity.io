extends Node
## Draws the floating stick at a few deflections so it can actually be looked at.
##   Godot res://tests/stick_shot.tscn -- --shot=/path/out.png
##
## It exists because the stick only ever draws while a finger is down, which no
## test and no screenshot harness produces — and "a screen that has never been
## rendered by anything" is how five broken modals and an unreadable settings page
## reached a device in this project. A structural check that the node exists says
## nothing about whether it draws something a player can use.

func _ready() -> void:
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.substr(7)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The arena floor's own tone, so the stick's contrast is judged against what it
	# will really sit on rather than against black.
	bg.color = Color(0.196, 0.192, 0.184)
	add_child(bg)

	var vp := get_viewport().get_visible_rect().size
	var reach: float = minf(vp.x, vp.y) * Intent.REACH_FRACTION
	# Centre, half tilt, full tilt, and pushed past the rim (which re-centres).
	var cases := [Vector2.ZERO, Vector2(reach * 0.5, 0), Vector2(0, reach),
			Vector2(reach * 3.0, reach * 3.0)]
	var spots := [Vector2(vp.x * 0.28, vp.y * 0.24), Vector2(vp.x * 0.72, vp.y * 0.24),
			Vector2(vp.x * 0.28, vp.y * 0.68), Vector2(vp.x * 0.72, vp.y * 0.68)]

	Game.set_value("joystick", true)
	for i in cases.size():
		var it := Intent.new()
		var down := InputEventScreenTouch.new()
		down.index = 0
		down.pressed = true
		down.position = spots[i]
		it.handle_event(down)
		if cases[i] != Vector2.ZERO:
			var drag := InputEventScreenDrag.new()
			drag.index = 0
			drag.position = spots[i] + cases[i]
			it.handle_event(drag)
		it.update(vp)

		var s := Ui.Stick.new()
		s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.intent = it
		add_child(s)

		var lbl := Label.new()
		lbl.position = spots[i] + Vector2(-90, reach + 24)
		lbl.text = "dir %.2f, %.2f" % [it.dir.x, it.dir.y]
		add_child(lbl)

	if shot == "":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("stick shot %s -> %s" % ["ok" if img.save_png(shot) == OK else "FAILED", shot])
	get_tree().quit(0)
