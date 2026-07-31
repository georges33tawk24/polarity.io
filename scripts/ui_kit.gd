class_name UiKit
extends RefCounted
## Shared widget builders. Both `Ui` and `MetaPanel` construct controls in code,
## and without this they drifted into two slightly different button styles.
##
## Design language, decided in ART_DIRECTION Part 6:
##
## 1. **Warm steel, not slate.** Every neutral used to be blue-dominant, which is
##    the generic dark-mode template look. ART_DIRECTION:48 specified a warm
##    charcoal and it was never actually applied to the tokens.
## 2. **Depth comes from fabrication, never from floating.** No drop shadows: this
##    world is steel bolted to steel, and `floor.gdshader` already proved the right
##    language — a recessed trough, a lit lip, and rivets with a contact shadow.
##    Material Design's paper metaphor would fight that on every surface.
## 3. **Colour means something.** The game is red pole / blue pole, attract /
##    repel. Every state a UI has to express is itself a polarity — gain/loss,
##    confirm/cancel, equipped/not — so those use POLE_POS / POLE_NEG. Amber is
##    money and nothing else; it was doing nine jobs on one screen.
## 4. **Motion is magnetic.** `snap()` is fast approach, hard arrest, one small
##    settle. Not TRANS_BACK, which is a rubber ball and the opposite of magnetic.
## 5. **Mass drives weight.** The whole scoring verb is accumulation, so heavier
##    things move later, slower and less far. See `weight_dur`.

# --- Neutrals. A warm steel ramp, hue ~38 deg, deliberately short: four surface
# steps and three inks. A ten-step ramp for six screens spreads contrast evenly,
# which is what makes correct screens unmemorable — the rest of the distinction
# comes from form (bevel, trough, rivet count), which is on-brand and free.
const STEEL_10 := Color(0.102, 0.094, 0.078)  # #1A1814 milled recess: inputs, bar troughs
const STEEL_20 := Color(0.149, 0.141, 0.122)  # #26241F base plate — the ground
const STEEL_30 := Color(0.200, 0.184, 0.157)  # #332F28 card / dialog / panel fill
const STEEL_40 := Color(0.259, 0.239, 0.200)  # #423D33 control rest fill
const STEEL_50 := Color(0.333, 0.306, 0.255)  # #554E41 dividers, borders, hover

const INK := Color(0.929, 0.910, 0.871)       # #EDE8DE warm white — headings, values
const INK_DIM := Color(0.780, 0.753, 0.698)   # #C7C0B2 secondary body, stat keys
const INK_MUTE := Color(0.604, 0.569, 0.518)  # #9A9184 captions, metadata
const INK_OFF := Color(0.431, 0.404, 0.341)   # #6E6757 disabled — must not read live

## The machined light edge. A 2px top highlight is the single cue that turns a
## flat fill into a fabricated part, and StyleBoxFlat has only ONE border colour —
## which is the actual reason every plate looked printed on rather than milled.
## So it is a child ColorRect, applied by `plate()` and the button tiers.
const BEVEL := Color(1, 1, 1, 0.20)
const TROUGH := Color(0, 0, 0, 0.55)          # dark inner top edge of a recess
const RIVET := Color(0.72, 0.70, 0.66, 0.55)

# --- The poles. Taken out of the skins-only ghetto and promoted into the chrome
# as meaning: this is the mechanic, so it is the palette no template can match.
const POLE_POS := Color(0.851, 0.310, 0.239)  # #D94F3D attract — claim, confirm, gain
const POLE_NEG := Color(0.290, 0.435, 0.647)  # #4A6FA5 repel — cancel, dismiss, loss

# --- Amber. Money, and nothing else.
const ACCENT := Color(0.910, 0.639, 0.239)      # #E8A33D price, buy, PLAY
const ACCENT_DEEP := Color(0.788, 0.510, 0.122) # #C9821F bottom lip, pressed fill
const ACCENT_INK := Color(0.102, 0.094, 0.078)  # label on amber
const BRASS := Color(0.690, 0.541, 0.290)       # non-interactive metal: chips, rank

# --- Signals
const SIGNAL_GOOD := Color(0.498, 0.627, 0.353) # olive: owned, complete
const DANGER := Color(0.769, 0.333, 0.239)      # terracotta fill, confirm step only
const DANGER_LINE := Color(0.878, 0.439, 0.353) # destructive border + ink

## Minimum height for anything tappable — 140 units at a 1080-wide base is
## comfortably past the 48dp floor on a phone (spec §6.4).
const TAP_MIN := 140

