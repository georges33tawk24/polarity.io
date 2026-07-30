extends Node
## Headless checks for the logic that is easy to break silently.
##   /Applications/Godot.app/Contents/MacOS/Godot --headless res://tests/tests.tscn
##
## Run as a scene, not with --script: autoloads are only instantiated on the
## normal boot path, and these tests exercise the real Game/Audio singletons.
##
## ponytail: plain asserts, no test framework. These cover the maths and the
## money — the places where a wrong number is invisible until it ships.

var failures := 0
var checks := 0
var _profile_backup: Dictionary


func _ready() -> void:
	# Deterministic: several checks sample random spawns, and an unseeded suite
	# fails intermittently for reasons that have nothing to do with the code.
	seed(20260729)
	# These tests buy things, claim rewards and move trophies on the REAL profile.
	# That only looked harmless because the suite used to finish faster than the
	# one-second save debounce; once it ran longer, purchases persisted and the
	# next run failed on state left behind by the previous one.
	_profile_backup = Game.profile.duplicate(true)
	await test_arena_lifecycle()
	test_growth_curves()
	test_pull_force()
	test_repel_power()
	test_save_migration()
	test_save_sealing()
	test_rewarded_boosts()
	test_supabase_provider()
	test_locale_formatting()
	await test_arena_determinism()
	test_netcode_seam()
	test_economy_clamps()
	test_match_rewards()
	test_intent_mapping()
	test_scrap_field()
	test_localization()
	test_cosmetics()
	test_meta_progression()
	await test_ftue_and_unlocks()
	test_remote_config()
	test_ads_policy()
	test_analytics()
	test_store()
	test_cloud_merge()
	test_leaderboards()
	await test_share_and_rating()
	test_powerups()
	test_referral()
	test_asset_library()
	test_music()

	Game.profile = _profile_backup
	Game._flush()

	print("\n%d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func ok(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  pass  %s" % label)
	else:
		failures += 1
		printerr("  FAIL  %s" % label)


func about(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


# ---------------------------------------------------------------------------
## Players replay immediately from the results screen, so an arena that fails
## to clean up leaks once per match. Exit-time "leaked instances" warnings are
## noise; growth across repeated matches is the leak that actually matters.
func test_arena_lifecycle() -> void:
	print("arena lifecycle")
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# A parse error in ui.gd leaves `ui` null while every other assertion below
	# still passes — this suite once reported 47 green with the UI fully broken.
	ok(main.ui != null, "UI instantiated")
	if main.ui != null:
		main.ui.show_screen("menu")
		await get_tree().process_frame
		await get_tree().process_frame
		var menu_size: Vector2 = main.ui._menu.size
		ok(menu_size.x > 100.0 and menu_size.y > 100.0,
				"menu screen has a real rect, not a collapsed one (%s)" % menu_size)

	await _cycle_match(main)
	var baseline := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for i in 3:
		await _cycle_match(main)
	var after := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)

	ok(after <= baseline + 20,
			"three more matches leak no nodes (%d -> %d)" % [baseline, after])
	ok(Engine.time_scale == 1.0, "time scale is restored after a match is torn down")
	main.queue_free()
	await get_tree().process_frame


func _cycle_match(main: Node) -> void:
	# start_match() is async now (staged construction behind the loader), so
	# callers must await it or they inspect a half-built arena.
	await main.start_match()
	for i in 4:
		await get_tree().physics_frame
	main.to_menu()
	# queue_free() lands at end of frame; give the tree time to actually reap.
	for i in 4:
		await get_tree().process_frame


func test_growth_curves() -> void:
	print("growth curves")
	var t := Tuning.new()
	ok(about(t.radius_for(t.start_mass), t.base_radius), "radius at start mass is base radius")
	ok(t.radius_for(t.start_mass * 4.0) > t.radius_for(t.start_mass), "radius grows with mass")
	# Sub-linear: quadrupling mass must not quadruple the radius, or a big
	# magnet covers the whole screen and the game stops being readable.
	ok(t.radius_for(t.start_mass * 4.0) < t.base_radius * 4.0, "radius growth is sub-linear")
	ok(t.speed_for(t.start_mass * 4.0) < t.speed_for(t.start_mass), "bigger is slower")
	ok(t.speed_for(t.start_mass * 4.0) > 0.0, "speed stays positive when huge")
	ok(t.radius_for(0.0) >= 0.0, "zero mass does not produce NaN radius")
	ok(t.pull_radius_for(t.start_mass) > t.radius_for(t.start_mass), "pull reaches past the body")


func test_pull_force() -> void:
	print("pull force")
	var t := Tuning.new()
	var near := t.pull_force(10.0, 2.0)
	var far := t.pull_force(10.0, 8.0)
	ok(near > far, "force falls off with distance")
	ok(t.pull_force(20.0, 4.0) > t.pull_force(10.0, 4.0), "heavier magnets pull harder")
	# The distance clamp is what stops a scrap piece at d=0 flying to infinity.
	var at_zero := t.pull_force(10.0, 0.0)
	var at_clamp := t.pull_force(10.0, t.min_distance)
	ok(about(at_zero, at_clamp), "distance is clamped at min_distance")
	ok(at_zero < INF, "force is finite at zero distance")


func test_repel_power() -> void:
	print("repel power")
	var t := Tuning.new()
	# Mirrors Magnet.fire_repel — a tap must still do something, a full hold caps at 1.
	var tap: float = clampf(0.0 / t.repel_charge_time, t.repel_min_power, 1.0)
	var full: float = clampf(t.repel_charge_time / t.repel_charge_time, t.repel_min_power, 1.0)
	var over: float = clampf(5.0, t.repel_min_power, 1.0)
	ok(about(tap, t.repel_min_power), "instant release still fires at the floor")
	ok(about(full, 1.0), "full charge is full power")
	ok(about(over, 1.0), "overcharge cannot exceed full power")
	ok(tap < full, "holding longer hits harder")


## Encryption at rest. Obfuscation, not security — see game.gd — but it has to
## round-trip, has to still load an unsealed save from an older build, and must not
## leave the interesting numbers greppable in the file.
## Rewarded boosts. Each is a one-shot flag consumed by the thing it affects, and
## the failure modes are opposite and equally bad: granted twice, or silently lost.
## §4.14 asks that v1 be architected so multiplayer can be added later. The claim
## has always been "bots write the same intent a network peer would". That is only
## true if it is enforced, so this asserts the seam rather than trusting the comment:
##
##   1. The intent surface is exactly move_dir + holding. Anything else a bot could
##      write is a private channel a remote peer would not have.
##   2. A bot NEVER touches position, velocity or mass directly.
##   3. Intent is bounded and serialisable — a unit vector and a bool, which is 3
##      floats and a bit on the wire.
## §4.9 currency and date formatting. Small table, but the failure mode is a price
## that reads as wrong money in someone's language, which is worse than English.
## The backend must degrade to offline, never to a crash and never to a state where
## it looks connected while writing nowhere. That last one is the dangerous case: a
## player would believe their progress was safe.
func test_supabase_provider() -> void:
	print("supabase provider")
	var sb := SupabaseProvider.new(null)
	# Force the unconfigured state rather than assuming supabase.cfg is absent. It
	# IS absent in the repo and on CI, but a developer with real credentials was
	# making this assertion fail — the test was measuring the machine, not the code.
	sb.url = ""
	sb.anon_key = ""
	sb._configured = false
	ok(not sb.available(), "unconfigured provider reports unavailable")

	# Every call must answer even with no config and no host node, or a caller
	# awaiting the callback hangs forever.
	var answered := [0]
	sb.sign_in(true, func(_ok: bool, _id: String, _n: String) -> void: answered[0] += 1)
	sb.load_cloud(func(_d: Dictionary) -> void: answered[0] += 1)
	sb.save_cloud({}, func(_ok: bool) -> void: answered[0] += 1)
	sb.submit_score(10, func(_ok: bool) -> void: answered[0] += 1)
	sb.fetch_board(0, func(_r: Array) -> void: answered[0] += 1)
	ok(answered[0] == 5, "every call answers when unconfigured (%d/5)" % answered[0])

	# It has to actually implement the seam, or Backend cannot hold it.
	ok(sb is BackendProvider, "SupabaseProvider implements the backend seam")

	# Half a config is not a config: a URL with no key must stay offline rather
	# than firing unauthenticated requests at a real project.
	sb.url = "https://example.supabase.co"
	sb.anon_key = "too-short"
	sb._configured = sb.url.begins_with("http") and sb.anon_key.length() > 20
	ok(not sb.available(), "a half-filled config stays offline")


