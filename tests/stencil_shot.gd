extends Node
## Renders the stencil glyph set to a PNG so the letterforms can be checked in
## isolation. Debugging a bad bridge inside a full menu capture is guesswork.
##   Godot res://tests/stencil_shot.tscn -- --shot=/path/out.png

func _ready() -> void:
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.substr(7)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.149, 0.141, 0.122)
	add_child(bg)

	var box := VBoxContainer.new()
	box.position = Vector2(30, 30)
	box.add_theme_constant_override("separation", 26)
	add_child(box)

	var w: Stencil.StencilLabel = Stencil.node("POLARITY", 96, Color(0.929, 0.910, 0.871))
	w.seam = 0.42
	w.rivet_in_o = true
	box.add_child(w)
	box.add_child(Stencil.node("0123456789", 74, Color(0.929, 0.910, 0.871)))
	box.add_child(Stencil.node("#3 +214 -12", 74, Color(0.910, 0.639, 0.239)))
	box.add_child(Stencil.node("1,240", 120, Color(0.929, 0.910, 0.871)))
	box.add_child(Stencil.node("POLARITY", 40, Color(0.780, 0.753, 0.698)))

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("stencil shot %s -> %s" % ["ok" if img.save_png(shot) == OK else "FAILED", shot])
	get_tree().quit()