## Type scale. Hierarchy comes from size and weight, not from colour — a screen
## where every label is a different colour reads as a template. The two sizes that
## carry the game (hero numbers, wordmark) are not typeset at all; see `Stencil`.
const T_HERO := 150
const T_DISPLAY := 104
const T_TITLE := 56
const T_LEAD := 44
const T_BODY := 34
const T_LABEL := 28
const T_CAPTION := 26
const T_MICRO := 22

## Spacing scale of 8, plus the two band gaps the composition never had.
const S0 := 4
const S1 := 8
const S2 := 16
const S3 := 24
const S4 := 40
const S5 := 64
const S6 := 96

## Radius by part size. One radius from a 3px bar to a 140px slab was as
## unmodulated as one accent. Nesting rule: a control inside an R_LG plate uses
## R_MD, because inner = outer - padding is what makes parts look fabricated.
const R_XS := 3
const R_SM := 6
const R_MD := 8
const R_LG := 12


# --- motion ----------------------------------------------------------------

## Read once. `dur()` is called from static context while controls are being
## built, and reaching into an autoload's Dictionary on every call couples the
## token layer to Game's initialisation order.
static var _reduced := -1


## Zero when reduced motion is on. A 0.0-duration tween still applies its final
## value next frame, so no screen needs a second code path — but NEVER call
## set_loops() on a tween whose steps are 0.0; branch to a static value instead.
static func dur(s: float) -> float:
	if _reduced < 0:
		_reduced = 1 if Game.profile.get("reduced_motion", false) else 0
	return 0.0 if _reduced == 1 else s


## Forget the cached flag, so toggling the setting takes effect without a restart.
static func motion_changed() -> void:
	_reduced = -1


## Magnetic easing: fast approach, hard arrest. TRANS_BACK — the default reach for
## "juice" — undershoots first and overshoots after, which is a rubber ball. A
## magnet accelerates into contact and stops. That is TRANS_EXPO out.
static func snap(tw: Tween) -> Tween:
	return tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


## Heavier things move later, slower, and less far. `magnitude` is whatever the
## number on screen is; the curve is deliberately shallow so a 10000 is slower
## than a 10 without being four times slower.
static func weight_dur(base: float, magnitude: float) -> float:
	return dur(base * (1.0 + clampf(log(maxf(magnitude, 1.0)) / 9.0, 0.0, 1.0)))


# --- text ------------------------------------------------------------------

