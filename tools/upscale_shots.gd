extends Node
## Doubles every store screenshot to 1080x1920.
##   Godot res://tools/upscale_shots.tscn
##
## macOS will not open a window taller than the display, so a capture at the real
## 1080x1920 comes back clamped to about 1574 tall — which is not 9:16, and Play
## rejects screenshots that are not 16:9 or 9:16. The window override is already
## exactly 9:16 at 540x960, so capture there and scale by an exact factor of two.
## Integer Lanczos is the least bad option available without a bigger display.

const DIR := "res://store/screenshots"


func _ready() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		print("no screenshots dir")
		get_tree().quit(1)
		return
	for f in d.get_files():
		if not f.ends_with(".png"):
			continue
		var path := DIR + "/" + f
		var img := Image.load_from_file(path)
		if img == null:
			continue
		if img.get_width() >= 1080:
			print("skip %s (already %dx%d)" % [f, img.get_width(), img.get_height()])
			continue
		img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_LANCZOS)
		print("%s -> %dx%d %s" % [f, img.get_width(), img.get_height(),
				"ok" if img.save_png(path) == OK else "FAILED"])
	get_tree().quit(0)
