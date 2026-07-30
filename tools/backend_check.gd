extends Node
## Live round-trip against the configured backend. This is the check that could
## never run before: every Supabase test in the suite covers the UNCONFIGURED
## path, because the repo has no credentials and never will.
##
##   Godot --headless res://tools/backend_check.tscn

var _fails := 0


func ok(cond: bool, msg: String) -> void:
	if cond:
		print("  pass  %s" % msg)
	else:
		_fails += 1
		printerr("  FAIL  %s" % msg)


func _ready() -> void:
	print("backend round-trip")
	var sb := SupabaseProvider.new(self)
	ok(sb.available(), "provider is configured (%s)" % sb.url)
	if not sb.available():
		_done()
		return

	# 1. anonymous sign-in
	var signed := [false]
	sb.sign_in(true, func(good: bool, id: String, _n: String) -> void:
		signed[0] = good and id != "")
	await _settle()
	ok(signed[0], "anonymous sign-in returned a user id (%s)" % sb.user_id.left(8))
	if not signed[0]:
		_done()
		return

	# 2. cloud save write then read, with a value that could not be a leftover
	var marker := "check-%d" % Time.get_ticks_usec()
	var saved := [false]
	sb.save_cloud({"marker": marker, "coins": 1234}, func(good: bool) -> void:
		saved[0] = good)
	await _settle()
	ok(saved[0], "cloud save accepted")

	var loaded := [{}]
	sb.load_cloud(func(d: Dictionary) -> void: loaded[0] = d)
	await _settle()
	ok(String((loaded[0] as Dictionary).get("marker", "")) == marker,
			"cloud save round-tripped the exact payload")

	# 3. score submit + board read
	var submitted := [false]
	sb.submit_score(4321, func(good: bool) -> void: submitted[0] = good)
	await _settle()
	ok(submitted[0], "score submitted through the SECURITY DEFINER function")

	var board := [[]]
	sb.fetch_board(0, func(rows: Array) -> void: board[0] = rows)
	await _settle()
	ok((board[0] as Array).size() > 0, "leaderboard returned %d row(s)"
			% (board[0] as Array).size())

	# 4. the property the whole security model rests on: a lower score must not
	#    overwrite a higher one, even though the client asked it to.
	var again := [false]
	sb.submit_score(11, func(good: bool) -> void: again[0] = good)
	await _settle()
	var after := [[]]
	sb.fetch_board(0, func(rows: Array) -> void: after[0] = rows)
	await _settle()
	var best := 0
	for r: Dictionary in after[0] as Array:
		best = maxi(best, int(r.get("score", 0)))
	ok(best >= 4321, "a lower submission did not overwrite the best score (%d)" % best)

	_done()


func _settle() -> void:
	# HTTPRequest is async; give it real wall time rather than a frame count.
	await get_tree().create_timer(2.5).timeout


func _done() -> void:
	print("backend round-trip: %d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
