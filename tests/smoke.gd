extends Node
## End-to-end match run: boots the real main scene, plays a short match through
## the real physics and bots, screenshots it, and asserts it reaches a result.
##   /Applications/Godot.app/Contents/MacOS/Godot res://tests/smoke.tscn -- --shot=/path/out.png
## Add --headless to skip the screenshot and just check the FSM.

const TIMEOUT := 40.0

var _main: Node
var _done := false
var _elapsed := 0.0
var _shot_path := ""
var _frames: Array[float] = []
var _magnet_count := 0
var _shot_at := 4.0
var _shot_taken := false
var _eliminations := 0
var _pre_fails := 0
var _started_ms := 0
var _matches_before := 0
var _trophies_before := 0
var _floor_style := -1


func _ready() -> void:
	# Fixed seed: spawn points, hazard placement and bot skill are all random,
	# and an unseeded run swings idle survival from 1.7s to 4.6s — which makes
	# the balance assertions below flaky instead of useful.
	seed(20260729)
	_started_ms = Time.get_ticks_msec()

	var real := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.substr(7)
		# Mid-match captures: at 4s the countdown has only just cleared, so
		# anything driven by player input is still idle and unverifiable.
		if arg.begins_with("--size="):
			var wh := arg.substr(7).split("x")
			if wh.size() == 2:
				DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
				get_viewport().size = Vector2i(int(wh[0]), int(wh[1]))
		if arg.begins_with("--shot-at="):
			_shot_at = float(arg.substr(10))
		elif arg == "--real":
			real = true
		elif arg.begins_with("--floor="):
			_floor_style = int(arg.substr(8))
		elif arg == "--ftue":
			Game.set_value("seen_tutorial", false)

	# Shipped tuning, compressed in time — same arena proportions and hazard
	# density as a real match, just a quarter of the length. `--real` plays a
	# full-length match with the shipped values untouched.
	if not real:
		var t: Tuning = Game.tuning.duplicate()
		t.match_duration = 25.0
		t.ring_shrink_delay = 3.0
		t.bot_count = 9
		t.ring_start_radius = 30.0
		t.ring_end_radius = 6.0
		t.countdown_time = 0.5
		t.scrap_count = 200
		Game.tuning = t

	Bus.match_ended.connect(_on_ended)
	Bus.magnet_eliminated.connect(func(_v: String, _k: String, _p: bool) -> void:
		_eliminations += 1)

	# Guarantee the daily missions can move: trophies start mid-ladder so the
	# trophy delta is measurable in both directions.
	Game.set_value("trophies", 500)
	_matches_before = int(Game.get_value("matches", 0))
	_trophies_before = int(Game.get_value("trophies", 0))

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await _main.start_match()
	print("match started: %d magnets" % _main.arena.magnets.size())
	if _floor_style >= 0:
		# Swap in the candidate shader so options can be compared in one scene.
		var m: ShaderMaterial = _main.arena._floor_mat
		m.shader = load("res://shaders/floor_options.gdshader")
		m.set_shader_parameter("style", _floor_style)
		m.set_shader_parameter("base_color", Color(0.145, 0.145, 0.152))
		m.set_shader_parameter("grid_color", Color(0.404, 0.404, 0.420))
		m.set_shader_parameter("danger_color", Color(0.360, 0.145, 0.125))
		m.set_shader_parameter("grid_size", 3.2)
		m.set_shader_parameter("ring_radius", _main.arena.ring_radius)

	# Checked before a single physics frame runs: the arena renders throughout
	# the countdown, and scrap whose instance transform was never written sits
	# stacked on the origin at identity, so the arena looks empty.
	# Scrap is spread across one MultiMesh per shape now, so walk them all.
	# The dummy renderer does not store MultiMesh transforms, so this reads 0 for
	# every instance no matter what the game did — a guaranteed false failure under
	# --headless. CI ran exactly this and would have been red from the first commit;
	# nobody saw it because there is no remote yet. Skip explicitly and say so, so
	# the check is visibly not-run rather than silently dropped.
	if DisplayServer.get_name() == "headless":
		print("scrap position check SKIPPED (dummy renderer stores no transforms)")
	else:
		var spread := 0.0
		for mm: MultiMesh in _main.arena.scrap._meshes:
			for i in mini(mm.instance_count, 100):
				spread = maxf(spread, mm.get_instance_transform(i).origin.length())
		if spread <= 1.0:
			printerr("FAIL  scrap unpositioned before first step (max origin %.2f)" % spread)
			_pre_fails += 1
		else:
			print("scrap positioned at spawn (max origin %.1f)" % spread)