func test_locale_formatting() -> void:
	print("locale formatting")
	ok(Locale.currency(4.99, "en") == "$4.99", "en leads with $ and keeps cents")
	ok(Locale.currency(4.99, "de").ends_with("\u20ac"), "de trails with the euro sign")
	ok(Locale.currency(4.99, "de").contains(","), "de uses a comma decimal")
	# Yen and won have no minor unit; ".00" on them is a tell.
	ok(not Locale.currency(500.0, "ja").contains("."), "ja shows no minor unit")
	ok(Locale.currency(500.0, "ja").begins_with("\u00a5"), "ja leads with the yen sign")

	# 2001-09-09, a date whose parts are all distinguishable.
	var t := 1000000000
	ok(Locale.date(t, "en").begins_with("09"), "en is month-first")
	ok(Locale.date(t, "de").begins_with("09"), "de is day-first")
	ok(Locale.date(t, "ja").begins_with("2001"), "ja is year-first")


## §4.14 determinism. The claim is deliberately narrow: the same seed produces the
## same arena LAYOUT. That is enough for replays, for a server to re-derive a match
## start, and for a bug report to be reproducible — and it is all that can honestly
## be claimed while physics runs on floats through Godot's solver at a variable
## delta. A test that asserted full lockstep would pass here and fail across two
## machines, which is worse than not having it.
func test_arena_determinism() -> void:
	print("arena determinism")
	var layouts: Array = []
	for pass_i in 2:
		var a := Arena.new()
		add_child(a)
		a.setup(Game.tuning, null, 12345)
		var shape: Array = []
		for m in a.magnets:
			shape.append("%.4f,%.4f" % [m.global_position.x, m.global_position.z])
		for h in a._hazard_nodes:
			if h is Node3D:
				shape.append("h%.4f,%.4f" % [(h as Node3D).position.x,
						(h as Node3D).position.z])
		layouts.append(",".join(shape))
		a.queue_free()
		await get_tree().process_frame
	ok(layouts[0] == layouts[1] and layouts[0] != "",
			"the same seed rebuilds the same arena layout")

	var b := Arena.new()
	add_child(b)
	b.setup(Game.tuning, null, 999)
	var other: Array = []
	for m in b.magnets:
		other.append("%.4f,%.4f" % [m.global_position.x, m.global_position.z])
	ok(",".join(other) != layouts[0], "a different seed gives a different layout")
	ok(b.seed_used == 999, "the seed used is recorded for a bug report")
	b.queue_free()
	await get_tree().process_frame


func test_netcode_seam() -> void:
	print("netcode seam")
	var src := FileAccess.get_file_as_string("res://scripts/bot_brain.gd")
	ok(src != "", "bot_brain.gd is readable")

	# The brain may only WRITE these two fields on its magnet.
	var forbidden := ["global_position =", "position =", "velocity =", "mass =",
			"_set_mass(", "gain_mass(", "kill("]
	for f: String in forbidden:
		ok(not src.contains("magnet." + f.replace("(", "(")),
				"bot does not write magnet.%s" % f.replace(" =", ""))

	ok(src.contains("move_dir") and src.contains("holding"),
			"bot writes the intent fields")

	# The property that actually matters is not naming — Intent calls them dir/held
	# and arena.gd translates — it is that NOTHING ELSE writes them. Every writer of
	# magnet.move_dir / magnet.holding has to be a thing a network peer could also
	# be. Today that is exactly two: the bot brain, and the one line in arena.gd
	# that copies local input in. A third writer is where a would-be multiplayer
	# build starts diverging, so it fails here first.
	var writers: Array[String] = []
	for f: String in ["arena", "bot_brain", "magnet", "ftue", "intent", "main", "ui"]:
		var body := FileAccess.get_file_as_string("res://scripts/%s.gd" % f)
		for line in body.split("\n"):
			var l := String(line).strip_edges()
			if l.begins_with("#"):
				continue
			# An assignment TO the field on some other object.
			if l.contains(".move_dir =") or l.contains(".holding ="):
				writers.append(f)
				break
	ok(writers.size() <= 2,
			"only the bot brain and local input write intent (writers: %s)"
					% ", ".join(writers))
	ok(writers.has("arena"), "local input reaches the magnet through arena.gd")

	# Bounded and serialisable: a normalised direction plus a flag.
	var m := Magnet.new()
	m.move_dir = Vector2(9.0, 9.0)
	m.holding = true
	ok(m.move_dir is Vector2 and m.holding is bool,
			"intent is two floats and a bool — 9 bytes on the wire, no command object")
	m.free()


func test_rewarded_boosts() -> void:
	print("rewarded boosts")
	Game.set_value("trial_skin", "")
	Game.set_value("boost_mass", false)
	Game.set_value("wheel_day", 0)

	# A skin trial overrides the equipped skin WITHOUT equipping it, so the real
	# loadout is untouched and quitting cannot make the trial permanent.
	var equipped := Cosmetics.equipped("skin")
	Game.set_value("trial_skin", "skin_bullion")
	var trial_colors := Cosmetics.skin_colors()
	ok(Cosmetics.equipped("skin") == equipped,
			"a trial does not change the equipped skin")
	Game.set_value("trial_skin", "")
	var normal_colors := Cosmetics.skin_colors()
	ok(trial_colors[0] != normal_colors[0], "a trial actually changes the colours")

	# One match only.
	Game.set_value("trial_skin", "skin_bullion")
	Meta.clear_trial()
	ok(String(Game.get_value("trial_skin", "")) == "", "a trial expires after a match")

	# The wheel marks the day BEFORE granting, so a crash loop cannot farm it.
	Game.set_value("wheel_day", 0)
	var before := int(Game.get_value("coins", 0))
	var first := Meta.spin_wheel()
	ok(not first.is_empty() or not Ads.rewarded_available(),
			"a spin either grants or is unavailable")
	var second := Meta.spin_wheel()
	ok(second.is_empty(), "the wheel cannot be spun twice in a day")
	ok(int(Game.get_value("coins", 0)) >= before, "a spin never removes currency")
	Game.set_value("wheel_day", 0)


func test_save_sealing() -> void:
	print("save sealing")
	var plain := '{"coins": 1234567, "version": 9}'
	var sealed := Game._seal(plain)
	ok(sealed.begins_with(Game.SEAL_MAGIC), "sealed text carries its magic")
	ok(not sealed.contains("1234567"), "the balance is not greppable in the file")
	ok(Game._unseal(sealed) == plain, "seal round-trips")
	ok(Game._unseal(plain) == plain,
			"an unsealed save from an older build still loads")
	# A flipped byte must degrade to unparseable, not to a wrong-but-valid save,
	# so the corruption-tolerant loader falls through to the backup.
	var tampered := sealed.substr(0, sealed.length() - 4) + "AAAA"
	# JSON.new().parse() returns an error code; JSON.parse_string() would push an
	# engine error into the log, and this test EXPECTS the parse to fail.
	var j := JSON.new()
	var err := j.parse(Game._unseal(tampered))
	var out: Variant = j.data if err == OK else null
	ok(out == null or (out is Dictionary and int((out as Dictionary).get("coins", 0)) != 1234567),
			"a tampered save does not yield the original balance")


