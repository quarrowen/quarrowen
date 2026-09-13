extends RefCounted
## Hosts a JavaScript mod: runs it in a sandboxed NativeJsRuntime (QuickJS) and exposes the regular
## ModApi to it through engine/server/js/prelude.js. Values cross as JSON; positions become {x, y, z}
## objects and players become {__player: peer_id} references that the prelude wraps in Player objects.

const ModApi = preload("res://engine/server/mod_api.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")

const PRELUDE := "res://engine/server/js/prelude.js"
## Milliseconds a single callback may run before QuickJS interrupts it.
const TIME_BUDGET_MS := 200

var api
var manifest: Dictionary
var runtime: Object
var _server


class HostError:
	var message: String

	func _init(text: String) -> void:
		message = text


func _init(server, mod_manifest: Dictionary) -> void:
	_server = server
	manifest = mod_manifest
	api = ModApi.new(server, mod_manifest)


func load() -> Error:
	if not ClassDB.class_exists(&"NativeJsRuntime"):
		printerr("[%s] JavaScript mods need the native extension (native/)" % manifest.id)
		return ERR_UNAVAILABLE
	runtime = ClassDB.instantiate(&"NativeJsRuntime")
	runtime.set_time_budget_ms(TIME_BUDGET_MS)
	runtime.set_host(_host)
	var error: String = runtime.eval_script("prelude.js", FileAccess.get_file_as_string(PRELUDE))
	if error.is_empty():
		var path: String = manifest.dir.path_join(manifest.main)
		if not FileAccess.file_exists(path):
			error = "missing %s" % path
		else:
			error = runtime.load_module("%s/%s" % [manifest.id, manifest.main], FileAccess.get_file_as_string(path))
	if error.is_empty():
		var reply = _parse(runtime.call_function("__setup", "{}"))
		if reply is Dictionary and reply.has("__error"):
			error = reply.__error
	if not error.is_empty():
		printerr("[%s] %s" % [manifest.id, error])
		return ERR_SCRIPT_FAILED
	return OK


# --- Engine -> script ---------------------------------------------------------------------------

func _invoke(callback_id: int, args: Array):
	var reply = _parse(runtime.call_function("__dispatch", JSON.stringify({"id": callback_id, "args": to_js(args)})))
	if reply is Dictionary and reply.has("__error"):
		printerr("[%s] script error: %s" % [manifest.id, reply.__error])
		return null
	return reply


func _on_event(ev: Dictionary, callback_id: int) -> void:
	var reply = _invoke(callback_id, [ev])
	if not (reply is Dictionary) or not (reply.get("event") is Dictionary):
		return
	var changed: Dictionary = reply.event
	if ev.has("cancelled") and changed.get("cancelled") != null:
		ev.cancelled = bool(changed.cancelled)
	if ev.has("drops") and changed.get("drops") is Array:
		var drops := []
		for d in changed.drops:
			if d is Array and d.size() == 2:
				drops.append([int(d[0]), int(d[1])])
			elif d is Dictionary and d.has("item"):
				drops.append([int(d.item), int(d.get("count", 1))])
		ev.drops = drops


func _on_command(player, args: PackedStringArray, callback_id: int) -> void:
	_invoke(callback_id, [player, Array(args)])


func _on_timer(callback_id: int) -> void:
	_invoke(callback_id, [])


# --- Script -> engine ---------------------------------------------------------------------------

func _host(method: String, args_json: String) -> String:
	var args = JSON.parse_string(args_json)
	if not (args is Array):
		return JSON.stringify({"__error": "arguments must be an array"})
	var result = _call_host(method, args)
	if result is HostError:
		return JSON.stringify({"__error": result.message})
	return JSON.stringify({"value": to_js(result)})


func _call_host(method: String, a: Array):
	if method.begins_with("player."):
		return _call_player(method.substr(7), a)
	match method:
		"info": api.info(_str(a, 0))
		"registerBlock": return api.register_block(_str(a, 0), _dict(a, 1))
		"registerItem": return api.register_item(_str(a, 0), _dict(a, 1))
		"registerRecipe": api.register_recipe(_dict(a, 0), _str(a, 1), _int(a, 2, 1))
		"block": return api.block(_str(a, 0))
		"item": return api.item(_str(a, 0))
		"itemName": return api.item_name(_int(a, 0))
		"itemDisplayName": return api.item_display_name(_int(a, 0))
		"blockName": return api.block_name(_int(a, 0))
		"isSolid": return api.is_solid(_int(a, 0))
		"getDrops": return api.get_drops(_int(a, 0))
		"addOrePass": api.add_ore_pass(_dict(a, 0))
		"getBlock": return api.get_block(_block_pos(a, 0))
		"getLoadedBlock": return api.get_loaded_block(_block_pos(a, 0))
		"setBlock": api.set_block(_block_pos(a, 0), _int(a, 1), bool(a[2]) if a.size() > 2 else false, _int(a, 3, 0))
		"fill": api.fill(_block_pos(a, 0), _block_pos(a, 1), _int(a, 2))
		"getBlockState": return api.get_block_state(_block_pos(a, 0))
		"getBlockData": return api.get_block_data(_block_pos(a, 0))
		"setBlockData": api.set_block_data(_block_pos(a, 0), _dict(a, 1))
		"clearBlockData": api.clear_block_data(_block_pos(a, 0))
		"findBlockData": return api.find_block_data(_int(a, 0, -1))
		"surfaceY": return api.surface_y(_int(a, 0), _int(a, 1))
		"seesSky": return api.sees_sky(_block_pos(a, 0))
		"setPhysics": api.set_physics(_dict(a, 0))
		"setWorldTime": api.set_world_time(float(a[0]) if a.size() > 0 else 0.5, float(a[1]) if a.size() > 1 else -1.0)
		"timeOfDay": return api.get_time_of_day()
		"daylight": return api.get_daylight()
		"facingFromYaw": return api.facing_from_yaw(float(a[0]) if a.size() > 0 else 0.0)
		"players": return api.get_players()
		"findPlayer": return api.find_player(_str(a, 0))
		"broadcast": api.broadcast(_str(a, 0))
		"setServerInfo": api.set_server_info(_dict(a, 0))
		"showCrafting":
			var player = _player_ref(a, 0)
			if player is HostError:
				return player
			api.show_crafting(player)
		"on": api.on(_str(a, 0), _on_event.bind(_int(a, 1)), _int(a, 2, 0))
		"command": api.register_command(_str(a, 0), _str(a, 1), _on_command.bind(_int(a, 2)), _str(a, 3))
		"after": return api.after(float(a[0]) if a.size() > 0 else 0.0, _on_timer.bind(_int(a, 1)))
		"every": return api.every(maxf(float(a[0]) if a.size() > 0 else 1.0, 0.05), _on_timer.bind(_int(a, 1)))
		"cancel": api.cancel(_int(a, 0))
		"storageGet": return api.storage.get(_str(a, 0), a[1] if a.size() > 1 else null)
		"storageSet": api.storage[_str(a, 0)] = a[1] if a.size() > 1 else null
		_: return HostError.new("unknown API method '%s'" % method)
	return null


