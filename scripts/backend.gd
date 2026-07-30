extends Node
## Auth, cloud save and leaderboards.
##
## The spec lists these as three services, but they are all one vendor account
## in practice (Nakama / PlayFab / Firebase / SilentWolf). One autoload with one
## provider seam keeps the swap to a single object.
##
## The shipped provider is Local: it authenticates a guest, persists "cloud"
## saves to disk, and serves a plausible leaderboard built from the same name
## pool the bots use. That is honest — §7 already establishes the lobby is bots —
## and it means every screen has real data to render offline.
##
## The merge logic is deliberately NOT in the provider: conflict resolution is
## the part that loses player money when it is wrong, so it is pure, static and
## unit-tested.

const CLOUD_PATH := "user://cloud_save.json"
const BOARD_PATH := "user://leaderboard.json"

signal auth_changed(signed_in: bool)
signal sync_finished(ok: bool, merged: bool)
signal board_ready(scope: String, rows: Array)

enum Scope { GLOBAL, FRIENDS, WEEKLY, COUNTRY }

class Provider:
	## Calls back with (ok, account_id, display_name).
	func sign_in(guest: bool, cb: Callable) -> void:
		cb.call(true, "guest-local", "")
	func sign_out() -> void:
		pass
	## Calls back with the remote payload, or {} when there is none.
	func load_cloud(cb: Callable) -> void:
		cb.call({})
	func save_cloud(_payload: Dictionary, cb: Callable) -> void:
		cb.call(true)
	func submit_score(_score: int, cb: Callable) -> void:
		cb.call(true)
	func fetch_board(_scope: int, cb: Callable) -> void:
		cb.call([])
	func available() -> bool:
		return false


var provider := Provider.new()
var account_id := ""
var signed_in := false
var _syncing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	sign_in_guest()
	Bus.match_ended.connect(_on_match_ended)


# --- auth ------------------------------------------------------------------
## Guest sign-in is automatic and silent. Nothing is ever gated behind an
## account (spec §16: never block the first play session).
func sign_in_guest() -> void:
	provider.sign_in(true, func(ok: bool, id: String, _name: String) -> void:
		if not ok:
			return
		account_id = id if id != "" else Game.install_id()
		signed_in = true
		auth_changed.emit(true))


func sign_out() -> void:
	provider.sign_out()
	signed_in = false
	account_id = ""
	auth_changed.emit(false)


