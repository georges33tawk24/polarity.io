class_name Stencil
extends RefCounted
## Stencil-cut plate lettering, drawn as polygons.
##
## The wordmark and the two numbers that carry the game — the HUD mass readout and
## the results placement — were Labels in Godot's fallback font. That face is the
## single most recognisable "nobody chose a typeface" signal there is, and the fix
## on offer was FontVariation.variation_embolden, which thickens by dilating the
## outline: at 150px it smears the stems and produces exactly the stroked-default
## look that reads as machine-generated.
##
## So these glyphs are drawn instead. This is the one place where "100% procedural,
## no font files" is an advantage rather than a constraint: industrial lettering IS
## stencil lettering, stencils are rectangles, and rectangles are free. Each stroke
## gets a lit top edge from the same light direction as the floor plates, so the
## letters read as milled into the plate rather than printed on it.
##
## Bridges — the gaps that stop the counter of an O or an A falling out of a real
## stencil plate — are why the letterforms look fabricated. They are not decoration;
## they are the reason the shape is shaped that way.
##
## Only the glyphs the game actually shows are here: POLARITY, the digits, and the
## few marks that appear beside a number. An unknown character advances the pen and
## draws nothing, which is the correct failure — a missing glyph must never become
## a mystery box in a shipped build.

const GW := 7.0      ## glyph grid width
const GH := 10.0     ## glyph grid height
const T := 2.0       ## stroke thickness
const ADVANCE := 8.9 ## pen advance, so tracking is built into the metric
const BRIDGE := 1.15 ## stencil bridge gap

static var _glyphs: Dictionary = {}


## Horizontal bar, split by a stencil bridge slightly off-centre. Dead-centre
## bridges line up across letters and read as a printing fault.
static func _hbar(y: float) -> Array:
	var cut := GW * 0.44
	return [Rect2(0.0, y, cut, T), Rect2(cut + BRIDGE, y, GW - cut - BRIDGE, T)]


## Diagonal stroke, as a quad from the top edge to the bottom edge. Rect-only
## glyphs cannot tell A from R — both collapse to two stems and two bars — and
## a wordmark that reads POLAAITY is worse than no wordmark.
static func _diag(x_top: float, x_bot: float, y0: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x_top, y0), Vector2(x_top + T, y0),
		Vector2(x_bot + T, y1), Vector2(x_bot, y1)])


static func _table() -> Dictionary:
	if not _glyphs.is_empty():
		return _glyphs

	var right := GW - T
	var mid := GH * 0.5
	var stem := (GW - T) * 0.5
	var apex := stem

	var top := _hbar(0.0)
	var centre := _hbar(mid - T * 0.5)
	var base := _hbar(GH - T)
	# Bridges exist to stop an enclosed counter falling out of the plate. A glyph
	# with no enclosed counter — 2, 3, 5, 7 — has nothing to hold, and bridging its
	# bars anyway just breaks them: a bridged 3 reads as a square bracket.
	var ftop := [Rect2(0, 0, GW, T)]
	var fcentre := [Rect2(0, mid - T * 0.5, GW, T)]
	var fbase := [Rect2(0, GH - T, GW, T)]

	var g := {}
	g["P"] = [Rect2(0, 0, T, GH), Rect2(right, 0, T, mid)] + top + centre
	g["O"] = [Rect2(0, 0, T, GH), Rect2(right, 0, T, GH)] + top + base
	g["L"] = [Rect2(0, 0, T, GH)] + fbase
	# Splayed legs meeting at a solid apex, plus the crossbar low enough that the
	# counter reads. This is the letter that has to be unmistakable.
	g["A"] = [_diag(apex, 0.0, 0.0, GH), _diag(apex, right, 0.0, GH)] + _hbar(GH * 0.60)
	# Bowl to the mid bar, then the leg kicks OUT. Same bowl as P, different leg.
	g["R"] = [Rect2(0, 0, T, GH), Rect2(right, 0, T, mid)] + top + centre \
			+ [_diag(GW * 0.42, right, mid, GH)]
	g["I"] = [Rect2(stem, 0, T, GH)] + _hbar(0.0) + _hbar(GH - T)
	g["T"] = [Rect2(stem, 0, T, GH)] + top
	g["Y"] = [_diag(0.0, stem, 0.0, mid + T), _diag(right, stem, 0.0, mid + T),
			Rect2(stem, mid, T, GH - mid)]

	g["0"] = g["O"]
	# No bridge on the foot: a bridged serif on a 1 reads as two marks.
	g["1"] = [Rect2(stem, 0, T, GH), Rect2(GW * 0.16, GH - T, GW * 0.68, T)]
	g["2"] = [Rect2(right, 0, T, mid), Rect2(0, mid - T * 0.5, T, mid + T * 0.5)] \
			+ ftop + fcentre + fbase
	g["3"] = [Rect2(right, 0, T, GH)] + ftop + fcentre + fbase
	g["4"] = [Rect2(0, 0, T, mid + T * 0.5), Rect2(right, 0, T, GH)] + centre
	g["5"] = [Rect2(0, 0, T, mid), Rect2(right, mid - T * 0.5, T, mid + T * 0.5)] \
			+ ftop + fcentre + fbase
	g["6"] = [Rect2(0, 0, T, GH), Rect2(right, mid - T * 0.5, T, mid + T * 0.5)] \
			+ top + centre + base
	g["7"] = ftop + [_diag(right, GW * 0.22, T, GH)]
	g["8"] = [Rect2(0, 0, T, GH), Rect2(right, 0, T, GH)] + top + centre + base
	g["9"] = [Rect2(0, 0, T, mid), Rect2(right, 0, T, GH)] + top + centre

	# S, N and D round out "1ST" / "2ND" / "3RD" — the placement headline is the
	# only place letters and digits mix. Declared after the digits because S is
	# literally the 5.
	g["S"] = g["5"]
	g["N"] = [Rect2(0, 0, T, GH), Rect2(right, 0, T, GH), _diag(0.0, right, 0.0, GH)]
	g["D"] = [Rect2(0, 0, T, GH), Rect2(right, 0, T, GH)] + top + base

	# Marks that appear next to a number. '#' leads the placement headline.
	g["+"] = [Rect2(stem, mid - GW * 0.34, T, GW * 0.68),
			Rect2(stem - GW * 0.28, mid - T * 0.5, GW * 0.68, T)]
	g["-"] = [Rect2(stem - GW * 0.28, mid - T * 0.5, GW * 0.68, T)]
	g["#"] = [Rect2(GW * 0.22, 0, T * 0.8, GH), Rect2(GW * 0.60, 0, T * 0.8, GH),
			Rect2(0, GH * 0.30, GW, T * 0.8), Rect2(0, GH * 0.62, GW, T * 0.8)]
	g[":"] = [Rect2(stem, mid - GH * 0.26, T, T), Rect2(stem, mid + GH * 0.12, T, T)]
	g["."] = [Rect2(stem, GH - T, T, T)]
	g[","] = [Rect2(stem, GH - T, T, T)]
	g["/"] = [Rect2(stem, 0, T, GH)]
	g[" "] = []
	_glyphs = g
	return _glyphs


