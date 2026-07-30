extends Node
## Analytics and crash reporting.
##
## Events are queued in memory, persisted to disk, and flushed in batches. The
## provider is Null (no vendor chosen), so `_send()` drains to a local file —
## but the queue, batching, offline survival and retry are all real, because
## those are exactly what breaks when a vendor is wired in late.
##
## Also owns the crash breadcrumb trail: on an unhandled error the last N events
## are what tells you what the player was doing.

const QUEUE_PATH := "user://analytics_queue.json"
const SINK_PATH := "user://analytics_sink.jsonl"
const MAX_QUEUE := 500
const BATCH_SIZE := 25
const FLUSH_SECONDS := 30.0
const BREADCRUMBS := 30

var _queue: Array[Dictionary] = []
var _breadcrumbs: Array[String] = []
var _flush_timer := 0.0
var _session_start := 0
var _match_start := 0
## Set false to silence analytics entirely (e.g. a user opting out under CCPA).
var enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session_start = int(Time.get_unix_time_from_system())
	_load_queue()

	# Funnel: everything downstream is measured against session_start.
	track("session_start", {
		"platform": Platform.os_name,
		"locale": String(Game.get_value("locale", "en")),
		"level": int(Game.get_value("level", 1)),
		"matches": int(Game.get_value("matches", 0)),
		"segment": Config.segment(),
	})

	Bus.match_started.connect(_on_match_started)
	Bus.match_ended.connect(_on_match_ended)
	Bus.currency_changed.connect(_on_currency)
	Bus.mission_completed.connect(func(id: String) -> void:
		track("mission_completed", {"id": id}))
	Bus.magnet_eliminated.connect(func(_v: String, _k: String, by_player: bool) -> void:
		if by_player:
			breadcrumb("kill"))


func _process(delta: float) -> void:
	_flush_timer += delta
	if _flush_timer >= FLUSH_SECONDS:
		_flush_timer = 0.0
		flush()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED,
			NOTIFICATION_APPLICATION_FOCUS_OUT]:
		track("session_pause", {"seconds": int(Time.get_unix_time_from_system()) - _session_start})
		flush()
		_save_queue()


# --- public ----------------------------------------------------------------
func track(event: String, props: Dictionary = {}) -> void:
	if not enabled:
		return
	var row := {
		"e": event,
		"t": int(Time.get_unix_time_from_system()),
		"p": props,
	}
	_queue.append(row)
	breadcrumb(event)
	# Drop the oldest rather than grow without bound — a player offline for a
	# week must not accumulate a queue that then fails to upload.
	if _queue.size() > MAX_QUEUE:
		_queue = _queue.slice(_queue.size() - MAX_QUEUE)


func breadcrumb(what: String) -> void:
	_breadcrumbs.append(what)
	if _breadcrumbs.size() > BREADCRUMBS:
		_breadcrumbs.pop_front()


## Called by the global error hook and by any caught-but-notable failure.
func report_error(message: String, context: Dictionary = {}) -> void:
	var payload := context.duplicate()
	payload["message"] = message
	payload["breadcrumbs"] = _breadcrumbs.duplicate()
	payload["fps"] = Engine.get_frames_per_second()
	payload["mem_mb"] = int(OS.get_static_memory_usage() / 1048576)
	payload["platform"] = Platform.os_name
	track("error", payload)
	flush()
	push_warning("[crash] %s" % message)


func queue_size() -> int:
	return _queue.size()


# --- funnel hooks ----------------------------------------------------------
func _on_match_started() -> void:
	_match_start = int(Time.get_unix_time_from_system())
	track("match_start", {"segment": Config.segment(),
			"trophies": int(Game.get_value("trophies", 0))})


func _on_match_ended(result: Dictionary) -> void:
	track("match_end", {
		"placement": int(result.get("placement", 0)),
		"mass": int(result.get("mass", 0.0)),
		"kills": int(result.get("kills", 0)),
		"seconds": int(Time.get_unix_time_from_system()) - _match_start,
		"coins": int(result.get("coins_earned", 0)),
	})


func _on_currency(currency: String, delta: int, source: String) -> void:
	# Sources and sinks are the economy's health check; every movement is logged.
	track("currency", {"c": currency, "d": delta, "src": source})


# --- transport -------------------------------------------------------------
func flush() -> void:
	if _queue.is_empty():
		return
	var batch := _queue.slice(0, mini(BATCH_SIZE, _queue.size()))
	if _send(batch):
		_queue = _queue.slice(batch.size())
	# On failure the batch stays queued and retries on the next flush — that is
	# the behaviour a real provider needs and the one most stubs get wrong.
	_save_queue()


## Null transport. A real provider POSTs the batch and returns success.
## Writing to disk keeps the data inspectable and proves the drain path works.
func _send(batch: Array) -> bool:
	var f := FileAccess.open(SINK_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(SINK_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.seek_end()
	for row: Dictionary in batch:
		f.store_line(JSON.stringify(row))
	f.close()
	return true


func _save_queue() -> void:
	var f := FileAccess.open(QUEUE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_queue))
		f.close()


func _load_queue() -> void:
	if not FileAccess.file_exists(QUEUE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUEUE_PATH))
	if parsed is Array:
		_queue.clear()
		for row: Variant in parsed:
			if row is Dictionary:
				_queue.append(row)