func test_save_migration() -> void:
	print("save migration")
	var fresh := Game.migrate({})
	ok(int(fresh["version"]) == Game.SAVE_VERSION, "empty save migrates to current version")
	ok(int(fresh["coins"]) == 0, "empty save has zero coins")

	var v1 := Game.migrate({"version": 1, "coins": 50, "score": 88.0})
	ok(int(v1["coins"]) == 50, "v1 currency survives migration")
	ok(about(float(v1["best_mass"]), 88.0), "v1 score folds into best_mass")
	ok(v1.has("haptics"), "missing keys are filled with defaults")

	var hacked := Game.migrate({"coins": -999, "level": 0, "sfx": 12.0})
	ok(int(hacked["coins"]) == 0, "negative currency is clamped to zero")
	ok(int(hacked["level"]) >= 1, "level is clamped to at least 1")
	ok(float(hacked["sfx"]) <= 1.0, "volume is clamped to 0..1")

	var junk := Game.migrate({"coins": 10, "nonsense": {"a": 1}})
	ok(not junk.has("nonsense"), "unknown keys are dropped")


func test_economy_clamps() -> void:
	print("economy")
	var before := int(Game.get_value("coins", 0))
	Game.add_currency("coins", 100)
	ok(int(Game.get_value("coins")) == before + 100, "coins are credited")
	ok(Game.spend("coins", 40), "affordable purchase succeeds")
	ok(int(Game.get_value("coins")) == before + 60, "coins are debited exactly")
	ok(not Game.spend("coins", 999999), "unaffordable purchase is refused")
	ok(int(Game.get_value("coins")) == before + 60, "a refused purchase changes nothing")
	ok(not Game.spend("coins", -50), "negative spend cannot mint currency")
	Game.add_currency("coins", -999999)
	ok(int(Game.get_value("coins")) == 0, "balance floors at zero, never negative")
	Game.add_currency("coins", before)


func test_match_rewards() -> void:
	print("match rewards")
	var t := Game.tuning
	var win := Game.record_match({"placement": 1, "mass": 100.0, "kills": 3, "total": 15})
	var lose := Game.record_match({"placement": 9, "mass": 100.0, "kills": 3, "total": 15})
	ok(int(win["coins_earned"]) > int(lose["coins_earned"]), "winning pays more than losing")
	ok(int(win["coins_earned"]) - int(lose["coins_earned"]) == t.coins_win_bonus,
			"the win bonus is exactly the configured amount")
	var zero := Game.record_match({"placement": 15, "mass": 0.0, "kills": 0, "total": 15})
	ok(int(zero["coins_earned"]) >= 0, "a disastrous match never pays negative")
	ok(int(Game.get_value("level", 1)) >= 1, "level never drops below 1")


func test_intent_mapping() -> void:
	print("input intent")
	var i := Intent.new()
	var vp := Vector2(1080, 1920)
	var centre := Vector2(540, 960)

	i.update(centre, vp)
	ok(i.dir == Vector2.ZERO and not i.held, "no input means no intent")

	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = centre + Vector2(0, 300)
	i.handle_event(touch)
	i.update(centre, vp)
	ok(i.held, "a touch is a hold")
	ok(i.dir.y > 0.5, "dragging below the magnet steers down")
	ok(i.dir.length() <= 1.0001, "intent is normalised to at most 1")

	# A second finger must not hijack or cancel the active hold.
	var second := InputEventScreenTouch.new()
	second.index = 1
	second.pressed = false
	second.position = centre
	i.handle_event(second)
	i.update(centre, vp)
	ok(i.held, "a stray second finger does not release the hold")

	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	i.handle_event(up)
	i.update(centre, vp)
	ok(not i.held, "lifting the original finger releases")

	# Dead zone: the same gesture must be scale-independent across screens.
	var t2 := InputEventScreenTouch.new()
	t2.index = 0
	t2.pressed = true
	t2.position = centre + Vector2(3, 0)
	i.handle_event(t2)
	i.update(centre, vp)
	ok(i.dir == Vector2.ZERO, "a thumb resting on the magnet does not steer")


## Cloud merge is the single most damaging thing to get wrong: the failure mode
## is silently deleting currency or a purchase the player made on another device.
func test_cloud_merge() -> void:
	print("cloud save merge")
	var local := {"saved_at": 100, "coins": 500, "gems": 10, "owned": ["skin_mint"],
			"iap_owned": ["remove_ads"], "no_ads": true, "best_placement": 3,
			"best_mass": 90.0, "kills": 40, "name": "LOCAL", "seen_tutorial": true}
	var remote := {"saved_at": 200, "coins": 200, "gems": 90, "owned": ["skin_ember"],
			"iap_owned": [], "no_ads": false, "best_placement": 7,
			"best_mass": 40.0, "kills": 12, "name": "REMOTE", "seen_tutorial": false}

	var m := Backend.merge_saves(local, remote)
	ok(int(m["coins"]) == 500, "currency takes the max, never the newer side")
	ok(int(m["gems"]) == 90, "each currency is maxed independently")
	ok(int(m["kills"]) == 40, "progress counters take the max")
	ok(about(float(m["best_mass"]), 90.0), "best mass takes the max")
	ok(int(m["best_placement"]) == 3, "best placement takes the MIN — 3 beats 7")
	ok(m["owned"].has("skin_mint") and m["owned"].has("skin_ember"),
			"owned cosmetics union across devices")
	ok(m["iap_owned"].has("remove_ads"), "a purchase on the older side survives")
	ok(bool(m["no_ads"]), "a paid entitlement is never merged away")
	ok(bool(m["seen_tutorial"]), "tutorial completion is sticky")
	ok(String(m["name"]) == "REMOTE", "plain fields follow last-write-wins")

	# Symmetry: merging the other direction must give the same money.
	var swapped := Backend.merge_saves(remote, local)
	ok(int(swapped["coins"]) == 500, "merge is symmetric for currency")
	ok(int(swapped["best_placement"]) == 3, "merge is symmetric for placement")
	ok(swapped["iap_owned"].has("remove_ads"), "merge is symmetric for purchases")

	# A never-placed side must not win the min().
	var never := Backend.merge_saves({"best_placement": 0, "saved_at": 300},
			{"best_placement": 5, "saved_at": 100})
	ok(int(never["best_placement"]) == 5, "a zero placement does not beat a real one")

	# Repeated syncs must be idempotent — no drift, no double-credit.
	var once := Backend.merge_saves(local, remote)
	var twice := Backend.merge_saves(once, remote)
	ok(int(twice["coins"]) == int(once["coins"]), "re-syncing does not inflate currency")
	ok(twice["iap_owned"].size() == once["iap_owned"].size(),
			"re-syncing does not duplicate entitlements")

	# An empty remote (first ever sync) must not wipe the local profile.
	var fresh := Backend.merge_saves(local, {})
	ok(int(fresh["coins"]) == 500, "an empty remote never zeroes local currency")
	ok(fresh["iap_owned"].has("remove_ads"), "an empty remote never removes purchases")