func _process(_delta: float) -> void:
	# Wall clock, not accumulated delta: hitstop scales Engine.time_scale down,
	# so a delta-based clock falls behind and the match can end before the
	# screenshot ever fires.
	_elapsed = float(Time.get_ticks_msec() - _started_ms) / 1000.0
	# Skip the first second: shader compilation and scene build are not gameplay.
	if _elapsed > 1.0:
		_frames.append(_delta)
		if _main != null and is_instance_valid(_main) and _main.arena != null:
			_magnet_count = _main.arena.magnets.size()
	if not _shot_taken and _shot_path != "" and _elapsed > _shot_at:
		_shot_taken = true
		_capture()
	if not _done and _elapsed > TIMEOUT:
		_done = true
		printerr("FAIL  match never reached a result in %ds" % TIMEOUT)
		get_tree().quit(1)


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("screenshot %s -> %s" % ["ok" if err == OK else "FAILED", _shot_path])


## Revive is the one feature whose failure mode is "the match never ends" — the
## arena deliberately holds in AWAITING_REVIVE until it is answered. Every exit has
## to be proven, or a dropped callback strands the player in a frozen arena.
func _check_revive() -> void:
	var a: Arena = _main.arena
	if a == null or a.player == null:
		printerr("FAIL  revive: no arena/player"); _pre_fails += 1
		return
	# Reviving resets placement, mass and alive. Snapshot and restore, so this
	# check cannot corrupt the result assertions standing next to it — it caught
	# itself doing exactly that ("bad placement 0 for YOU").
	var was_placement := a.player.placement
	var was_mass := a.player.mass
	var was_alive := a.player.alive
	var was_state := a.state

	# Declining must finish the match exactly as dying used to.
	a._finished_emitted = false
	a.state = Arena.State.AWAITING_REVIVE
	a.decline_revive()
	if a.state != Arena.State.FINISHED:
		printerr("FAIL  revive: declining did not finish the match"); _pre_fails += 1
	else:
		print("revive: declining ends the match")

	# Accepting must bring the player back, alive, inside the ring.
	# Set `alive` directly rather than calling kill(): kill() emits `eliminated`,
	# which re-enters the arena's own handler and finishes the match out from under
	# the test. What is under test is revive_player, not the death path.
	a._finished_emitted = false
	a.player.alive = false
	a.state = Arena.State.AWAITING_REVIVE
	a.revive_player()
	var ok_alive: bool = a.player.alive and a.state == Arena.State.PLAYING
	var inside: bool = Vector2(a.player.global_position.x,
			a.player.global_position.z).length() < a.ring_radius
	if not ok_alive or not inside:
		printerr("FAIL  revive: player not restored inside the ring (alive=%s state=%d)"
				% [a.player.alive, a.state]); _pre_fails += 1
	else:
		print("revive: player restored at %.1f mass inside the ring" % a.player.mass)

	# Once per match. A second offer must not be made.
	if not a._revive_used:
		printerr("FAIL  revive: not marked as used"); _pre_fails += 1
	else:
		print("revive: marked used, so it cannot be taken twice")

	a.player.placement = was_placement
	a.player.mass = was_mass
	a.player.alive = was_alive
	a.state = was_state


