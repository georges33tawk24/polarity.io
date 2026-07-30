extends Node
## Boots the main scene, screenshots whichever UI screen is asked for, quits.
##   Godot res://tests/menu_shot.gd -- --shot=/path/out.png [--screen=results]

var _shot := ""
var _screen := "menu"
## Animated screens need to finish before they are photographed.
var _settle := 1.9
var _locale_set := false
var _kind := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot = arg.substr(7)
		elif arg.begins_with("--screen="):
			_screen = arg.substr(9)
		elif arg == "--noconsent":
			Game.set_value("age_bracket", 2)
			Game.set_value("consent", Ads.Consent.GRANTED_NON_PERSONALISED)
			Ads.consent = Ads.Consent.GRANTED_NON_PERSONALISED
			Game.set_value("daily", {"last_day": Meta.today(), "streak": 3})
			Game.set_value("matches", 20)
		elif arg == "--consent":
			Game.set_value("age_bracket", 0)
			Game.set_value("consent", 0)
			Ads.consent = Ads.Consent.UNKNOWN
		elif arg == "--daily":
			# --noconsent marks today as already claimed, so the calendar could not
			# be captured at all and the one screen whose job is to feel like a
			# prize was never actually looked at.
			Game.set_value("daily", {"last_day": Meta.today() - 1, "streak": 3})
		elif arg.begins_with("--kind="):
			# The shop always opened on skins, so four of its five categories could
			# not be captured at all — which is how they all shipped previewing as
			# the same two-pole chip.
			_kind = arg.substr(7)
		elif arg.begins_with("--settle="):
			_settle = float(arg.substr(9))
		elif arg == "--reduced":
			# Also a real test of the reduced-motion path: every value must be
			# present and final on the first frame, with no tween left running.
			Game.profile["reduced_motion"] = true
			UiKit.motion_changed()
			_settle = 0.0
		elif arg.begins_with("--locale="):
			var code := arg.substr(9)
			_locale_set = true
			Game.set_value("locale", code)
			Locale.apply(code)

	# --locale writes into the profile, so a run that set ja left every later run
	# rendering in Japanese until something set it back. Default explicitly rather
	# than inheriting whatever the previous capture happened to leave behind.
	if not _locale_set:
		Game.set_value("locale", "en")
		Locale.apply("en")

	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 6:
		await get_tree().process_frame
	if _screen == "results":
		# Forcing the screen shows an empty shell — the title and stat rows are
		# filled by the match_ended handler. Emit a representative result so the
		# capture shows what a player actually sees.
		Game.last_result = {"placement": 3, "mass": 142.0, "kills": 5,
				"survived": 71.0, "total": 15, "won": false,
				"coins_earned": 214, "xp_earned": 68}
		Bus.match_ended.emit(Game.last_result)
	elif _screen in MetaPanel.TABS:
		main.ui.show_screen("menu")
		main.ui.open_meta(_screen)
		if _kind != "" and main.ui._meta_panel != null:
			main.ui._meta_panel._shop_kind = _kind
			main.ui._meta_panel._rebuild()
	elif _screen != "menu":
		main.ui.show_screen(_screen)
	# Six frames used to be enough because nothing on any screen moved. Now the
	# results screen cascades its rows in over ~0.9s, so a six-frame capture
	# photographs five invisible rows and reports success — the harness would be
	# lying about the exact thing it exists to check.
	for i in 6:
		await get_tree().process_frame
	if _settle > 0.0:
		await get_tree().create_timer(_settle).timeout

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("screen=%s save=%s" % [_screen, "ok" if img.save_png(_shot) == OK else "FAIL"])
	get_tree().quit(0)