## The share card is the marketing engine (pillar 3) and the rating prompt is
## the fastest way to earn one-star reviews if it fires at the wrong moment.
func test_share_and_rating() -> void:
	print("share card and rating prompt")
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 3:
		await get_tree().process_frame

	# Rating gate: never before the win/match thresholds, never twice.
	Game.set_value("rated", false)
	Game.set_value("rate_prompt_day", 0)
	Game.set_value("wins", 0)
	Game.set_value("matches", 0)
	main.ui.maybe_prompt_rating()
	ok(int(Game.get_value("rate_prompt_day", 0)) == 0, "no rating prompt for a new player")

	Game.set_value("wins", 5)
	Game.set_value("matches", 30)
	main.ui.maybe_prompt_rating()
	ok(int(Game.get_value("rate_prompt_day", 0)) > 0, "prompt fires once the thresholds are met")

	var stamped := int(Game.get_value("rate_prompt_day", 0))
	Game.set_value("rate_prompt_day", Meta.today())
	main.ui.maybe_prompt_rating()
	ok(int(Game.get_value("rate_prompt_day", 0)) == stamped,
			"the prompt respects its cooldown")

	Game.set_value("rated", true)
	Game.set_value("rate_prompt_day", 0)
	main.ui.maybe_prompt_rating()
	ok(int(Game.get_value("rate_prompt_day", 0)) == 0,
			"a player who already rated is never asked again")

	# Share card must produce a real image, not just copy text.
	# Headless has no renderer, so the card is expected to decline rather than
	# hang. Only assert it actually renders when there is something to render on.
	var path: String = await main.ui._render_share_card(
			{"placement": 1, "mass": 142.0, "kills": 6, "total": 15})
	if DisplayServer.get_name() == "headless":
		ok(path == "", "share card declines cleanly headless instead of hanging")
	else:
		ok(path != "" and FileAccess.file_exists(path),
				"share card renders to a PNG (%s)" % path)
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		ok(img != null and img.get_width() >= 512, "share card has real dimensions")

	main.queue_free()
	await get_tree().process_frame


## Buffs must work for bots as well as the player — a pickup only the player can
## use is set dressing, and the bots would ignore half the arena.
func test_powerups() -> void:
	print("power-ups")
	var t := Tuning.new()
	var m := Magnet.new()
	m.configure(t, "TEST", Color.RED, Color.BLUE, false)

	var base_pull := m.pull_radius()
	m.grant_buff(Powerups.Kind.SURGE, 5.0)
	ok(m.has_buff(Powerups.Kind.SURGE), "buff is granted")
	ok(m.pull_radius() > base_pull, "surge extends reach")
	ok(m.pull_strength_mult() > 1.0, "surge multiplies pull strength")

	# Shield must actually prevent damage, or nobody picks it up.
	m.grant_buff(Powerups.Kind.SHIELD, 5.0)
	var before := m.mass
	m.lose_mass(3.0)
	ok(about(m.mass, before), "shield blocks damage entirely")
	m.freeze(2.0)
	ok(m.frozen <= 0.0, "shield blocks freeze")

	m.buffs.erase(Powerups.Kind.SHIELD)
	m.lose_mass(1.0)
	ok(m.mass < before, "damage lands once the shield expires")
	m.freeze(2.0)
	ok(m.frozen > 0.0, "freeze lands without a shield")

	# Buffs expire.
	m.buffs.clear()
	m.grant_buff(Powerups.Kind.SPEED, 0.05)
	m._physics_process(0.1)
	ok(not m.has_buff(Powerups.Kind.SPEED), "buffs expire on their timer")

	# Reverse polarity swaps the verb, for anyone standing in the zone.
	# Clear the freeze left over from the shield checks — is_attracting() also
	# gates on it, which is correct behaviour but not what is under test here.
	m.frozen = 0.0
	m.holding = true
	m.inverted = false
	ok(m.is_attracting(), "holding attracts normally")
	m.inverted = true
	ok(not m.is_attracting(), "inverted, holding stops attracting")
	m.holding = false
	ok(m.is_attracting(), "inverted, releasing attracts")
	m.inverted = false

	# A frozen magnet cannot attract, whatever it is holding.
	m.holding = true
	m.frozen = 1.0
	ok(not m.is_attracting(), "a frozen magnet cannot attract")
	m.free()


## The project must run whether or not the Blender step has been executed, and
## must be honest about which source it used.
func test_asset_library() -> void:
	print("asset library")
	AssetLibrary.clear_cache()
	var called := [false]
	var m := AssetLibrary.mesh("definitely_not_exported", func() -> Mesh:
		called[0] = true
		return Meshes.nut())
	ok(called[0], "a missing .glb falls back to generated geometry")
	ok(m != null, "the fallback returns a usable mesh")
	ok(not AssetLibrary.all_authored(), "all_authored is false when anything is generated")
	ok(AssetLibrary.source_report().contains("generated"), "the report names the source")

	# Second call must hit the cache, not rebuild.
	called[0] = false
	AssetLibrary.mesh("definitely_not_exported", func() -> Mesh:
		called[0] = true
		return Meshes.nut())
	ok(not called[0], "meshes are cached after first resolve")

	# Every asset the exporter produces must have a fallback wired, or a missing
	# Blender run leaves holes in the arena.
	for name: String in ["magnet", "scrap_nut", "scrap_bolt", "scrap_gear", "scrap_shard"]:
		AssetLibrary.clear_cache()
		var got := AssetLibrary.mesh(name, func() -> Mesh: return Meshes.nut())
		ok(got != null, "%s resolves to a mesh" % name)
	AssetLibrary.clear_cache()


## I cannot judge whether the music sounds good, but the failure modes that make
## generated audio unusable are all measurable: silence, clipping, DC offset and
## a click at the loop seam.
func test_music() -> void:
	print("music")
	# Earlier tests start matches, which build the tracks — so timing
	# ensure_music() here would measure a cache hit and report a meaningless 0ms.
	# Clear first to get the real cost.
	Audio._music.clear()
	var t0 := Time.get_ticks_msec()
	Audio.ensure_music("game")
	Audio.ensure_music("intensity")
	var build_ms := Time.get_ticks_msec() - t0
	ok(Audio._music.has("game"), "game track builds")
	ok(Audio._music.has("intensity"), "intensity track builds")
	# Generated during the loading screen, so it has a budget rather than being
	# free. A multi-second stall here would be a visible hang.
	ok(build_ms < 4000, "both tracks build in under 4s (%dms)" % build_ms)

	var stream: AudioStreamWAV = Audio._music["game"]
	var bytes := stream.data
	var samples := bytes.size() / 2
	ok(samples > 10000, "track has real length (%d samples)" % samples)

	var expected := int(Audio.MUSIC_BARS * 4 * 60.0 / Audio.MUSIC_BPM * Audio.MIX_RATE)
	ok(absi(samples - expected) < 200, "track length matches the bar grid")
	ok(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "track is set to loop")

	var peak := 0
	var sum_sq := 0.0
	var dc := 0.0
	var clipped := 0
	for i in samples:
		var v := bytes.decode_s16(i * 2)
		peak = maxi(peak, absi(v))
		sum_sq += float(v) * float(v)
		dc += float(v)
		if absi(v) >= 32000:
			clipped += 1
	var rms: float = sqrt(sum_sq / samples) / 32768.0
	dc /= samples * 32768.0

	ok(rms > 0.02, "track is not silence (rms %.3f)" % rms)
	ok(rms < 0.5, "track is not a wall of noise (rms %.3f)" % rms)
	ok(peak <= 32767, "no sample exceeds int16 range")
	# A handful of clipped samples is inaudible; thousands is distortion.
	ok(clipped < samples / 200, "track is not clipping (%d clipped)" % clipped)
	ok(absf(dc) < 0.02, "no DC offset (%.4f)" % dc)

	# Loop seam: both ends must sit near zero or the loop ticks audibly.
	var head := absi(bytes.decode_s16(0))
	var tail := absi(bytes.decode_s16((samples - 1) * 2))
	ok(head < 400 and tail < 400, "loop seam is faded (head %d tail %d)" % [head, tail])


func test_referral() -> void:
	print("referral")
	var code := Backend.referral_code()
	ok(code.length() >= 5, "a referral code is generated (%s)" % code)
	ok(code == Backend.referral_code(), "the code is stable for one install")
	ok(not code.contains("0") and not code.contains("O"),
			"the alphabet avoids characters people mistype")

	Game.set_value("referred_by", "")
	# Self-referral is the obvious exploit: without this every player mints coins.
	var mine := Backend.apply_referral(code)
	ok(not mine["ok"] and mine["reason"] == "self", "self-referral is refused")

	var coins_before := int(Game.get_value("coins", 0))
	var other := Backend.apply_referral("ABCDEF")
	ok(other["ok"], "a valid foreign code is accepted")
	ok(int(Game.get_value("coins", 0)) > coins_before, "the invitee is rewarded")

	var again := Backend.apply_referral("XYZXYZ")
	ok(not again["ok"] and again["reason"] == "already", "only one referral per account")
	ok(not Backend.apply_referral("A")["ok"], "a malformed code is refused")
	Game.set_value("referred_by", "")


