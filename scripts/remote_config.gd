extends Node
## Remote config, feature flags, A/B assignment and player segmentation.
##
## Layering: `data/remote_config.json` (shipped defaults) <- cached remote <-
## live remote. The game must boot and play correctly with only the first layer,
## so nothing here may be required to exist.
##
## The provider is Null today (no vendor chosen). It caches to disk and merges
## exactly as a real one would, so swapping in Firebase/PlayFab touches only
## `_fetch()`.

const DEFAULTS_PATH := "res://data/remote_config.json"
const CACHE_PATH := "user://remote_config.json"

signal refreshed

var _defaults: Dictionary = {}
var _remote: Dictionary = {}
## Experiment exposures logged this session, so each is reported once.
var _exposed: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULTS_PATH))
	_defaults = parsed if parsed is Dictionary else {}
	if _defaults.is_empty():
		push_error("remote_config.json missing — running on hard-coded fallbacks")
	_load_cache()
	refresh()


# --- layered lookup --------------------------------------------------------
## Dotted path, e.g. `get_value("ads.interstitial_min_seconds", 60)`.
func get_value(path: String, fallback: Variant = null) -> Variant:
	var remote: Variant = _dig(_remote, path)
	if remote != null:
		return remote
	var local: Variant = _dig(_defaults, path)
	return local if local != null else fallback


func _dig(source: Dictionary, path: String) -> Variant:
	var node: Variant = source
	for part in path.split("."):
		if node is not Dictionary or not node.has(part):
			return null
		node = node[part]
	return node


func flag(name: String) -> bool:
	# A monetisation kill switch has to beat every individual flag — that is the
	# whole point of having one.
	if name.begins_with("ads_") or name.begins_with("interstitial") \
			or name.begins_with("rewarded") or name.begins_with("banner") \
			or name.begins_with("iap"):
		if bool(get_value("flags.kill_switch_monetisation", false)):
			return false
	return bool(get_value("flags." + name, false))


func num(path: String, fallback: float) -> float:
	return float(get_value(path, fallback))


func int_val(path: String, fallback: int) -> int:
	return int(get_value(path, fallback))


# --- A/B testing -----------------------------------------------------------
## Stable per-install assignment. Hashing the install id means the same player
## always lands in the same bucket without the server telling us.
func variant(experiment: String) -> String:
	var cfg: Variant = get_value("experiments." + experiment, null)
	if cfg is not Dictionary:
		return "control"
	var variants: Array = cfg.get("variants", [])
	if variants.is_empty():
		return "control"
	var weights: Array = cfg.get("weights", [])
	var total := 0
	for w: int in weights:
		total += w
	if total <= 0 or weights.size() != variants.size():
		return String(variants[0])

	var bucket: int = abs(hash("%s:%s" % [Game.install_id(), experiment])) % total
	var running := 0
	for i in variants.size():
		running += int(weights[i])
		if bucket < running:
			var chosen := String(variants[i])
			_log_exposure(experiment, chosen)
			return chosen
	return String(variants[0])


func _log_exposure(experiment: String, chosen: String) -> void:
	if _exposed.get(experiment, "") == chosen:
		return
	_exposed[experiment] = chosen
	Analytics.track("experiment_exposure", {"experiment": experiment, "variant": chosen})


# --- segmentation ----------------------------------------------------------
## Cohort used to pick offers and tune difficulty. Deliberately coarse — finer
## segments need real retention data, which does not exist yet.
func segment() -> String:
	if int(Game.get_value("iap_count", 0)) > 0:
		return "payer"
	var matches := int(Game.get_value("matches", 0))
	var days_away := Game.days_since_last_session()
	if days_away >= int_val("offers.churn_offer_after_days_away", 3) and matches > 0:
		return "churn_risk"
	if matches < 3:
		return "new"
	return "engaged"


# --- provider --------------------------------------------------------------
## Null provider: no vendor is configured, so there is nothing to fetch and the
## cached/default layers stand. A real provider replaces the body of this
## function and emits `refreshed` when the payload lands.
func refresh() -> void:
	refreshed.emit()


## Discards the cached remote layer and falls back to shipped defaults. Needed
## because a bad payload is written to disk and reloaded on every launch — there
## has to be a way back that does not involve reinstalling.
func clear_remote() -> void:
	_remote = {}
	if FileAccess.file_exists(CACHE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE_PATH))
	refreshed.emit()


func apply_remote(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	_remote = payload
	_save_cache()
	refreshed.emit()
	Analytics.track("remote_config_applied", {"keys": payload.size()})


func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE_PATH))
	if parsed is Dictionary:
		_remote = parsed


func _save_cache() -> void:
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_remote))
		f.close()
