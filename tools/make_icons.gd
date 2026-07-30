extends Node
## Generates the app icon at every store size, from code.
##   /Applications/Godot.app/Contents/MacOS/Godot res://tools/make_icons.tscn
##
## The project shipped Godot's default `icon.svg`, which is the single most
## recognisable "this is an engine demo" signal a store listing can carry — and it
## survived every art pass because nothing on screen ever showed it.
##
## Drawn into a SubViewport rather than rasterised per pixel: `Icons.get_icon`
## builds its 128px glyphs pixel by pixel in GDScript and one of those measures
## ~120ms, so a 1024x1024 icon that way would take most of a second per size. The
## GPU draws it once and every smaller size is a resize of that image.
##
## The mark is the horseshoe with its two poles, because that IS the game: the
## silhouette reads at 48px, and red/blue says "magnet" with no text at all. It sits
## inside the inner 62% of the canvas so Android's circular adaptive mask cannot
## clip it.

const SIZES := [1024, 512, 432, 192, 180, 144, 96, 72, 48]
const OUT := "res://store/icons"


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1024, 1024)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)

	var art := IconArt.new()
	art.size = Vector2(1024, 1024)
	vp.add_child(art)

	# Two frames: one for the viewport to size itself, one for the draw.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var base := vp.get_texture().get_image()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for s: int in SIZES:
		var img := base.duplicate() as Image
		if s != 1024:
			# Lanczos: the mark has a hard keyline and bilinear turned it to mush
			# at 48px.
			img.resize(s, s, Image.INTERPOLATE_LANCZOS)
		var path := "%s/icon_%d.png" % [OUT, s]
		var err := img.save_png(path)
		print("%s  %s" % ["ok  " if err == OK else "FAIL", path])
	get_tree().quit(0)


class IconArt extends Control:
	func _draw() -> void:
		var w := size.x
		var c := size * 0.5
		var u := w / 1024.0

		# Warm steel plate, matching STEEL_20 so the icon is cut from the same
		# material as the game.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.149, 0.141, 0.122))

		# One seam cross and four rivets — the floor's language at icon scale. Any
		# more detail than this disappears at 48px and only adds noise.
		var seam := Color(0.333, 0.306, 0.255, 0.55)
		draw_rect(Rect2(0, c.y - 3 * u, w, 6 * u), seam)
		draw_rect(Rect2(c.x - 3 * u, 0, 6 * u, w), seam)
		for sx in [0.13, 0.87]:
			for sy in [0.13, 0.87]:
				var p := Vector2(w * sx, w * sy)
				draw_circle(p + Vector2(0, 4 * u), 17 * u, Color(0, 0, 0, 0.40))
				draw_circle(p, 14 * u, Color(0.72, 0.70, 0.66, 0.62))

		# The horseshoe. Inside 62% of the canvas so a circular adaptive mask on
		# Android cannot clip the poles off.
		var r := w * 0.27
		var thick := w * 0.155
		# Gap at the bottom, split at the top: left arm attract, right arm repel.
		draw_arc(c, r, deg_to_rad(112.0), deg_to_rad(270.0), 40,
				Color(0.851, 0.310, 0.239), thick)
		draw_arc(c, r, deg_to_rad(270.0), deg_to_rad(428.0), 40,
				Color(0.290, 0.435, 0.647), thick)
		# Keyline, per the flat-fill-plus-keyline rule — without it the mark bleeds
		# into the plate at small sizes.
		var key := Color(0.055, 0.051, 0.043, 0.85)
		draw_arc(c, r + thick * 0.5, deg_to_rad(112.0), deg_to_rad(428.0), 64, key, 7 * u, true)
		draw_arc(c, r - thick * 0.5, deg_to_rad(112.0), deg_to_rad(428.0), 64, key, 7 * u, true)
