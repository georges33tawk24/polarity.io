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
			ui._settings.visible = true
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

	_check_icons()
	_check_audio()
	_finish()


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
