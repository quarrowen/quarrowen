extends RefCounted
## The player's own creations on this computer (skins, accessories, models), saved as
## <dir>/<id>.json (manifest) and <dir>/<id>.<png|json|glb> (payload), with the id's colon replaced.
## VOXEL_CREATIONS_DIR overrides the folder (tests). See engine/shared/creations.gd for the format.

const Creations = preload("res://engine/shared/creations.gd")

const DIR := "user://creations"


static func dir() -> String:
	var override := OS.get_environment("VOXEL_CREATIONS_DIR")
	return override if not override.is_empty() else DIR


static func _file(id: String) -> String:
	return dir().path_join(id.replace(":", "_"))


## Validates and saves a creation. Returns {ok, error, manifest}.
static func save(manifest: Dictionary, payload: PackedByteArray) -> Dictionary:
	var checked := Creations.validate(manifest, payload)
	if not checked.ok:
		return checked
	var m: Dictionary = checked.manifest
	DirAccess.make_dir_recursive_absolute(dir())
	var data := FileAccess.open(_file(m.id) + "." + Creations.payload_extension(m.kind), FileAccess.WRITE)
	if data == null:
		return {"ok": false, "error": "could not write to %s" % dir(), "manifest": {}}
	data.store_buffer(payload)
	data.close()
	var meta := FileAccess.open(_file(m.id) + ".json", FileAccess.WRITE)
	meta.store_string(JSON.stringify(m, "\t"))
	meta.close()
	return checked


## Manifests of every creation, newest first.
static func list() -> Array:
	var out := []
	for file in DirAccess.get_files_at(dir()):
		if not file.ends_with(".json") or not file.begins_with("ugc_") or file.count(".") != 1:
			continue
		var m = JSON.parse_string(FileAccess.get_file_as_string(dir().path_join(file)))
		if m is Dictionary and Creations.is_id(str(m.get("id", ""))):
			out.append(m)
	out.sort_custom(func(a, b): return int(a.get("created", 0)) > int(b.get("created", 0)))
	return out


static func get_manifest(id: String) -> Dictionary:
	var path := _file(id) + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var m = JSON.parse_string(FileAccess.get_file_as_string(path))
	return m if m is Dictionary else {}


static func get_payload(id: String) -> PackedByteArray:
	var m := get_manifest(id)
	if m.is_empty():
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(_file(id) + "." + Creations.payload_extension(str(m.kind)))


## Changes the name or color (the id stays: it depends only on the content).
static func update(id: String, changes: Dictionary) -> bool:
	var m := get_manifest(id)
	if m.is_empty():
		return false
	for key in ["name", "color", "tint", "model_transform"]:
		if changes.has(key):
			m[key] = changes[key]
	return save(m, get_payload(id)).ok


## Registers every creation as a cosmetic, putting skin images in `images` (asset name -> Image) for the
## look builder. Returns how many were added.
static func register_all(registry, images: Dictionary) -> int:
	var added := 0
	for m in list():
		if add_to(registry, images, m, get_payload(m.id)):
			added += 1
	return added


static func add_to(registry, images: Dictionary, manifest: Dictionary, payload: PackedByteArray) -> bool:
	if registry.register(Creations.to_cosmetic(manifest, payload)).is_empty():
		return false
	if manifest.kind == "skin":
		var img := Image.new()
		if img.load_png_from_buffer(payload) == OK:
			images[Creations.asset_name(manifest)] = img
	return true


## Model bytes by asset name ("ugc:....glb"), for LookBuilder's model reader.
static func read_model(asset: String) -> PackedByteArray:
	return get_payload(asset.get_basename()) if Creations.is_id(asset.get_basename()) else PackedByteArray()


static func remove(id: String) -> void:
	var m := get_manifest(id)
	if m.is_empty():
		return
	DirAccess.remove_absolute(_file(id) + "." + Creations.payload_extension(str(m.kind)))
	DirAccess.remove_absolute(_file(id) + ".json")
