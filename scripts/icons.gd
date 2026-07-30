class_name Icons
extends RefCounted
## Procedurally drawn UI icons (spec §13A: "one consistent icon set; currency
## icons; rarity frames").
##
## Drawn into ImageTextures at first use rather than shipped as PNGs — same
## reasoning as the synthesised audio: no binary assets, no licensing, no import
## step, and the whole set costs a few KB of RAM. Supersampled 4x then shrunk,
## which is how these get clean edges without an SVG rasteriser.

const SIZE := 64
const SS := 4        # supersample factor

static var _cache: Dictionary = {}

const COIN := Color("#d9a13c")
const COIN_DARK := Color("#c9821f")
const GEM := Color("#6e9ba8")
const GEM_DARK := Color("#3e5e68")


static func get_icon(name: String, tint := Color.WHITE) -> Texture2D:
	var key := "%s:%s" % [name, tint.to_html()]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(SIZE * SS, SIZE * SS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match name:
		"coin": _draw_coin(img)
		"gem": _draw_gem(img)
		"trophy": _draw_trophy(img, tint)
		"lock": _draw_lock(img, tint)
		"check": _draw_check(img, tint)
		"star": _draw_star(img, tint)
		"bag": _draw_bag(img, tint)
		"target": _draw_target(img, tint)
		"bars": _draw_bars(img, tint)
		"gear": _draw_gear(img, tint)
		"card": _draw_card(img, tint)
		"skin": _draw_skin(img, tint)
		"trail": _draw_trail(img, tint)
		"effect": _draw_effect(img, tint)
		"plate": _draw_plate(img, tint)
		"arena": _draw_arena(img, tint)
		# An unknown name silently becomes a plain disc, which is why five
		# different nav tabs could render as five identical circles and throw no
		# error. Anything added to a nav bar needs a case here.
		_: _draw_disc(img, tint)
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


# --- primitives ------------------------------------------------------------
static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	# Manual source-over: Image has no blend for single pixels.
	var dst := img.get_pixel(x, y)
	var a := c.a + dst.a * (1.0 - c.a)
	if a <= 0.0001:
		return
	img.set_pixel(x, y, Color(
		(c.r * c.a + dst.r * dst.a * (1.0 - c.a)) / a,
		(c.g * c.a + dst.g * dst.a * (1.0 - c.a)) / a,
		(c.b * c.a + dst.b * dst.a * (1.0 - c.a)) / a, a))


static func _disc(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	var r2 := r * r
	for y in range(int(cy - r) - 1, int(cy + r) + 2):
		for x in range(int(cx - r) - 1, int(cx + r) + 2):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r2:
				_px(img, x, y, c)


static func _ring(img: Image, cx: float, cy: float, r: float, thickness: float, c: Color) -> void:
	var outer := r * r
	var inner := (r - thickness) * (r - thickness)
	for y in range(int(cy - r) - 1, int(cy + r) + 2):
		for x in range(int(cx - r) - 1, int(cx + r) + 2):
			var dx := x - cx
			var dy := y - cy
			var d := dx * dx + dy * dy
			if d <= outer and d >= inner:
				_px(img, x, y, c)


## Scanline fill of an arbitrary polygon — covers gem, star, trophy and check.
## `erase` punches a hole instead of painting. Needed because `_px` does source-over
## blending, so filling with an alpha-0 colour is a silent no-op — which is exactly
## how two glyphs (a horseshoe gap and a card stripe) shipped as solid blobs with no
## error anywhere. If a glyph needs a hole, it needs this.
static func _poly(img: Image, points: PackedVector2Array, c: Color,
		erase := false) -> void:
	if points.size() < 3:
		return
	var min_y := points[0].y
	var max_y := points[0].y
	for p in points:
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	for y in range(int(min_y), int(max_y) + 1):
		var xs: Array[float] = []
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var i := 0
		while i + 1 < xs.size():
			for x in range(int(xs[i]), int(xs[i + 1]) + 1):
				if erase:
					if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
						img.set_pixel(x, y, Color(0, 0, 0, 0))
				else:
					_px(img, x, y, c)
			i += 2


# --- icons -----------------------------------------------------------------
static func _draw_disc(img: Image, tint: Color) -> void:
	var s := img.get_width()
	_disc(img, s * 0.5, s * 0.5, s * 0.42, tint)


static func _draw_coin(img: Image) -> void:
	var s := img.get_width()
	var c := s * 0.5
	_disc(img, c, c, s * 0.44, COIN_DARK)
	_disc(img, c, c, s * 0.38, COIN)
	_ring(img, c, c, s * 0.30, s * 0.035, COIN_DARK)
	# Off-centre highlight reads as a struck coin rather than a flat circle.
	_disc(img, c - s * 0.10, c - s * 0.12, s * 0.07, Color(1, 1, 1, 0.55))


static func _draw_gem(img: Image) -> void:
	var s := float(img.get_width())
	var pts := PackedVector2Array([
		Vector2(s * 0.5, s * 0.10), Vector2(s * 0.86, s * 0.40),
		Vector2(s * 0.5, s * 0.90), Vector2(s * 0.14, s * 0.40),
	])
	_poly(img, pts, GEM_DARK)
	_poly(img, PackedVector2Array([
		Vector2(s * 0.5, s * 0.16), Vector2(s * 0.78, s * 0.41),
		Vector2(s * 0.5, s * 0.82), Vector2(s * 0.22, s * 0.41),
	]), GEM)
	# Facet: the diamond needs an internal line or it reads as a plain rhombus.
	_poly(img, PackedVector2Array([
		Vector2(s * 0.5, s * 0.16), Vector2(s * 0.5, s * 0.82),
		Vector2(s * 0.30, s * 0.41),
	]), Color(1, 1, 1, 0.22))


static func _draw_trophy(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	_poly(img, PackedVector2Array([
		Vector2(s * 0.28, s * 0.16), Vector2(s * 0.72, s * 0.16),
		Vector2(s * 0.63, s * 0.56), Vector2(s * 0.37, s * 0.56),
	]), tint)
	_poly(img, PackedVector2Array([
		Vector2(s * 0.44, s * 0.56), Vector2(s * 0.56, s * 0.56),
		Vector2(s * 0.58, s * 0.74), Vector2(s * 0.42, s * 0.74),
	]), tint)
	_poly(img, PackedVector2Array([
		Vector2(s * 0.28, s * 0.74), Vector2(s * 0.72, s * 0.74),
		Vector2(s * 0.72, s * 0.86), Vector2(s * 0.28, s * 0.86),
	]), tint)


static func _draw_lock(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	_ring(img, s * 0.5, s * 0.38, s * 0.20, s * 0.075, tint)
	# Cover the lower half of the shackle so it reads as a closed padlock.
	_poly(img, PackedVector2Array([
		Vector2(s * 0.24, s * 0.44), Vector2(s * 0.76, s * 0.44),
		Vector2(s * 0.76, s * 0.86), Vector2(s * 0.24, s * 0.86),
	]), tint)


static func _draw_check(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	_poly(img, PackedVector2Array([
		Vector2(s * 0.18, s * 0.52), Vector2(s * 0.30, s * 0.40),
		Vector2(s * 0.44, s * 0.56), Vector2(s * 0.74, s * 0.22),
		Vector2(s * 0.86, s * 0.34), Vector2(s * 0.44, s * 0.80),
	]), tint)


static func _draw_star(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	var pts := PackedVector2Array()
	for i in 10:
		var a: float = -PI * 0.5 + TAU * i / 10.0
		var r: float = s * (0.42 if i % 2 == 0 else 0.18)
		pts.append(Vector2(s * 0.5 + cos(a) * r, s * 0.5 + sin(a) * r))
	_poly(img, pts, tint)


static func clear_cache() -> void:
	_cache.clear()


# --- navigation glyphs -----------------------------------------------------
## Shop. A tapered body with a handle above it, which reads as a bag rather than
## as the generic cart every store icon uses.
static func _draw_bag(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	_poly(img, PackedVector2Array([
		Vector2(s * 0.22, s * 0.38), Vector2(s * 0.78, s * 0.38),
		Vector2(s * 0.70, s * 0.84), Vector2(s * 0.30, s * 0.84),
	]), tint)
	_ring(img, s * 0.5, s * 0.38, s * 0.16, s * 0.055, tint)


## Missions. Concentric rings with a filled centre.
static func _draw_target(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	_ring(img, s * 0.5, s * 0.5, s * 0.34, s * 0.055, tint)
	_ring(img, s * 0.5, s * 0.5, s * 0.20, s * 0.055, tint)
	_disc(img, s * 0.5, s * 0.5, s * 0.075, tint)


## Leaderboard. Three ascending bars — a podium read without needing three shapes.
static func _draw_bars(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	var w := s * 0.18
	var xs := [0.18, 0.41, 0.64]
	var tops := [0.56, 0.30, 0.44]
	for i in 3:
		_poly(img, PackedVector2Array([
			Vector2(s * float(xs[i]), s * float(tops[i])),
			Vector2(s * float(xs[i]) + w, s * float(tops[i])),
			Vector2(s * float(xs[i]) + w, s * 0.84),
			Vector2(s * float(xs[i]), s * 0.84),
		]), tint)


## Settings. A toothed ring — the one shape every player already reads as settings,
## so this is the wrong place to be original.
static func _draw_gear(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	var c := s * 0.5
	var teeth := 8
	for i in teeth:
		var a: float = TAU * float(i) / float(teeth)
		var d := Vector2(cos(a), sin(a))
		var n := Vector2(-d.y, d.x) * s * 0.075
		var inner := Vector2(c, c) + d * s * 0.24
		var outer := Vector2(c, c) + d * s * 0.40
		_poly(img, PackedVector2Array([inner - n, inner + n, outer + n * 0.6,
				outer - n * 0.6]), tint)
	_ring(img, c, c, s * 0.26, s * 0.10, tint)


## Store. A card with a stripe. The gem glyph would have been the obvious choice and
## is wrong here: coin and gem are colour-locked so they read as currency wherever
## they appear, which means they cannot dim when a nav cell is inactive or turn amber
## when it is active — the store tab was the one cell that never changed state.
static func _draw_card(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	_poly(img, PackedVector2Array([
		Vector2(s * 0.12, s * 0.26), Vector2(s * 0.88, s * 0.26),
		Vector2(s * 0.88, s * 0.74), Vector2(s * 0.12, s * 0.74),
	]), tint)
	_poly(img, PackedVector2Array([
		Vector2(s * 0.12, s * 0.36), Vector2(s * 0.88, s * 0.36),
		Vector2(s * 0.88, s * 0.47), Vector2(s * 0.12, s * 0.47),
	]), tint, true)
	_poly(img, PackedVector2Array([
		Vector2(s * 0.20, s * 0.56), Vector2(s * 0.44, s * 0.56),
		Vector2(s * 0.44, s * 0.64), Vector2(s * 0.20, s * 0.64),
	]), tint, true)


# --- cosmetic kind glyphs --------------------------------------------------
## Skins. The horseshoe itself — the thing a skin actually recolours. The gap has to
## be punched with `erase`, since _px blends and an alpha-0 fill does nothing.
static func _draw_skin(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	_ring(img, s * 0.5, s * 0.46, s * 0.30, s * 0.15, tint)
	_poly(img, PackedVector2Array([
		Vector2(s * 0.41, s * 0.52), Vector2(s * 0.59, s * 0.52),
		Vector2(s * 0.59, s * 0.98), Vector2(s * 0.41, s * 0.98),
	]), tint, true)


## Trails. Three discs receding, which is what a trail looks like in game.
static func _draw_trail(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	_disc(img, s * 0.74, s * 0.32, s * 0.14, tint)
	_disc(img, s * 0.50, s * 0.50, s * 0.105, Color(tint, tint.a * 0.62))
	_disc(img, s * 0.29, s * 0.68, s * 0.075, Color(tint, tint.a * 0.34))


## Launch effects. Radiating spokes with a gap at the centre — a burst, not a star.
static func _draw_effect(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	var c := s * 0.5
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		var d := Vector2(cos(a), sin(a))
		var n := Vector2(-d.y, d.x) * s * 0.045
		var inner := Vector2(c, c) + d * s * 0.16
		var outer := Vector2(c, c) + d * s * 0.42
		_poly(img, PackedVector2Array([inner - n, inner + n, outer + n * 0.4,
				outer - n * 0.4]), tint)


## Nameplates. A tag with a line of text on it.
static func _draw_plate(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	_poly(img, PackedVector2Array([
		Vector2(s * 0.10, s * 0.32), Vector2(s * 0.90, s * 0.32),
		Vector2(s * 0.90, s * 0.68), Vector2(s * 0.10, s * 0.68),
	]), tint)
	_poly(img, PackedVector2Array([
		Vector2(s * 0.22, s * 0.44), Vector2(s * 0.78, s * 0.44),
		Vector2(s * 0.78, s * 0.56), Vector2(s * 0.22, s * 0.56),
	]), tint, true)


## Arena themes. Four plates with a seam between them — the floor, in miniature.
static func _draw_arena(img: Image, tint: Color) -> void:
	var s := float(img.get_width())
	_poly(img, PackedVector2Array([
		Vector2(s * 0.12, s * 0.12), Vector2(s * 0.88, s * 0.12),
		Vector2(s * 0.88, s * 0.88), Vector2(s * 0.12, s * 0.88),
	]), tint)
	var g := s * 0.05
	_poly(img, PackedVector2Array([
		Vector2(s * 0.5 - g, s * 0.12), Vector2(s * 0.5 + g, s * 0.12),
		Vector2(s * 0.5 + g, s * 0.88), Vector2(s * 0.5 - g, s * 0.88),
	]), tint, true)
	_poly(img, PackedVector2Array([
		Vector2(s * 0.12, s * 0.5 - g), Vector2(s * 0.88, s * 0.5 - g),
		Vector2(s * 0.88, s * 0.5 + g), Vector2(s * 0.12, s * 0.5 + g),
	]), tint, true)