## GDPR erasure. Wipes every local trace, then signs back in as a fresh guest.
func delete_account() -> void:
	Analytics.track("account_delete")
	Analytics.flush()
	for path in [CLOUD_PATH, BOARD_PATH, Game.SAVE_PATH, Game.BACKUP_PATH,
			Analytics.QUEUE_PATH, Analytics.SINK_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Game.profile = Game.defaults()
	Game.profile["install_id"] = ""
	Game._flush()
	sign_out()
	sign_in_guest()
	Bus.profile_changed.emit()


## GDPR portability. Returns the full profile as pretty JSON for the player to
## export; contains no data we do not already hold locally.
func export_data() -> String:
	return JSON.stringify({
		"profile": Game.profile,
		"ledger": Game.ledger,
		"account_id": account_id,
	}, "  ")


# --- cloud save ------------------------------------------------------------
func sync(cb := Callable()) -> void:
	if _syncing or not Config.flag("cloud_save_enabled"):
		if cb.is_valid():
			cb.call(false)
		return
	_syncing = true
	provider.load_cloud(func(remote: Dictionary) -> void:
		var merged := false
		if not remote.is_empty():
			var result := merge_saves(Game.profile, remote)
			Game.profile = result
			merged = true
			Bus.profile_changed.emit()
		provider.save_cloud(Game.profile, func(ok: bool) -> void:
			_syncing = false
			sync_finished.emit(ok, merged)
			Analytics.track("cloud_sync", {"ok": ok, "merged": merged})
			if cb.is_valid():
				cb.call(ok)))


## Conflict resolution. Static and pure so it can be tested without a provider.
##
## Rules, in order of how much damage getting them wrong does:
##  - Currencies take the MAX of both sides. Summing double-credits every sync;
##    last-write-wins silently deletes money the player earned on another device.
##  - Entitlements and owned cosmetics UNION. A purchase must never disappear.
##  - Progress counters (best mass, kills, matches) take the max.
##  - Best placement takes the MIN, because 1 is better than 9.
##  - Everything else is last-write-wins on `saved_at`.
static func merge_saves(local: Dictionary, remote: Dictionary) -> Dictionary:
	var local_time := int(local.get("saved_at", 0))
	var remote_time := int(remote.get("saved_at", 0))
	# Start from whichever side is newer, then repair the fields where
	# last-write-wins would destroy something.
	var out: Dictionary = (remote if remote_time > local_time else local).duplicate(true)

	for key: String in ["coins", "gems", "xp", "trophies", "best_mass", "matches",
			"wins", "kills", "scrap_absorbed", "iap_count", "sessions", "level"]:
		out[key] = maxf(float(local.get(key, 0)), float(remote.get(key, 0)))
		if key != "best_mass":
			out[key] = int(out[key])

	# Best placement: 0 means "never placed", so it must not win a min().
	var lp := int(local.get("best_placement", 0))
	var rp := int(remote.get("best_placement", 0))
	if lp == 0:
		out["best_placement"] = rp
	elif rp == 0:
		out["best_placement"] = lp
	else:
		out["best_placement"] = mini(lp, rp)

	for key: String in ["owned", "iap_owned"]:
		var union: Array = []
		for source: Dictionary in [local, remote]:
			var list: Variant = source.get(key, [])
			if list is Array:
				for item: Variant in list:
					if not union.has(item):
						union.append(item)
		out[key] = union

	out["no_ads"] = bool(local.get("no_ads", false)) or bool(remote.get("no_ads", false))
	out["seen_tutorial"] = bool(local.get("seen_tutorial", false)) \
			or bool(remote.get("seen_tutorial", false))
	out["saved_at"] = maxi(local_time, remote_time)
	return out


# --- referral / deep links -------------------------------------------------
## Short, human-typeable code derived from the install id. Deterministic, so it
## never needs storing and survives a reinstall of the same profile.
func referral_code() -> String:
	const ALPHABET := "ACDEFGHJKLMNPQRTUVWXY3479"   # no O/0, I/1, S/5, B/8
	var h: int = abs(hash("ref:" + Game.install_id()))
	var out := ""
	for i in 6:
		out += ALPHABET[h % ALPHABET.length()]
		h /= ALPHABET.length()
	return out


func referral_link() -> String:
	return "https://example.com/polarity?ref=%s" % referral_code()


## Applies someone else's code. Returns false with a reason for the UI.
## Guards, in order: self-referral, double-claim, malformed input.
func apply_referral(code: String) -> Dictionary:
	var clean := code.strip_edges().to_upper()
	if clean.length() < 4:
		return {"ok": false, "reason": "invalid"}
	if clean == referral_code():
		# Without this, every player can refer themselves for free currency.
		return {"ok": false, "reason": "self"}
	if String(Game.get_value("referred_by", "")) != "":
		return {"ok": false, "reason": "already"}

	Game.set_value("referred_by", clean)
	var reward := Config.int_val("referral.invitee_coins", 500)
	Game.add_currency("coins", reward, "referral_invitee")
	Analytics.track("referral_applied", {"code": clean, "reward": reward})
	return {"ok": true, "reward": reward}


## Reads a referral code handed to us by a deep link or a web query string.
## Returns "" when there is none.
func pending_deep_link() -> String:
	# Web: ?ref=CODE on the page URL.
	if Platform.is_web():
		var url := _web_query_ref()
		if url != "":
			return url
	# Native: polarity://ref/CODE or --ref=CODE passed by the OS.
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--ref="):
			return arg.substr(6)
		if arg.begins_with("polarity://ref/"):
			return arg.substr(15)
	return ""


func _web_query_ref() -> String:
	# Reading location.search needs a JS bridge; without one there is nothing to
	# parse. Returning "" keeps every caller on the no-referral path.
	return ""


# --- leaderboards ----------------------------------------------------------
func submit(score: int) -> void:
	if not Config.flag("leaderboards_enabled"):
		return
	# Client-side sanity clamp. The server must re-check this — a client can
	# always lie, so this only stops honest bugs (spec §4.13).
	if score < 0 or score > 100000:
		Analytics.track("score_rejected", {"score": score})
		return
	provider.submit_score(score, func(_ok: bool) -> void: pass)
	_record_local(score)


func fetch(scope: Scope) -> void:
	provider.fetch_board(int(scope), func(rows: Array) -> void:
		if rows.is_empty():
			rows = _local_board(scope)
		board_ready.emit(_scope_name(scope), rows))


func _scope_name(scope: Scope) -> String:
	return ["global", "friends", "weekly", "country"][int(scope)]


func _on_match_ended(result: Dictionary) -> void:
	submit(int(result.get("mass", 0.0)))


## Local board. Seeded from the bot name pool so it is consistent run to run,
## with the player's real best score inserted at its true rank.
func _local_board(scope: Scope) -> Array:
	# Guarded: parsing a missing file yields "" and JSON.parse_string logs an
	# error for it, which buries real failures in noise.
	var saved: Dictionary = {}
	if FileAccess.file_exists(BOARD_PATH):
		var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOARD_PATH))
		if stored is Dictionary:
			saved = stored
	var key := _scope_name(scope)
	var rows: Array = saved.get(key, [])

	if rows.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("board:%s:%d" % [key, Meta.this_week() if scope == Scope.WEEKLY else 0])
		# Sample WITHOUT replacement — picking by random index put "Gauss" on the
		# board three times, which immediately reads as fake.
		var names: Array = Arena.BOT_NAMES.duplicate()
		for i in range(names.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: Variant = names[i]
			names[i] = names[j]
			names[j] = tmp
		var size: int = 20 if scope != Scope.FRIENDS else 8
		var top: float = 320.0 if scope != Scope.WEEKLY else 180.0
		for i in mini(size, names.size()):
			rows.append({
				"name": String(names[i]),
				"score": int(top * pow(0.93, i) + rng.randf_range(-6.0, 6.0)),
			})
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["score"]) > int(b["score"]))
		saved[key] = rows
		var f := FileAccess.open(BOARD_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(saved))
			f.close()

	var out := rows.duplicate(true)
	var mine := int(Game.get_value("best_mass", 0.0))
	if scope == Scope.WEEKLY:
		mine = int(Game.get_value("weekly_best", 0))
	out.append({"name": Game.player_name(), "score": mine, "is_player": true})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"]))
	for i in out.size():
		out[i]["rank"] = i + 1
	return out


func _record_local(score: int) -> void:
	# Weekly best resets with the mission week, so the weekly board means
	# something rather than mirroring the all-time board.
	var week := Meta.this_week()
	if int(Game.get_value("weekly_week", -1)) != week:
		Game.set_value("weekly_week", week)
		Game.set_value("weekly_best", 0)
	if score > int(Game.get_value("weekly_best", 0)):
		Game.set_value("weekly_best", score)