## HUD label: light ink with a dark halo, legible over any part of the arena.
static func hud_lbl(text: String, size: int, color := INK,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := lbl(text, size, color, align)
	# Proportional, not a constant 12. At 12 the halo was 46% of a 26px glyph's
	# height, which is why the MASS caption rendered as a grey smear.
	l.add_theme_constant_override("outline_size", maxi(4, roundi(size * 0.13)))
	l.add_theme_color_override("font_outline_color", Color(0.055, 0.051, 0.043, 0.9))
	return l


static func lbl(text: String, size: int, color := INK,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# No outline on menu text — an outline on dark-on-light reads as a fringe.
	l.add_theme_constant_override("outline_size", 0)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Caps + a caption size. Case is a token, not a call-site convention, so the
## three ad-hoc .to_upper() calls can go. Skips uppercasing for scripts that have
## no case — ja/ko have no capitals and .to_upper() there is a no-op that hides
## the intent.
static func lbl_label(text: String, size := T_LABEL, color := INK_DIM,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return lbl(text.to_upper(), size, color, align)


## The wordmark, drawn rather than typeset. See `Stencil` for why.
static func wordmark(height := 96.0, color := INK) -> Node:
	var w: Stencil.StencilLabel = Stencil.node("POLARITY", height, color)
	w.seam = 0.44
	w.rivet_in_o = true
	return w


# --- surfaces --------------------------------------------------------------

static func flat(color: Color, radius := R_MD, pad := Vector2(S3, S3)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad.x
	sb.content_margin_right = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_bottom = pad.y
	return sb


## A bolted steel plate. This is the one surface primitive: a lit top bevel and
## rivets set into the corners, which is how every other object in this game
## expresses depth. `rivets` is 0, 2 or 4 — varying it by plate size gives
## structural variety without adding a decoration layer.
static func plate(fill := STEEL_30, radius := R_LG, rivets := 2,
		edge := Color.TRANSPARENT) -> PanelContainer:
	var p := Plate.new()
	p.rivets = rivets
	var sb := flat(fill, radius, Vector2(S3, S3))
	sb.border_color = edge if edge.a > 0.0 else STEEL_50
	sb.set_border_width_all(2)
	# The seam treatment from floor.gdshader: dark on the top inside edge so the
	# plate looks stepped down into, and a lit bevel drawn over it by Plate._draw.
	sb.border_width_top = 3
	p.add_theme_stylebox_override("panel", sb)
	return p


## Kept as the old name so existing call sites keep working. An explicit `inlay`
## now controls the accent left edge — it used to be inferred from `border.a > 0`,
## which was also true for the translucent locked-card branch, so every card in
## the shop got the inlay and it distinguished nothing.
static func panel(border := Color.TRANSPARENT, inlay := false) -> PanelContainer:
	var p := plate(STEEL_30, R_LG, 2, border)
	if inlay and border.a > 0.0:
		var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
		sb.border_width_left = 6
	return p


## Recessed field: a milled slot. Used for inputs and bar troughs — the two
## things that should read as cut INTO the plate rather than sitting on it.
static func recess(radius := R_MD) -> StyleBoxFlat:
	var sb := flat(STEEL_10, radius, Vector2(S3, S2))
	sb.border_color = TROUGH
	sb.border_width_top = 3
	return sb


class Plate extends PanelContainer:
	var rivets := 2
	var bevel := true

	func _init() -> void:
		# Rivet positions depend on the final rect, which containers decide.
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := size
		if bevel and r.x > 8.0:
			draw_rect(Rect2(Vector2(UiKit.R_LG, 3.0),
					Vector2(maxf(0.0, r.x - UiKit.R_LG * 2.0), 2.0)), UiKit.BEVEL)
		if rivets <= 0:
			return
		var inset := 15.0
		var pts: Array = [Vector2(inset, inset), Vector2(r.x - inset, inset)]
		if rivets >= 4:
			pts.append(Vector2(inset, r.y - inset))
			pts.append(Vector2(r.x - inset, r.y - inset))
		for p: Vector2 in pts:
			# Contact shadow first, then the head — same order as the floor.
			draw_circle(p + Vector2(0, 1.5), 5.0, Color(0, 0, 0, 0.40))
			draw_circle(p, 4.0, UiKit.RIVET)


# --- buttons ---------------------------------------------------------------

## Press feedback for every tier, applied once. `button_down`, not `pressed`:
## Godot fires `pressed` on RELEASE, so holding PLAY delayed its own click sound.
## The button travels TOWARD the finger and arrests — a press is a pull.
static func _press_feel(b: Button, primary: bool) -> void:
	b.button_down.connect(func() -> void:
		Audio.play("ui_tap", 0.92 if primary else 1.14, -9.0 if primary else -14.0)
		Platform.vibrate(8 if primary else 4, 0.20 if primary else 0.10)
		# b.create_tween, not create_tween: a locale change frees every screen, and
		# a tween owned by the caller would outlive its target.
		snap(b.create_tween()).tween_property(b, "scale", Vector2(0.975, 0.94), dur(0.05)))
	b.button_up.connect(func() -> void:
		snap(b.create_tween()).tween_property(b, "scale", Vector2.ONE, dur(0.14)))


static func _base_btn(text: String, height: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	# Focus rings are wrong on a phone and essential on the web build, where
	# keyboard navigation is the only input some players have.
	b.focus_mode = Control.FOCUS_NONE if Platform.prefers_touch() else Control.FOCUS_ALL
	# Set from `resized`, never from `size` at build time: a screen hidden across
	# a viewport resize has a zero rect at exactly the moment it is shown again,
	# which is the bug ui.gd's preset re-assert loop already exists for.
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	return b


## Primary: the amber key. Money and the one action a screen exists for.
static func btn(text: String, accent := Color.TRANSPARENT, height := TAP_MIN) -> Button:
	var b := _base_btn(text, height)
	if accent.a <= 0.0:
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		_press_feel(b, false)
		return b

	var sb := flat(accent, R_MD, Vector2(S3, 26))
	# A darker bottom edge gives the button physical depth. Flat slabs were the
	# single biggest reason these read as unfinished.
	sb.border_width_bottom = 6
	sb.border_color = accent.darkened(0.35)
	var hv: StyleBoxFlat = sb.duplicate()
	hv.bg_color = accent.lightened(0.10)
	var pr: StyleBoxFlat = sb.duplicate()
	pr.bg_color = accent.darkened(0.12)
	# Pressed loses the lip and shifts down — the button visibly travels.
	pr.border_width_bottom = 0
	pr.content_margin_top = 32
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, ACCENT_INK)
	_bevel_child(b, height)
	_press_feel(b, true)
	return b


## Secondary: a steel slab. BACK, MENU, PLAY AGAIN, RESTORE.
static func btn_secondary(text: String, height := TAP_MIN) -> Button:
	var b := _base_btn(text, height)
	var sb := flat(STEEL_40, R_MD, Vector2(S3, 26))
	sb.border_color = STEEL_50
	sb.set_border_width_all(2)
	sb.border_width_bottom = 5
	var hv: StyleBoxFlat = sb.duplicate()
	hv.bg_color = STEEL_50
	var pr: StyleBoxFlat = sb.duplicate()
	pr.bg_color = STEEL_40.darkened(0.12)
	pr.border_width_bottom = 0
	pr.content_margin_top = 31
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	_press_feel(b, false)
	return b


## Tertiary: an outline. "no thanks", SKIP, header back.
static func btn_ghost(text: String, height := TAP_MIN) -> Button:
	var b := _base_btn(text, height)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.set_corner_radius_all(R_MD)
	sb.border_color = STEEL_50
	sb.set_border_width_all(2)
	sb.content_margin_left = S3
	sb.content_margin_right = S3
	var hv: StyleBoxFlat = sb.duplicate()
	hv.bg_color = STEEL_40
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_color_override("font_color", INK_DIM)
	b.add_theme_color_override("font_hover_color", INK)
	_press_feel(b, false)
	return b


## Kept as the old name; the fill was 1.07:1 against the theme default, i.e.
## invisible, and its only caller shipped with visible = false.
static func btn_outline(text: String, height := TAP_MIN) -> Button:
	return btn_ghost(text, height)


## Destructive. Outlined until the confirm step, which is when it fills — so
## DELETE MY DATA reads dangerous and RESTORE PURCHASES does not.
static func btn_danger(text: String, confirm := false, height := TAP_MIN) -> Button:
	var b := _base_btn(text, height)
	var sb := StyleBoxFlat.new()
	sb.bg_color = DANGER if confirm else Color.TRANSPARENT
	sb.set_corner_radius_all(R_MD)
	sb.border_color = DANGER_LINE
	sb.set_border_width_all(2)
	sb.content_margin_left = S3
	sb.content_margin_right = S3
	var hv: StyleBoxFlat = sb.duplicate()
	hv.bg_color = DANGER if confirm else Color(DANGER.r, DANGER.g, DANGER.b, 0.22)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	var ink := INK if confirm else DANGER_LINE
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", ink)
	_press_feel(b, false)
	return b


## Text-only button — for things like "maybe later".
static func btn_text(text: String, height := 96) -> Button:
	var b := _base_btn(text, height)
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", INK_MUTE)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_font_size_override("font_size", 32)
	_press_feel(b, false)
	return b


## Priced but unaffordable. Still tappable, so tapping can explain why instead of
## doing nothing silently. Losing the lip is what reads as inert.
static func dim_btn(text: String, height := TAP_MIN) -> Button:
	var b := _base_btn(text, height)
	var sb := flat(ACCENT.darkened(0.45), R_MD, Vector2(S3, 26))
	sb.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.40)
	sb.set_border_width_all(2)
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.60))
	_press_feel(b, false)
	return b


## The bevel is a child because StyleBoxFlat has exactly one border colour, so a
## light top edge and a dark bottom edge cannot both come from the stylebox.
static func _bevel_child(c: Control, _height: int) -> void:
	var v := ColorRect.new()
	v.color = BEVEL
	v.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	v.offset_left = R_MD
	v.offset_right = -R_MD
	v.offset_top = 2
	v.custom_minimum_size = Vector2(0, 2)
	v.size = Vector2(0, 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)


## A terminal state — EQUIPPED, OWNED, CLAIMED. Not a Button, because it is not
## tappable: in the old shop these were dim buttons pixel-identical to the live
## tab beside them, so a player could not learn what responds to a tap.
static func state_tag(text: String, icon_name := "check", color := SIGNAL_GOOD) -> Control:
	var h := row([icon(icon_name, 30, color), lbl_label(text, T_LABEL, color)], S1)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


# --- misc ------------------------------------------------------------------

## A milled channel with the fill sitting in it. Was a flat 13% white wash.
static func bar(value: float, color := ACCENT, height := 16) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = 1.0
	p.value = clampf(value, 0.0, 1.0)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = STEEL_10
	bg.set_corner_radius_all(R_XS)
	bg.border_color = TROUGH
	bg.border_width_top = 2
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(R_XS)
	fg.border_color = color.lightened(0.28)
	fg.border_width_top = 2
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	return p


## Icon beside a label, at text height. Used for rarity, rank and currency rows.
static func icon(name: String, size := 34, tint := Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Icons.get_icon(name, tint)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Full-screen menu backdrop matching the arena ground.
static func backdrop(dim := 0.0) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ui_backdrop.gdshader")
	mat.set_shader_parameter("base_color", STEEL_20)
	mat.set_shader_parameter("rivet_color", STEEL_50)
	mat.set_shader_parameter("field_color", ACCENT)
	mat.set_shader_parameter("dim", dim)
	r.material = mat
	return r


## Point the backdrop's field lines at a control — they converge on whatever the
## screen wants you to press. `target` is in the backdrop's own pixel space.
static func set_pole(back: ColorRect, target: Control, strength := 1.0) -> void:
	if back == null or target == null or back.material == null:
		return
	var vp := back.get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var c := target.get_global_rect().get_center() / vp
	var mat: ShaderMaterial = back.material
	mat.set_shader_parameter("pole", c)
	mat.set_shader_parameter("pole_strength", strength)


static func spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func row(children: Array, separation := S2) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	for c: Control in children:
		h.add_child(c)
	return h


## Currency chip: a drawn coin/gem icon beside the balance.
static func currency_chip(currency: String) -> Control:
	var dot := icon("coin" if currency == "coins" else "gem", 34, Color.WHITE)
	var value := lbl(Locale.number(int(Game.get_value(currency, 0))), 38, INK)
	value.name = "Value"
	var h := row([dot, value], 10)
	h.set_meta("currency", currency)
	return h


## Counts the balance up rather than swapping the text, so claimed currency
## visibly lands in the wallet instead of two unrelated numbers changing.
static func refresh_chip(chip: Control) -> void:
	var currency := String(chip.get_meta("currency", "coins"))
	var value := chip.get_node_or_null("Value") as Label
	if value == null:
		return
	var target := int(Game.get_value(currency, 0))
	var from := int(chip.get_meta("shown", target))
	chip.set_meta("shown", target)
	if from == target or dur(1.0) == 0.0:
		value.text = Locale.number(target)
		return
	snap(value.create_tween()).tween_method(
			func(v: float) -> void: value.text = Locale.number(roundi(v)),
			float(from), float(target), weight_dur(0.40, absf(target - from)))


## Horizontal filter chips. Replaces two wrapping button grids: five slabs in a
## 3-column grid leaves two ragged holes, and a filled slab for SELECTION spends
## the amber that is supposed to mean money. Here selection is an indicator, which
## is what selection should be.
static func chip_row(labels: Array, keys: Array, active: String,
		on_pick: Callable, size := T_LABEL) -> Control:
	# NOT TouchScroll: that one drags vertically, and this row scrolls sideways —
	# it would swallow chip taps while scrolling nothing. A short row of chips has
	# empty space around it, so Godot's built-in touch scrolling is enough here.
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 76)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", S3)
	sc.add_child(h)
	for i in keys.size():
		var k := String(keys[i])
		var on := k == active
		var b := Button.new()
		b.text = String(labels[i]).to_upper()
		# Past the 48dp floor even though it has no box — an invisible hit area
		# still has to be thumb-sized.
		b.custom_minimum_size = Vector2(0, 72)
		b.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		b.add_theme_font_size_override("font_size", size)
		b.add_theme_color_override("font_color", INK if on else INK_MUTE)
		b.add_theme_color_override("font_hover_color", INK)
		if on:
			var u := ColorRect.new()
			u.color = ACCENT
			u.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			u.offset_top = -4
			u.custom_minimum_size = Vector2(0, 4)
			u.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(u)
		b.pressed.connect(func() -> void: on_pick.call(k))
		h.add_child(b)
	return sc


## Cosmetic preview: the magnet's two poles, split down the middle, drawn the way
## magnet.gdshader draws them.
##
## Drawn in a Control, deliberately NOT generated as an ImageTexture. Icons.gd
## rasterises per-pixel in GDScript, and one 128px preview at the existing
## supersample measured 122ms — so building fifteen of them to open the SKINS tab
## would stall for most of two seconds on desktop and worse on a phone.
## `minimap.gd` is the precedent: _draw is on the GPU, and retinting is free.
static func swatch(pole_a: Color, pole_b: Color, size := 96) -> Control:
	var s := Swatch.new()
	s.a = pole_a
	s.b = pole_b
	s.custom_minimum_size = Vector2(size, size)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


## Kind-aware preview. Every cosmetic used to preview as the same two-pole ring, so
## a trail, an effect, a nameplate and an arena were four identical chips — the shop
## could not tell you what you were buying for four of its five categories.
##
## Still a Control that draws, never a generated texture: one 128px procedural
## texture measured ~120ms, so a fifteen-item list would stall for most of two
## seconds (DECISIONS §12m).
static func cosmetic_preview(item: Dictionary, size := 96) -> Control:
	var s := Swatch.new()
	s.kind = String(item.get("kind", "skin"))
	s.a = Color(String(item.get("pole_a", item.get("color", item.get("base", "#8892a4")))))
	s.b = Color(String(item.get("pole_b", item.get("outline", item.get("grid", "#4a6fa5")))))
	s.c = Color(String(item.get("danger", "#5c2520")))
	s.enabled = bool(item.get("enabled", true))
	s.custom_minimum_size = Vector2(size, size)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


class Swatch extends Control:
	var a := Color.RED
	var b := Color.BLUE
	var c := Color.BLACK
	var kind := "skin"
	var enabled := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		match kind:
			"trail": _draw_trail()
			"launch_vfx": _draw_burst()
			"nameplate": _draw_plate()
			"arena_theme": _draw_arena()
			_: _draw_poles()

	## Three discs receding, exactly as the trail renders behind a magnet.
	func _draw_trail() -> void:
		if not enabled:
			# "None" is a real option and has to look like one, not like a bug.
			var mid := size * 0.5
			var w: float = minf(size.x, size.y) * 0.22
			draw_line(mid - Vector2(w, 0), mid + Vector2(w, 0), UiKit.INK_OFF, 4.0)
			return
		var r: float = minf(size.x, size.y) * 0.5
		for i in 3:
			var f := float(i) / 2.0
			draw_circle(size * 0.5 + Vector2(r * (0.42 - f * 0.42), r * (-0.42 + f * 0.84)),
					r * (0.30 - f * 0.13), Color(a, 1.0 - f * 0.62))

	## Concentric rings, which is what a launch burst is.
	func _draw_burst() -> void:
		var ctr := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5
		for i in 3:
			draw_arc(ctr, r * (0.28 + float(i) * 0.22), 0.0, TAU, 28,
					Color(a, 0.95 - float(i) * 0.26), r * 0.09, true)

	## The literal thing the item does: a name, in its colour, with its outline.
	func _draw_plate() -> void:
		var f := ThemeDB.fallback_font
		var px: int = int(minf(size.x, size.y) * 0.34)
		var text := "ACE"
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var at := Vector2((size.x - w) * 0.5, size.y * 0.5 + px * 0.36)
		for dx in [-2, 2]:
			for dy in [-2, 2]:
				draw_string(f, at + Vector2(dx, dy), text, HORIZONTAL_ALIGNMENT_LEFT,
						-1, px, b)
		draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, a)

	## Four plates with seams and one danger corner — three of the theme's colours
	## instead of one, so the five arenas stop previewing as identical near-blacks.
	func _draw_arena() -> void:
		var half := size * 0.5
		var g := minf(size.x, size.y) * 0.035
		draw_rect(Rect2(Vector2.ZERO, size), a)
		draw_rect(Rect2(half.x - g * 0.5, 0, g, size.y), b)
		draw_rect(Rect2(0, half.y - g * 0.5, size.x, g), b)
		draw_rect(Rect2(half.x + g * 0.5, half.y + g * 0.5,
				half.x - g * 0.5, half.y - g * 0.5), c)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45), false, 3.0)

	func _draw_poles() -> void:
		var ctr := size * 0.5
		var r: float = minf(size.x, size.y) * 0.36
		var w: float = r * 0.86
		# Two half-rings rather than two half-discs: the silhouette is the game's
		# own horseshoe, so a flat colour chip becomes a picture of the object you
		# are buying. A single flat fill also threw pole_b away entirely — every
		# two-tone skin previewed as one colour.
		# Top/bottom, matching magnet.gdshader's split on model Z. A preview that
		# divides the other way to the thing it previews is worse than no preview.
		# pole_a is on the BOTTOM: +Z is toward the bottom of the screen under a
		# top-down camera, and the shader gives pole_a to positive Z.
		draw_arc(ctr, r, PI, TAU, 20, b, w)
		draw_arc(ctr, r, 0.0, PI, 20, a, w)
		draw_arc(ctr, r + w * 0.5, 0.0, TAU, 32, Color(0, 0, 0, 0.45), 3.0, true)


