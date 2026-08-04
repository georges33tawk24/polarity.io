extends Node
## App-level state: the tuning resource, the player profile, and save/load.

const SAVE_PATH := "user://profile.json"
const BACKUP_PATH := "user://profile.bak.json"
const SAVE_VERSION := 3

var tuning: Tuning
var profile: Dictionary = {}
## Result of the most recent match, read by the results screen.
var last_result: Dictionary = {}

var _dirty := false
var _save_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	tuning = load("res://data/default_tuning.tres") as Tuning
	if tuning == null:
		push_warning("default_tuning.tres missing — falling back to script defaults")
		tuning = Tuning.new()
	profile = _load()
	_apply_audio_settings()
	# First launch follows the device language; after that the saved choice wins.
	if String(profile.get("locale", "")) == "":
		profile["locale"] = Locale.detect()
		mark_dirty()
	Locale.apply(String(profile["locale"]))
	_begin_session()


## Stable per-install identity for A/B bucketing and analytics. Not tied to any
## account and never sent anywhere by the shipped (Null) providers.
func install_id() -> String:
	var id := String(profile.get("install_id", ""))
	if id == "":
		id = "%d-%d" % [Time.get_unix_time_from_system(), randi()]
		profile["install_id"] = id
		mark_dirty()
	return id


func _begin_session() -> void:
	install_id()
	profile["sessions"] = int(profile.get("sessions", 0)) + 1
	profile["last_session_day"] = int(Time.get_unix_time_from_system()) / 86400
	mark_dirty()


## Whole days since the previous session, for churn segmentation.
func days_since_last_session() -> int:
	var last := int(profile.get("last_session_day", 0))
	if last <= 0:
		return 0
	return maxi(0, int(Time.get_unix_time_from_system()) / 86400 - last)


func _process(delta: float) -> void:
	# Coalesce writes: currency changes several times a match, we write once.
	if _dirty:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_flush()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED:
			_flush()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			# Required on web: browsers suspend audio on a hidden tab and Godot
			# keeps mixing into a dead context otherwise.
			AudioServer.set_bus_mute(0, true)
			_flush()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			AudioServer.set_bus_mute(0, false)


# --- profile ---------------------------------------------------------------
## ONE source of truth for profile shape. `migrate()` used to carry its own copy
## of this dict and the two drifted every time a field was added.
static func defaults() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"name": "",
		"coins": 0,
		"gems": 0,
		"xp": 0,
		"level": 1,
		"trophies": 0,
		"best_mass": 0.0,
		"best_survived": 0.0,
		"best_placement": 0,
		"matches": 0,
		"wins": 0,
		"kills": 0,
		"scrap_absorbed": 0,
		"owned": [],
		"loadout": {},
		"music": 0.6,
		"sfx": 0.85,
		"haptics": true,
		"haptics_level": "light",
		"joystick": true,
		"show_fps": false,
		"reduced_motion": false,
		"colorblind": false,
		"quality": "auto",
		"locale": "",
		"ui_scale": 1.0,
		"seen_tutorial": false,
		"install_id": "",
		"sessions": 0,
		"last_session_day": 0,
		"consent": 0,
		"age_bracket": 0,
		# Rewarded boosts. All one-shot and consumed by the thing they affect, so a
		# crash between watching the ad and starting the match cannot lose them and
		# cannot duplicate them either.
		"boost_mass": false,
		"trial_skin": "",
		"wheel_day": 0,
		"iap_count": 0,
		"no_ads": false,
		"iap_owned": [],
		"offer": {},
		"saved_at": 0,
		"weekly_best": 0,
		"weekly_week": -1,
		"rewarded_day": -1,
		"rewarded_count": 0,
		"rated": false,
		"notifications": true,
		"referred_by": "",
		"left_handed": false,
		"control_scheme": "drag",
		"rate_prompt_day": 0,
		"daily": {},
		"missions": {},
		"battlepass": {},
		"stats": {},
	}


func get_value(key: String, fallback: Variant = null) -> Variant:
	return profile.get(key, fallback)


func set_value(key: String, value: Variant) -> void:
	if profile.get(key) == value:
		return
	profile[key] = value
	mark_dirty()
	Bus.profile_changed.emit()


