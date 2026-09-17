extends RefCounted
## The client side of player creations (see engine/server/ugc.gd): offers the player's own worn
## creations to the server and uploads them when asked, fetches creations other players wear, checks and
## caches them (user://ugc_cache), registers them as cosmetics, and browses the server library.

signal status_changed(id: String, status: String, reason: String)
signal library_received(items: Array, total: int, policy: Dictionary)
## A creation's files arrived and it can be drawn.
signal creation_ready(id: String)

const Creations = preload("res://engine/shared/creations.gd")
const CreationLibrary = preload("res://engine/client/creation_library.gd")

const CACHE_DIR := "user://ugc_cache"
const PIECE_SIZE := 32 * 1024
const PIECE_INTERVAL := 0.08  # seconds between upload pieces (~400 KB/s, under the server's limit)

var statuses := {}  # id -> {status, reason}
var policy := {}

var _client
var _uploads: Array = []  # [{id, bytes, offset}]
var _upload_timer := 0.0
var _incoming := {}  # id -> {manifest, bytes}
var _requested := {}  # id -> time asked


func _init(game_client) -> void:
	_client = game_client


static func cache_dir() -> String:
	var override := OS.get_environment("QW_UGC_CACHE_DIR")
	return override if not override.is_empty() else CACHE_DIR


## Offers the player's own creations worn in `avatar` to the server.
func offer_worn(avatar: Dictionary) -> void:
	var manifests := []
	for id in worn_ids(avatar):
		var m := CreationLibrary.get_manifest(id)
		if not m.is_empty():
			manifests.append(m)
	if not manifests.is_empty():
		Net.c_ugc_offer.rpc_id(1, manifests)


static func worn_ids(avatar) -> Array:
	var out := []
	if avatar is Dictionary and avatar.get("wear") is Dictionary:
		for cat_name in avatar.wear:
			var entry = avatar.wear[cat_name]
			if entry is Dictionary and Creations.is_id(str(entry.get("id", ""))):
				out.append(str(entry.id))
	return out


func on_request(ids: PackedStringArray) -> void:
	for id in ids:
		var bytes := CreationLibrary.get_payload(id)
		if not bytes.is_empty() and not _uploads.any(func(u): return u.id == id):
			_uploads.append({"id": id, "bytes": bytes, "offset": 0})


func on_status(id: String, status: String, reason: String) -> void:
	var before: String = statuses.get(id, {}).get("status", "")
	statuses[id] = {"status": status, "reason": reason}
	status_changed.emit(id, status, reason)
	var m := CreationLibrary.get_manifest(id)
	var name: String = m.get("name", "Your creation")
	match status:
		"pending":
			_client.notify("✎ %s is waiting for an admin to approve it" % name)
		"approved":
			if before in ["pending", ""] and before != status and not m.is_empty():
				_client.notify("✎ %s is ready: others can see it" % name)
		"refused", "rejected", "removed":
			_client.notify("✎ %s: %s" % [name, reason if not reason.is_empty() else status])


## Makes sure the creations in someone's avatar can be drawn: registers known ones, fetches the rest.
func ensure_known(avatar) -> void:
	var missing := PackedStringArray()
	var now := Time.get_ticks_msec() / 1000.0
	for id in worn_ids(avatar):
		if not _client.cosmetics.get_def(id).is_empty():
			continue
		if _load_local(id):
			continue
		if now - float(_requested.get(id, -100.0)) > 10.0:
			_requested[id] = now
			missing.append(id)
	if not missing.is_empty():
		Net.c_ugc_fetch.rpc_id(1, missing)


## Asks the server for creations (e.g. from the library) even if nobody wears them yet.
func fetch(ids: Array) -> void:
	var missing := PackedStringArray()
	for id in ids:
		if _client.cosmetics.get_def(str(id)).is_empty() and not _load_local(str(id)):
			missing.append(str(id))
	if not missing.is_empty():
		Net.c_ugc_fetch.rpc_id(1, missing)


## From the player's library or the download cache.
func _load_local(id: String) -> bool:
	var m := CreationLibrary.get_manifest(id)
	var bytes := PackedByteArray()
	if not m.is_empty():
		bytes = CreationLibrary.get_payload(id)
	else:
		var meta := cache_dir().path_join(id.replace(":", "_") + ".json")
		if not FileAccess.file_exists(meta):
			return false
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(meta))
		if not (parsed is Dictionary):
			return false
		m = parsed
		bytes = FileAccess.get_file_as_bytes(cache_dir().path_join(id.replace(":", "_") + "." + Creations.payload_extension(str(m.get("kind", "")))))
	return _register(m, bytes)


func _register(manifest: Dictionary, bytes: PackedByteArray) -> bool:
	var checked := Creations.validate(manifest, bytes)
	if not checked.ok:
		return false
	var m: Dictionary = checked.manifest
	if not CreationLibrary.add_to(_client.cosmetics, _client._asset_images, m, bytes):
		return false
	if m.kind == "model":
		_client.ugc_models[Creations.asset_name(m)] = bytes
	creation_ready.emit(m.id)
	return true


func on_defs(manifests: Array) -> void:
	for m in manifests.slice(0, 32):
		if m is Dictionary and Creations.is_id(str(m.get("id", ""))):
			_incoming[str(m.id)] = {"manifest": m, "bytes": PackedByteArray()}


func on_piece(id: String, offset: int, total: int, bytes: PackedByteArray) -> void:
	var entry: Dictionary = _incoming.get(id, {})
	if entry.is_empty() or offset != entry.bytes.size() or total > Creations.MAX_MODEL_BYTES:
		return
	entry.bytes.append_array(bytes)
	if entry.bytes.size() < total:
		return
	_incoming.erase(id)
	var checked := Creations.validate(entry.manifest, entry.bytes)
	if not checked.ok:
		push_warning("[ugc] %s failed its checks: %s" % [id, checked.error])
		return
	DirAccess.make_dir_recursive_absolute(cache_dir())
	var base := cache_dir().path_join(id.replace(":", "_"))
	var f := FileAccess.open(base + "." + Creations.payload_extension(checked.manifest.kind), FileAccess.WRITE)
	if f != null:
		f.store_buffer(entry.bytes)
		f.close()
		var meta := FileAccess.open(base + ".json", FileAccess.WRITE)
		meta.store_string(JSON.stringify(checked.manifest))
		meta.close()
	if _register(checked.manifest, entry.bytes):
		_client.refresh_looks()


func request_library(query := {}, offset := 0) -> void:
	Net.c_ugc_library.rpc_id(1, query, offset)


func on_library(items: Array, total: int, server_policy: Dictionary) -> void:
	policy = server_policy
	library_received.emit(items.filter(func(m): return m is Dictionary and Creations.is_id(str(m.get("id", "")))), total, server_policy)


func update(delta: float) -> void:
	if _uploads.is_empty():
		return
	_upload_timer += delta
	if _upload_timer < PIECE_INTERVAL:
		return
	_upload_timer = 0.0
	var u: Dictionary = _uploads[0]
	var piece: PackedByteArray = u.bytes.slice(u.offset, u.offset + PIECE_SIZE)
	Net.c_ugc_upload.rpc_id(1, u.id, u.offset, u.bytes.size(), piece)
	u.offset += piece.size()
	if u.offset >= u.bytes.size():
		_uploads.pop_front()