## One modal, so the four hand-rolled copies (consent, daily calendar, delete
## confirm, rating prompt) cannot drift apart. Returns the content box to fill;
## close it with `dismiss(box)`.
##
## `opaque` is for the age gate, which is a legal precondition rather than a
## dialog: nothing may show through it.
## Comfortably more than any safe-area inset plus layout padding — the largest
## real inset is a landscape notch at ~130px.
const MODAL_BLEED := 400.0


static func modal(parent: Control, opaque := false) -> VBoxContainer:
	var popup := Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var shade := ColorRect.new()
	# 0.97, not 0.88: at any lower value the menu's amber PLAY button read as a
	# lighter band straight through the dialog, and the wordmark ghosted behind the
	# title. A modal is a different surface, not a tint over the previous one.
	shade.color = Color(0.055, 0.051, 0.043, 1.0 if opaque else 0.97)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Overshoot the parent on every side. Modals are parented into the safe-area
	# layout, so a scrim that stops at the parent's rect leaves a bright frame of
	# plate around a blacked-out middle — the same "picture frame" already fixed
	# once for the results screen (§12). Overshooting rather than measuring the
	# inset because the inset is not known until a layout pass has run, and a scrim
	# that is correct one frame late flashes on the way in. The excess is clipped by
	# the viewport and a flat ColorRect costs nothing to overdraw.
	shade.offset_left = -MODAL_BLEED
	shade.offset_top = -MODAL_BLEED
	shade.offset_right = MODAL_BLEED
	shade.offset_bottom = MODAL_BLEED
	shade.modulate.a = 0.0
	popup.add_child(shade)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", S2)
	box.modulate.a = 0.0
	# From `resized`, never from `size` here: the box has no rect until the parent
	# has run a layout pass, and a zero pivot scales from the top-left corner.
	box.resized.connect(func() -> void: box.pivot_offset = box.size * 0.5)
	popup.add_child(box)

	parent.add_child(popup)
	box.set_meta("popup", popup)

	# Pulled into place and arrested — not bounced. See `snap`.
	box.scale = Vector2(0.94, 0.94)
	shade.create_tween().tween_property(shade, "modulate:a", 1.0, dur(0.12))
	var tw := box.create_tween()
	tw.parallel().tween_property(box, "modulate:a", 1.0, dur(0.14))
	snap(tw.parallel()).tween_property(box, "scale", Vector2.ONE, dur(0.26))
	return box


