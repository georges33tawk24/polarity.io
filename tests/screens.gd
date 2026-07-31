extends Node
## Structural check on every screen: does it actually contain anything?
##
## This exists because four separate times in this project a green check sat on
## top of a visibly broken screen (DECISIONS §9, §12k, §12o, §12r). Every one of
## them was invisible to the existing suites for the same reason: `tests.tscn`
## asserts on game logic and never builds a screen, and `smoke.tscn` builds the HUD
## but never looks at it. A parse error that made `Ui.new()` return null reported
## 47/47 green. Thirty runtime errors from `rarity_color` reported 267/267 green.
##
## Screenshots would catch more, but they need a real rendering device and CI
## runners do not have one. Structure does not: a screen that failed to build has
## no children, a screen that lost its layout has a zero rect, and a glyph that
## fell through to the fallback is byte-identical to every other fallback. All
## three are checkable headless, and all three are what actually went wrong.
##
##   Godot --headless res://tests/screens.tscn

var _fails := 0
var _checks := 0


func ok(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  pass  %s" % msg)
	else:
		_fails += 1
		printerr("  FAIL  %s" % msg)


## Every Control in the subtree, so "did this screen build" is a real question and
## not a guess about one node.
func _descendants(n: Node) -> int:
	var total := 0
	for c in n.get_children():
		total += 1 + _descendants(c)
	return total


func _visible_text(n: Node) -> int:
	var found := 0
	for c in n.get_children():
		if c is Label and not (c as Label).text.strip_edges().is_empty():
			found += 1
		elif c is Button and not (c as Button).text.strip_edges().is_empty():
			found += 1
		found += _visible_text(c)
	return found


func _ready() -> void:
	print("screen structure")
	# A first session, so progressive unlock does not hide half the menu.
	Game.set_value("matches", 20)
	Game.set_value("coins", 5000)

	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 8:
		await get_tree().process_frame

	var ui = main.ui
	ok(ui != null, "Ui instantiated")
	if ui == null:
		_finish()
		return

	# --- top-level screens --------------------------------------------------
	for screen: String in ["menu", "hud", "results", "settings"]:
		if screen == "settings":
			ui.show_screen("menu")
			ui._open_settings()
		else:
			ui.show_screen(screen)
		await get_tree().process_frame
		await get_tree().process_frame
		var root: Control = {"menu": ui._menu, "hud": ui._hud,
				"results": ui._results, "settings": ui._settings}[screen]
		ok(root != null and is_instance_valid(root), "%s: root exists" % screen)
		if root == null:
			continue
		# 12 is well under any real screen and well over a screen that failed to
		# build — the broken-UI bug produced roots with 0 or 1 children.
		ok(_descendants(root) >= 12,
				"%s: has content (%d nodes)" % [screen, _descendants(root)])
		ok(root.size.x > 100.0 and root.size.y > 100.0,
				"%s: has a real rect (%.0fx%.0f)" % [screen, root.size.x, root.size.y])
		ok(_visible_text(root) >= 1, "%s: has readable text" % screen)

	# Screens are mutually exclusive. Settings used to be shown by flipping its own
	# visibility while the menu stayed up, so the wordmark and PLAY button showed
	# through it — none of the screenshots caught it because the harness was driving
	# settings through a path that hid it entirely.
	ui.show_screen("menu")
	ui._open_settings()
	await get_tree().process_frame
	ok(not ui._menu.visible, "opening settings hides the menu")
	ui._close_settings()
	await get_tree().process_frame
	ok(ui._menu.visible and not ui._settings.visible, "closing settings restores the menu")

	var lit: Array[String] = []
	for pair in [["menu", ui._menu], ["hud", ui._hud], ["results", ui._results],
			["settings", ui._settings]]:
		if (pair[1] as Control).visible:
			lit.append(String(pair[0]))
	ok(lit.size() <= 1, "at most one top-level screen is visible (%s)" % ", ".join(lit))

	# --- meta tabs ----------------------------------------------------------
	ui.show_screen("menu")
	await get_tree().process_frame
	for tab: String in MetaPanel.TABS:
		ui.open_meta(tab)
		for i in 3:
			await get_tree().process_frame
		var panel = ui._meta_panel
		ok(panel != null and panel.visible, "%s: panel is open" % tab)
		if panel == null:
			continue
		ok(_descendants(panel) >= 12,
				"%s: has content (%d nodes)" % [tab, _descendants(panel)])
		ok(_visible_text(panel) >= 2, "%s: has readable text" % tab)
	if ui._meta_panel != null:
		ui._meta_panel.visible = false

	await _check_hud_layout(ui)
	await _check_scrolling(ui)
	await _check_modals(ui)
	_check_board_collapse(ui)
	_check_icons()
	_check_audio()
	_finish()


## Nothing hides under the minimap, and the stick cannot eat the game's own input.
##
## The map grew from 230 to 320 to 460 across three requests. Each time it grew it
## swallowed more of the bottom-right corner, and the emote button was already
## overlapping the map circle at 320 — nothing was checking, because on desktop you
## simply do not look at that corner.
func _check_hud_layout(ui) -> void:
	ui.show_screen("hud")
	for i in 3:
		await get_tree().process_frame

	var stick: Control = ui._stick
	ok(stick != null and is_instance_valid(stick), "the floating stick exists")
	if stick != null:
		# If this control ever accepted input it would swallow every touch before
		# the arena saw it, and the game would be unplayable.
		ok(stick.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"the stick is untouchable, so it cannot steal the steering gesture")
		ok(stick.size.x > 100.0 and stick.size.y > 100.0,
				"the stick spans the viewport (%.0fx%.0f)" % [stick.size.x, stick.size.y])

	# ...and it must not survive into the results screen, which is exactly what
	# would happen if the player died mid-hold.
	ui.show_screen("results")
	await get_tree().process_frame
	ok(stick == null or not stick.visible, "the stick is gone once the match ends")
	ui.show_screen("hud")
	await get_tree().process_frame
	ok(stick == null or stick.visible, "the stick returns with the HUD")

	var map: Control = ui._minimap
	ok(map != null and is_instance_valid(map), "minimap exists")
	if map == null:
		return
	# The map draws as a circle inscribed in its square, so the corners are free —
	# the map toggle deliberately sits in one. Testing against the circle is what
	# the player actually sees.
	var centre := map.get_global_rect().get_center()
	var radius := map.size.x * 0.5

	var probes := [["emote button", ui._emote_btn], ["emote row", ui._emote_row],
			["hint line", ui._hint]]
	var was: Array[bool] = []
	for pair in probes:
		var ctl := pair[1] as Control
		was.append(ctl.visible if ctl != null else false)
		if ctl != null:
			ctl.visible = true
	await get_tree().process_frame

	for idx in probes.size():
		var name := String(probes[idx][0])
		var ctl := probes[idx][1] as Control
		ok(ctl != null, "%s exists" % name)
		if ctl == null:
			continue
		var rect := ctl.get_global_rect()
		ok(rect.size.x > 1.0 and rect.size.y > 1.0,
				"%s has a real rect (%.0fx%.0f)" % [name, rect.size.x, rect.size.y])
		ok(not _rect_hits_circle(rect, centre, radius),
				"%s clears the minimap" % name)
	for idx in probes.size():
		var ctl := probes[idx][1] as Control
		if ctl != null:
			ctl.visible = was[idx]


## Closest point on the rect to the centre; inside the radius means they overlap.
func _rect_hits_circle(rect: Rect2, centre: Vector2, radius: float) -> bool:
	var closest := Vector2(
			clampf(centre.x, rect.position.x, rect.position.x + rect.size.x),
			clampf(centre.y, rect.position.y, rect.position.y + rect.size.y))
	return closest.distance_to(centre) < radius


## Every long list, dragged for real.
##
## On a phone Godot hands a touch to the topmost Control, so a drag that starts on
## a shop card goes to the CARD and the ScrollContainer never sees it. Its built-in
## touch scrolling only works on empty space, and these screens are wall-to-wall
## cards — so on a device they simply did not scroll.
##
## Asserted rather than screenshotted because this cannot reproduce on desktop: a
## mouse wheel scrolls a plain ScrollContainer perfectly. Same shape as the dead
## touch input that shipped (DECISIONS §12s) — desktop-only verification is blind
## to an entire input path.
func _check_scrolling(ui) -> void:
	for tab: String in MetaPanel.TABS:
		ui.open_meta(tab)
		for i in 3:
			await get_tree().process_frame
		var panel = ui._meta_panel
		if panel == null:
			continue
		var sc: ScrollContainer = panel._scroll
		ok(sc is UiKit.TouchScroll, "%s: list is touch-draggable" % tab)
		if not (sc is UiKit.TouchScroll):
			continue
		var reach: float = sc.get_v_scroll_bar().max_value - sc.size.y
		if reach <= 1.0:
			# Nothing to scroll to at this resolution; a drag correctly does nothing.
			ok(true, "%s: content fits, nothing to scroll" % tab)
			continue
		# A tab you just opened starts at the top, unless it deliberately jumps to
		# where the player is (the pass jumps to their current tier).
		ok(sc.scroll_vertical == 0 or tab == "pass",
				"%s: opens at the top (%d)" % [tab, sc.scroll_vertical])
		var before: int = sc.scroll_vertical
		_drag(sc, 160.0)
		ok(sc.scroll_vertical > before,
				"%s: drag scrolls the list (%d -> %d)" % [tab, before, sc.scroll_vertical])
		sc.scroll_vertical = 0
	if ui._meta_panel != null:
		ui._meta_panel.visible = false

	# Settings is the other long list, and it is the one the user hit: the back
	# button sits at the bottom, so a screen that will not scroll has no way out.
	ui.show_screen("menu")
	ui._open_settings()
	for i in 3:
		await get_tree().process_frame
	ok(_find_touch_scroll(ui._settings) != null, "settings: list is touch-draggable")
	ui._close_settings()
	await get_tree().process_frame


func _find_touch_scroll(n: Node) -> ScrollContainer:
	for c in n.get_children():
		if c is UiKit.TouchScroll:
			return c as ScrollContainer
		var found := _find_touch_scroll(c)
		if found != null:
			return found
	return null


## A finger pressing in the middle of the list and sliding up by `dy`.
func _drag(sc: ScrollContainer, dy: float) -> void:
	var mid := sc.get_global_rect().get_center()
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = mid
	sc._input(down)
	var move := InputEventScreenDrag.new()
	move.index = 0
	move.position = mid - Vector2(0.0, dy)
	sc._input(move)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = move.position
	sc._input(up)


## Every modal, opened for real.
##
## This exists because an audit found that FIVE of the six modals in the game had
## never been rendered by anything — no test, no screenshot, no device. Settings
## drawing on top of the menu was exactly that bug: a screen nobody had ever looked
## at. A modal that has never been opened is a screen that has never been checked.
func _check_modals(ui) -> void:
	ui.show_screen("menu")
	await get_tree().process_frame

	# name -> a callable that opens it. Anything reachable by a player belongs here.
	# Minimal arena so the revive offer has something to call back into.
	var stub := Arena.new()
	add_child(stub)
	stub.setup(Game.tuning, null, 4242)
	ui.attach_arena(stub)

	var openers := {
		"daily": func() -> void: ui.show_daily_if_due(true),
		"credits": func() -> void: ui._build_about(),
		"delete_confirm": func() -> void: ui._confirm_delete(),
		# _on_player_down returns early with no arena attached, which is exactly why
		# this modal had never been rendered by anything.
		"revive": func() -> void: ui._on_player_down(),
	}
	var base_children: int = ui._layout.get_child_count()
	for name: String in openers.keys():
		base_children = int(ui._layout.get_child_count())
		var before := _descendants(ui._layout)
		(openers[name] as Callable).call()
		for i in 3:
			await get_tree().process_frame
		var after := _descendants(ui._layout)
		ok(after > before, "%s modal built something (%d -> %d nodes)"
				% [name, before, after])
		# A modal with no readable text is a blank rectangle over the game.
		ok(_visible_text(ui._layout) >= 1, "%s modal has readable text" % name)
		# HIDE what this modal added; do not free it. Two earlier attempts went
		# wrong here: matching on "@Control" (Godot's auto-name for any unnamed
		# Control) also deleted the real screens, and free()ing a popup mid-tween
		# hung the run outright. Hiding is enough — the assertion is that the modal
		# BUILT something, and a hidden node cannot obscure a later check.
		for idx in range(base_children, ui._layout.get_child_count()):
			var extra: Node = ui._layout.get_child(idx)
			if extra is CanvasItem:
				(extra as CanvasItem).visible = false
		await get_tree().process_frame

	# The codex lives on the meta panel, not the main layout.
	ui.open_meta("shop")
	for i in 3:
		await get_tree().process_frame
	var panel = ui._meta_panel
	if panel != null:
		var before_codex := _descendants(panel)
		panel._open_codex()
		for i in 3:
			await get_tree().process_frame
		ok(_descendants(panel) > before_codex, "codex modal built something")
		panel.visible = false
	ui.show_screen("menu")
	await get_tree().process_frame
	stub.queue_free()
	await get_tree().process_frame


## The in-match leaderboard covers the top-right quadrant of the arena, which is
## where a rival comes from. Collapsing it has to keep YOUR row — the one line you
## act on — and has to survive _on_board, which rewrites row visibility three times
## a second and would otherwise undo it immediately.
func _check_board_collapse(ui) -> void:
	ui.show_screen("hud")
	# Start from a known board. This check used to inherit rows from whatever ran
	# before it, which is the same defect as depending on the machine's config.
	for k: String in ui._board_rows.keys():
		var stale: Control = ui._board_rows[k]
		if is_instance_valid(stale):
			stale.queue_free()
	ui._board_rows.clear()
	ui._board_ranks.clear()
	ui._board_collapsed = false
	# One player row plus two rivals is enough to prove the rule.
	ui._on_board([
		{"name": "Ferro", "mass": 90.0, "is_player": false, "rank": 1},
		{"name": "YOU", "mass": 40.0, "is_player": true, "rank": 2},
		{"name": "Rust", "mass": 20.0, "is_player": false, "rank": 3},
	])
	ok(ui._board_rows.size() == 3, "board built 3 rows")

	ui._board_collapsed = false
	ui._apply_board_collapsed()
	var open_visible := 0
	for k: String in ui._board_rows.keys():
		if (ui._board_rows[k] as Control).visible:
			open_visible += 1
	ok(open_visible == 3, "expanded shows every row (%d)" % open_visible)

	ui._board_collapsed = true
	ui._apply_board_collapsed()
	var shut_visible: Array[String] = []
	for k: String in ui._board_rows.keys():
		if (ui._board_rows[k] as Control).visible:
			shut_visible.append(k)
	ok(shut_visible == ["YOU"], "collapsed shows only the player's row (%s)"
			% ", ".join(shut_visible))

	# The real trap: the 0.35s board refresh must not undo the collapse.
	ui._on_board([
		{"name": "Ferro", "mass": 95.0, "is_player": false, "rank": 1},
		{"name": "YOU", "mass": 41.0, "is_player": true, "rank": 2},
		{"name": "Rust", "mass": 21.0, "is_player": false, "rank": 3},
	])
	var after: Array[String] = []
	for k: String in ui._board_rows.keys():
		if (ui._board_rows[k] as Control).visible:
			after.append(k)
	ok(after == ["YOU"], "a board refresh does not undo the collapse (%s)"
			% ", ".join(after))

	ui._board_collapsed = false
	ui._apply_board_collapsed()


## Unknown icon names silently fall through to a plain disc, so a nav bar of five
## tabs renders five identical circles and throws nothing. This is the only place
## that failure is visible without eyes on it.
func _check_icons() -> void:
	var named := ["coin", "gem", "trophy", "lock", "check", "star",
			"bag", "target", "bars", "gear", "card",
			"skin", "trail", "effect", "plate", "arena"]
	var fallback := Icons.get_icon("__definitely_not_a_glyph__", Color.WHITE)
	var fallback_png := fallback.get_image().save_png_to_buffer()
	var seen := {}
	for n: String in named:
		var tex := Icons.get_icon(n, Color.WHITE)
		ok(tex != null, "icon %s exists" % n)
		if tex == null:
			continue
		var png := tex.get_image().save_png_to_buffer()
		ok(png != fallback_png, "icon %s is not the fallback disc" % n)
		ok(not seen.has(png), "icon %s is distinct from the others" % n)
		seen[png] = n


## Every sound effect, checked numerically. Nobody can listen to a CI run, and a
## synthesis change that produces silence or a clipped buzz is invisible to every
## other check in this project — the audio layer is 100% generated from oscillators,
## so a bad constant produces a valid, playable, useless WAV.
func _check_audio() -> void:
	var names := ["absorb", "absorb_big", "launch", "eliminate", "hit",
			"charge_ready", "ui_tap", "size_up", "alarm", "reward", "win", "lose", "hum"]
	for n: String in names:
		var stream: AudioStreamWAV = Audio._sfx.get(n)
		ok(stream != null, "sfx %s exists" % n)
		if stream == null:
			continue
		var bytes: PackedByteArray = stream.data
		ok(bytes.size() > 1000, "sfx %s has samples (%d bytes)" % [n, bytes.size()])
		if bytes.size() < 4:
			continue
		var peak := 0.0
		var sum_sq := 0.0
		var count := bytes.size() / 2
		# Every 7th sample: enough to characterise a waveform, fast enough that
		# thirteen of these do not dominate the run.
		var step := 7
		var taken := 0
		for i in range(0, count, step):
			var v: float = float(bytes.decode_s16(i * 2)) / 32768.0
			peak = maxf(peak, absf(v))
			sum_sq += v * v
			taken += 1
		var rms: float = sqrt(sum_sq / maxf(1.0, float(taken)))
		ok(peak > 0.05, "sfx %s is not silent (peak %.3f)" % [n, peak])
		ok(peak < 0.999, "sfx %s is not clipped (peak %.3f)" % [n, peak])
		ok(rms > 0.004, "sfx %s carries energy (rms %.4f)" % [n, rms])


func _finish() -> void:
	print("%d screen checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