## Width in pixels for `text` at a given cap height. The last glyph does not pay
## the trailing advance, or every centred string sits visibly left of centre.
static func measure(text: String, height: float) -> float:
	var u := height / GH
	var n := text.length()
	if n == 0:
		return 0.0
	return (float(n - 1) * ADVANCE + GW) * u


## A Control that draws `text`. Cap height, not font size: what you set is the
## height the capitals actually occupy, which a font size never tells you.
static func node(text: String, height: float, color := Color.WHITE) -> Node:
	var n := StencilLabel.new()
	n.stencil_text = text
	n.cap_height = height
	n.ink = color
	return n


class StencilLabel extends Control:
	var stencil_text := "":
		set(v):
			stencil_text = v
			_resize()
	var cap_height := 100.0:
		set(v):
			cap_height = v
			_resize()
	var ink := Color.WHITE:
		set(v):
			ink = v
			queue_redraw()
	## Lit top edge on every stroke, from the same light direction as the floor
	## plates. Without it the letters are flat fills and the stencil reads as clip
	## art; with it they read as milled.
	var bevel := Color(1, 1, 1, 0.22)
	## Set > 0 to run a plate seam across the lettering at this fraction of the
	## cap height, so the wordmark sits on the same panel grid as everything else.
	var seam := 0.0
	var rivet_in_o := false
	## Offset dark pass, for lettering that sits on the open arena rather than on a
	## panel. A Label gets this from outline_size; drawn glyphs have to do it
	## themselves, and without it the mass readout disappears over a pale nut.
	var shadow := Color(0, 0, 0, 0.0)
	var shadow_offset := Vector2(4, 5)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _resize() -> void:
		custom_minimum_size = Vector2(Stencil.measure(stencil_text, cap_height), cap_height)
		queue_redraw()

	func _draw() -> void:
		if shadow.a > 0.0:
			_pass(shadow_offset, shadow, false)
		_pass(Vector2.ZERO, ink, true)

	func _pass(off: Vector2, tint: Color, lit: bool) -> void:
		var table := Stencil._table()
		var u := cap_height / Stencil.GH
		var pen := 0.0
		var bevel_h: float = maxf(2.0, cap_height * 0.028)
		for i in stencil_text.length():
			var ch := stencil_text[i].to_upper()
			var strokes: Array = table.get(ch, [])
			for s: Variant in strokes:
				if s is Rect2:
					var r: Rect2 = s
					var p := Rect2(off + Vector2(pen + r.position.x * u, r.position.y * u),
							Vector2(r.size.x * u, r.size.y * u))
					draw_rect(p, tint)
					# Only strokes with real height get a lit edge — a bevel on a
					# 2px bar is just a lighter bar.
					if lit and p.size.y > bevel_h * 2.0:
						draw_rect(Rect2(p.position, Vector2(p.size.x, bevel_h)), bevel)
				else:
					var q: PackedVector2Array = s
					var out := PackedVector2Array()
					for v: Vector2 in q:
						out.append(off + Vector2(pen + v.x * u, v.y * u))
					draw_colored_polygon(out, tint)
			if lit and ch == "O" and rivet_in_o:
				var c := Vector2(pen + Stencil.GW * 0.5 * u, cap_height * 0.5)
				var rr: float = cap_height * 0.075
				draw_circle(c, rr, ink)
				draw_circle(c, rr * 0.45, Color(0, 0, 0, 0.45))
			pen += Stencil.ADVANCE * u

		if lit and seam > 0.0:
			var y := cap_height * seam
			var w := Stencil.measure(stencil_text, cap_height)
			draw_rect(Rect2(-cap_height * 0.10, y, w + cap_height * 0.20, maxf(2.0, u * 0.16)),
					Color(0, 0, 0, 0.34))