func add_currency(key: String, amount: int, source := "unspecified") -> void:
	# Clamped at zero: a bug elsewhere must never produce a negative balance.
	profile[key] = maxi(0, int(profile.get(key, 0)) + amount)
	mark_dirty()
	log_transaction(source, key, amount, "")
	Bus.profile_changed.emit()


func spend(key: String, amount: int) -> bool:
	if amount < 0:
		return false
	var have := int(profile.get(key, 0))
	if have < amount:
		return false
	profile[key] = have - amount
	mark_dirty()
	Bus.profile_changed.emit()
	return true


## Every currency movement is recorded so sources and sinks can be audited
## (spec §4.3). Kept in memory and capped — AnalyticsService drains it.
var ledger: Array[Dictionary] = []

func log_transaction(source: String, currency: String, delta: int, item := "") -> void:
	if delta == 0:
		return
	ledger.append({
		"source": source, "currency": currency, "delta": delta, "item": item,
		"balance": int(profile.get(currency, 0)),
		"t": Time.get_unix_time_from_system(),
	})
	if ledger.size() > 200:
		ledger = ledger.slice(ledger.size() - 200)
	Bus.currency_changed.emit(currency, delta, source)


func add_xp(amount: int) -> void:
	profile["xp"] = maxi(0, int(profile.get("xp", 0)) + amount)
	var lvl := 1
	var need := 0
	while int(profile["xp"]) >= need + xp_for_level(lvl):
		need += xp_for_level(lvl)
		lvl += 1
	profile["level"] = lvl
	mark_dirty()
	Bus.profile_changed.emit()


func xp_for_level(level: int) -> int:
	return 100 + (level - 1) * 45


func player_name() -> String:
	var n := String(profile.get("name", "")).strip_edges()
	return n if n != "" else "YOU"


func mark_dirty() -> void:
	_dirty = true
	_save_timer = 1.0


# --- persistence -----------------------------------------------------------
func _flush() -> void:
	_dirty = false
	# Atomic-ish: keep the previous good file as a backup, then write fresh.
	if FileAccess.file_exists(SAVE_PATH):
		var old := FileAccess.get_file_as_string(SAVE_PATH)
		if old != "":
			var b := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
			if b:
				b.store_string(old)
				b.close()
	# Stamped on write so cloud merge can tell which side is newer.
	profile["saved_at"] = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("could not write save: %s" % FileAccess.get_open_error())
		return
	f.store_string(_seal(JSON.stringify(profile)))
	f.close()


func _load() -> Dictionary:
	for path in [SAVE_PATH, BACKUP_PATH]:
		var data := _read(path)
		if not data.is_empty():
			return migrate(data)
	return defaults()


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := _unseal(FileAccess.get_file_as_string(path))
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("corrupt save at %s — ignoring" % path)
	return {}


## --- encryption at rest -----------------------------------------------------
##
## Obfuscation, and named honestly as such. A local save on a device the player
## controls can never be *secure* — anyone determined enough owns the machine the
## key is on. What this does buy is that a casual player cannot open the file in a
## text editor and set coins to a million, which is the actual threat model for a
## single-player-ish game with no server (§4.13 puts authoritative validation
## behind a backend that does not exist yet).
##
## Deliberately NOT Godot's FileAccess.open_encrypted_with_pass: that throws on a
## wrong key, which would turn a corrupted byte into an unrecoverable save. This
## degrades to "unreadable, fall back to the backup" instead, which is what the
## corruption-tolerant loader already handles.
const SEAL_MAGIC := "P0LSEAL1:"

## Device-derived so a save cannot simply be copied between installs, mixed with a
## build constant so the key is not guessable from the device id alone.
static func _seal_key() -> PackedByteArray:
	var seed_text := "polarity/" + OS.get_unique_id() + "/v1"
	return seed_text.sha256_buffer()


static func _xor(bytes: PackedByteArray, key: PackedByteArray) -> PackedByteArray:
	var out := bytes.duplicate()
	var n := key.size()
	if n == 0:
		return out
	for i in out.size():
		out[i] = out[i] ^ key[i % n]
	return out


static func _seal(text: String) -> String:
	return SEAL_MAGIC + Marshalls.raw_to_base64(
			_xor(text.to_utf8_buffer(), _seal_key()))