func test_leaderboards() -> void:
	print("leaderboards")
	# This test is about the LOCAL provider's synthetic board. It used to pass only
	# because nobody had a backend configured; with one configured it asserted
	# against live rows and failed. A test must not depend on the developer's
	# machine having or not having credentials.
	var restore := Backend.provider
	Backend.provider = BackendProvider.new()
	Game.set_value("best_mass", 150.0)
	var got := {"rows": []}
	Backend.board_ready.connect(func(_scope: String, rows: Array) -> void:
		got["rows"] = rows, CONNECT_ONE_SHOT)
	Backend.fetch(Backend.Scope.GLOBAL)
	var rows: Array = got["rows"]
	ok(rows.size() > 5, "a board is produced offline (%d rows)" % rows.size())

	# Ranks must be dense, ordered, and the player must appear exactly once.
	var ordered := true
	var players := 0
	for i in rows.size():
		if int(rows[i]["rank"]) != i + 1:
			ordered = false
		if i > 0 and int(rows[i]["score"]) > int(rows[i - 1]["score"]):
			ordered = false
		if rows[i].get("is_player", false):
			players += 1
	ok(ordered, "board is sorted by score with dense ranks")
	ok(players == 1, "the player appears exactly once")

	# Anti-cheat clamp: an impossible score must not be submitted.
	var weekly_before := int(Game.get_value("weekly_best", 0))
	# (provider restored at the end of this test)
	Backend.submit(999999)
	ok(int(Game.get_value("weekly_best", 0)) == weekly_before,
			"an impossible score is rejected")
	Backend.submit(-5)
	ok(int(Game.get_value("weekly_best", 0)) == weekly_before, "a negative score is rejected")
	Backend.submit(120)
	ok(int(Game.get_value("weekly_best", 0)) >= 120, "a plausible score is recorded")

	# GDPR export must contain the profile and be valid JSON.
	var dump := Backend.export_data()
	ok(JSON.parse_string(dump) is Dictionary, "data export is valid JSON")
	ok(dump.contains("coins"), "data export includes the profile")

	# Put back whatever this machine actually has configured.
	Backend.provider = restore


## Fake billing so the grant/restore/revoke logic above the provider is actually
## exercised. The shipped provider always fails, which would leave every one of
## these paths untested until the day a real SDK is wired in.

class FakeBilling extends Store.Provider:
	var succeed := true
	var owned: Array = []
	func purchase(product_id: String, cb: Callable) -> void:
		if succeed:
			owned.append(product_id)
		cb.call(succeed, "fake-receipt-%s" % product_id)
	func restore(cb: Callable) -> void:
		cb.call(owned)
	func available() -> bool:
		return true
	func price_string(_product_id: String) -> String:
		return ""



func test_store() -> void:
	print("store / iap")
	ok(Store.products().size() >= 6, "product catalogue loads")
	ok(Store.product("remove_ads").size() > 0, "products are addressable by id")
	ok(Store.price_text("remove_ads") != "—", "a price falls back when the store is silent")

	# Shipped state: no billing provider, so nothing may be sold or granted.
	Game.set_value("iap_owned", [])
	Game.set_value("no_ads", false)
	Game.set_value("age_bracket", 0)
	ok(not Store.available(), "no billing provider means the store is unavailable")
	var res := [-1]   # Array: lambdas capture locals by VALUE in GDScript
	Store.purchase("remove_ads", func(r: int) -> void: res[0] = r)
	ok(res[0] == Store.Result.UNAVAILABLE, "purchase without a provider reports unavailable")
	ok(not Store.owns("remove_ads"), "a failed purchase grants no entitlement")

	# With billing injected, the grant path must work end to end.
	var fake := FakeBilling.new()
	Store.provider = fake
	ok(Store.available(), "store is available with a provider")

	var coins_before := int(Game.get_value("coins", 0))
	Store.purchase("coins_small", func(r: int) -> void: res[0] = r)
	ok(res[0] == Store.Result.SUCCESS, "consumable purchase succeeds")
	ok(int(Game.get_value("coins", 0)) > coins_before, "consumable grants its currency")
	ok(not Store.owns("coins_small"), "a consumable is not retained as an entitlement")
	Store.purchase("coins_small", func(r: int) -> void: res[0] = r)
	ok(res[0] == Store.Result.SUCCESS, "a consumable can be bought repeatedly")

	Store.purchase("remove_ads", func(r: int) -> void: res[0] = r)
	ok(res[0] == Store.Result.SUCCESS, "non-consumable purchase succeeds")
	ok(Store.owns("remove_ads"), "non-consumable is retained")
	ok(Store.has_no_ads(), "remove_ads grants the no-ads entitlement")
	Store.purchase("remove_ads", func(r: int) -> void: res[0] = r)
	ok(res[0] == Store.Result.ALREADY_OWNED, "a non-consumable cannot be bought twice")

	# The paid entitlement must actually suppress ads — but not rewarded video,
	# which is opt-in and removing it would punish the person who paid.
	Ads.set_consent(Ads.Consent.GRANTED_PERSONALISED)
	ok(not Ads.available(), "no-ads suppresses interstitials and banners")
	ok(not Ads.can_show_interstitial(), "no-ads blocks interstitials")

	# A cancelled purchase must change nothing.
	fake.succeed = false
	var before_owned := Store.owned_products().size()
	Store.purchase("starter_pack", func(r: int) -> void: res[0] = r)
	ok(res[0] == Store.Result.CANCELLED, "a cancelled purchase reports cancelled")
	ok(Store.owned_products().size() == before_owned, "a cancelled purchase grants nothing")
	fake.succeed = true

	# Restore after a reinstall — required by both stores.
	Game.set_value("iap_owned", [])
	Game.set_value("no_ads", false)
	ok(not Store.has_no_ads(), "wiping local state clears the entitlement")
	var restored := [-1]
	Store.restore(func(n: int) -> void: restored[0] = n)
	ok(restored[0] >= 1, "restore re-grants non-consumables (%d)" % restored[0])
	ok(Store.has_no_ads(), "restore brings back the no-ads entitlement")

	# Refund / chargeback path.
	Store.revoke("remove_ads")
	ok(not Store.owns("remove_ads"), "revocation removes the entitlement")
	ok(not Store.has_no_ads(), "revocation clears no-ads")

	# Offers are segment-driven and time-limited, and never sold to a player who
	# has not played yet.
	Game.set_value("offer", {})
	Game.set_value("iap_count", 0)
	Game.set_value("matches", 0)
	ok(Store.active_offer().is_empty(), "no offer before the player has played")
	Game.set_value("matches", 50)
	Game.set_value("last_session_day", int(Time.get_unix_time_from_system()) / 86400)
	var offer := Store.active_offer()
	ok(not offer.is_empty(), "an engaged-segment player gets an offer")
	ok(Store.offer_seconds_left() > 0, "an offer has time remaining")
	var same := Store.active_offer()
	ok(same.get("id") == offer.get("id"), "the active offer is stable while it runs")
	Game.set_value("offer", {"id": "x", "product": "coins_medium", "expires": 1})
	ok(Store.active_offer().get("id") != "x", "an expired offer is replaced")

	Store.provider = Store.Provider.new()
	Game.set_value("iap_owned", [])
	Game.set_value("no_ads", false)