func _on_ended(result: Dictionary) -> void:
	if _done:
		return
	_done = true
	print("match ended: %s" % result)
	# The player is bot-driven here and dies whenever it dies, so a capture timed
	# from match start is a race: a request for a shot at 6s silently produced no
	# file on any run where the player was eliminated at 4s. Take the pending shot
	# before quitting so every run that asks for one gets one.
	if _shot_path != "" and not _shot_taken:
		_shot_taken = true
		print("shot deadline missed (match ended at %.1fs) - capturing now" % _elapsed)
		await _capture()

	_check_revive()
	var fails := _pre_fails
	var placement := int(result.get("placement", 0))
	if placement < 1 or placement > int(result.get("total", 0)):
		printerr("FAIL  placement %d outside 1..%d" % [placement, result.get("total", 0)])
		fails += 1
	if float(result.get("mass", -1.0)) < 0.0:
		printerr("FAIL  negative final mass")
		fails += 1
	if int(result.get("coins_earned", -1)) < 0:
		printerr("FAIL  negative coin payout")
		fails += 1
	if _eliminations < 1:
		printerr("FAIL  no eliminations in a shrinking ring — pressure is broken")
		fails += 1
	# The player never touches the controls here, so this is the worst case.
	# Two different deaths, two different bugs: dying at the mass floor means
	# drain is too strong, dying at high mass means you were launched out of
	# the ring — legitimate, but not within a second of the gun.
	var survived := float(result.get("survived", 0.0))
	var final_mass := float(result.get("mass", 0.0))
	var drained := final_mass <= Game.tuning.min_mass + 0.5
	# Floor lowered from 3.0s to 2.0s deliberately, not to make a failure go away.
	# It encoded the ORIGINAL balance, where an idle player lasted ~3.5s — which the
	# player reported as "takes wayyyy too long to kill someone". Kills are meant to
	# be faster now, and 2.3s for a magnet that never touches the controls while
	# being actively eaten is the intended cost. The check still earns its place: it
	# catches drain that kills in well under a second, which is a real bug and is
	# what it was written for.
	if drained and survived < 2.0:
		printerr("FAIL  idle player drained to death in %.1fs — drain is too lethal" % survived)
		fails += 1
	if not drained and survived < 1.5:
		printerr("FAIL  idle player launched out in %.1fs at mass %.1f — spawns are too near the edge"
				% [survived, final_mass])
		fails += 1
	# An arena that wipes the lobby in the first seconds is a tuning bug that
	# would otherwise ship silently: the FSM still "works", the game does not.
	if _eliminations >= int(result.get("total", 0)) - 1 and float(result.get("survived", 0.0)) < 5.0:
		printerr("FAIL  lobby wiped in %.1fs — hazard/ring pressure is lethal on spawn"
				% result.get("survived", 0.0))
		fails += 1
	# Every magnet must end with a unique, assigned placement.
	# The meta layer must actually receive the match. It listens on Bus, so a
	# renamed signal or a missing emit breaks progression silently.
	if int(Game.get_value("matches", 0)) <= _matches_before:
		printerr("FAIL  match not recorded in the profile")
		fails += 1
	var mission_moved := false
	for m: Dictionary in Meta.active("daily"):
		if int(m["current"]) > 0:
			mission_moved = true
	if not mission_moved:
		printerr("FAIL  no daily mission progressed from a full match — the meta "
				+ "layer is not hearing gameplay events")
		fails += 1
	if int(Game.get_value("trophies", 0)) == _trophies_before:
		printerr("FAIL  placement awarded no trophy change")
		fails += 1

	var seen := {}
	for m: Magnet in _main.arena.magnets:
		if m.placement < 1 or seen.has(m.placement):
			printerr("FAIL  bad placement %d for %s" % [m.placement, m.display_name])
			fails += 1
		seen[m.placement] = true

	# Frame time, so "optimise it" has a number attached instead of a feeling.
	# A sorted percentile rather than a mean: the mean hides exactly the hitches a
	# player notices.
	_frames.sort()
	if not _frames.is_empty():
		var p50: float = _frames[_frames.size() / 2]
		var p99: float = _frames[mini(_frames.size() - 1, int(_frames.size() * 0.99))]
		print("smoke: frame ms p50=%.2f p99=%.2f over %d frames, %d magnets"
				% [p50 * 1000.0, p99 * 1000.0, _frames.size(), _magnet_count])
	print("\nsmoke: %d eliminations, %d failures" % [_eliminations, fails])
	get_tree().quit(1 if fails > 0 else 0)
