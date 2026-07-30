extends Node
## Renders every named icon to one sheet, so a glyph that silently fell through to
## `_draw_disc` is visible instead of shipping as a circle.
##   Godot res://tools/icon_sheet.tscn -- --shot=/path/out.png

const NAMES := ["coin", "gem", "trophy", "lock", "check", "star",
		"bag", "target", "bars", "gear", "card",
		"skin", "trail", "effect", "plate", "arena", "does_not_exist"]

func _ready() -> void:
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.substr(7)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.149, 0.141, 0.122)
	add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.position = Vector2(30, 30)
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 20)
	add_child(grid)
	for n: String in NAMES:
		var col := VBoxContainer.new()
		col.add_child(UiKit.icon(n, 96, UiKit.INK))
		col.add_child(UiKit.lbl(n, 20, UiKit.INK_MUTE, HORIZONTAL_ALIGNMENT_CENTER))
		grid.add_child(col)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("sheet %s -> %s" % ["ok" if img.save_png(shot) == OK else "FAIL", shot])
	get_tree().quit()