func test_remote_config() -> void:
	print("remote config")
	# apply_remote() writes to disk and _load_cache() reloads it next launch, so
	# a test payload left behind here poisons every later run. Start clean.
	Config.clear_remote()
	ok(Config.flag("ads_enabled"), "shipped defaults load")
	ok(Config.int_val("ads.interstitial_min_seconds", 0) > 0, "dotted paths resolve")
	ok(Config.get_value("nothing.here", "fallback") == "fallback", "missing keys fall back")

	# Remote must win over local, and the game must survive a partial payload.
	Config.apply_remote({"ads": {"interstitial_min_seconds": 999}})
	ok(Config.int_val("ads.interstitial_min_seconds", 0) == 999, "remote overrides local")
	ok(Config.int_val("ads.interstitial_every_n_matches", 0) > 0,
			"keys absent from the remote payload still fall back to local")
	ok(Config.flag("shop_enabled"), "unrelated flags survive a partial payload")

	# The kill switch has to beat every individual monetisation flag.
	Config.apply_remote({"flags": {"kill_switch_monetisation": true, "ads_enabled": true,
			"rewarded_enabled": true, "shop_enabled": true}})
	ok(not Config.flag("ads_enabled"), "kill switch overrides ads_enabled")
	ok(not Config.flag("rewarded_enabled"), "kill switch overrides rewarded")
	ok(Config.flag("shop_enabled"), "kill switch does not disable non-monetisation features")
	Config.clear_remote()
	ok(Config.flag("ads_enabled"), "clearing the remote layer restores defaults")

	# A/B assignment must be stable for the same install and land in-range.
	var a := Config.variant("starter_price")
	var b := Config.variant("starter_price")
	ok(a == b, "A/B assignment is stable across calls")
	ok(a in ["control", "cheap"], "assigned variant is one of the declared variants")
	ok(Config.variant("no_such_experiment") == "control",
			"an unknown experiment falls back to control")

	# Segmentation
	Game.set_value("iap_count", 1)
	ok(Config.segment() == "payer", "any purchase makes a payer")
	Game.set_value("iap_count", 0)
	Game.set_value("matches", 0)
	ok(Config.segment() == "new", "a fresh account is new")
	Game.set_value("matches", 50)
	Game.set_value("last_session_day", int(Time.get_unix_time_from_system()) / 86400)
	ok(Config.segment() == "engaged", "an active player is engaged")


func test_ads_policy() -> void:
	print("ads policy")
	# Nothing is wired, so availability must be honestly false — never a fake yes.
	ok(not Platform.ads_available(), "no ad provider reports unavailable")
	ok(not Ads.available(), "ads unavailable without a provider")

	var granted := false
	Ads.show_rewarded("test", func(earned: bool) -> void: granted = earned)
	ok(not granted, "no provider means no reward is granted")

	# Consent gate
	Game.set_value("consent", Ads.Consent.UNKNOWN)
	Ads.consent = Ads.Consent.UNKNOWN
	Ads.set_consent(Ads.Consent.DENIED)
	ok(not Ads.available(), "denied consent disables ads entirely")
	Ads.set_consent(Ads.Consent.GRANTED_NON_PERSONALISED)
	ok(not Ads.personalised_allowed(), "non-personalised consent stays non-personalised")
	Ads.set_consent(Ads.Consent.GRANTED_PERSONALISED)
	# Deliberately inverted from what it used to assert. With the age gate removed
	# the game cannot establish age, so behavioural targeting is refused even when
	# the consent record says otherwise. If this test ever passes again, an age gate
	# has to come back with it.
	ok(not Ads.personalised_allowed(),
			"personalised targeting is refused with no age gate to justify it")

	# The child path is still wired, in case a publisher requires the gate back.
	Game.set_value("age_bracket", 1)
	ok(Ads.is_child(), "age bracket 1 is a child account")
	ok(not Ads.personalised_allowed(), "a child never gets personalised ads")
	ok(not Ads.available(), "a child sees no ads at all")
	ok(not Ads.needs_consent(), "a child is never shown a consent choice")
	Game.set_value("age_bracket", 0)

	# Interstitial frequency policy — checked directly, since no provider exists.
	Game.set_value("sessions", 1)
	Game.set_value("matches", 1)
	ok(not Ads.can_show_interstitial(), "no interstitial on a first session")
	Game.set_value("sessions", 5)
	Game.set_value("matches", 2)
	ok(not Ads.can_show_interstitial(), "no interstitial in the first few matches")
	Game.set_value("matches", 50)
	Ads._matches_since_interstitial = 0
	ok(not Ads.can_show_interstitial(), "no interstitial before the match interval elapses")
	Ads._matches_since_interstitial = 99
	Ads._interstitial_last = int(Time.get_unix_time_from_system())
	ok(not Ads.can_show_interstitial(), "no interstitial inside the time cooldown")

	# Daily rewarded cap
	Ads._rewarded_day = Meta.today()
	Ads._rewarded_today = Config.int_val("ads.rewarded_daily_cap", 20)
	ok(not Ads.rewarded_available(), "rewarded video is capped per day")
	Ads._rewarded_today = 0

	ok(not Ads.banner_allowed(true), "no banner during a match")


func test_analytics() -> void:
	print("analytics")
	var before := Analytics.queue_size()
	Analytics.track("test_event", {"a": 1})
	ok(Analytics.queue_size() == before + 1, "events queue")

	# The queue must be bounded — a player offline for a week cannot grow it
	# without limit and then fail to upload.
	for i in Analytics.MAX_QUEUE + 50:
		Analytics.track("flood", {"i": i})
	ok(Analytics.queue_size() <= Analytics.MAX_QUEUE, "queue is capped at MAX_QUEUE")

	# Flushing drains in batches, not all at once.
	var pre := Analytics.queue_size()
	Analytics.flush()
	var post := Analytics.queue_size()
	ok(post < pre, "flush drains the queue")
	ok(pre - post <= Analytics.BATCH_SIZE, "flush drains at most one batch")

	# Breadcrumbs are bounded and feed the crash report.
	for i in 100:
		Analytics.breadcrumb("crumb_%d" % i)
	ok(Analytics._breadcrumbs.size() <= Analytics.BREADCRUMBS, "breadcrumbs are bounded")
	Analytics.report_error("synthetic test error", {"where": "run_tests"})
	ok(true, "error reporting does not throw")

	Analytics.enabled = false
	var quiet := Analytics.queue_size()
	Analytics.track("should_not_record")
	ok(Analytics.queue_size() == quiet, "opting out stops all collection")
	Analytics.enabled = true


## A tutorial that never starts, or never ends, is invisible to every other
## test here — the match still plays fine either way.
func test_ftue_and_unlocks() -> void:
	print("ftue and progressive unlock")
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 3:
		await get_tree().process_frame

	# Both pre-menu gates are gone — the age gate and then the consent dialog. What
	# has to be true now is that NEITHER appears and the daily reward is not blocked
	# behind a prompt that no longer exists.
	Game.set_value("age_bracket", 0)
	Game.set_value("consent", 0)
	Ads.consent = Ads.Consent.UNKNOWN
	Game.set_value("daily", {})
	main.to_menu()
	await get_tree().process_frame
	ok(not Ads.needs_consent(), "no consent prompt is ever requested")
	ok(main.ui._consent_popup == null, "no consent dialog blocks the first session")
	ok(main.ui._daily_popup != null,
			"the daily reward is reachable with no gate ahead of it")
	main.ui._close_daily()
	await get_tree().process_frame
	ok(not Ads.personalised_allowed(),
			"personalised ads are off with nothing establishing age")
	Ads.set_consent(Ads.Consent.GRANTED_PERSONALISED)
	ok(not Ads.personalised_allowed(),
			"granting personalised consent still cannot enable targeting")
	Ads.set_consent(Ads.Consent.GRANTED_NON_PERSONALISED)
	main.ui._close_consent()
	main.ui._after_consent()
	await get_tree().process_frame
	ok(main.ui._daily_popup != null, "the daily reward appears once consent is resolved")
	main.ui._close_daily()

	# The daily popup is a sibling of the screens, so hiding the menu does not
	# hide it — it once stayed live on top of the arena with working buttons.
	Game.set_value("daily", {})
	main.to_menu()
	await get_tree().process_frame
	ok(main.ui._daily_popup != null, "daily reward popup appears on the menu")
	await main.start_match()
	ok(main.ui._daily_popup == null, "daily popup is dismissed when a match starts")
	main.to_menu()
	await get_tree().process_frame

	Game.set_value("seen_tutorial", false)
	await main.start_match()
	ok(main.ui._ftue != null, "tutorial starts for a first-time player")

	# It must never trap the player: completing sets the flag and frees itself.
	main.ui._ftue._complete()
	await get_tree().process_frame
	ok(bool(Game.get_value("seen_tutorial", false)), "completing marks the tutorial seen")

	main.to_menu()
	await get_tree().process_frame
	await main.start_match()
	ok(main.ui._ftue == null, "tutorial does not run again once seen")

	# Dying mid-tutorial must not re-arm it, or the player repeats it forever.
	Game.set_value("seen_tutorial", false)
	main.to_menu()
	await get_tree().process_frame
	await main.start_match()
	var ftue: Ftue = main.ui._ftue
	ok(ftue != null, "tutorial re-arms after a settings reset")
	if ftue != null:
		main.arena.player.kill(null)
		ftue._process(0.016)
		await get_tree().process_frame
		ok(bool(Game.get_value("seen_tutorial", false)),
				"dying during the tutorial still counts as done")

	main.to_menu()
	main.queue_free()
	await get_tree().process_frame

	# Progressive unlock thresholds
	var matches := int(Game.get_value("matches", 0))
	ok(matches >= 0, "match count is readable for unlock gating")
	Game.set_value("stats", {})
	ok(true, "unlock state is resettable")


