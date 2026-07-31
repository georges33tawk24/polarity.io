class_name Ui
extends CanvasLayer
## Every screen: menu, HUD, results, settings.
##
## Built in code rather than as .tscn files — the layout is driven by runtime
## breakpoints and safe-area insets anyway, so a scene file would only be a
## second place to keep the same anchors in sync.

signal play_pressed
signal menu_pressed

## Amber only. BG/UiKit.DANGER_LINE/UiKit.INK_DIM used to be aliased here too, which meant the deprecated
## names outlived the deprecation: a screen could reach either system and nothing
## flagged it.
const ACCENT := UiKit.ACCENT

var theme_res: Theme

## Plain Control, deliberately NOT a MarginContainer: a container overwrites its
## child's anchors every layout pass, which silently discarded the landscape
## width clamp below.
var _safe: Control
var _layout: Control
var _backdrop: ColorRect
var _menu: Control
var _hud: Control
var _results: Control
var _settings: Control

# HUD widgets
## Board geometry. Rows are hand-positioned, so these are load-bearing.
const BOARD_W := 430
const BOARD_ROW_H := 44

var _mass_label: Stencil.StencilLabel
var _mass_shown := 0.0
var _mass_target := 0.0
var _ring_bar: ProgressBar
var _ring_shown := -1.0
var _last_clock := -1
var _alive_caption: Label
var _board_rows: Dictionary = {}
var _board_ranks: Dictionary = {}
var _board_toggle: Button
var _board_collapsed := false
var _map_toggle: Button
var _map_collapsed := false
var _clock_label: Label
var _alive_label: Label
var _board: Control
var _feed: VBoxContainer
var _charge: ProgressBar
var _centre: Label
var _warning: Label
var _hint: Label

# Menu / results widgets
var _name_edit: LineEdit
var _pole_target: Control
var _result_trophy: HBoxContainer
var _arena: Arena
var _revive_box: Control
var _emote_row: HBoxContainer
var _result_pose: Control

## Store review requires a working support contact on both platforms. Replace with
## a real address before submitting — a dead mailto is a rejection.
const SUPPORT_EMAIL := "support@example.com"
var _wallet: Label
var _result_rows: VBoxContainer
var _result_title: Stencil.StencilLabel
var _result_sub: Label
var _double_btn: Button

var _portrait := true
var _rank_label: Label
var _meta_panel: MetaPanel = null
var _minimap: Minimap
var _daily_popup: Control = null
var _ftue: Ftue = null
var _consent_popup: Control = null


func _ready() -> void:
	layer = 10
	_build_theme()

	# Full-viewport, and deliberately OUTSIDE _safe: a shade drawn inside the
	# safe-area inset leaves the arena visible in the margin strips.
	_backdrop = UiKit.backdrop()
	_backdrop.visible = false
	add_child(_backdrop)

	_safe = Control.new()
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# CanvasLayer has no theme of its own — the topmost Control carries it and
	# every descendant inherits.
	_safe.theme = theme_res
	add_child(_safe)

	_layout = Control.new()
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_layout)

	_menu = _build_menu()
	_hud = _build_hud()
	_results = _build_results()
	_settings = _build_settings()
	for c in [_menu, _hud, _results, _settings]:
		_layout.add_child(c)
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.visible = false

	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_connect_bus()
	Bus.locale_changed.connect(rebuild)


## Rebuilds every screen in the current language, preserving which one is shown.
## `tr()` resolves when a Control is constructed, so there is nothing to refresh
## in place — the screens have to be rebuilt.
func rebuild() -> void:
	var current := "menu"
	if _hud.visible:
		current = "hud"
	elif _results.visible:
		current = "results"
	var settings_open := _settings.visible

	for c in [_menu, _hud, _results, _settings]:
		_layout.remove_child(c)
		c.queue_free()
	if _meta_panel != null:
		_meta_panel.queue_free()
		_meta_panel = null
	if _daily_popup != null:
		UiKit.dismiss(_daily_popup)
		_daily_popup = null
	stop_ftue()
	_close_consent()

	_menu = _build_menu()
	_hud = _build_hud()
	_results = _build_results()
	_settings = _build_settings()
	for c in [_menu, _hud, _results, _settings]:
		_layout.add_child(c)
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.visible = false

	# RTL languages flip the whole tree; Godot inherits this down from the root.
	_safe.layout_direction = Control.LAYOUT_DIRECTION_RTL if \
			Locale.is_rtl(String(Game.get_value("locale", "en"))) \
			else Control.LAYOUT_DIRECTION_LTR

	_relayout()
	show_screen(current)
	_settings.visible = settings_open
	# Menu and settings are mutually exclusive; a rebuild must not leave both up.
	if settings_open:
		_menu.visible = false
	_update_backdrop()


func _connect_bus() -> void:
	# The score used to be a bare string assignment, so it teleported. It now
	# climbs toward the target, and Locale.number stops it disagreeing with the
	# leaderboard's own row for the same player (1200 vs 1,200, both on screen).
	Bus.player_mass_changed.connect(func(m: float) -> void: _mass_target = m)
	Bus.player_absorbed.connect(func(_p: Vector3, _a: float) -> void: _punch_mass())
	Bus.ring_changed.connect(_on_ring)
	Bus.player_down.connect(_on_player_down)
	Bus.clock_changed.connect(_on_clock)
	Bus.alive_count_changed.connect(_on_alive)
	Bus.leaderboard_changed.connect(_on_board)
	Bus.player_charge_changed.connect(_on_charge)
	Bus.countdown_tick.connect(_on_countdown)
	Bus.match_started.connect(func() -> void: _flash_centre(tr("UI_GO"), 0.6))
	Bus.sudden_death_started.connect(func() -> void:
		_flash_centre(tr("UI_SUDDEN_DEATH"), 1.4)
		Audio.set_intensity(1.0))
	Bus.magnet_eliminated.connect(_on_eliminated)
	Bus.player_outside_ring.connect(func(out: bool) -> void: _warning.visible = out)
	Bus.match_ended.connect(_on_match_ended)
	Bus.profile_changed.connect(_refresh_wallet)


# --- layout ----------------------------------------------------------------
func _relayout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_portrait = vp.y >= vp.x

	# Safe-area insets and the landscape width clamp are both applied as offsets
	# on one full-rect Control, so nothing can overwrite them.
	var insets := Platform.safe_insets()
	# UI scale is applied as extra inset rather than a Control scale: scaling a
	# CanvasLayer breaks anchor maths and hit-testing, padding does not.
	var ui_scale: float = clampf(float(Game.get_value("ui_scale", 1.0)), 0.75, 1.5)
	var pad := 24.0 * ui_scale
	var side := 0.0
	if not _portrait:
		# Stop the UI spreading to the far corners of a 21:9 monitor — clamp it
		# to a readable column and centre it.
		side = maxf(0.0, (vp.x - minf(vp.x, vp.y * 1.05 / ui_scale)) * 0.5)
	_safe.offset_left = insets.x + pad + side
	_safe.offset_top = insets.y + pad
	_safe.offset_right = -(insets.z + pad + side)
	_safe.offset_bottom = -(insets.w + pad)

	# Touch devices get the charge meter near the thumb; desktop gets a hint line.
	# The instruction strip is onboarding, not HUD. It retires after a few
	# matches — a permanent hint line is the least .io thing on screen.
	_hint.text = tr("UI_HINT_TOUCH") if Platform.prefers_touch() else tr("UI_HINT_DESKTOP")
	_hint.visible = int(Game.get_value("matches", 0)) < 3


func _build_theme() -> void:
	theme_res = Theme.new()
	# Ink-on-light: the surface flipped, so a white translucent fill and white
	# label are now invisible against it.
	var normal := StyleBoxFlat.new()
	normal.bg_color = UiKit.STEEL_40
	normal.set_corner_radius_all(UiKit.R_MD)
	normal.content_margin_left = 36
	normal.content_margin_right = 36
	normal.content_margin_top = 28
	normal.content_margin_bottom = 28
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = UiKit.STEEL_50
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = UiKit.STEEL_40.darkened(0.12)

	theme_res.set_stylebox("normal", "Button", normal)
	theme_res.set_stylebox("hover", "Button", hover)
	theme_res.set_stylebox("pressed", "Button", pressed)
	theme_res.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme_res.set_font_size("font_size", "Button", UiKit.T_LEAD)
	theme_res.set_color("font_color", "Button", UiKit.INK)

	# A milled slot, not a translucent slab. At menu dim the old 6% fill showed a
	# plate seam and two rivet heads through the field's interior — the same defect
	# already recorded and fixed for cards in ART_DIRECTION Part 4.
	var edit := UiKit.recess(UiKit.R_MD)
	edit.content_margin_left = 28
	edit.content_margin_right = 28
	edit.content_margin_top = 22
	edit.content_margin_bottom = 22
	# The field had no focus feedback at all — "focus" reused the same box.
	var edit_focus: StyleBoxFlat = edit.duplicate()
	edit_focus.border_color = Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.75)
	edit_focus.set_border_width_all(2)
	edit_focus.border_width_top = 3
	theme_res.set_stylebox("normal", "LineEdit", edit)
	theme_res.set_stylebox("focus", "LineEdit", edit_focus)
	theme_res.set_font_size("font_size", "LineEdit", 42)
	theme_res.set_color("font_color", "LineEdit", UiKit.INK)
	theme_res.set_color("font_placeholder_color", "LineEdit", UiKit.INK_DIM)


