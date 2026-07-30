extends Node
## Daily rewards, missions, battle pass and the rank ladder.
##
## Listens to `Bus` for gameplay facts and counts them. Gameplay never knows
## missions exist — the arena emits "scrap absorbed", not "mission progress".
##
## All periods are UTC day indices. Local-time rollover lets a player re-claim a
## daily by changing timezone, and midnight-local resets are ambiguous anyway.

const PATH := "res://data/meta.json"
const DAY_SECONDS := 86400

var config: Dictionary = {}

# Counters for the match in progress, folded into missions when it ends.
var _run_scrap := 0.0
var _run_kills := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	config = parsed if parsed is Dictionary else {}
	if config.is_empty():
		push_error("meta.json missing or malformed — meta progression disabled")

	Bus.scrap_absorbed.connect(func(amount: float) -> void: _run_scrap += amount)
	Bus.player_eliminated_rival.connect(func() -> void: _run_kills += 1)
	Bus.match_started.connect(_on_match_started)
	Bus.match_ended.connect(_on_match_ended)
	_refresh_periods()


# --- time ------------------------------------------------------------------
static func today() -> int:
	return int(Time.get_unix_time_from_system()) / DAY_SECONDS


static func this_week() -> int:
	return today() / 7


## Seconds until the next UTC midnight, for "resets in" labels.
static func seconds_to_rollover() -> int:
	return DAY_SECONDS - (int(Time.get_unix_time_from_system()) % DAY_SECONDS)


# --- daily reward ----------------------------------------------------------
func daily_state() -> Dictionary:
	var d: Dictionary = Game.get_value("daily", {})
	var last := int(d.get("last_day", -1))
	var streak := int(d.get("streak", 0))
	var day := today()
	# A missed day breaks the streak; the same day means already claimed.
	if last >= 0 and day - last > 1:
		streak = 0
	var calendar: Array = config.get("daily_rewards", [])
	var slot: int = (streak % maxi(1, calendar.size()))
	return {
		"can_claim": day != last,
		"streak": streak,
		"slot": slot,
		"calendar": calendar,
		"next_in": seconds_to_rollover(),
	}


func claim_daily() -> Dictionary:
	var state := daily_state()
	if not state["can_claim"]:
		return {}
	var calendar: Array = state["calendar"]
	if calendar.is_empty():
		return {}
	var reward: Dictionary = calendar[int(state["slot"])]
	var currency := String(reward.get("currency", "coins"))
	var amount := int(reward.get("amount", 0))
	Game.add_currency(currency, amount, "daily_reward")
	Game.set_value("daily", {
		"last_day": today(),
		"streak": int(state["streak"]) + 1,
	})
	Audio.play("reward", 1.0, -6.0)
	Bus.reward_claimed.emit(currency, amount)
	return {"currency": currency, "amount": amount}