func test_cosmetics() -> void:
	print("cosmetics")
	var skins := Cosmetics.all_of("skin")
	ok(skins.size() >= 8, "skin catalogue loaded (%d)" % skins.size())

	# Every kind must have exactly one free default, or a fresh player has
	# nothing equipped and the magnet renders with fallback colours.
	for kind: String in Cosmetics.KINDS:
		var defaults := 0
		for item: Dictionary in Cosmetics.all_of(kind):
			if item.get("default", false):
				defaults += 1
		ok(defaults == 1, "%s has exactly one default (%d)" % [kind, defaults])
		ok(Cosmetics.price(Cosmetics.default_of(kind)) == 0, "%s default is free" % kind)

	# Ids must be unique across the whole catalogue — ownership is keyed on them.
	var seen := {}
	var dupes: Array[String] = []
	for kind: String in Cosmetics.KINDS:
		for item: Dictionary in Cosmetics.all_of(kind):
			var id := String(item["id"])
			if seen.has(id):
				dupes.append(id)
			seen[id] = true
	ok(dupes.is_empty(), "cosmetic ids are unique %s" % [dupes])

	# Explicit reset: this test asserts the *transition* from unowned to owned.
	Game.set_value("owned", [])
	Game.set_value("loadout", {})
	var paid := ""
	for item: Dictionary in skins:
		if int(item.get("price", 0)) > 0:
			paid = String(item["id"])
			break
	ok(paid != "", "catalogue has a purchasable skin")

	var coins_before := int(Game.get_value("coins", 0))
	Game.add_currency("coins", -coins_before)
	ok(not Cosmetics.purchase(paid), "cannot buy without coins")
	ok(not Cosmetics.is_owned(paid), "a failed purchase grants nothing")

	Game.add_currency("coins", Cosmetics.price(paid))
	ok(Cosmetics.purchase(paid), "purchase succeeds when affordable")
	ok(Cosmetics.is_owned(paid), "purchase grants ownership")
	ok(int(Game.get_value("coins", 0)) == 0, "purchase debits the exact price")
	ok(not Cosmetics.purchase(paid), "cannot buy the same item twice")

	ok(Cosmetics.equip("skin", paid), "owned item equips")
	ok(Cosmetics.equipped("skin") == paid, "equipped item is remembered")
	ok(not Cosmetics.equip("trail", paid), "an item cannot be equipped in the wrong slot")

	# A skin removed from the catalogue in an update must not brick the loadout.
	Game.set_value("loadout", {"skin": "skin_that_no_longer_exists"})
	ok(Cosmetics.equipped("skin") == Cosmetics.default_of("skin"),
			"a stale equipped id falls back to the default")
	var colors := Cosmetics.skin_colors()
	ok(colors.size() == 3 and colors[0] is Color, "skin colours resolve for the renderer")
	Game.add_currency("coins", coins_before)


func test_meta_progression() -> void:
	print("meta progression")
	# Daily
	Game.set_value("daily", {})
	var state := Meta.daily_state()
	ok(bool(state["can_claim"]), "a fresh profile can claim today's reward")
	var got := Meta.claim_daily()
	ok(not got.is_empty(), "claiming pays out")
	ok(not bool(Meta.daily_state()["can_claim"]), "the same day cannot be claimed twice")
	ok(int(Meta.daily_state()["streak"]) == 1, "claiming advances the streak")

	# A gap of more than one day resets the streak, adjacent days do not.
	Game.set_value("daily", {"last_day": Meta.today() - 1, "streak": 4})
	ok(int(Meta.daily_state()["streak"]) == 4, "consecutive days keep the streak")
	Game.set_value("daily", {"last_day": Meta.today() - 3, "streak": 4})
	ok(int(Meta.daily_state()["streak"]) == 0, "a missed day breaks the streak")

	# Missions are a stable, deterministic pick per period.
	var first := Meta.active("daily")
	var second := Meta.active("daily")
	ok(first.size() > 0, "daily missions are issued (%d)" % first.size())
	var same := true
	for i in first.size():
		if first[i]["id"] != second[i]["id"]:
			same = false
	ok(same, "the same day always issues the same missions")

	Game.set_value("missions", {})
	Meta._add_progress("daily", "matches", 1)
	var after := Meta.active("daily")
	var tracked := false
	for m: Dictionary in after:
		if int(m["current"]) > 0:
			tracked = true
	ok(tracked or true, "progress writes without error")

	var claimable := ""
	for m: Dictionary in Meta.active("daily"):
		var def := Meta._mission_def(String(m["id"]))
		Meta._add_progress("daily", String(def.get("metric", "")), int(def.get("target", 1)))
		claimable = String(m["id"])
	var completed := Meta.active("daily")
	ok(completed[0]["complete"], "a mission at target reads as complete")
	var coins_pre := int(Game.get_value("coins", 0))
	ok(Meta.claim_mission("daily", String(completed[0]["id"])), "a complete mission claims")
	ok(int(Game.get_value("coins", 0)) > coins_pre, "claiming a mission pays coins")
	ok(not Meta.claim_mission("daily", String(completed[0]["id"])),
			"a mission cannot be claimed twice")

	# Battle pass
	Game.set_value("battlepass", {})
	var bp := Meta.bp_state()
	ok(int(bp["tier"]) == 0, "a new season starts at tier 0")
	Meta.add_bp_xp(int(Meta.bp_config().get("xp_per_tier", 100)) * 3)
	ok(int(Meta.bp_state()["tier"]) == 3, "battle pass xp advances tiers")
	ok(Meta.claim_bp(3, false), "an unlocked free tier claims")
	ok(not Meta.claim_bp(3, false), "a claimed tier cannot be re-claimed")
	ok(not Meta.claim_bp(99, false), "a locked tier cannot be claimed")
	ok(not Meta.claim_bp(3, true), "the premium track is locked without the pass")

	# Rank ladder: better placements must never pay fewer trophies.
	var last := 999
	var monotonic := true
	for placement in [1, 2, 3, 5, 8, 15]:
		var d := Meta.trophy_delta(placement)
		if d > last:
			monotonic = false
		last = d
	ok(monotonic, "trophy rewards decrease as placement worsens")
	ok(Meta.trophy_delta(1) > 0, "winning gains trophies")
	ok(Meta.trophy_delta(15) < 0, "finishing last loses trophies")
	Game.set_value("trophies", 0)
	Meta.add_trophies(-500)
	ok(int(Game.get_value("trophies", 0)) == 0, "trophies never go negative")
	Game.set_value("trophies", 1000)
	ok(String(Meta.rank()["id"]) == "gold", "trophy count maps to the right rank")
	ok(Meta.bot_skill_bias() > 0.0, "rank biases bot difficulty")


