extends RefCounted
## Named sounds. Mods register sounds made of one or more audio assets (.ogg or .wav; one is picked
## at random per play) with volume and pitch variation. "engine:*" sounds are built into the client
## (hurt, pickup, ...) and need no download. Sound ids are indexes into `defs` and are what the
## server sends when it plays a sound.

const MAX_SOUNDS := 4096
const MAX_FILES := 8
const BUILTIN := ["engine:hurt", "engine:pickup", "engine:swing", "engine:death", "engine:ui_click", "engine:drop",
	"engine:equip", "engine:item_break", "engine:crit", "engine:craft", "engine:discover", "engine:munch", "engine:burp"]
const NETWORK_FIELDS := ["name", "files", "volume", "pitch", "pitch_variance", "range"]

var defs: Array[Dictionary] = []
var ids := {}  # name -> id


func _init() -> void:
	for sound_name in BUILTIN:
		register({"name": sound_name})


## def: name, files (asset names), volume (linear, 0-2), pitch (1 = original), pitch_variance
## (random +/- added to pitch), range (blocks until inaudible). Returns the id or -1.
func register(def: Dictionary) -> int:
	var sound_name := String(def.get("name", ""))
	if sound_name.is_empty() or ids.has(sound_name) or defs.size() >= MAX_SOUNDS:
		push_error("Invalid or duplicate sound '%s'" % sound_name)
		return -1
	var files := []
	var given = def.get("files", [])
	for f in (given if given is Array else [given]):
		if f is String and not f.is_empty() and files.size() < MAX_FILES:
			files.append(String(f).left(256))
	var d := {
		"name": sound_name,
		"files": files,
		"volume": clampf(float(def.get("volume", 1.0)), 0.0, 2.0),
		"pitch": clampf(float(def.get("pitch", 1.0)), 0.25, 4.0),
		"pitch_variance": clampf(float(def.get("pitch_variance", 0.1)), 0.0, 1.0),
		"range": clampf(float(def.get("range", 24.0)), 2.0, 128.0),
	}
	var id := defs.size()
	d.id = id
	defs.append(d)
	ids[sound_name] = id
	return id


func id_of(sound_name: String) -> int:
	return ids.get(sound_name, -1)


func is_valid(id: int) -> bool:
	return id >= 0 and id < defs.size()


func to_network() -> Array:
	var out := []
	for d in defs:
		var entry := {}
		for field in NETWORK_FIELDS:
			entry[field] = d[field]
		out.append(entry)
	return out


func load_network(data) -> bool:
	if not (data is Array) or data.size() > MAX_SOUNDS:
		return false
	defs.clear()
	ids.clear()
	for entry in data:
		if not (entry is Dictionary) or not (entry.get("name") is String) or register(entry) < 0:
			return false
	return true
