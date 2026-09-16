extends RefCounted
## Settings a mod exposes so a host can change how it plays without editing its code: spawn rates, whether
## a feature is on, a difficulty.
##
## A mod declares them once (ModApi.register_settings) and reads them anywhere (ModApi.setting):
##
##   api.register_settings({
##       "monster_rate": {"label": "How many monsters", "type": "float", "default": 1.0, "min": 0.0, "max": 3.0,
##                        "help": "Multiplies how often monsters appear."},
##       "difficulty":   {"label": "Difficulty", "type": "choice", "default": "normal",
##                        "choices": [["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]]},
##   })
##
## The server owns the values, so a setting is not a piece of client UI: the admin screen and /modsettings
## only ask the server to change what it already holds. Where a value comes from, last wins:
##
##   1. the schema's default;
##   2. mod_settings.json in the server's data folder (or --mod-settings), for a server nobody logs into;
##   3. what an admin changed in game, kept in the world's world.json under `mod_settings`, so the setting
##      travels with the world and a backup brings it back.
##
## A value for a mod that is not loaded is kept, not dropped, so turning a mod off for a session and back
## on again does not lose how it was set up.

const TYPES := ["bool", "int", "float", "choice", "text"]
const FILE := "mod_settings.json"
const MAX_TEXT := 200

var _schema := {}    # mod id -> {key: entry}
var _file := {}      # mod id -> {key: value}, from the data folder: read, never written
var _world := {}     # mod id -> {key: value}, saved with the world
var _resolved := {}  # mod id -> {key: value}, what the defaults and those two add up to
var _server


func _init(game_server) -> void:
	_server = game_server


## Declares a mod's settings. A malformed entry is dropped with a warning rather than taken as a value,
## so a typo in a mod cannot stop the server from starting.
func register(mod_id: String, schema: Dictionary) -> void:
	var clean := {}
	for key in schema:
		var setting_name := String(key)
		var entry = schema[key]
		if not (entry is Dictionary) or not setting_name.is_valid_identifier():
			_warn(mod_id, "Setting '%s' needs a valid name and a definition" % setting_name)
			continue
		var type := String(entry.get("type", "bool"))
		if not type in TYPES:
			_warn(mod_id, "Setting '%s' has an unknown type '%s' (%s)" % [setting_name, type, ", ".join(TYPES)])
			continue
		var out := {"type": type, "label": String(entry.get("label", setting_name.capitalize())).left(64),
			"help": String(entry.get("help", "")).left(200)}
		match type:
			"bool":
				out.default = bool(entry.get("default", false))
			"int", "float":
				out.min = float(entry.get("min", 0.0))
				out.max = maxf(out.min, float(entry.get("max", maxf(out.min, 100.0))))
				out.step = maxf(0.001, float(entry.get("step", 1.0 if type == "int" else 0.05)))
				out.default = _coerce(out, entry.get("default", out.min))
				if out.default == null:  # a default that is not a number at all: fall back to the range
					_warn(mod_id, "Setting '%s' has a default that is not a number; using %s" % [setting_name, out.min])
					out.default = out.min
			"choice":
				var choices := []
				for choice in (entry.get("choices", []) as Array):
					if choice is Array and choice.size() == 2:
						choices.append([String(choice[0]), String(choice[1]).left(64)])
				if choices.is_empty():
					_warn(mod_id, "Setting '%s' is a choice with no choices" % setting_name)
					continue
				out.choices = choices
				out.default = String(entry.get("default", choices[0][0]))
				if _coerce(out, out.default) == null:
					out.default = choices[0][0]
			"text":
				out.default = String(entry.get("default", "")).left(MAX_TEXT)
		clean[setting_name] = out
	if clean.is_empty():
		return
	var existing: Dictionary = _schema.get(mod_id, {})
	existing.merge(clean, true)
	_schema[mod_id] = existing
	_resolve(mod_id)


## The value in force for a mod's setting: its default until a file or an admin changed it. null when the
## mod never declared it.
func get_value(mod_id: String, key: String):
	return _resolved.get(mod_id, {}).get(key)


## Changes one setting and saves it with the world. Returns "" or why it was refused; tells the mod
## through `settings_changed` so it can react without a restart.
func set_value(mod_id: String, key: String, value) -> String:
	var entry: Dictionary = _schema.get(mod_id, {}).get(key, {})
	if entry.is_empty():
		return "%s has no setting called '%s'" % [mod_id, key] if _schema.has(mod_id) else "No mod called '%s' is loaded" % mod_id
	var clean = _coerce(entry, value)
	if clean == null:
		return "'%s' is not a value %s takes (%s)" % [str(value), key, describe(entry)]
	var before = get_value(mod_id, key)
	if not _world.has(mod_id):
		_world[mod_id] = {}
	_world[mod_id][key] = clean
	_resolve(mod_id)
	_server._meta.mod_settings = to_saved()
	if before != clean:
		_server.emit("settings_changed", {"mod": mod_id, "key": key, "value": clean, "previous": before})
	return ""


