class_name Minimap
extends Control
## Bottom-right minimap — a genre requirement, not a nice-to-have.
##
## Every .io game has one and its absence is the first thing a player of the
## genre notices. It also does real work here: the arena is 88 units across and
## the camera shows ~21, so without a map you cannot see the ring closing or
## where the big threats are.
##
## Drawn with `_draw` rather than viewports or sprites — it is a dozen circles
## and a rectangle, redrawn at a throttled rate.

## Bigger than it was (230): at that size the dots were 2-3px on a phone and the
## map was decorative rather than usable. It can be hidden entirely now, so the
## trade for screen space is the player's to make.
const SIZE := 320.0
const REDRAW_HZ := 12.0

var arena: Arena

var _timer := 0.0
# One step darker than the plate, not five. At 0.07 this was darker than every
# other surface in the game, so the one element whose whole job is to look like a
# mounted gauge read as a hole punched in the screen.
var _bg := Color(0.102, 0.094, 0.078, 0.90)
var _border := Color(0.62, 0.60, 0.56, 0.55)
var _ring_col := Color(0.95, 0.82, 0.45, 0.55)
var _rival := Color(0.85, 0.85, 0.87, 0.7)
var _threat := Color(0.769, 0.333, 0.239, 0.9)
var _leader := Color(0.851, 0.631, 0.235, 0.95)


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	# The map does not need 60fps; dots moving a fraction of a pixel per frame
	# is invisible and redrawing costs more than it is worth.
	_timer += delta
	if _timer >= 1.0 / REDRAW_HZ:
		_timer = 0.0
		queue_redraw()


func _draw() -> void:
	var r := SIZE * 0.5
	var centre := Vector2(r, r)
	draw_circle(centre, r, _bg)
	# Machined bezel plus four rivets, so the map is bolted to the same steel as
	# everything else rather than floating on it.
	draw_arc(centre, r - 3.0, 0.0, TAU, 64, _border, 5.0, true)
	draw_arc(centre, r - 8.0, 0.0, TAU, 48, Color(_border, 0.30), 1.0, true)
	for i in 4:
		var a := PI * 0.25 + float(i) * PI * 0.5
		var rp := centre + Vector2(cos(a), sin(a)) * (r - 9.0)
		draw_circle(rp + Vector2(0, 1.0), 4.5, Color(0, 0, 0, 0.45))
		draw_circle(rp, 3.5, Color(0.72, 0.70, 0.66, 0.75))

	if arena == null or not is_instance_valid(arena) or arena.t == null:
		return

	# World -> map. Scaled to the ARENA, not the ring, so the ring visibly
	# shrinks inside the map as the match progresses.
	var world_r: float = arena.t.ring_start_radius
	var scale := (r - 15.0) / world_r

	# Safe zone.
	draw_arc(centre, arena.ring_radius * scale, 0.0, TAU, 40, _ring_col, 2.5, true)

	var player: Magnet = arena.player
	var player_mass: float = player.mass if player != null and player.alive else 0.0

	for m: Magnet in arena.magnets:
		if not m.alive or m.is_player:
			continue
		var p := centre + Vector2(m.global_position.x, m.global_position.z) * scale
		# Anything that can eat you is drawn in the danger colour. This is the
		# map's actual job: telling you which direction not to go.
		var dangerous := m.mass > player_mass * arena.t.absorb_mass_ratio
		# Sized off RELATIVE mass: absolute mass at match start says nothing about
		# whether something can eat you.
		var dot: float = clampf(2.5 + (m.mass / maxf(player_mass, 1.0)) * 3.0, 2.5, 9.0)
		if m.is_leader:
			# The biggest magnet gets a diamond in brass — a third shape, so leader,
			# threat and prey are all distinguishable without relying on hue.
			var d := dot * 1.35
			draw_colored_polygon(PackedVector2Array([
					p + Vector2(0, -d), p + Vector2(d, 0),
					p + Vector2(0, d), p + Vector2(-d, 0)]), _leader)
		elif dangerous:
			draw_colored_polygon(PackedVector2Array([
					p + Vector2(0, -dot * 1.25), p + Vector2(dot * 1.1, dot * 0.8),
					p + Vector2(-dot * 1.1, dot * 0.8)]), _threat)
		else:
			draw_circle(p, dot, _rival)

	if player != null and player.alive:
		var pp := centre + Vector2(player.global_position.x, player.global_position.z) * scale
		draw_circle(pp, 5.5, Color(0.98, 0.98, 0.99))
		draw_arc(pp, 9.0, 0.0, TAU, 20, Color(0.95, 0.82, 0.45, 0.95), 2.0, true)