## Fades a modal out and frees it. Safe to call on null or on an already-freed box,
## because every close path in the UI is reachable more than once.
static func dismiss(box: Control) -> void:
	if box == null or not is_instance_valid(box):
		return
	var popup: Control = box.get_meta("popup", null)
	if popup == null or not is_instance_valid(popup):
		return
	if popup.get_meta("closing", false):
		return
	popup.set_meta("closing", true)
	var tw := popup.create_tween()
	tw.tween_property(popup, "modulate:a", 0.0, dur(0.13))
	tw.tween_callback(popup.queue_free)


## Screen entrance. Scale only — NEVER position: show_screen re-asserts the
## full-rect preset on whatever became visible, and that would fight an offset
## tween every frame.
static func enter(root: Control) -> void:
	if root == null or not is_instance_valid(root):
		return
	root.modulate.a = 0.0
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, dur(0.16))


## A round icon button. Text-only links gave no signal that they were controls at
## all — which is a real complaint, not a theoretical one. A circular button with a
## glyph is the convention every player already knows from every other game on
## their phone, and this is the wrong place to be original.
static func icon_btn(icon_name: String, diameter := 116, tint := INK_DIM) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.focus_mode = Control.FOCUS_NONE if Platform.prefers_touch() else Control.FOCUS_ALL
	var sb := StyleBoxFlat.new()
	sb.bg_color = STEEL_40
	sb.set_corner_radius_all(diameter / 2)
	sb.border_color = STEEL_50
	sb.set_border_width_all(2)
	sb.border_width_bottom = 4
	var hv: StyleBoxFlat = sb.duplicate()
	hv.bg_color = STEEL_50
	var pr: StyleBoxFlat = sb.duplicate()
	pr.bg_color = STEEL_40.darkened(0.12)
	pr.border_width_bottom = 0
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.icon = Icons.get_icon(icon_name, tint)
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	_press_feel(b, false)
	return b