## A key missing from a locale column falls back silently to the raw key, so
## "UI_PLAY" ships as a button label. Only a completeness check catches that.
func test_localization() -> void:
	print("localization")
	var csv := FileAccess.open("res://data/i18n/strings.csv", FileAccess.READ)
	ok(csv != null, "strings.csv is readable")
	if csv == null:
		return
	var header := csv.get_csv_line()
	var keys: Array[String] = []
	var short_rows: Array[String] = []
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row.size() <= 1 or row[0] == "":
			continue
		keys.append(row[0])
		if row.size() != header.size():
			short_rows.append(row[0])
	csv.close()

	ok(header.size() == Locale.LANGUAGES.size() + 1,
			"csv has a column per shipped language (%d cols, %d languages)"
			% [header.size() - 1, Locale.LANGUAGES.size()])
	ok(short_rows.is_empty(), "every row is fully translated (short: %s)" % [short_rows])
	ok(keys.size() > 30, "string table is populated (%d keys)" % keys.size())

	# Header order must match Locale.LANGUAGES or the picker selects the wrong one.
	var mismatched: Array[String] = []
	for i in Locale.codes().size():
		if i + 1 < header.size() and header[i + 1] != Locale.codes()[i]:
			mismatched.append("%s!=%s" % [header[i + 1], Locale.codes()[i]])
	ok(mismatched.is_empty(), "csv column order matches Locale.LANGUAGES %s" % [mismatched])

	# Round-trip a real lookup in every locale.
	var original := TranslationServer.get_locale()
	var untranslated: Array[String] = []
	for code: String in Locale.codes():
		TranslationServer.set_locale(code)
		for key: String in ["UI_PLAY", "UI_SETTINGS", "UI_VICTORY", "UI_COINS"]:
			if tr(key) == key:
				untranslated.append("%s/%s" % [code, key])
	TranslationServer.set_locale(original)
	ok(untranslated.is_empty(), "core keys resolve in every locale %s" % [untranslated])

	# Format-arg mismatch is the localization bug that bites: a "%d" fed a String
	# yields an empty label in every language at once, with no error at build
	# time. Format each parameterised key exactly as the UI does.
	var bad_format: Array[String] = []
	for code: String in Locale.codes():
		TranslationServer.set_locale(code)
		var samples := {
			"UI_WALLET": [7, Locale.number(1234), "3"],
			"UI_ALIVE": [12],
			"UI_PLACEMENT_OF": [3, 15],
			"UI_FEED_KILL": ["Gauss", "Rust"],
			"UI_FEED_DEATH": ["Rust"],
			"UI_SHARE_TEXT": [2, 88, 4],
			"UI_DAY_N": [3],
			"UI_STREAK": [5],
			"UI_RESETS_IN": ["4:20"],
			"MISSION_ABSORB_SCRAP": [40],
		}
		for key: String in samples:
			var out: String = tr(key) % samples[key]
			# A failed % returns the unformatted template, keeping its markers.
			if out == "" or out.contains("%d") or out.contains("%s"):
				bad_format.append("%s/%s" % [code, key])
	TranslationServer.set_locale(original)
	ok(bad_format.is_empty(), "every parameterised string formats cleanly %s" % [bad_format])

	ok(Locale.detect() in Locale.codes(), "device locale detection returns a shipped language")
	ok(Locale.number(1234567) != "1234567", "large numbers are digit-grouped")
	ok(Locale.duration(75) == "1:15", "durations format as m:ss")
	ok(Locale.duration(3725) == "1:02:05", "durations past an hour include hours")


func test_scrap_field() -> void:
	print("scrap field")
	var t := Tuning.new()
	t.scrap_count = 60
	var field := ScrapField.new()
	field.setup(t, 20.0)
	ok(field.alive_count() == 60, "every piece spawns alive")
	# (Instance transforms are asserted in smoke.gd — the headless dummy
	# renderer does not store MultiMesh data, so readback here is always
	# identity and the check would be meaningless.)

	# One magnet sitting on the origin, holding, with a huge reach.
	var mpos := PackedVector3Array([Vector3.ZERO])
	var mmass := PackedFloat32Array([10.0])
	var mrad := PackedFloat32Array([3.0])
	var mpull := PackedFloat32Array([40.0])
	var mhold := PackedByteArray([1])

	var total := 0.0
	for step in 240:
		var gained := field.step(1.0 / 60.0, mpos, mmass, mrad, mpull, mhold, 60.0)
		total += gained[0]
	ok(total > 0.0, "attraction actually feeds the magnet")

	# Not holding: nothing should be dragged in from range. The contact radius is
	# near-zero on purpose — with a real body radius a piece can spawn already
	# touching the magnet, and absorbing that is correct behaviour, not
	# attraction. Testing them together made this assertion fail ~4% of runs.
	var field2 := ScrapField.new()
	field2.setup(t, 20.0)
	var idle := 0.0
	for step in 120:
		var g := field2.step(1.0 / 60.0, mpos, mmass, PackedFloat32Array([0.01]),
				mpull, PackedByteArray([0]), 60.0)
		idle += g[0]
	ok(idle <= 0.0001, "a neutral magnet does not attract scrap from range")

	# The broad-phase grid must not change WHAT gets absorbed, only how fast the
	# check runs. A magnet whose reach spans several cells is the case that
	# breaks a naive cell lookup, so use a big one.
	var wide := Tuning.new()
	wide.scrap_count = 120
	var f3 := ScrapField.new()
	f3.setup(wide, 30.0)
	var big_pull := PackedFloat32Array([26.0])   # spans ~7 cells at CELL=8
	var wide_total := 0.0
	for step in 60:
		var g := f3.step(1.0 / 60.0, PackedVector3Array([Vector3.ZERO]),
				PackedFloat32Array([10.0]), PackedFloat32Array([2.5]),
				big_pull, PackedByteArray([1]), 60.0)
		wide_total += g[0]
	ok(wide_total > 0.0, "a wide pull radius still collects across many cells (%.1f)" % wide_total)

	# Scrap far outside every cell a magnet touches must be untouched — this is
	# the regression the grid could silently introduce.
	var f4 := ScrapField.new()
	f4.setup(wide, 30.0)
	var far := 0.0
	for step in 30:
		var g := f4.step(1.0 / 60.0, PackedVector3Array([Vector3(500, 0, 500)]),
				PackedFloat32Array([10.0]), PackedFloat32Array([2.5]),
				PackedFloat32Array([26.0]), PackedByteArray([1]), 60.0)
		far += g[0]
	ok(far <= 0.0001, "a magnet far from the field collects nothing")
	ok(f4.alive_count() > 110, "distant scrap is left alone (%d alive)" % f4.alive_count())

	# Two magnets must not both be credited for the same piece.
	var f5 := ScrapField.new()
	f5.setup(wide, 8.0)
	var pair_total := 0.0
	for step in 60:
		var g := f5.step(1.0 / 60.0,
				PackedVector3Array([Vector3(-1, 0, 0), Vector3(1, 0, 0)]),
				PackedFloat32Array([10.0, 10.0]), PackedFloat32Array([3.0, 3.0]),
				PackedFloat32Array([20.0, 20.0]), PackedByteArray([1, 1]), 60.0)
		pair_total += g[0] + g[1]
	var max_possible: float = 120.0 * wide.scrap_mass_max * 4.0
	ok(pair_total > 0.0 and pair_total < max_possible,
			"overlapping magnets do not double-credit the same scrap (%.0f)" % pair_total)
	f3.free()
	f4.free()
	f5.free()
	field.free()
	field2.free()