## Puts a setting back to its default (and to whatever the data folder's file says).
func reset(mod_id: String, key: String) -> String:
	if not _schema.get(mod_id, {}).has(key):
		return "%s has no setting called '%s'" % [mod_id, key]
	if not _world.get(mod_id, {}).has(key):
		return ""
	var before = get_value(mod_id, key)
	_world[mod_id].erase(key)
	if _world[mod_id].is_empty():
		_world.erase(mod_id)
	_resolve(mod_id)
	_server._meta.mod_settings = to_saved()
	var now = get_value(mod_id, key)
	if before != now:
		_server.emit("settings_changed", {"mod": mod_id, "key": key, "value": now, "previous": before})
	return ""


## Every setting of every mod (or one mod), for the admin screen and /modsettings:
## [{mod, key, type, label, help, value, default, changed, ...}], in a stable order.
func list(mod_id := "") -> Array:
	var out := []
	for id: String in _schema:
		if not mod_id.is_empty() and id != mod_id:
			continue
		for key: String in _schema[id]:
			var entry: Dictionary = _schema[id][key].duplicate(true)
			entry.mod = id
			entry.key = key
			entry.value = get_value(id, key)
			entry.changed = _world.get(id, {}).has(key)
			out.append(entry)
	out.sort_custom(func(a, b): return [a.mod, a.key] < [b.mod, b.key])
	return out


## Ids of the mods that have settings, in load order.
func mods() -> Array:
	var out := []
	for id in _server.mod_order:
		if _schema.has(id):
			out.append(id)
	for id: String in _schema:
		if not out.has(id):
			out.append(id)
	return out


## What a setting accepts, for an error message or a tooltip.
static func describe(entry: Dictionary) -> String:
	match String(entry.get("type", "")):
		"bool":
			return "on or off"
		"int", "float":
			return "%s to %s" % [_number(entry.get("min", 0.0)), _number(entry.get("max", 0.0))]
		"choice":
			var names := []
			for choice in entry.get("choices", []):
				names.append(String(choice[0]))
			return ", ".join(names)
	return "any text"


## Reads the values a host set outside the game, before the mods load, so a mod can read its own settings
## while it is still starting up. `override` is a path to a JSON file or the JSON itself (--mod-settings).
func load_sources(meta: Dictionary, data_dir: String, override := "") -> void:
	_file = {}
	_world = {}
	_resolved = {}
	for source in [_read_file(data_dir.path_join(FILE)), _read_override(override)]:
		_merge_into(_file, source)
	_merge_into(_world, meta.get("mod_settings"))
	for mod_id: String in _schema:
		_resolve(mod_id)


## What goes into world.json: the values an admin set, untouched for mods that are not loaded now.
func to_saved() -> Dictionary:
	return _world.duplicate(true)


## The defaults, the file and the world, added up for one mod.
func _resolve(mod_id: String) -> void:
	var schema: Dictionary = _schema.get(mod_id, {})
	var values := {}
	for key: String in schema:
		values[key] = schema[key].default
		for source in [_file, _world]:
			if source.get(mod_id, {}).has(key):
				var clean = _coerce(schema[key], source[mod_id][key])
				if clean == null:
					_warn(mod_id, "Ignoring '%s' for %s: it takes %s" % [str(source[mod_id][key]), key, describe(schema[key])])
				else:
					values[key] = clean
	_resolved[mod_id] = values


func _merge_into(target: Dictionary, source) -> void:
	if not (source is Dictionary):
		return
	for mod_id in source:
		if not (source[mod_id] is Dictionary):
			continue
		var into: Dictionary = target.get(String(mod_id), {})
		into.merge(source[mod_id], true)
		target[String(mod_id)] = into


func _read_override(override: String):
	if override.strip_edges().is_empty():
		return null
	if override.strip_edges().begins_with("{"):
		var parsed = JSON.parse_string(override)
		if not (parsed is Dictionary):
			_warn("server", "--mod-settings is not a JSON object of {mod: {setting: value}}")
		return parsed
	return _read_file(override)


func _read_file(path: String):
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		_warn("server", "%s is not a JSON object of {mod: {setting: value}}" % path.get_file())
		return null
	return parsed


func _warn(source: String, message: String) -> void:
	_server.dev_log.add("warn", source, message)


## The value as the schema wants it, or null when it cannot be one.
func _coerce(entry: Dictionary, value):
	match String(entry.get("type", "")):
		"bool":
			if value is bool:
				return value
			if value is int or value is float:
				return float(value) != 0.0
			return String(value).to_lower() in ["true", "on", "1", "yes"] if value is String else null
		"int", "float":
			if value is bool or (value is String and not String(value).strip_edges().is_valid_float()):
				return null
			if not (value is String or value is int or value is float):
				return null
			var number := clampf(float(value), float(entry.min), float(entry.max))
			return int(round(number)) if entry.type == "int" else snappedf(number, 0.001)
		"choice":
			for choice in entry.get("choices", []):
				if choice[0] == String(value):
					return String(value)
			return null
		"text":
			return String(value).left(MAX_TEXT) if not (value is Dictionary or value is Array) else null
	return null


static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, round(value)) else str(snappedf(value, 0.001))