# --- missions --------------------------------------------------------------
## Deterministic per-period pick, so the same slots persist across restarts
## without having to store the chosen ids.
func _pick(scope: String, slots: int, period: int) -> Array:
	var pool: Array = []
	for m: Dictionary in config.get("missions", []):
		if String(m.get("scope", "")) == scope:
			pool.append(m)
	if pool.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [scope, period])
	var indices: Array[int] = []
	for i in pool.size():
		indices.append(i)
	# Fisher-Yates with a seeded RNG — shuffle() uses the global RNG and would
	# hand out different missions every launch.
	for i in range(indices.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := indices[i]
		indices[i] = indices[j]
		indices[j] = tmp
	var out: Array = []
	for i in mini(slots, indices.size()):
		out.append(pool[indices[i]])
	return out


func _state() -> Dictionary:
	var s: Variant = Game.get_value("missions", {})
	return s if s is Dictionary else {}


## Wipes progress for any period that has rolled over.
func _refresh_periods() -> void:
	var s := _state()
	var changed := false
	if int(s.get("day", -1)) != today():
		s["day"] = today()
		s["daily_progress"] = {}
		s["daily_claimed"] = []
		changed = true
	if int(s.get("week", -1)) != this_week():
		s["week"] = this_week()
		s["weekly_progress"] = {}
		s["weekly_claimed"] = []
		changed = true
	if changed:
		Game.set_value("missions", s)


func active(scope: String) -> Array:
	_refresh_periods()
	var s := _state()
	var period := today() if scope == "daily" else this_week()
	var list: Array = []
	if scope == "achievement":
		list = []
		for m: Dictionary in config.get("missions", []):
			if String(m.get("scope", "")) == "achievement":
				list.append(m)
	else:
		var slots := int(config.get(scope + "_slots", 3))
		list = _pick(scope, slots, period)

	var progress: Dictionary = s.get(_progress_key(scope), {})
	var claimed: Array = s.get(_claimed_key(scope), [])
	var out: Array = []
	for m: Dictionary in list:
		var id := String(m["id"])
		var current := int(progress.get(id, 0)) if scope != "achievement" \
				else _lifetime(String(m.get("metric", "")))
		var target := int(m.get("target", 1))
		out.append({
			"id": id,
			"name": _mission_name(String(m.get("name_key", "")), target),
			"current": mini(current, target),
			"target": target,
			"coins": int(m.get("coins", 0)),
			"bp_xp": int(m.get("bp_xp", 0)),
			"complete": current >= target,
			"claimed": claimed.has(id),
		})
	return out


## Not every mission name takes the target ("Finish top 3" has no placeholder),
## and applying % to one that does not corrupts the label.
func _mission_name(name_key: String, target: int) -> String:
	var raw := tr(name_key)
	return (raw % target) if raw.contains("%d") else raw


func _progress_key(scope: String) -> String:
	return "daily_progress" if scope == "daily" else "weekly_progress"


func _claimed_key(scope: String) -> String:
	return ("daily_claimed" if scope == "daily"
			else ("weekly_claimed" if scope == "weekly" else "achievement_claimed"))


func _lifetime(metric: String) -> int:
	match metric:
		"kills_total": return int(Game.get_value("kills", 0))
		"matches_total": return int(Game.get_value("matches", 0))
		"wins_total": return int(Game.get_value("wins", 0))
		"scrap_total": return int(Game.get_value("scrap_absorbed", 0))
	return 0


func claim_mission(scope: String, id: String) -> bool:
	for m: Dictionary in active(scope):
		if m["id"] != id or not m["complete"] or m["claimed"]:
			continue
		var s := _state()
		var claimed: Array = s.get(_claimed_key(scope), [])
		claimed.append(id)
		s[_claimed_key(scope)] = claimed
		Game.set_value("missions", s)
		Game.add_currency("coins", int(m["coins"]), "mission_" + scope)
		add_bp_xp(int(m["bp_xp"]))
		Audio.play("reward", 1.0, -6.0)
		Bus.mission_completed.emit(id)
		Bus.reward_claimed.emit("coins", int(m["coins"]))
		return true
	return false


func _add_progress(scope: String, metric: String, amount: int) -> void:
	if amount <= 0:
		return
	var s := _state()
	var key := _progress_key(scope)
	var progress: Dictionary = s.get(key, {})
	for m: Dictionary in active(scope):
		var def := _mission_def(String(m["id"]))
		if String(def.get("metric", "")) != metric:
			continue
		var id := String(m["id"])
		var before := int(progress.get(id, 0))
		var target := int(def.get("target", 1))
		if before >= target:
			continue
		progress[id] = before + amount
		Bus.mission_progress.emit(id, mini(progress[id], target), target)
	s[key] = progress
	Game.set_value("missions", s)


func _mission_def(id: String) -> Dictionary:
	for m: Dictionary in config.get("missions", []):
		if String(m.get("id", "")) == id:
			return m
	return {}


# --- match hooks -----------------------------------------------------------
func _on_match_started() -> void:
	_run_scrap = 0.0
	_run_kills = 0


func _on_match_ended(result: Dictionary) -> void:
	_refresh_periods()
	var placement := int(result.get("placement", 99))
	var mass := int(result.get("mass", 0.0))
	var scrap := int(_run_scrap)

	Game.set_value("scrap_absorbed", int(Game.get_value("scrap_absorbed", 0)) + scrap)

	for scope: String in ["daily", "weekly"]:
		_add_progress(scope, "scrap", scrap)
		_add_progress(scope, "kills", _run_kills)
		_add_progress(scope, "matches", 1)
		if placement == 1:
			_add_progress(scope, "wins", 1)
		if placement <= 3:
			_add_progress(scope, "top3", 1)
		# "Reach N mass in a match" is a high-water mark, not a running total.
		_set_high_water(scope, "mass", mass)

	add_bp_xp(10 + maxi(0, 16 - placement) * 2)
	add_trophies(trophy_delta(placement))


func _set_high_water(scope: String, metric: String, value: int) -> void:
	var s := _state()
	var key := _progress_key(scope)
	var progress: Dictionary = s.get(key, {})
	for m: Dictionary in active(scope):
		var def := _mission_def(String(m["id"]))
		if String(def.get("metric", "")) != metric:
			continue
		var id := String(m["id"])
		if value > int(progress.get(id, 0)):
			progress[id] = value
			Bus.mission_progress.emit(id, mini(value, int(def.get("target", 1))),
					int(def.get("target", 1)))
	s[key] = progress
	Game.set_value("missions", s)


# --- battle pass -----------------------------------------------------------
func bp_config() -> Dictionary:
	return config.get("battlepass", {})


## Seasons are numbered from the launch epoch, not from the Unix epoch.
func season_index() -> int:
	var cfg := bp_config()
	var length := maxi(1, int(cfg.get("season_length_days", 28)))
	return maxi(0, today() - int(cfg.get("epoch_day", 0))) / length + 1


func _bp_state() -> Dictionary:
	var b: Variant = Game.get_value("battlepass", {})
	var s: Dictionary = b if b is Dictionary else {}
	if int(s.get("season", -1)) != season_index():
		# Seasonal reset. Premium ownership does not carry across seasons.
		s = {"season": season_index(), "xp": 0, "claimed_free": [],
				"claimed_premium": [], "premium": false}
		Game.set_value("battlepass", s)
	return s


func add_bp_xp(amount: int) -> void:
	if amount <= 0:
		return
	var s := _bp_state()
	s["xp"] = int(s.get("xp", 0)) + amount
	Game.set_value("battlepass", s)


func bp_state() -> Dictionary:
	var s := _bp_state()
	var cfg := bp_config()
	var per := maxi(1, int(cfg.get("xp_per_tier", 100)))
	var tiers := int(cfg.get("tiers", 30))
	var xp := int(s.get("xp", 0))
	return {
		"season": season_index(),
		"xp": xp,
		"tier": mini(tiers, xp / per),
		"tiers": tiers,
		"progress": float(xp % per) / per,
		"premium": bool(s.get("premium", false)),
		"claimed_free": s.get("claimed_free", []),
		"claimed_premium": s.get("claimed_premium", []),
		"days_left": _season_days_left(),
	}


func _season_days_left() -> int:
	var cfg := bp_config()
	var length := maxi(1, int(cfg.get("season_length_days", 28)))
	var elapsed := maxi(0, today() - int(cfg.get("epoch_day", 0)))
	return length - (elapsed % length)


## What a tier hands out. Free track pays every `free_every` tiers.
func bp_reward(tier: int, premium: bool) -> Dictionary:
	var cfg := bp_config()
	var skins: Dictionary = cfg.get("skin_tiers", {})
	if premium and skins.has(str(tier)):
		return {"kind": "cosmetic", "id": String(skins[str(tier)])}
	if premium:
		var gem_tiers: Array = cfg.get("premium_gem_tiers", [])
		if gem_tiers.has(tier):
			return {"kind": "currency", "currency": "gems",
					"amount": int(cfg.get("premium_gem_amount", 15))}
		var pr: Dictionary = cfg.get("premium_reward", {})
		return {"kind": "currency", "currency": String(pr.get("currency", "coins")),
				"amount": int(pr.get("amount", 500))}
	if tier % maxi(1, int(cfg.get("free_every", 3))) != 0:
		return {}
	var fr: Dictionary = cfg.get("free_reward", {})
	return {"kind": "currency", "currency": String(fr.get("currency", "coins")),
			"amount": int(fr.get("amount", 250))}


func claim_bp(tier: int, premium: bool) -> bool:
	var state := bp_state()
	if tier > int(state["tier"]) or tier < 1:
		return false
	if premium and not state["premium"]:
		return false
	var key := "claimed_premium" if premium else "claimed_free"
	var s := _bp_state()
	var claimed: Array = s.get(key, [])
	if claimed.has(tier):
		return false
	var reward := bp_reward(tier, premium)
	if reward.is_empty():
		return false
	claimed.append(tier)
	s[key] = claimed
	Game.set_value("battlepass", s)

	if String(reward.get("kind", "")) == "cosmetic":
		Cosmetics.grant(String(reward["id"]))
	else:
		Game.add_currency(String(reward["currency"]), int(reward["amount"]),
				"battlepass_" + key)
		Bus.reward_claimed.emit(String(reward["currency"]), int(reward["amount"]))
	Audio.play("reward", 1.0, -6.0)
	return true


func unlock_premium() -> bool:
	var price := int(bp_config().get("premium_price_gems", 400))
	if not Game.spend("gems", price):
		return false
	var s := _bp_state()
	s["premium"] = true
	Game.set_value("battlepass", s)
	Game.log_transaction("battlepass_unlock", "gems", -price, "premium")
	return true


# --- rank ladder -----------------------------------------------------------
func trophy_delta(placement: int) -> int:
	var table: Dictionary = config.get("trophies_by_placement", {})
	var best := -12
	var best_key := 9999
	# Table keys are "at most this placement"; take the tightest matching bracket.
	for key: String in table:
		var threshold := int(key)
		if placement <= threshold and threshold < best_key:
			best_key = threshold
			best = int(table[key])
	return best


func add_trophies(delta: int) -> void:
	var now := maxi(0, int(Game.get_value("trophies", 0)) + delta)
	Game.set_value("trophies", now)


func rank() -> Dictionary:
	var trophies := int(Game.get_value("trophies", 0))
	var ranks: Array = config.get("ranks", [])
	var current: Dictionary = {"id": "bronze", "min": 0, "color": "#c07c42"}
	var next: Dictionary = {}
	for r: Dictionary in ranks:
		if trophies >= int(r.get("min", 0)):
			current = r
		elif next.is_empty():
			next = r
	return {
		"id": String(current.get("id", "bronze")),
		"color": Color(String(current.get("color", "#c07c42"))),
		"trophies": trophies,
		"next_at": int(next.get("min", 0)) if not next.is_empty() else 0,
	}


## Bot difficulty follows the ladder, so climbing actually means something.
func bot_skill_bias() -> float:
	var trophies := float(Game.get_value("trophies", 0))
	return clampf(trophies / 4000.0, 0.0, 1.0)


# --- rewarded boosts --------------------------------------------------------

## One spin per UTC day, and only when an ad can actually be shown.
func wheel_available() -> bool:
	return Config.flag("wheel_enabled") and Ads.rewarded_available() \
			and int(Game.get_value("wheel_day", 0)) != today()


## Weighted pick from the remote table, granted immediately. Marks the day BEFORE
## granting: a crash mid-grant costs the player one reward, whereas marking after
## would let a crash loop hand out unlimited ones.
func spin_wheel() -> Dictionary:
	if not wheel_available():
		return {}
	Game.set_value("wheel_day", today())
	var table: Array = Config.get_value("wheel.rewards", [])
	if table.is_empty():
		return {}
	var total := 0.0
	for r: Dictionary in table:
		total += float(r.get("weight", 1))
	var roll := randf() * total
	var pick: Dictionary = table[0]
	for r: Dictionary in table:
		roll -= float(r.get("weight", 1))
		if roll <= 0.0:
			pick = r
			break
	var kind := String(pick.get("kind", "coins"))
	var amount := int(pick.get("amount", 0))
	match kind:
		"coins", "gems":
			Game.add_currency(kind, amount, "wheel")
		"boost_mass":
			Game.set_value("boost_mass", true)
	Analytics.track("wheel_spin", {"kind": kind, "amount": amount})
	return {"kind": kind, "amount": amount}


## The skin trial lasts exactly one match. Cleared on record_match rather than on
## match start, so a player who backs out of a match keeps what they paid for.
func clear_trial() -> void:
	if String(Game.get_value("trial_skin", "")) != "":
		Game.set_value("trial_skin", "")