## Round button with a caption beneath it. The caption is what makes an icon
## unambiguous — an icon alone is a guess, and a label alone is not obviously
## tappable, so navigation wants both.
static func icon_nav(icon_name: String, caption: String, diameter := 126) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", S1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := icon_btn(icon_name, diameter)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(b)
	col.add_child(lbl_label(caption, T_MICRO, INK_MUTE, HORIZONTAL_ALIGNMENT_CENTER))
	col.set_meta("button", b)
	return col


## A small amber disc pinned to a control's top-right. Replaces the "  ·  NEW"
## string suffix, which read as a typo and was never translated.
static func new_dot(host: Control) -> void:
	var d := ColorRect.new()
	d.color = ACCENT
	d.custom_minimum_size = Vector2(18, 18)
	d.size = Vector2(18, 18)
	d.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	d.offset_left = -22
	d.offset_top = 4
	d.offset_right = -4
	d.offset_bottom = 22
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(d)


## Full-width tab bar: equal cells, icon over label, active cell marked by an amber
## top inlay rather than a fill — selection is an indicator, not money.
##
## This replaces a text-only chip row for TOP-LEVEL navigation. Five words in a
## line gave no affordance that they were tappable at all, and the row occupied a
## fraction of the width so the tap targets were small and unevenly spaced.
static func nav_bar(labels: Array, keys: Array, glyphs: Array, active: String,
		on_pick: Callable, height := 148) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	h.custom_minimum_size = Vector2(0, height)
	for i in keys.size():
		var k := String(keys[i])
		var on := k == active
		var cell := Button.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size = Vector2(0, height)
		cell.focus_mode = Control.FOCUS_NONE if Platform.prefers_touch() \
				else Control.FOCUS_ALL
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(STEEL_40.r, STEEL_40.g, STEEL_40.b, 0.55) if on \
				else Color.TRANSPARENT
		var hv := StyleBoxFlat.new()
		hv.bg_color = Color(STEEL_40.r, STEEL_40.g, STEEL_40.b, 0.8)
		cell.add_theme_stylebox_override("normal", sb)
		cell.add_theme_stylebox_override("hover", hv)
		cell.add_theme_stylebox_override("pressed", hv)

		# Button is not a Container, so the content is placed by anchors. Same trick
		# as the button bevel.
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", S0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tint: Color = ACCENT if on else INK_MUTE
		var ic := icon(String(glyphs[i]), 50, tint)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ic)
		col.add_child(lbl_label(String(labels[i]), T_MICRO, tint,
				HORIZONTAL_ALIGNMENT_CENTER))
		cell.add_child(col)

		if on:
			var inlay := ColorRect.new()
			inlay.color = ACCENT
			inlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			inlay.custom_minimum_size = Vector2(0, 4)
			inlay.offset_bottom = 4
			inlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(inlay)

		cell.pressed.connect(func() -> void: on_pick.call(k))
		_press_feel(cell, false)
		h.add_child(cell)
	return h