func _btn(text: String, accent := Color.TRANSPARENT) -> Button:
	return UiKit.btn(text, accent)


func _lbl(text: String, size: int, color := UiKit.INK,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return UiKit.lbl(text, size, color, align)


# --- menu ------------------------------------------------------------------
func _build_menu() -> Control:
	var root := Control.new()

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", UiKit.S2)
	root.add_child(box)

	# "POLARITY" is the brand — deliberately never translated, and deliberately
	# drawn rather than typeset: it was Godot's fallback font at 104px, which is
	# the loudest "nobody chose a typeface" signal a title screen can send.
	var mark: Control = UiKit.wordmark(UiKit.T_DISPLAY)
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(mark)
	box.add_child(_lbl(tr("UI_TAGLINE"), UiKit.T_BODY, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	box.add_child(UiKit.spacer(UiKit.S4))

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = tr("UI_YOUR_NAME")
	_name_edit.max_length = 12
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.text = String(Game.get_value("name", ""))
	_name_edit.text_changed.connect(func(v: String) -> void: Game.set_value("name", v))
	# Matches PLAY so the two read as one stacked control rather than two widths.
	UiKit.cap_width(_name_edit, 700)
	box.add_child(_name_edit)

	var play := _btn(tr("UI_PLAY"), ACCENT)
	UiKit.cap_width(play, 700)
	play.pressed.connect(func() -> void: play_pressed.emit())
	box.add_child(play)
	# The backdrop's field lines converge here. Kept as a reference rather than a
	# one-off call because the pole has to be re-aimed after every layout pass.
	_pole_target = play


	# One secondary row of text links, not a stack of slabs. An .io front end is
	# a name field and a PLAY button; everything else lives underneath, small.
	# Progressive unlock (spec §4.7) still applies — a first-timer sees only PLAY.
	var event: Dictionary = Meta.active_event()
	if not event.is_empty():
		var banner := UiKit.plate(UiKit.STEEL_30, UiKit.R_LG, 2, UiKit.ACCENT)
		UiKit.cap_width(banner, 700)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", UiKit.S0)
		col.add_child(_lbl(tr(String(event.get("name_key", ""))), UiKit.T_LABEL,
				UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
		col.add_child(_lbl(tr("UI_EVENT_ENDS") % Locale.duration(
				Meta.event_seconds_left()), UiKit.T_MICRO, UiKit.INK_MUTE,
				HORIZONTAL_ALIGNMENT_CENTER))
		banner.add_child(col)
		box.add_child(banner)
		box.add_child(UiKit.spacer(UiKit.S1))

	var matches := int(Game.get_value("matches", 0))
	var boosts := HBoxContainer.new()
	boosts.alignment = BoxContainer.ALIGNMENT_CENTER
	boosts.add_theme_constant_override("separation", UiKit.S2)
	if matches >= 2 and Config.flag("boost_enabled") and Ads.rewarded_available() \
			and not bool(Game.get_value("boost_mass", false)):
		var boost := UiKit.btn_ghost(tr("UI_BOOST_START"), 104)
		boost.add_theme_font_size_override("font_size", UiKit.T_LABEL)
		boost.pressed.connect(_on_boost)
		boosts.add_child(boost)
	if matches >= 2 and Meta.wheel_available():
		var spin := UiKit.btn_ghost(tr("UI_DAILY_SPIN"), 104)
		spin.add_theme_font_size_override("font_size", UiKit.T_LABEL)
		spin.pressed.connect(_on_wheel)
		boosts.add_child(spin)
	if boosts.get_child_count() > 0:
		box.add_child(UiKit.spacer(UiKit.S1))
		box.add_child(boosts)
	box.add_child(UiKit.spacer(UiKit.S1))

	# Round icon buttons, not text links. Four words in a row gave no signal that
	# they were controls at all, and a 34x36dp text hit area is under the 48dp floor
	# this project's own rules set.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UiKit.S4)
	if matches >= 1:
		# First tile: it is the only time-sensitive one, and the dot tells you
		# whether it is worth opening without opening it.
		row.add_child(_nav_tile("gift", "UI_DAILY_SHORT",
				func() -> void: show_daily_if_due(true),
				bool(Meta.daily_state().get("can_claim", false))))
		row.add_child(_nav_tile("bag", "UI_SHOP", func() -> void: open_meta("shop"),
				_is_new("shop", matches == 1)))
	if matches >= 2:
		row.add_child(_nav_tile("target", "UI_MISSIONS",
				func() -> void: open_meta("missions"), _is_new("missions", matches == 2)))
	if matches >= 3:
		row.add_child(_nav_tile("bars", "UI_LEADERBOARD",
				func() -> void: open_meta("board"), false))
	row.add_child(_nav_tile("gear", "UI_SETTINGS", _open_settings, false))
	box.add_child(row)

	box.add_child(UiKit.spacer(UiKit.S3))
	_rank_label = _lbl("", UiKit.T_CAPTION, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_rank_label)
	_wallet = _lbl("", UiKit.T_CAPTION, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_wallet)
	_refresh_wallet()
	return root


## The consent screen was removed at the user's request. Ads are contextual-only, so
## there is nothing to ask permission for; the ADS toggle in Settings is the player's
## control. Kept as a no-op because show_screen() and the daily-reward flow both call
## it, and because Ads.needs_consent() is the one switch that brings a prompt back if
## an ad network demands its own.
func show_consent_if_needed() -> void:
	if not Ads.needs_consent():
		return
	push_warning("Ads.needs_consent() is true but the consent dialog was removed")


func _close_consent() -> void:
	if _consent_popup != null:
		UiKit.dismiss(_consent_popup)
		_consent_popup = null


## Runs once the whole consent flow is resolved — anything that was suppressed
## while it was on screen happens now.
func _after_consent() -> void:
	# The daily reward used to open itself here. It is a button on the menu now —
	# a modal that appears unbidden between a player and the PLAY button is the
	# thing §16 exists to prevent.
	pass


## Starts the guided first match if the player has never finished the tutorial.
## Safe to call every match — it no-ops once `seen_tutorial` is set.
func start_ftue(arena: Arena) -> void:
	if bool(Game.get_value("seen_tutorial", false)):
		return
	if _ftue != null and is_instance_valid(_ftue):
		_ftue.queue_free()
	_ftue = Ftue.new()
	_ftue.setup(arena)
	_layout.add_child(_ftue)


func stop_ftue() -> void:
	if _ftue != null and is_instance_valid(_ftue):
		_ftue.queue_free()
	_ftue = null


## Daily calendar, shown once per UTC day when the player reaches the menu.
## Deliberately non-blocking: it is dismissible and never gates the PLAY button
## (spec §16 — never block the first play session).
## `manual` means the player pressed the button, so the calendar opens even when
## there is nothing to claim today — they asked to see their streak. Called with
## false it does nothing, which is what every automatic caller now does.
func show_daily_if_due(manual := false) -> void:
	if not manual:
		return
	var state := Meta.daily_state()
	if _daily_popup != null:
		return

	var box := UiKit.modal(_layout)

	box.add_child(_lbl(tr("UI_DAILY_REWARD"), UiKit.T_TITLE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_lbl(tr("UI_STREAK") % int(state["streak"]), 34, UiKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.spacer(20))

	var calendar: Array = state["calendar"]
	var grid := GridContainer.new()
	grid.columns = 4
	# The grid used to be left-aligned in a full-width box, so a 7-cell calendar sat
	# in the left half of the screen with the title centred above it.
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for i in calendar.size():
		var entry: Dictionary = calendar[i]
		var is_today: bool = i == int(state["slot"])
		var cell := UiKit.panel(ACCENT if is_today else Color.TRANSPARENT)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 4)
		inner.add_child(_lbl(tr("UI_DAY_N") % int(entry.get("day", i + 1)), 26,
				UiKit.INK if is_today else UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER))
		# These were the last two raw hex colours in the UI, and one of them was
		# #5ce1ff — the saturated cyan the art direction bans by name.
		inner.add_child(_lbl("+%s" % Locale.number(int(entry.get("amount", 0))), 32,
				UiKit.BRASS if entry.get("currency") == "coins" else UiKit.POLE_NEG,
				HORIZONTAL_ALIGNMENT_CENTER))
		cell.add_child(inner)
		# Equal cells: content-sized ones made DAY 3 (+5) narrower than DAY 7 (+750)
		# and the calendar read as ragged.
		cell.custom_minimum_size = Vector2(150, 150)
		grid.add_child(cell)
		# This is the one screen in the build whose whole job is to feel like a
		# prize, and every cell used to arrive in the same frame.
		cell.modulate.a = 0.0
		var ct := cell.create_tween()
		ct.tween_interval(UiKit.dur(0.06 + float(i) * 0.04))
		ct.tween_property(cell, "modulate:a", 1.0, UiKit.dur(0.12))
		if is_today:
			# A slow breath on the one cell you can actually claim. Never under
			# reduced motion — a zero-duration looping tween errors out.
			if UiKit.dur(1.0) > 0.0:
				var bt := cell.create_tween().set_loops()
				bt.tween_property(cell, "scale", Vector2(1.03, 1.03), 0.9)
				bt.tween_property(cell, "scale", Vector2.ONE, 0.9)
				cell.resized.connect(func() -> void: cell.pivot_offset = cell.size * 0.5)
	box.add_child(grid)
	box.add_child(UiKit.spacer(20))

	if not bool(state["can_claim"]):
		# Reachable now that the player can open this whenever they like. A CLAIM
		# button that silently does nothing would be worse than saying so.
		box.add_child(UiKit.state_tag(tr("UI_COME_BACK_TOMORROW"), "check",
				UiKit.INK_MUTE))
		var shut := UiKit.btn_secondary(tr("UI_BACK"))
		UiKit.cap_width(shut, 640)
		shut.pressed.connect(_close_daily)
		box.add_child(shut)
		_daily_popup = box
		return

	var claim := _btn(tr("UI_CLAIM"), ACCENT)
	UiKit.cap_width(claim, 640)
	claim.pressed.connect(func() -> void:
		var got := Meta.claim_daily()
		if not got.is_empty():
			_flash_toast("+%s" % Locale.number(int(got["amount"])))
		_close_daily())
	box.add_child(claim)

	var later := UiKit.btn_text(tr("UI_COME_BACK"))
	later.pressed.connect(_close_daily)
	box.add_child(later)

	_daily_popup = box


func _close_daily() -> void:
	if _daily_popup != null:
		_daily_popup.queue_free()
		_daily_popup = null
	_refresh_wallet()


## Meta screens live in their own node, created on first use — the menu should
## not pay to build a 30-tier battle pass list that most sessions never open.
func open_meta(tab: String) -> void:
	if _meta_panel == null:
		_meta_panel = MetaPanel.new()
		_layout.add_child(_meta_panel)
		_meta_panel.closed.connect(func() -> void:
			_meta_panel.visible = false
			_refresh_wallet())
	# The daily popup lives in the same layer; leaving it open lets it show
	# through and steal taps.
	_close_daily()
	_meta_panel.visible = true
	_meta_panel.open_tab(tab)
	_mark_seen(tab)


## Coach mark. A text suffix rather than a badge node — it survives the button
## being rebuilt on every locale change and costs nothing.
func _new_dot(key: String, just_unlocked: bool) -> String:
	var seen: Variant = Game.get_value("stats", {})
	var dict: Dictionary = seen if seen is Dictionary else {}
	if dict.get("seen_" + key, false):
		return ""
	if not just_unlocked:
		return ""
	return "   ·  " + tr("UI_NEW")


func _mark_seen(key: String) -> void:
	var seen: Variant = Game.get_value("stats", {})
	var dict: Dictionary = seen if seen is Dictionary else {}
	dict["seen_" + key] = true
	Game.set_value("stats", dict)


func _refresh_wallet() -> void:
	if _wallet == null:
		return
	var best := int(Game.get_value("best_placement", 0))
	_wallet.text = "%s %s   ·   %s" % [
		tr("UI_BEST"),
		("#%d" % best) if best > 0 else "—",
		Locale.number(int(Game.get_value("coins", 0))) + " " + tr("UI_COINS"),
	]
	if _rank_label != null:
		var r := Meta.rank()
		_rank_label.text = "%s   ·   %s" % [String(r["id"]).to_upper(),
				Locale.number(int(r["trophies"]))]
		# meta.json rank colours were chosen against a dark UI; darken for ink.
		var rc: Color = r["color"]
		_rank_label.add_theme_color_override("font_color",
				rc if rc.get_luminance() > 0.35 else rc.lightened(0.45))


# --- hud -------------------------------------------------------------------
func _build_hud() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# --- score, bottom-left. The one number that matters. -------------------
	var score_box := VBoxContainer.new()
	score_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	score_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	score_box.add_theme_constant_override("separation", 0)
	score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mass_label = Stencil.node("10", 88, UiKit.INK)
	# Drawn glyphs get no outline_size, so the dark pass has to be explicit — over
	# a pale nut the readout would otherwise vanish.
	_mass_label.shadow = Color(0.055, 0.051, 0.043, 0.85)
	score_box.add_child(_mass_label)
	# Charge lives here, beside the number, not as a 4px strip pinned to the very
	# bottom edge of the screen where it was not findable at all.
	_charge = UiKit.bar(0.0, ACCENT, 14)
	_charge.custom_minimum_size.x = 260
	score_box.add_child(_charge)
	score_box.add_child(UiKit.hud_lbl(tr("UI_MASS"), UiKit.T_CAPTION, UiKit.INK_DIM))
	root.add_child(score_box)

	# --- leaderboard, top-right. In this genre it IS the motivation loop. ---
	var board_panel := VBoxContainer.new()
	board_panel.custom_minimum_size.x = BOARD_W
	board_panel.add_theme_constant_override("separation", UiKit.S1)
	board_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Two unlabelled size-30 numbers eight pixels apart read as one string. Each
	# gets its unit, and a divider separates them.
	_alive_label = UiKit.lbl("15", UiKit.T_LEAD, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	_alive_label.pivot_offset = Vector2(20, 26)
	_alive_caption = UiKit.lbl(tr("UI_LEFT_SHORT"), UiKit.T_MICRO, UiKit.INK_MUTE)
	_alive_caption.size_flags_vertical = Control.SIZE_SHRINK_END
	_alive_caption.custom_minimum_size.y = 34
	var divider := ColorRect.new()
	divider.color = UiKit.STEEL_50
	divider.custom_minimum_size = Vector2(1, 34)
	_clock_label = UiKit.lbl("1:40", UiKit.T_LEAD, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_toggle = UiKit.btn_text("", 52)
	_board_toggle.custom_minimum_size.x = 52
	_board_toggle.add_theme_font_size_override("font_size", UiKit.T_LABEL)
	_board_toggle.pressed.connect(_toggle_board)
	var board_head := UiKit.row([_alive_label, _alive_caption, spring, divider,
			_clock_label, _board_toggle], UiKit.S1)
	board_panel.add_child(board_head)

	# The ring closes for most of the match and the only previous cue was the clock
	# going red under 15 seconds — i.e. after you were already dying. ring_changed
	# was emitted every frame and had zero consumers.
	_ring_bar = UiKit.bar(1.0, UiKit.BRASS, 6)
	board_panel.add_child(_ring_bar)

	# A plain Control, NOT a container: rows are positioned by hand so a rank
	# change can be tweened. A container would overwrite position every layout
	# pass and silently discard the motion.
	_board = Control.new()
	_board.custom_minimum_size = Vector2(BOARD_W, BOARD_ROW_H)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.clip_contents = true
	board_panel.add_child(_board)
	# Restored from the profile: a player who collapsed it wants it collapsed next
	# match too, not every match.
	_board_collapsed = bool(Game.get_value("board_collapsed", false))
	_apply_board_collapsed()

	# Bolted into the corner: square on the two edges that meet the screen, round
	# on the inside one. The riveted material appeared in the HUD zero times.
	var board_plate := PanelContainer.new()
	var plate_sb := UiKit.flat(Color(UiKit.STEEL_30.r, UiKit.STEEL_30.g,
			UiKit.STEEL_30.b, 0.86), 0, Vector2(UiKit.S2, UiKit.S2))
	plate_sb.corner_radius_bottom_left = UiKit.R_LG
	plate_sb.border_color = UiKit.STEEL_50
	plate_sb.border_width_left = 2
	plate_sb.border_width_bottom = 2
	board_plate.add_theme_stylebox_override("panel", plate_sb)
	board_plate.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	board_plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	board_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_plate.add_child(board_panel)
	root.add_child(board_plate)

	# --- minimap, bottom-right ----------------------------------------------
	_minimap = Minimap.new()
	# Explicit offsets, not just a preset: PRESET_BOTTOM_RIGHT pins all four
	# anchors to 1 and zeroes the offsets, which collapses the control to a
	# zero-size point in the corner.
	_minimap.anchor_left = 1.0
	_minimap.anchor_top = 1.0
	_minimap.anchor_right = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.offset_left = -Minimap.SIZE
	_minimap.offset_top = -Minimap.SIZE
	_minimap.offset_right = 0.0
	_minimap.offset_bottom = 0.0
	root.add_child(_minimap)

	# Minimise toggle, mirroring the leaderboard's. The map is the second largest
	# thing covering the arena.
	_map_toggle = UiKit.btn_text("", 56)
	_map_toggle.custom_minimum_size.x = 56
	_map_toggle.add_theme_font_size_override("font_size", UiKit.T_LABEL)
	_map_toggle.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_map_toggle.offset_left = -Minimap.SIZE - 8.0
	_map_toggle.offset_right = -Minimap.SIZE + 48.0
	_map_toggle.offset_top = -Minimap.SIZE - 4.0
	_map_toggle.offset_bottom = -Minimap.SIZE + 52.0
	_map_toggle.pressed.connect(_toggle_map)
	root.add_child(_map_toggle)
	_map_collapsed = bool(Game.get_value("map_collapsed", false))
	_apply_map_collapsed()

	# --- transient overlays --------------------------------------------------
	_feed = VBoxContainer.new()
	# Left column, not centred. Centred at the top it ran straight under the
	# top-right leaderboard and the two overlapped on narrow screens.
	_feed.anchor_left = 0.0
	_feed.anchor_right = 0.0
	_feed.anchor_top = 0.0
	_feed.anchor_bottom = 0.0
	_feed.offset_left = 0.0
	_feed.offset_right = 470.0
	_feed.offset_top = 150.0
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)

	_centre = UiKit.hud_lbl("", 150, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_centre.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_centre.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(_centre)

	# Was pinned at screen centre + 200 — directly over the magnet you have to
	# steer to survive, and overlapping _centre so sudden death stacked two labels.
	_warning = UiKit.hud_lbl(tr("UI_OUT_OF_RING"), UiKit.T_LEAD, UiKit.DANGER_LINE,
			HORIZONTAL_ALIGNMENT_CENTER)
	_warning.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_warning.offset_top = 380
	_warning.visible = false
	root.add_child(_warning)

	# Emotes. Collapsed behind one button: an always-open row of four would sit in
	# the same corner the minimap needs, and this is a side feature.
	_emote_row = HBoxContainer.new()
	_emote_row.add_theme_constant_override("separation", UiKit.S1)
	_emote_row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_emote_row.offset_left = -560.0
	_emote_row.offset_right = -250.0
	_emote_row.offset_top = -330.0
	_emote_row.offset_bottom = -242.0
	_emote_row.visible = false
	root.add_child(_emote_row)
	for i in Magnet.EMOTES.size():
		var e := UiKit.btn_secondary(Magnet.EMOTES[i], 88)
		e.custom_minimum_size.x = 74
		e.add_theme_font_size_override("font_size", UiKit.T_LABEL)
		e.pressed.connect(func() -> void: _send_emote(i))
		_emote_row.add_child(e)

	var emote_btn := UiKit.icon_btn("star", 92)
	emote_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	emote_btn.offset_left = -356.0
	emote_btn.offset_right = -264.0
	emote_btn.offset_top = -228.0
	emote_btn.offset_bottom = -136.0
	emote_btn.pressed.connect(func() -> void:
		_emote_row.visible = not _emote_row.visible)
	root.add_child(emote_btn)

	_hint = UiKit.hud_lbl("", UiKit.T_CAPTION, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 300.0
	_hint.offset_right = -300.0
	_hint.offset_top = -78.0
	_hint.offset_bottom = -30.0
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_hint)
	return root


## The revive offer needs to call back into the arena, and the HUD's tension cue
## needs the tuning. Ui held neither.
func attach_arena(a: Arena) -> void:
	_arena = a


func attach_minimap(a: Arena) -> void:
	if _minimap != null and is_instance_valid(_minimap):
		_minimap.arena = a


func _on_clock(seconds: float) -> void:
	# clock_changed is emitted EVERY frame. add_theme_color_override invalidates the
	# theme cache and forces a font re-resolve and a relayout, so this was doing
	# that 60 times a second for a label that changes once a second.
	var whole := int(seconds)
	if whole == _last_clock:
		return
	_last_clock = whole
	_clock_label.text = "%d:%02d" % [whole / 60, whole % 60]
	_clock_label.add_theme_color_override("font_color",
			UiKit.DANGER_LINE if seconds < 15.0 else UiKit.INK)


## Same gate: ring_changed is also emitted every frame.
func _on_ring(radius: float) -> void:
	if _ring_bar == null or Game.tuning == null:
		return
	var t: Tuning = Game.tuning
	var span: float = maxf(0.001, t.ring_start_radius - t.ring_end_radius)
	var v := clampf((radius - t.ring_end_radius) / span, 0.0, 1.0)
	if absf(v - _ring_shown) < 0.004:
		return
	_ring_shown = v
	_ring_bar.value = v
	var sb := _ring_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if sb != null:
		sb.bg_color = UiKit.DANGER if v < 0.35 else UiKit.BRASS


func _on_charge(charge01: float, ready: bool) -> void:
	# Cooldown fills in steel rather than emptying in amber, so the half second
	# after a repel stops looking identical to standing still.
	_charge.value = charge01 if ready else 1.0 - charge01
	var sb := _charge.get_theme_stylebox("fill") as StyleBoxFlat
	if sb:
		sb.bg_color = ACCENT if ready else UiKit.STEEL_50


## One row, built once and then reused. Rows live at a hand-set position.y so a
## rank change can be tweened; the player's row is a physically different object,
## which is the agar/slither read.
func _make_board_row(mine: bool) -> Control:
	var r := Control.new()
	r.set_meta("is_player", mine)
	r.custom_minimum_size = Vector2(BOARD_W, BOARD_ROW_H)
	r.size = Vector2(BOARD_W, BOARD_ROW_H)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if mine:
		var bg := ColorRect.new()
		bg.color = Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.14)
		bg.size = Vector2(BOARD_W, BOARD_ROW_H)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_child(bg)
		var edge := ColorRect.new()
		edge.color = UiKit.ACCENT
		edge.size = Vector2(4, BOARD_ROW_H)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_child(edge)

	var size := UiKit.T_LABEL + (6 if mine else 0)
	var ink: Color = UiKit.INK if mine else UiKit.INK_MUTE
	var rank := UiKit.lbl("", size, ink, HORIZONTAL_ALIGNMENT_RIGHT)
	rank.name = "Rank"
	rank.position = Vector2(12, 4)
	rank.size = Vector2(46, BOARD_ROW_H - 8)
	r.add_child(rank)

	var who := UiKit.lbl("", size, ink)
	who.name = "Who"
	who.position = Vector2(70, 4)
	# Wider score column: a six-figure mass ran straight into the name because the
	# column was sized for three digits.
	who.size = Vector2(BOARD_W - 70 - 200, BOARD_ROW_H - 8)
	# German UI_FEED_KILL is eight characters longer; clip_text truncates
	# mid-glyph, an ellipsis says the name continues.
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	r.add_child(who)

	var score := UiKit.lbl("", size, UiKit.ACCENT if mine else ink,
			HORIZONTAL_ALIGNMENT_RIGHT)
	score.name = "Score"
	score.position = Vector2(BOARD_W - 196, 4)
	score.size = Vector2(186, BOARD_ROW_H - 8)
	score.clip_text = true
	r.add_child(score)
	return r


func _on_board(rows: Array) -> void:
	# Was: free every child and allocate 11 HBoxes plus 33 Labels with five theme
	# overrides each, on a 0.35s timer — roughly 130 node allocations a second on
	# the mid-range Android target. It is also the mechanical reason climbing a
	# rank could never animate: the row that moved up was a brand new node.
	var seen := {}
	for i in rows.size():
		var row: Dictionary = rows[i]
		var who := String(row["name"])
		seen[who] = true
		var mine := bool(row["is_player"])
		var r: Control = _board_rows.get(who)
		var fresh := r == null or not is_instance_valid(r)
		if fresh:
			r = _make_board_row(mine)
			_board_rows[who] = r
			_board.add_child(r)
		var rank := int(row["rank"])
		(r.get_node("Rank") as Label).text = "%d" % rank
		(r.get_node("Who") as Label).text = who
		(r.get_node("Score") as Label).text = Locale.number(roundi(row["mass"]))

		var target := 0.0 if _board_collapsed else float(i) * BOARD_ROW_H
		if fresh:
			r.position = Vector2(0, target)
		elif absf(r.position.y - target) > 0.5:
			# Overtaking is the whole motivation loop of the genre and it used to
			# be a silent text swap.
			UiKit.snap(r.create_tween()).tween_property(r, "position:y", target,
					UiKit.dur(0.18))
		if mine:
			var was := int(_board_ranks.get(who, rank))
			if rank < was:
				var tw := r.create_tween()
				tw.tween_property(r, "modulate", Color(1.7, 1.45, 1.05), UiKit.dur(0.08))
				tw.tween_property(r, "modulate", Color.WHITE, UiKit.dur(0.24))
				Platform.vibrate(6, 0.15)
		_board_ranks[who] = rank

	for who: String in _board_rows.keys():
		if not seen.has(who):
			var dead: Control = _board_rows[who]
			if is_instance_valid(dead):
				dead.queue_free()
			_board_rows.erase(who)
			_board_ranks.erase(who)
	# The plate shrinks as the arena empties, which is a free tension cue — and
	# _refresh_board_height re-applies the collapsed state, which _on_board would
	# otherwise undo three times a second.
	_refresh_board_height()


func _on_eliminated(victim: String, killer: String, by_player: bool) -> void:
	var text: String = (tr("UI_FEED_KILL") % [killer, victim]) if killer != "" \
			else (tr("UI_FEED_DEATH") % victim)
	var l := UiKit.hud_lbl(text, UiKit.T_LABEL,
			UiKit.SIGNAL_GOOD if by_player else UiKit.INK_DIM)
	# clip_text truncates mid-glyph; the German kill string is eight characters
	# longer, so DE/RU/TR clipped on every single elimination.
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var mark := ColorRect.new()
	mark.color = UiKit.SIGNAL_GOOD if by_player else UiKit.STEEL_50
	mark.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	mark.offset_right = 3
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_child(mark)
	_feed.add_child(l)
	if _feed.get_child_count() > 4:
		_feed.get_child(0).queue_free()
	# Owned by the label, not by self: show_screen frees the feed's children, and a
	# tween on `self` would outlive its target.
	UiKit.snap(l.create_tween()).tween_property(l, "position:x", 0.0, UiKit.dur(0.18)) \
			.from(-40.0)
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, UiKit.dur(0.6))
	tw.tween_callback(l.queue_free)


func _on_countdown(seconds: int) -> void:
	_flash_centre(str(seconds) if seconds > 0 else "", 0.5)


func _flash_centre(text: String, duration: float) -> void:
	_centre.text = text
	_centre.modulate.a = 1.0
	_centre.scale = Vector2.ONE
	if text == "":
		return
	var tw := create_tween()
	tw.tween_interval(duration)
	tw.tween_property(_centre, "modulate:a", 0.0, 0.3)


# --- results ---------------------------------------------------------------
func _build_results() -> Control:
	var root := Control.new()

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", UiKit.S2)
	root.add_child(box)

	# The player's own magnet, shown only on a win. A victory pose in-arena would
	# delay the results screen, which is the one place this genre must never add
	# friction — so the flourish happens here, on the object the player owns.
	_result_pose = UiKit.cosmetic_preview({"kind": "skin"}, 190)
	_result_pose.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_result_pose.visible = false
	box.add_child(_result_pose)

	# Placement is the headline — in this genre the number IS the result.
	_result_title = Stencil.node("", UiKit.T_HERO, UiKit.INK)
	_result_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_result_title)
	_result_sub = _lbl("", UiKit.T_BODY, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_result_sub)

	# Trophy delta, directly under the placement. This is the number that decides
	# whether the next lobby is harder, and it appeared nowhere on the screen that
	# exists to tell you how the match went.
	_result_trophy = UiKit.row([], UiKit.S1)
	_result_trophy.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_result_trophy)

	box.add_child(UiKit.spacer(UiKit.S3))

	# Stats sit on a plate. Bare rows floating on the backdrop had no edge, so the
	# block read as loose text rather than as a readout.
	var card := UiKit.plate(UiKit.STEEL_30, UiKit.R_LG, 4)
	UiKit.cap_width(card, 700)
	_result_rows = VBoxContainer.new()
	_result_rows.add_theme_constant_override("separation", UiKit.S1)
	card.add_child(_result_rows)
	box.add_child(card)

	box.add_child(UiKit.spacer(UiKit.S3))

	# One primary action. Re-entry in a single tap is the whole loop.
	var again := _btn(tr("UI_PLAY_AGAIN"), ACCENT)
	UiKit.cap_width(again, 700)
	again.pressed.connect(func() -> void: play_pressed.emit())
	box.add_child(again)

	_double_btn = UiKit.btn_outline(tr("UI_DOUBLE_COINS"))
	_double_btn.visible = false
	_double_btn.pressed.connect(_on_double_coins)
	box.add_child(_double_btn)

	box.add_child(UiKit.spacer(UiKit.S1))
	var links := HBoxContainer.new()
	links.alignment = BoxContainer.ALIGNMENT_CENTER
	links.add_theme_constant_override("separation", UiKit.S3)
	# Two real buttons, not text links. On a phone these were ~34dp tall with no box,
	# sitting directly under a 140px amber slab — impossible to tell they were
	# controls and awkward to hit.
	var share := UiKit.btn_secondary(tr("UI_SHARE"), 116)
	share.custom_minimum_size.x = 330
	share.pressed.connect(_on_share)
	links.add_child(share)
	var home := UiKit.btn_secondary(tr("UI_MENU"), 116)
	home.custom_minimum_size.x = 330
	home.pressed.connect(func() -> void: menu_pressed.emit())
	links.add_child(home)
	box.add_child(links)
	return root


func _on_match_ended(result: Dictionary) -> void:
	var placement := int(result.get("placement", 99))
	# A win says WON, not a translated word the stencil has no glyphs for — the
	# glyph set is deliberately only what the game shows, and an unknown character
	# draws nothing rather than becoming a mystery box.
	_result_title.stencil_text = "1ST" if placement == 1 else "#%d" % placement
	_result_title.ink = UiKit.ACCENT if placement == 1 else UiKit.INK
	_show_pose(placement == 1)
	_result_sub.text = tr("UI_PLACEMENT_OF") % [placement, int(result.get("total", 0))]

	# Trophies: gained on a good finish, lost on a bad one. The sign is carried by
	# the pole colours, which is what they are for — attract for gain, repel for
	# loss — so it survives being read at a glance and in greyscale.
	for c in _result_trophy.get_children():
		c.queue_free()
	var delta := int(result.get("trophy_delta", Meta.trophy_delta(placement)))
	var gained := delta >= 0
	_result_trophy.add_child(UiKit.icon("trophy", 34, UiKit.BRASS))
	_result_trophy.add_child(_lbl("%s%d" % ["+" if gained else "", delta],
			UiKit.T_LEAD, UiKit.POLE_POS if gained else UiKit.POLE_NEG))
	var r: Dictionary = Meta.rank()
	_result_trophy.add_child(_lbl("%s  %s" % [String(r.get("id", "")).to_upper(),
			Locale.number(int(r.get("trophies", 0)))], UiKit.T_LABEL, UiKit.INK_MUTE))

	for c in _result_rows.get_children():
		c.queue_free()
	var stats := [
		[tr("UI_MASS"), Locale.number(roundi(float(result.get("mass", 0.0))))],
		[tr("UI_ELIMINATIONS"), "%d" % int(result.get("kills", 0))],
		[tr("UI_SURVIVED"), Locale.duration(int(result.get("survived", 0.0)))],
		[tr("UI_COINS"), "+" + Locale.number(int(result.get("coins_earned", 0)))],
		[tr("UI_XP"), "+" + Locale.number(int(result.get("xp_earned", 0)))],
	]
	# Row order is load-bearing for the reward count-up below.
	var keys := ["mass", "kills", "survived", "coins", "xp"]
	for i in stats.size():
		stats[i].append(keys[i])
	# Keys and values were both T_BODY at one weight, so a 150/34 size jump was
	# faking the entire hierarchy. Keys become tracked caps at a lighter ink.
	var built: Array[Control] = []
	for s: Array in stats:
		var row := HBoxContainer.new()
		var a := UiKit.lbl_label(s[0], UiKit.T_LABEL, UiKit.INK_DIM)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(a)
		row.add_child(_lbl(s[1], UiKit.T_LEAD, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT))
		row.name = String(s[2])
		var reward := String(s[2]) in ["coins", "xp"]
		if reward:
			(row.get_child(1) as Label).add_theme_color_override("font_color",
					UiKit.SIGNAL_GOOD)
		if String(s[2]) == "coins":
			var rule := ColorRect.new()
			rule.color = UiKit.STEEL_50
			rule.custom_minimum_size = Vector2(0, 1)
			_result_rows.add_child(rule)
		_result_rows.add_child(row)
		built.append(row)
	_choreograph(built, int(result.get("coins_earned", 0)),
			int(result.get("xp_earned", 0)), placement == 1)

	# Rewarded double-coins. Only offered when an ad is genuinely available, and
	# never required — the base reward is already banked (spec §4.4).
	if _double_btn != null:
		_double_btn.visible = Ads.rewarded_available() and int(result.get("coins_earned", 0)) > 0
		_double_btn.disabled = false
		_double_btn.text = tr("UI_DOUBLE_COINS")

	show_screen("results")
	# Post-match is the natural break; the policy inside decides whether to show.
	Ads.try_show_interstitial("post_match")
	# Only after a win — asking someone who just lost is how you earn one star.
	if int(result.get("placement", 99)) == 1:
		maybe_prompt_rating()


func _on_double_coins() -> void:
	if _double_btn == null:
		return
	_double_btn.disabled = true
	var earned := int(Game.last_result.get("coins_earned", 0))
	Ads.show_rewarded("double_coins", func(granted: bool) -> void:
		if granted:
			var bonus := earned * (Config.int_val("ads.double_coins_multiplier", 2) - 1)
			Game.add_currency("coins", bonus, "rewarded_double_coins")
			_flash_toast("+%s" % Locale.number(bonus))
			if _double_btn != null:
				_double_btn.visible = false
		else:
			# No ad, no reward, no penalty — the player keeps what they earned.
			_flash_toast(tr("UI_NOT_ENOUGH") if false else tr("UI_COME_BACK"))
			if _double_btn != null:
				_double_btn.disabled = false)


func _on_share() -> void:
	var r := Game.last_result
	var text: String = tr("UI_SHARE_TEXT") % [
		int(r.get("placement", 0)), roundi(float(r.get("mass", 0.0))), int(r.get("kills", 0))]
	Analytics.track("share", {"placement": int(r.get("placement", 0))})
	var path := await _render_share_card(r)
	if path != "":
		Platform.share_image(path, text)
		_flash_toast(tr("UI_SAVED_TO"))
	elif Platform.share_text(text):
		_flash_toast(tr("UI_COPIED"))


## Renders the result as an image (spec §6.7). A text-only share is invisible in
## a feed; the card is the whole point of the "clip moment" pillar.
## Returns the saved path, or "" if rendering failed.
func _render_share_card(result: Dictionary) -> String:
	# `RenderingServer.frame_post_draw` never fires without a renderer, so
	# awaiting it headless hangs the caller forever. Bail out before the await.
	if DisplayServer.get_name() == "headless" or not Config.flag("share_card_enabled"):
		return ""
	var vp := SubViewport.new()
	vp.size = Vector2i(1080, 1080)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)

	var bg := ColorRect.new()
	bg.color = UiKit.STEEL_20
	bg.size = Vector2(1080, 1080)
	vp.add_child(bg)

	var box := VBoxContainer.new()
	box.size = Vector2(1080, 1080)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	vp.add_child(box)

	var placement := int(result.get("placement", 0))
	var colors := Cosmetics.skin_colors()
	box.add_child(_lbl("POLARITY", 96, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	var headline := _lbl(tr("UI_VICTORY") if placement == 1 else "#%d" % placement,
			200, colors[0] if placement == 1 else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(headline)
	box.add_child(_lbl(Game.player_name(), 56, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.spacer(30))
	box.add_child(_lbl("%s %s   ·   %d %s" % [
			Locale.number(roundi(float(result.get("mass", 0.0)))), tr("UI_MASS"),
			int(result.get("kills", 0)), tr("UI_ELIMINATIONS")],
			46, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))

	# Two frames: one to lay the controls out, one to actually draw them.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	vp.queue_free()
	if image == null:
		return ""
	var path := "user://share_card.png"
	if image.save_png(path) != OK:
		return ""
	return path


## Rating prompt, shown only after a genuinely positive moment and capped hard.
func maybe_prompt_rating() -> void:
	if not Config.flag("rating_prompt_enabled") or bool(Game.get_value("rated", false)):
		return
	if int(Game.get_value("wins", 0)) < Config.int_val("rating.prompt_after_wins", 2):
		return
	if int(Game.get_value("matches", 0)) < Config.int_val("rating.prompt_min_matches", 8):
		return
	var last := int(Game.get_value("rate_prompt_day", 0))
	var cooldown := Config.int_val("rating.prompt_cooldown_days", 60)
	if last > 0 and Meta.today() - last < cooldown:
		return
	Game.set_value("rate_prompt_day", Meta.today())
	Analytics.track("rating_prompt")

	var box := UiKit.modal(_layout)
	box.add_child(_lbl(tr("UI_RATE_TITLE"), UiKit.T_TITLE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	var yes := _btn(tr("UI_RATE_YES"), ACCENT)
	yes.pressed.connect(func() -> void:
		Game.set_value("rated", true)
		Platform.request_review()
		Analytics.track("rating_accepted")
		UiKit.dismiss(box))
	box.add_child(yes)
	var later := UiKit.btn_text(tr("UI_LATER"))
	later.pressed.connect(func() -> void: UiKit.dismiss(box))
	box.add_child(later)


func _flash_toast(text: String) -> void:
	var l := _lbl(text, 36, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.offset_top = -160
	_layout.add_child(l)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


# --- settings --------------------------------------------------------------
func _build_settings() -> Control:
	var root := Control.new()
	# Pinned header with the exit in it. The only way out used to be a button at the
	# very bottom of a long scroll — on a phone that is a scroll to leave a screen
	# you opened by mistake.
	var head := UiKit.row([], UiKit.S2)
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = UiKit.S3
	head.offset_right = -UiKit.S3
	head.offset_top = UiKit.S2
	head.offset_bottom = UiKit.S2 + 112
	var head_back := UiKit.btn_ghost(tr("UI_BACK"), 96)
	head_back.custom_minimum_size.x = 160
	head_back.pressed.connect(_close_settings)
	head.add_child(head_back)
	var head_title := _lbl(tr("UI_SETTINGS"), UiKit.T_TITLE, UiKit.INK,
			HORIZONTAL_ALIGNMENT_CENTER)
	head_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_title)
	head.add_child(UiKit.spacer(160))
	root.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Every other screen breathes at the edges; this one ran flush to them, so the
	# dropdown arrows and the toggle pills sat against the bezel.
	scroll.offset_left = UiKit.S3
	scroll.offset_right = -UiKit.S3
	scroll.offset_top = UiKit.S2 + 152   # clear of the pinned header
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 22)
	scroll.add_child(box)

	box.add_child(_slider(tr("UI_MUSIC"), "music", func(v: float) -> void: Audio.set_volume("Music", v)))
	box.add_child(_slider(tr("UI_SOUND"), "sfx", func(v: float) -> void: Audio.set_volume("SFX", v)))
	box.add_child(_toggle(tr("UI_HAPTICS"), "haptics"))
	box.add_child(_toggle(tr("UI_REDUCED_MOTION"), "reduced_motion"))

	var language_row_label := tr("UI_LANGUAGE")
	var lang_opt := OptionButton.new()
	for n: String in Locale.names():
		lang_opt.add_item(n)
	lang_opt.selected = maxi(0, Locale.codes().find(String(Game.get_value("locale", "en"))))
	lang_opt.item_selected.connect(func(i: int) -> void:
		var code: String = Locale.codes()[i]
		Game.set_value("locale", code)
		Locale.apply(code)
		Bus.locale_changed.emit())
	box.add_child(_setting_row(language_row_label, lang_opt))

	var quality_row_label := tr("UI_QUALITY")
	var opt := OptionButton.new()
	for q in ["auto", "low", "medium", "high"]:
		opt.add_item(tr("UI_QUALITY_" + q.to_upper()))
	var current := String(Game.get_value("quality", "auto"))
	opt.selected = maxi(0, ["auto", "low", "medium", "high"].find(current))
	opt.item_selected.connect(func(i: int) -> void:
		Game.set_value("quality", ["auto", "low", "medium", "high"][i]))
	box.add_child(_setting_row(quality_row_label, opt))

	box.add_child(_toggle(tr("UI_COLORBLIND"), "colorblind"))
	box.add_child(_toggle(tr("UI_LEFT_HANDED"), "left_handed"))

	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 24)
	var scale_lbl := _lbl(tr("UI_UI_SCALE"), 40, UiKit.INK_DIM)
	scale_lbl.custom_minimum_size = Vector2(300, 0)
	scale_row.add_child(scale_lbl)
	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.75
	scale_slider.max_value = 1.5
	scale_slider.step = 0.05
	scale_slider.value = float(Game.get_value("ui_scale", 1.0))
	scale_slider.custom_minimum_size = Vector2(0, 80)
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_slider.value_changed.connect(func(v: float) -> void:
		Game.set_value("ui_scale", v)
		_relayout())
	scale_row.add_child(scale_slider)
	box.add_child(scale_row)

	var controls_row_label := tr("UI_CONTROLS")
	var ctrl_opt := OptionButton.new()
	const SCHEMES := ["drag", "joystick", "toggle"]
	for key: String in ["UI_CONTROL_DRAG", "UI_CONTROL_JOYSTICK", "UI_CONTROL_TOGGLE"]:
		ctrl_opt.add_item(tr(key))
	ctrl_opt.selected = maxi(0, SCHEMES.find(String(Game.get_value("control_scheme", "drag"))))
	ctrl_opt.item_selected.connect(func(i: int) -> void:
		Game.set_value("control_scheme", SCHEMES[i]))
	box.add_child(_setting_row(controls_row_label, ctrl_opt))

	box.add_child(_toggle(tr("UI_NOTIFICATIONS"), "notifications"))
	box.add_child(UiKit.spacer(24))
	box.add_child(_lbl(tr("UI_ACCOUNT"), UiKit.T_TITLE, UiKit.INK,
			HORIZONTAL_ALIGNMENT_CENTER))

	# Federated sign-in. Shown only where a plugin could actually service it, so
	# the section never offers a button that cannot work.
	for pair in [["google", "UI_SIGN_IN_GOOGLE"], ["apple", "UI_SIGN_IN_APPLE"]]:
		if not Platform.federated_auth_available(String(pair[0])):
			continue
		var sign_btn := UiKit.btn_secondary(tr(String(pair[1])))
		sign_btn.pressed.connect(func() -> void:
			Backend.sign_in_federated(String(pair[0]), func(ok: bool) -> void:
				_flash_toast(tr("UI_SIGNED_IN") if ok else tr("UI_UNAVAILABLE"))))
		box.add_child(sign_btn)

	var restore_iap := _btn(tr("UI_RESTORE"))
	restore_iap.pressed.connect(func() -> void:
		Store.restore(func(n: int) -> void: _flash_toast("%s %d" % [tr("UI_RESTORE"), n])))
	box.add_child(restore_iap)

	var about_btn := UiKit.btn_ghost(tr("UI_CREDITS"))
	about_btn.pressed.connect(func() -> void: _build_about())
	box.add_child(about_btn)

	var export_btn := _btn(tr("UI_EXPORT_DATA"))
	export_btn.pressed.connect(func() -> void:
		var path := "user://polarity_data_export.json"
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(Backend.export_data())
			f.close()
			DisplayServer.clipboard_set(ProjectSettings.globalize_path(path))
			_flash_toast(tr("UI_SAVED_TO")))
	box.add_child(export_btn)

	# Deletion is irreversible, so it is two taps and the confirm is the
	# non-default action.
	var delete_btn := UiKit.btn_danger(tr("UI_DELETE_DATA"))
	delete_btn.pressed.connect(func() -> void: _confirm_delete())
	box.add_child(delete_btn)

	var privacy := _btn(tr("UI_PRIVACY_POLICY"))
	privacy.pressed.connect(func() -> void:
		# Replace with the real hosted policy URL before store submission.
		OS.shell_open("https://example.com/polarity/privacy"))
	box.add_child(privacy)

	box.add_child(UiKit.spacer(16))
	var replay := _btn(tr("UI_REPLAY_TUTORIAL"))
	replay.pressed.connect(func() -> void:
		Game.set_value("seen_tutorial", false)
		_flash_toast(tr("UI_REPLAY_TUTORIAL")))
	box.add_child(replay)

	box.add_child(_lbl("v%s · %s" % [
			ProjectSettings.get_setting("application/config/version", "0.1.0"),
			Platform.os_name], 30, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	var back := _btn(tr("UI_BACK"), ACCENT)
	UiKit.cap_width(back, 700)
	back.pressed.connect(_close_settings)
	box.add_child(back)
	return root


func _confirm_delete() -> void:
	var box := UiKit.modal(_layout)
	box.add_child(_lbl(tr("UI_CONFIRM"), UiKit.T_TITLE, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_lbl(tr("UI_DELETE_DATA"), 36, UiKit.DANGER_LINE,
			HORIZONTAL_ALIGNMENT_CENTER))
	# Cancel is the safe default, so it is the plain steel slab. It used to be the
	# amber one, which put the loudest colour in the game on "do nothing".
	var cancel := UiKit.btn_secondary(tr("UI_CANCEL"))
	cancel.pressed.connect(func() -> void: UiKit.dismiss(box))
	box.add_child(cancel)
	# Filled, because this IS the confirm step.
	var confirm := UiKit.btn_danger(tr("UI_DELETE_DATA"), true)
	confirm.pressed.connect(func() -> void:
		Backend.delete_account()
		UiKit.dismiss(box)
		rebuild())
	box.add_child(confirm)


func _slider(label: String, key: String, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var l := _lbl(label, 36, UiKit.INK_DIM)
	l.custom_minimum_size = Vector2(300, 0)
	l.clip_text = true
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Game.get_value(key, 0.7))
	s.custom_minimum_size = Vector2(0, 80)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float) -> void:
		Game.set_value(key, v)
		on_change.call(v))
	row.add_child(s)
	return row


func _toggle(label: String, key: String) -> Control:
	var row := HBoxContainer.new()
	var l := _lbl(label, 36, UiKit.INK_DIM)
	l.custom_minimum_size = Vector2(300, 0)
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var c := CheckButton.new()
	c.button_pressed = bool(Game.get_value(key, true))
	c.toggled.connect(func(v: bool) -> void: Game.set_value(key, v))
	row.add_child(c)
	return row


# --- routing ---------------------------------------------------------------
func show_screen(which: String) -> void:
	_menu.visible = which == "menu"
	_hud.visible = which == "hud"
	_results.visible = which == "results"
	if which != "results":
		_settings.visible = false
	if which == "hud":
		Audio.play_music("game")
		_warning.visible = false
		_centre.text = ""
		for c in _feed.get_children():
			c.queue_free()
	if which == "menu":
		Audio.play_music("menu")
		Audio.set_intensity(0.0)
		_refresh_wallet()
		show_consent_if_needed()
	else:
		# The popup and the meta panel are siblings of the screens, not children
		# of them — hiding the menu does not hide either, and the daily calendar
		# stayed live on top of the arena during play.
		_close_daily()
		_close_consent()
		if _meta_panel != null:
			_meta_panel.visible = false

	# Hidden Controls skip layout passes, so a screen that was invisible while
	# the viewport resized comes back with a stale (often zero) rect. Re-assert
	# the full-rect preset on whatever just became visible.
	for c: Control in [_menu, _hud, _results, _settings]:
		if c.visible:
			c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Every screen change used to be a hard cut — show_screen was six boolean
	# assignments. The HUD is deliberately excluded: it appears with the match and
	# fading it in would delay the one screen the player is trying to act on.
	if which == "menu":
		UiKit.enter(_menu)
	elif which == "results":
		UiKit.enter(_results)
	_update_backdrop()


func _update_backdrop() -> void:
	var mat: ShaderMaterial = _backdrop.material
	if _settings.visible:
		mat.set_shader_parameter("dim", 0.45)
	elif _menu.visible:
		mat.set_shader_parameter("dim", 0.0)
	elif _results.visible:
		mat.set_shader_parameter("dim", 0.55)
	_backdrop.visible = _settings.visible or _menu.visible or _results.visible
	# Field lines only where there is a single thing to press. On settings there
	# is not, so the pass switches off rather than pointing at nothing.
	if _menu.visible and _pole_target != null and is_instance_valid(_pole_target):
		_aim_pole.call_deferred(_pole_target, 1.0)
	elif _results.visible and _result_title != null:
		_aim_pole.call_deferred(_result_title, 0.75)
	else:
		UiKit.set_pole(_backdrop, _backdrop, 0.0)


func _aim_pole(target: Control, strength: float) -> void:
	if is_instance_valid(target) and is_instance_valid(_backdrop):
		UiKit.set_pole(_backdrop, target, strength)


## Mass climbs rather than teleporting, and heavier numbers settle slower — the
## whole scoring verb is accumulation, so weight belongs in the motion.
func _process(delta: float) -> void:
	if _mass_label == null or not is_instance_valid(_mass_label):
		return
	if absf(_mass_target - _mass_shown) < 0.05:
		return
	_mass_shown = lerpf(_mass_shown, _mass_target,
			clampf(delta * (9.0 - clampf(log(maxf(_mass_target, 1.0)) * 1.4, 0.0, 5.0)),
					0.0, 1.0))
	var shown := Locale.number(roundi(_mass_shown))
	if _mass_label.stencil_text != shown:
		_mass_label.stencil_text = shown


func _punch_mass() -> void:
	if _mass_label == null or not is_instance_valid(_mass_label):
		return
	# Grows upward from the baseline, because the readout is bottom-anchored.
	_mass_label.pivot_offset = Vector2(0, _mass_label.size.y)
	var tw := _mass_label.create_tween()
	tw.tween_property(_mass_label, "scale", Vector2(1.07, 1.07), UiKit.dur(0.06))
	UiKit.snap(tw).tween_property(_mass_label, "scale", Vector2.ONE, UiKit.dur(0.13))


## Fifteen alive and two alive looked identical. Below the sudden-death threshold
## the count turns and pulses on every elimination.
func _on_alive(n: int) -> void:
	if _alive_label == null or not is_instance_valid(_alive_label):
		return
	_alive_label.text = "%d" % n
	var tense := n <= _sudden_death_at() + 2
	_alive_label.add_theme_color_override("font_color",
			UiKit.DANGER_LINE if tense else UiKit.INK)
	if not tense:
		return
	var tw := _alive_label.create_tween()
	tw.tween_property(_alive_label, "scale", Vector2(1.12, 1.12), UiKit.dur(0.09))
	UiKit.snap(tw).tween_property(_alive_label, "scale", Vector2.ONE, UiKit.dur(0.20))


## Ui holds no Arena, so read the shipped tuning directly rather than threading a
## reference through attach_minimap for one integer.
func _sudden_death_at() -> int:
	return int(Game.tuning.sudden_death_at) if Game.tuning != null else 3


## The results screen is the payoff and it used to arrive fully formed in one frame:
## five numbers, already final, no order. Now the placement lands, the rows arrive in
## sequence against a rising five-note ladder built from the one existing blip, and
## only the two EARNED numbers count up — which is what directs the eye to the
## reward rather than to the recap.
func _choreograph(rows: Array[Control], coins: int, xp: int, won: bool) -> void:
	if _result_title != null and is_instance_valid(_result_title):
		_result_title.pivot_offset = _result_title.size * 0.5
		_result_title.scale = Vector2(1.35, 1.35)
		_result_title.modulate.a = 0.0
		var ht := _result_title.create_tween()
		ht.parallel().tween_property(_result_title, "modulate:a", 1.0, UiKit.dur(0.12))
		UiKit.snap(ht.parallel()).tween_property(_result_title, "scale", Vector2.ONE,
				UiKit.dur(0.40))

	for i in rows.size():
		var r := rows[i]
		r.modulate.a = 0.0
		var tw := r.create_tween()
		tw.tween_interval(UiKit.dur(0.22 + float(i) * 0.07))
		tw.tween_property(r, "modulate:a", 1.0, UiKit.dur(0.14))
		# A rising ladder from one 680Hz blip. No new asset.
		tw.tween_callback(func() -> void: Audio.play("ui_tap", 1.0 + float(i) * 0.11, -18.0))

	_count_up(rows, "coins", coins)
	_count_up(rows, "xp", xp)

	# Lands as the payoff of the cascade rather than on top of its first note.
	var arp := create_tween()
	arp.tween_interval(UiKit.dur(0.22 + float(rows.size()) * 0.07 + 0.35))
	arp.tween_callback(func() -> void: Audio.play("reward" if won else "hit",
			1.0 if won else 0.8, -8.0))


func _count_up(rows: Array[Control], key: String, amount: int) -> void:
	if amount <= 0:
		return
	for r: Control in rows:
		if r.name != key or r.get_child_count() < 2:
			continue
		var value := r.get_child(1) as Label
		if value == null:
			return
		value.text = "+0"
		# Bigger rewards take longer to land — the same weight rule as the mass
		# readout, because a number that counts is a number with mass.
		var tw := value.create_tween()
		tw.tween_interval(UiKit.dur(0.62))
		tw.set_ease(Tween.EASE_OUT).tween_method(
				func(v: float) -> void: value.text = "+" + Locale.number(roundi(v)),
				0.0, float(amount), UiKit.weight_dur(0.45, float(amount)))
		return


## One menu navigation tile: round button, glyph, caption, optional coach dot.
func _nav_tile(glyph: String, key: String, on_press: Callable, is_new: bool) -> Control:
	var tile := UiKit.icon_nav(glyph, tr(key))
	var b: Button = tile.get_meta("button")
	b.pressed.connect(on_press)
	if is_new:
		UiKit.new_dot(b)
	return tile


## Coach mark, as a boolean now. It used to be a "  ·  NEW" string suffix appended to
## the label, which read as a typo and was never translated for ja/ko.
func _is_new(key: String, just_unlocked: bool) -> bool:
	var seen: Variant = Game.get_value("stats", {})
	var dict: Dictionary = seen if seen is Dictionary else {}
	if dict.get("seen_" + key, false):
		return false
	return just_unlocked


## The revive offer. Held open by the arena, so the ONE thing this must never do is
## return without answering — every path below ends in revive_player() or
## decline_revive(), including the timeout and the ad failing.
func _on_player_down() -> void:
	if _arena == null or not is_instance_valid(_arena):
		return
	var box := UiKit.modal(_layout)
	_revive_box = box
	var answered := [false]

	var answer := func(take: bool) -> void:
		if answered[0]:
			return
		answered[0] = true
		UiKit.dismiss(box)
		_revive_box = null
		if not is_instance_valid(_arena):
			return
		if not take:
			_arena.decline_revive()
			return
		Ads.show_rewarded("revive", func(granted: bool) -> void:
			if not is_instance_valid(_arena):
				return
			if granted:
				_arena.revive_player()
			else:
				# No ad, no revive, no penalty — the match ends as it would have.
				_flash_toast(tr("UI_COME_BACK"))
				_arena.decline_revive())

	box.add_child(_lbl(tr("UI_ELIMINATED"), UiKit.T_TITLE, UiKit.DANGER_LINE,
			HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_lbl(tr("UI_REVIVE_BODY"), UiKit.T_BODY, UiKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.spacer(UiKit.S2))

	var take := _btn(tr("UI_REVIVE"), ACCENT)
	UiKit.cap_width(take, 640)
	take.pressed.connect(func() -> void: answer.call(true))
	box.add_child(take)

	var no := UiKit.btn_ghost(tr("UI_NO_THANKS"))
	UiKit.cap_width(no, 640)
	no.pressed.connect(func() -> void: answer.call(false))
	box.add_child(no)

	# A countdown, and a hard auto-decline behind it. Without this a player who
	# backgrounds the app leaves the match frozen forever.
	var clock := _lbl("", UiKit.T_LABEL, UiKit.INK_MUTE, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(clock)
	var left := [8]
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	box.add_child(tick)
	clock.text = tr("UI_SECONDS_LEFT") % left[0]
	tick.timeout.connect(func() -> void:
		left[0] -= 1
		if is_instance_valid(clock):
			clock.text = tr("UI_SECONDS_LEFT") % maxi(0, left[0])
		if left[0] <= 0:
			answer.call(false))


## Rewarded: start the next match heavier.
func _on_boost() -> void:
	Ads.show_rewarded("boost_mass", func(granted: bool) -> void:
		if granted:
			Game.set_value("boost_mass", true)
			_flash_toast(tr("UI_BOOST_READY"))
		else:
			_flash_toast(tr("UI_COME_BACK"))
		rebuild())


## Rewarded: one spin a day.
func _on_wheel() -> void:
	Ads.show_rewarded("wheel", func(granted: bool) -> void:
		if not granted:
			_flash_toast(tr("UI_COME_BACK"))
			return
		var got := Meta.spin_wheel()
		if got.is_empty():
			_flash_toast(tr("UI_COME_BACK"))
			return
		var text := ""
		match String(got["kind"]):
			"coins": text = "+%s %s" % [Locale.number(int(got["amount"])), tr("UI_COINS")]
			"gems": text = "+%s %s" % [Locale.number(int(got["amount"])), tr("UI_GEMS")]
			_: text = tr("UI_BOOST_READY")
		_flash_toast(text)
		rebuild())


## Emotes are cosmetic only. The symbol appears above the SENDER's own magnet, so
## it can be ignored by looking elsewhere — which is why a fixed symbol set needs no
## moderation and no mute button.
func _send_emote(index: int) -> void:
	if _emote_row != null:
		_emote_row.visible = false
	if _arena != null and is_instance_valid(_arena) and _arena.player != null:
		_arena.player.emote(index)
		Audio.play("ui_tap", 1.1, -14.0)


## Victory pose: the winner's own magnet, spinning up into place. Only on a win —
## a flourish after a loss reads as mockery.
func _show_pose(won: bool) -> void:
	if _result_pose == null or not is_instance_valid(_result_pose):
		return
	_result_pose.visible = won
	if not won:
		return
	var colors := Cosmetics.skin_colors()
	var sw := _result_pose as UiKit.Swatch
	if sw != null:
		sw.a = colors[0]
		sw.b = colors[1]
		sw.queue_redraw()
	_result_pose.pivot_offset = _result_pose.size * 0.5
	_result_pose.scale = Vector2(0.2, 0.2)
	_result_pose.rotation = -TAU * 0.75
	var tw := _result_pose.create_tween()
	tw.parallel().tween_property(_result_pose, "scale", Vector2.ONE, UiKit.dur(0.5)) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_result_pose, "rotation", 0.0, UiKit.dur(0.6)) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# One slow idle rotation afterwards, so the winner's magnet stays alive on
	# screen instead of freezing the moment it arrives.
	if UiKit.dur(1.0) > 0.0:
		var idle := _result_pose.create_tween().set_loops()
		idle.tween_interval(0.6)
		idle.tween_property(_result_pose, "rotation", 0.10, 1.6) \
				.set_trans(Tween.TRANS_SINE)
		idle.tween_property(_result_pose, "rotation", -0.10, 1.6) \
				.set_trans(Tween.TRANS_SINE)


## Support and credits. Both were missing entirely, and a store review will ask for
## the first one — Apple and Google both require a working support contact.
func _build_about() -> Control:
	var box := UiKit.modal(_layout)
	box.add_child(_lbl(tr("UI_CREDITS"), UiKit.T_TITLE, UiKit.INK,
			HORIZONTAL_ALIGNMENT_CENTER))
	var body := _lbl("POLARITY\n\n%s\n\nGodot %s\n%s" % [
			tr("UI_CREDITS_BODY"),
			"%d.%d" % [Engine.get_version_info()["major"], Engine.get_version_info()["minor"]],
			Game.build_string() if Game.has_method("build_string") else ""],
			UiKit.T_BODY, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	box.add_child(UiKit.spacer(UiKit.S2))

	var support := UiKit.btn_secondary(tr("UI_SUPPORT"))
	UiKit.cap_width(support, 560)
	support.pressed.connect(func() -> void:
		# mailto: is the only contact channel that needs no backend and works on
		# every platform this ships to.
		OS.shell_open("mailto:%s?subject=POLARITY%%20support" % SUPPORT_EMAIL))
	box.add_child(support)

	var close := UiKit.btn_ghost(tr("UI_BACK"))
	UiKit.cap_width(close, 560)
	close.pressed.connect(func() -> void: UiKit.dismiss(box))
	box.add_child(close)
	return box


## Collapse / expand the in-match leaderboard.
func _toggle_board() -> void:
	_board_collapsed = not _board_collapsed
	Game.set_value("board_collapsed", _board_collapsed)
	_apply_board_collapsed()
	Audio.play("ui_tap", 1.05, -14.0)


func _apply_board_collapsed() -> void:
	if _board_toggle != null and is_instance_valid(_board_toggle):
		# A glyph rather than a word: it sits in a 52px cell and has to work in ten
		# languages.
		_board_toggle.text = "+" if _board_collapsed else "\u2013"
	if _ring_bar != null and is_instance_valid(_ring_bar):
		_ring_bar.visible = not _board_collapsed
	_refresh_board_height()


## The board is a hand-positioned Control, so its height is set rather than derived.
## Collapsed it shows only the player's own row — the one line you act on — and the
## plate shrinks to match instead of leaving an empty panel over the arena.
func _refresh_board_height() -> void:
	if _board == null or not is_instance_valid(_board):
		return
	var shown := 0
	for who: String in _board_rows.keys():
		var r: Control = _board_rows[who]
		if not is_instance_valid(r):
			continue
		# get_meta returns Variant, so this needs an explicit type.
		var mine: bool = bool(r.get_meta("is_player", false))
		r.visible = (not _board_collapsed) or mine
		if r.visible:
			shown += 1
	_board.custom_minimum_size.y = maxf(BOARD_ROW_H, float(maxi(shown, 1)) * BOARD_ROW_H)


## Settings is a SCREEN, not an overlay. It used to be shown by flipping its own
## visibility while leaving the menu visible underneath, and because it has no
## opaque surface of its own the wordmark, the name field and the PLAY button all
## showed through it. On desktop screenshots this was never noticed because the
## harness only ever reported that the PNG saved.
func _open_settings() -> void:
	_settings.visible = true
	_menu.visible = false
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_backdrop()
	UiKit.enter(_settings)


func _close_settings() -> void:
	_settings.visible = false
	_menu.visible = true
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_backdrop()
	UiKit.enter(_menu)


## One settings row: a fixed-width label and a control that fills the rest. The
## label width is fixed rather than EXPAND_FILL so every row lines up, and the
## control clips rather than demanding the width of its longest item.
func _setting_row(label: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiKit.S2)
	var l := _lbl(label, 36, UiKit.INK_DIM)
	l.custom_minimum_size = Vector2(300, 0)
	l.clip_text = true
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if control is Button:
		(control as Button).clip_text = true
	row.add_child(control)
	return row


## Hide the minimap. Same reasoning as the leaderboard: on a phone the map covers a
## corner of the arena you may want to see, and whether that trade is worth it is
## the player's call, not mine.
func _toggle_map() -> void:
	_map_collapsed = not _map_collapsed
	Game.set_value("map_collapsed", _map_collapsed)
	_apply_map_collapsed()
	Audio.play("ui_tap", 1.05, -14.0)


func _apply_map_collapsed() -> void:
	if _minimap != null and is_instance_valid(_minimap):
		_minimap.visible = not _map_collapsed
	if _map_toggle != null and is_instance_valid(_map_toggle):
		_map_toggle.text = "+" if _map_collapsed else "\u2013"
