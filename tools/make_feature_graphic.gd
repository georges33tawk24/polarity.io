extends Node
## Google Play's 1024x500 feature graphic.
##   Godot res://tools/make_feature_graphic.tscn
##
## Required for a Play listing and there was no way to produce one. Drawn from
## the same parts as everything else — plate, seams, rivets, the horseshoe, the
## stencil wordmark — because a store banner that does not match the game is the
## most common "asset made in a hurry" tell.
##
## Play crops this on some surfaces, so nothing that matters goes near the edges.

const W := 1024
const H := 500
const OUT := "res://store/feature_graphic.png"


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)

	var art := Banner.new()
	art.size = Vector2(W, H)
	vp.add_child(art)

	# Sized to the gap left of the right edge rather than to a guessed constant —
	# the first version ran "POLARIT" off the canvas and pushed ".IO" out of frame
	# entirely. Play also crops this image on some surfaces, so it stops well short.
	var left := float(W) * 0.375
	var avail := float(W) * 0.94 - left
	var mark_h := float(H) * 0.20
	var gap_frac := 0.12
	while mark_h > 10.0:
		var total := Stencil.measure("POLARITY", mark_h) \
				+ mark_h * gap_frac + Stencil.measure(".IO", mark_h * 0.52)
		if total <= avail:
			break
		mark_h -= 2.0

	var mark: Stencil.StencilLabel = Stencil.node("POLARITY", mark_h,
			Color(0.929, 0.910, 0.871))
	mark.seam = 0.44
	mark.rivet_in_o = true
	mark.position = Vector2(left, float(H) * 0.46 - mark_h * 0.5)
	art.add_child(mark)

	var tag: Stencil.StencilLabel = Stencil.node(".IO", mark_h * 0.52,
			Color(0.604, 0.569, 0.518))
	tag.seam = 0.44
	tag.rivet_in_o = true
	# Baseline-aligned with the wordmark, exactly as on the menu.
	tag.position = mark.position + Vector2(
			Stencil.measure("POLARITY", mark_h) + mark_h * gap_frac,
			mark_h - mark_h * 0.52)
	art.add_child(tag)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	print("feature graphic %s -> %s"
			% ["ok" if img.save_png(OUT) == OK else "FAILED", OUT])
	get_tree().quit(0)


class Banner extends Control:
	func _draw() -> void:
		var u := size.y / 500.0

		draw_rect(Rect2(Vector2.ZERO, size), Color(0.149, 0.141, 0.122))
		# Plate seams and rivets, at the floor's own spacing.
		var seam := Color(0.333, 0.306, 0.255, 0.5)
		var step := 210.0 * u
		var x := step
		while x < size.x:
			draw_rect(Rect2(x - 2 * u, 0, 4 * u, size.y), seam)
			x += step
		var y := step
		while y < size.y:
			draw_rect(Rect2(0, y - 2 * u, size.x, 4 * u), seam)
			y += step
		for gx in range(1, int(size.x / step) + 1):
			for gy in range(1, int(size.y / step) + 1):
				var p := Vector2(gx * step, gy * step)
				draw_circle(p + Vector2(0, 3 * u), 11 * u, Color(0, 0, 0, 0.38))
				draw_circle(p, 9 * u, Color(0.72, 0.70, 0.66, 0.55))

		# Vignette, so the wordmark sits on a calmer field than bare plate.
		for i in 26:
			var t := float(i) / 26.0
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.043, 0.039, 0.035, 0.035 * (1.0 - t)))

		# The mark: the same U the magnet body is, not the old 316-degree arc. A
		# banner showing a ring while the game shows a horseshoe is the tell that
		# the
		# art was made separately.
		var c := Vector2(size.x * 0.20, size.y * 0.46)
		var r := size.y * 0.22
		var th := size.y * 0.115
		var leg := size.y * 0.20
		var red := Color(0.851, 0.310, 0.239)
		var blue := Color(0.290, 0.435, 0.647)
		# Top half, split down the middle: PI..3PI/2 is the left arm in Godot's
		# y-down space, 3PI/2..TAU the right.
		draw_arc(c, r, PI, PI * 1.5, 32, red, th)
		draw_arc(c, r, PI * 1.5, TAU, 32, blue, th)
		draw_rect(Rect2(c.x - r - th * 0.5, c.y, th, leg), red)
		draw_rect(Rect2(c.x + r - th * 0.5, c.y, th, leg), blue)
		# Flat pole faces.
		draw_rect(Rect2(c.x - r - th * 0.5, c.y + leg - th * 0.28, th, th * 0.28),
				Color(0.055, 0.051, 0.043, 0.5))
		draw_rect(Rect2(c.x + r - th * 0.5, c.y + leg - th * 0.28, th, th * 0.28),
				Color(0.055, 0.051, 0.043, 0.5))

		# Wordmark is added as StencilLabel children in _ready — Stencil draws
		# through Control nodes, not a static draw call.
		draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.375, size.y * 0.74),
				"HOLD TO ATTRACT   RELEASE TO REPEL",
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * u),
				Color(0.604, 0.569, 0.518))