## Caps a primary action's width and centres it. A button spanning the full frame
## edge to edge has no shape of its own — it reads as a coloured band, not a key.
static func cap_width(c: Control, max_w := 620) -> Control:
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.custom_minimum_size.x = max_w
	return c


## A ScrollContainer you can drag anywhere inside, including on top of buttons.
##
## Godot delivers a touch to the topmost Control, so a drag that starts on a shop
## card goes to the CARD and the ScrollContainer never hears about it. Its built-in
## touch scrolling only works on empty space — and a shop is packed with cards, so
## on a phone these screens simply did not scroll.
##
## Handled in `_input`, which runs BEFORE the GUI pass, so the drag is seen no
## matter what is under the finger. Past a small threshold the release is swallowed
## too: without that, scrolling past a price button would buy the item.
class TouchScroll extends ScrollContainer:
	## Below this the gesture is a tap and the button underneath keeps it.
	const SLOP := 14.0

	var _finger := -1
	var _last := 0.0
	var _travel := 0.0

	func _init() -> void:
		# Godot's own touch handling would fight this one.
		set_deferred("scroll_deadzone", 0)

	func _input(event: InputEvent) -> void:
		if not is_visible_in_tree():
			return
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed:
				if get_global_rect().has_point(touch.position):
					_finger = touch.index
					_last = touch.position.y
					_travel = 0.0
			elif touch.index == _finger:
				_finger = -1
				if _travel > SLOP:
					# This was a scroll, not a tap. Swallow the release so the
					# control under the finger never fires.
					get_viewport().set_input_as_handled()
		elif event is InputEventScreenDrag:
			var drag := event as InputEventScreenDrag
			if drag.index != _finger:
				return
			var dy := drag.position.y - _last
			_last = drag.position.y
			_travel += absf(dy)
			scroll_vertical -= int(dy)
			if _travel > SLOP:
				get_viewport().set_input_as_handled()


## Use everywhere a list has to scroll on a phone.
static func scroll() -> ScrollContainer:
	var s := TouchScroll.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s
