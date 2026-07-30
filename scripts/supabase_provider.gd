class_name SupabaseProvider
extends BackendProvider
## Backend.Provider backed by Supabase.
##
## Chosen because the seam is already HTTP-shaped and Supabase is a REST API over
## Postgres, so this is `HTTPRequest` and nothing else — no native plugin, which
## matters because the same build has to run on Web where plugins do not exist.
##
## ## Credentials
##
## The URL and anon key live in `user://supabase.cfg` (or `res://supabase.cfg`
## bundled at export), NEVER in source. See `supabase.cfg.example`.
##
## The **anon key is public by design** — it ships inside every client of every
## Supabase app and is safe to embed. What makes that safe is Row Level Security:
## the key alone grants nothing, and every policy checks `auth.uid()`. The
## `service_role` key is the actual secret and must never appear in a client, in
## this repo, or in a chat window.
##
## ## Auth
##
## Anonymous sign-in, so cloud save works before a player has an account and
## nothing gates the first session (§16). Upgrading an anonymous user to Google or
## Apple later keeps the same `auth.uid()`, so saves carry over — that is the
## reason to use Supabase anonymous auth rather than a self-invented guest id.

const CFG_USER := "user://supabase.cfg"
const CFG_RES := "res://supabase.cfg"
const TIMEOUT := 12.0

var url := ""
var anon_key := ""
var access_token := ""
var refresh_token := ""
var user_id := ""

## Set by Backend so HTTPRequest nodes have somewhere to live.
var host: Node = null

var _configured := false


func _init(host_node: Node = null) -> void:
	host = host_node
	_load_config()


## Reads credentials from disk. Deliberately tolerant: a missing or half-filled
## config means "not configured", which makes `available()` false and leaves the
## game on the local provider. A backend that is misconfigured must degrade to
## offline, never to a crash or to silent data loss.
func _load_config() -> void:
	for path in [CFG_USER, CFG_RES]:
		if not FileAccess.file_exists(path):
			continue
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK:
			push_warning("supabase: %s is unreadable" % path)
			continue
		url = String(cfg.get_value("supabase", "url", "")).rstrip("/")
		anon_key = String(cfg.get_value("supabase", "anon_key", ""))
		break
	_configured = url.begins_with("http") and anon_key.length() > 20
	if not _configured and (url != "" or anon_key != ""):
		push_warning("supabase: config present but incomplete — staying offline")


func available() -> bool:
	return _configured


# --- transport --------------------------------------------------------------

## One request. Every call goes through here so headers, auth and error handling
## cannot drift between endpoints.
func _request(method: int, path: String, body: Variant, cb: Callable,
		use_auth := true) -> void:
	if not _configured or host == null or not is_instance_valid(host):
		cb.call(false, {})
		return
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	host.add_child(req)

	var headers := PackedStringArray([
		"apikey: " + anon_key,
		"Content-Type: application/json",
	])
	if use_auth and access_token != "":
		headers.append("Authorization: Bearer " + access_token)
	else:
		headers.append("Authorization: Bearer " + anon_key)
	# Upserts need this or Postgres returns 409 on a second save.
	headers.append("Prefer: return=representation,resolution=merge-duplicates")

	req.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray,
			data: PackedByteArray) -> void:
		req.queue_free()
		var text := data.get_string_from_utf8()
		var parsed: Variant = null
		if text != "":
			var j := JSON.new()
			if j.parse(text) == OK:
				parsed = j.data
		var ok := code >= 200 and code < 300
		if not ok:
			# Logged, never surfaced to the player: a failed sync must be silent
			# and retried, because the local save is always authoritative offline.
			push_warning("supabase %s %s -> %d %s" % [path, code, code, text.left(200)])
		cb.call(ok, parsed if parsed != null else {}))

	var payload := "" if body == null else JSON.stringify(body)
	var err := req.request(url + path, headers, method, payload)
	if err != OK:
		req.queue_free()
		cb.call(false, {})


# --- auth -------------------------------------------------------------------