func _call_player(method: String, a: Array):
	if method == "online":
		return not (_player_ref(a, 0) is HostError)
	var player = _player_ref(a, 0)
	if player is HostError:
		return player
	match method:
		"position": return player.position
		"eyePosition": return player.get_eye_position()
		"yaw": return player.yaw
		"lookDirection": return Vector3(-sin(player.yaw) * cos(player.pitch), sin(player.pitch), -cos(player.yaw) * cos(player.pitch))
		"give": return player.give(_int(a, 1), _int(a, 2, 1))
		"take": return player.take(_int(a, 1), _int(a, 2, 1))
		"countOf": return player.count_of(_int(a, 1))
		"teleport": player.teleport(_vec3(a, 1))
		"sendMessage": player.send_message(_str(a, 1))
		"showTitle": player.show_title(_str(a, 1), _str(a, 2), float(a[3]) if a.size() > 3 else 3.0)
		"showUi": player.show_ui("%s:%s" % [manifest.id, _str(a, 1)] if not _str(a, 1).contains(":") else _str(a, 1), _dict(a, 2))
		"hideUi": player.hide_ui("%s:%s" % [manifest.id, _str(a, 1)] if not _str(a, 1).contains(":") else _str(a, 1))
		"isCreative": return player.is_creative()
		"isAdmin": return player.is_admin()
		"setCreative": player.set_creative(bool(a[1]) if a.size() > 1 else false)
		"setHotbar": player.set_hotbar(a[1] if a.size() > 1 and a[1] is Array else [])
		"getData":
			var own: Dictionary = player.data.get(manifest.id, {})
			return own.get(_str(a, 1), a[2] if a.size() > 2 else null)
		"setData":
			if not (player.data.get(manifest.id) is Dictionary):
				player.data[manifest.id] = {}
			player.data[manifest.id][_str(a, 1)] = a[2] if a.size() > 2 else null
		"kick": player.kick(_str(a, 1))
		_: return HostError.new("unknown player method '%s'" % method)
	return null


# --- Conversion ---------------------------------------------------------------------------------

## Engine values -> JSON-safe values for the prelude.
func to_js(value):
	if value is Vector3i or value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z}
	if value is Object and value.get_script() == ServerPlayer:
		return {"__player": value.peer_id, "name": value.name}
	if value is Dictionary:
		var out := {}
		for key in value:
			out[str(key)] = to_js(value[key])
		return out
	if value is Array or (typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) <= TYPE_PACKED_VECTOR4_ARRAY):
		var out := []
		for item in value:
			out.append(to_js(item))
		return out
	if value is Object:
		return null
	return value


static func _parse(text: String):
	return JSON.parse_string(text) if not text.is_empty() else null


static func _str(a: Array, i: int) -> String:
	return str(a[i]) if i < a.size() and a[i] != null else ""


static func _int(a: Array, i: int, fallback := 0) -> int:
	return int(a[i]) if i < a.size() and (a[i] is float or a[i] is int or a[i] is bool) else fallback


static func _dict(a: Array, i: int) -> Dictionary:
	return a[i] if i < a.size() and a[i] is Dictionary else {}


static func _vec3(a: Array, i: int) -> Vector3:
	var v = a[i] if i < a.size() else null
	if v is Dictionary:
		return Vector3(float(v.get("x", 0)), float(v.get("y", 0)), float(v.get("z", 0)))
	if v is Array and v.size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


static func _block_pos(a: Array, i: int) -> Vector3i:
	var v := _vec3(a, i)
	return Vector3i(floori(v.x), floori(v.y), floori(v.z))


func _player_ref(a: Array, i: int):
	var ref = a[i] if i < a.size() else null
	var peer_id := int(ref.get("__player", -1)) if ref is Dictionary else (int(ref) if ref is float or ref is int else -1)
	var player = _server.players.get(peer_id)
	return player if player != null else HostError.new("player %d is not online" % peer_id)