## Accepts plaintext too, so a save written by an older build still loads. That
## one-way compatibility is why this can ship without a migration step.
static func _unseal(text: String) -> String:
	if not text.begins_with(SEAL_MAGIC):
		return text
	var raw := Marshalls.base64_to_raw(text.substr(SEAL_MAGIC.length()))
	return _xor(raw, _seal_key()).get_string_from_utf8()


## Fills in anything a newer build added, and upgrades old shapes.
## Static + pure so the test suite can hit it without booting the game.
static func migrate(data: Dictionary) -> Dictionary:
	var out := defaults()
	var version := int(data.get("version", 1))
	for key: String in out:
		if data.has(key):
			out[key] = data[key]
	if version < 2:
		# v1 stored a single "score"; fold it into best_mass and drop it.
		out["best_mass"] = maxf(float(out["best_mass"]), float(data.get("score", 0.0)))
	if version < 3:
		# v2 stored one equipped skin id; v3 uses a per-kind loadout dictionary.
		var old_skin := String(data.get("skin", ""))
		if old_skin != "" and out["loadout"] is Dictionary and not out["loadout"].has("skin"):
			out["loadout"]["skin"] = old_skin
	out["version"] = SAVE_VERSION
	# Sanity clamps — a hand-edited save must not produce a broken game.
	out["coins"] = maxi(0, int(out["coins"]))
	out["gems"] = maxi(0, int(out["gems"]))
	out["xp"] = maxi(0, int(out["xp"]))
	out["trophies"] = maxi(0, int(out["trophies"]))
	out["level"] = maxi(1, int(out["level"]))
	out["music"] = clampf(float(out["music"]), 0.0, 1.0)
	out["sfx"] = clampf(float(out["sfx"]), 0.0, 1.0)
	out["ui_scale"] = clampf(float(out["ui_scale"]), 0.75, 1.5)
	# Types must survive a corrupt or hand-edited file, or every consumer crashes.
	for key: String in ["owned", "iap_owned"]:
		if out[key] is not Array:
			out[key] = []
	for key: String in ["loadout", "daily", "missions", "battlepass", "stats", "offer"]:
		if out[key] is not Dictionary:
			out[key] = {}
	return out


func _apply_audio_settings() -> void:
	Audio.set_volume("Music", float(profile.get("music", 0.6)))
	Audio.set_volume("SFX", float(profile.get("sfx", 0.85)))


# --- match rewards ---------------------------------------------------------
## Converts a finished match into currency/XP and folds it into the profile.
func record_match(result: Dictionary) -> Dictionary:
	# A skin trial is worth exactly one match. Cleared on the way out rather than
	# on the way in, so backing out of a match does not burn it.
	Meta.clear_trial()
	var t := tuning
	var kills := int(result.get("kills", 0))
	var mass := float(result.get("mass", 0.0))
	var placement := int(result.get("placement", 99))
	var coins := int(kills * t.coins_per_kill + mass * t.coins_per_mass)
	var xp := int(kills * t.xp_per_kill + mass * 0.2)
	if placement == 1:
		coins += t.coins_win_bonus
		xp += t.xp_win_bonus
	# A live event scales the payout. Applied here, once, so every consumer — the
	# results screen, analytics, the ledger — sees the same number and nothing has
	# to remember to multiply.
	coins = int(round(coins * Meta.event_multiplier("coins")))
	xp = int(round(xp * Meta.event_multiplier("xp")))
	result["coins_earned"] = coins
	result["xp_earned"] = xp
	result["event"] = String(Meta.active_event().get("id", ""))

	profile["matches"] = int(profile.get("matches", 0)) + 1
	profile["kills"] = int(profile.get("kills", 0)) + kills
	profile["best_mass"] = maxf(float(profile.get("best_mass", 0.0)), mass)
	# Survival is half the score now that the round is gone, so it needs a best of
	# its own — best_mass alone cannot describe a long, careful run.
	profile["best_survived"] = maxf(float(profile.get("best_survived", 0.0)),
			float(result.get("survived", 0.0)))
	var best := int(profile.get("best_placement", 0))
	profile["best_placement"] = placement if best == 0 else mini(best, placement)
	if placement == 1:
		profile["wins"] = int(profile.get("wins", 0)) + 1
	add_currency("coins", coins)
	add_xp(xp)
	_flush()
	last_result = result
	return result
