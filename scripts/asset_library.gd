class_name AssetLibrary
extends RefCounted
## Resolves a mesh by name: authored glTF if it has been exported, generated
## geometry otherwise.
##
## The project must run whether or not anyone has run the Blender step, so this
## never hard-fails on a missing file. `tools/blender_export.py` writes into
## `res://assets/`; drop the .glb files in and the game picks them up on the
## next launch with no code change.
##
## Which source is in use is reported by `source_report()` and printed on boot,
## so "did the art actually load?" is never a guess.

const ASSET_DIR := "res://assets/"

static var _cache: Dictionary = {}
static var _authored: Dictionary = {}   # name -> bool, for reporting


## `name` is the asset stem, e.g. "magnet" or "scrap_nut".
## `fallback` builds the generated mesh if no .glb is present.
static func mesh(name: String, fallback: Callable) -> Mesh:
	if _cache.has(name):
		return _cache[name]

	var loaded := _load_glb(name)
	if loaded != null:
		_cache[name] = loaded
		_authored[name] = true
		return loaded

	var generated: Mesh = fallback.call()
	_cache[name] = generated
	_authored[name] = false
	return generated


static func _load_glb(name: String) -> Mesh:
	var path := ASSET_DIR + name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene := ResourceLoader.load(path)
	if scene is Mesh:
		return scene
	if scene is not PackedScene:
		return null
	# A glTF import is a scene; pull the first MeshInstance3D out of it so the
	# caller gets a Mesh regardless of how the file was authored.
	var root := (scene as PackedScene).instantiate()
	var found := _first_mesh(root)
	root.queue_free()
	return found


static func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and node.mesh != null:
		return node.mesh
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


## True when every requested asset came from an authored file.
static func all_authored() -> bool:
	if _authored.is_empty():
		return false
	for name: String in _authored:
		if not _authored[name]:
			return false
	return true


static func source_report() -> String:
	var authored: Array[String] = []
	var generated: Array[String] = []
	for name: String in _authored:
		if _authored[name]:
			authored.append(name)
		else:
			generated.append(name)
	return "assets: %d authored %s, %d generated %s" % [
		authored.size(), authored, generated.size(), generated]


static func clear_cache() -> void:
	_cache.clear()
	_authored.clear()
