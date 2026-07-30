class_name Cosmetics
extends RefCounted
## Cosmetic catalogue, ownership and loadout.
##
## Data-driven from `data/cosmetics.json` — adding a skin never touches code
## (spec §16). Static rather than an autoload: this is a lookup table over
## `Game.profile`, with no state or per-frame work of its own.
##
## Cosmetics are visual only. Nothing here may be read by a gameplay rule.

const PATH := "res://data/cosmetics.json"
const KINDS := ["skin", "trail", "launch_vfx", "nameplate", "arena_theme"]

static var _items: Dictionary = {}      # id -> item dict
static var _by_kind: Dictionary = {}    # kind -> Array[item]
static var _rarities: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		push_error("cosmetics.json missing or malformed — catalogue is empty")
		return
	_rarities = parsed.get("rarities", {})
	for kind: String in KINDS:
		_by_kind[kind] = []
	for item: Dictionary in parsed.get("items", []):
		var id := String(item.get("id", ""))
		if id == "" or not _by_kind.has(item.get("kind", "")):
			push_warning("skipping malformed cosmetic: %s" % item)
			continue
		_items[id] = item
		_by_kind[item["kind"]].append(item)


static func all_of(kind: String) -> Array:
	_load()
	return _by_kind.get(kind, [])


static func get_item(id: String) -> Dictionary:
	_load()
	return _items.get(id, {})


static func exists(id: String) -> bool:
	_load()
	return _items.has(id)


## The free item every player starts with, per kind.
static func default_of(kind: String) -> String:
	for item: Dictionary in all_of(kind):
		if item.get("default", false):
			return String(item["id"])
	var list := all_of(kind)
	return String(list[0]["id"]) if not list.is_empty() else ""


static func rarity_color(rarity: String) -> Color:
	_load()
	var r: Dictionary = _rarities.get(rarity, {})
	return Color(String(r.get("color", "#9aa4b2")))


static func rarity_key(rarity: String) -> String:
	return "UI_RARITY_" + rarity.to_upper()


static func price(id: String) -> int:
	return int(get_item(id).get("price", 0))


# --- ownership -------------------------------------------------------------
static func owned_ids() -> Array:
	var list: Variant = Game.get_value("owned", [])
	return list if list is Array else []


static func is_owned(id: String) -> bool:
	# Free/default items are always owned — never make a player buy the default.
	if price(id) <= 0:
		return true
	return owned_ids().has(id)


static func grant(id: String) -> void:
	if not exists(id) or is_owned(id):
		return
	var list := owned_ids()
	list.append(id)
	Game.set_value("owned", list)


## Spends coins and grants. Returns false if unaffordable or already owned.
static func purchase(id: String) -> bool:
	if not exists(id) or is_owned(id):
		return false
	var cost := price(id)
	if not Game.spend("coins", cost):
		return false
	grant(id)
	Game.log_transaction("cosmetic_purchase", "coins", -cost, id)
	return true


# --- loadout ---------------------------------------------------------------
static func equipped(kind: String) -> String:
	var loadout: Variant = Game.get_value("loadout", {})
	var id := ""
	if loadout is Dictionary:
		id = String(loadout.get(kind, ""))
	# Fall back if the saved id was removed from the catalogue in an update, or
	# the player somehow has an unowned item equipped.
	if id == "" or not exists(id) or not is_owned(id):
		return default_of(kind)
	return id


static func equipped_item(kind: String) -> Dictionary:
	return get_item(equipped(kind))


static func equip(kind: String, id: String) -> bool:
	if not exists(id) or not is_owned(id):
		return false
	if String(get_item(id).get("kind", "")) != kind:
		return false
	var loadout: Variant = Game.get_value("loadout", {})
	var dict: Dictionary = loadout if loadout is Dictionary else {}
	dict[kind] = id
	Game.set_value("loadout", dict)
	return true


## Owned / total, for the collection screen.
static func completion() -> Vector2i:
	_load()
	var total := 0
	var have := 0
	for id: String in _items:
		total += 1
		if is_owned(id):
			have += 1
	return Vector2i(have, total)


# --- convenience for gameplay visuals --------------------------------------
static func skin_colors() -> Array:
	var s := equipped_item("skin")
	var a := Color(String(s.get("pole_a", "#d94f3d")))
	var b := Color(String(s.get("pole_b", "#477fff")))
	if bool(Game.get_value("colorblind", false)):
		# Red/blue poles are the worst possible pair for deuteranopia and
		# protanopia. Blue/yellow separates for every common type, and the
		# shader's hard split already gives the shape cue the spec asks for.
		a = Color("#ffd24a")
		b = Color("#2f6fe0")
	return [a, b, float(s.get("emission", 0.0))]


static func trail_config() -> Dictionary:
	return equipped_item("trail")


static func launch_color() -> Color:
	return Color(String(equipped_item("launch_vfx").get("color", "#ffffff")))


static func launch_scale() -> float:
	return float(equipped_item("launch_vfx").get("scale", 1.0))


static func nameplate_colors() -> Array:
	var p := equipped_item("nameplate")
	return [
		Color(String(p.get("color", "#ffffff"))),
		Color(String(p.get("outline", "#000000"))),
	]


static func arena_theme() -> Dictionary:
	return equipped_item("arena_theme")