func sign_in(guest: bool, cb: Callable) -> void:
	if not _configured:
		cb.call(false, "", "")
		return
	# Anonymous sign-in. A stored refresh token is reused so a returning player
	# keeps the same uid — and therefore the same cloud save — across launches.
	refresh_token = String(Game.get_value("sb_refresh", ""))
	if refresh_token != "":
		_refresh(func(ok: bool) -> void:
			if ok:
				cb.call(true, user_id, "")
			else:
				# A refresh token can be revoked or expire; fall through to a new
				# anonymous identity rather than leaving the player signed out.
				refresh_token = ""
				_sign_in_anonymous(cb))
		return
	_sign_in_anonymous(cb)


func _sign_in_anonymous(cb: Callable) -> void:
	_request(HTTPClient.METHOD_POST, "/auth/v1/signup", {},
			func(ok: bool, data: Variant) -> void:
				if not ok or not (data is Dictionary):
					cb.call(false, "", "")
					return
				_absorb_session(data as Dictionary)
				cb.call(user_id != "", user_id, ""), false)


func _refresh(cb: Callable) -> void:
	_request(HTTPClient.METHOD_POST,
			"/auth/v1/token?grant_type=refresh_token",
			{"refresh_token": refresh_token},
			func(ok: bool, data: Variant) -> void:
				if ok and data is Dictionary:
					_absorb_session(data as Dictionary)
				cb.call(ok and user_id != ""), false)


func _absorb_session(data: Dictionary) -> void:
	access_token = String(data.get("access_token", ""))
	var rt := String(data.get("refresh_token", ""))
	if rt != "":
		refresh_token = rt
		Game.set_value("sb_refresh", rt)
	var user: Variant = data.get("user", {})
	if user is Dictionary:
		user_id = String((user as Dictionary).get("id", ""))


func sign_out() -> void:
	access_token = ""
	refresh_token = ""
	user_id = ""
	Game.set_value("sb_refresh", "")


# --- cloud save -------------------------------------------------------------

func load_cloud(cb: Callable) -> void:
	if user_id == "":
		cb.call({})
		return
	_request(HTTPClient.METHOD_GET,
			"/rest/v1/saves?select=payload&user_id=eq." + user_id, null,
			func(ok: bool, data: Variant) -> void:
				if not ok or not (data is Array) or (data as Array).is_empty():
					cb.call({})
					return
				var row: Variant = (data as Array)[0]
				var payload: Variant = (row as Dictionary).get("payload", {}) \
						if row is Dictionary else {}
				cb.call(payload if payload is Dictionary else {}))


func save_cloud(payload: Dictionary, cb: Callable) -> void:
	if user_id == "":
		cb.call(false)
		return
	# Upsert on user_id. The merge itself happens in Backend, on purpose — conflict
	# resolution is the part that loses player money when it is wrong, so it stays
	# pure and unit-tested rather than living inside a network call.
	_request(HTTPClient.METHOD_POST, "/rest/v1/saves",
			{"user_id": user_id, "payload": payload,
			"updated_at": Time.get_datetime_string_from_system(true)},
			func(ok: bool, _d: Variant) -> void: cb.call(ok))


# --- leaderboards -----------------------------------------------------------

func submit_score(score: int, cb: Callable) -> void:
	if user_id == "":
		cb.call(false)
		return
	# The server keeps the best score, not the latest — enforced by the SQL
	# function, so a replayed or tampered request cannot lower someone's entry.
	_request(HTTPClient.METHOD_POST, "/rest/v1/rpc/submit_score",
			{"p_score": score, "p_name": Game.player_name()},
			func(ok: bool, _d: Variant) -> void: cb.call(ok))


func fetch_board(scope: int, cb: Callable) -> void:
	var q := "/rest/v1/leaderboard?select=name,score&order=score.desc&limit=50"
	if scope == 2:   # Backend.Scope.WEEKLY
		q = "/rest/v1/leaderboard_weekly?select=name,score&order=score.desc&limit=50"
	_request(HTTPClient.METHOD_GET, q, null,
			func(ok: bool, data: Variant) -> void:
				if not ok or not (data is Array):
					cb.call([])
					return
				var rows: Array = []
				for r: Variant in data as Array:
					if r is Dictionary:
						rows.append({"name": String((r as Dictionary).get("name", "?")),
								"score": int((r as Dictionary).get("score", 0))})
				cb.call(rows))
