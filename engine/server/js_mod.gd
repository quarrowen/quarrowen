extends RefCounted
## Hosts a JavaScript mod: runs it in a sandboxed NativeJsRuntime (QuickJS) and exposes the regular
## ModApi to it through engine/server/js/prelude.js. Values cross as JSON; positions become {x, y, z}
## objects and players become {__player: peer_id} references that the prelude wraps in Player objects.

const ModApi = preload("res://engine/server/mod_api.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")
const Entity = preload("res://engine/server/entity.gd")
const ContainerView = preload("res://engine/server/container.gd")

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
	# Other fields handlers may rewrite, when the event carries them.
	for key in ["amount", "damage"]:
		if ev.has(key) and (changed.get(key) is float or changed.get(key) is int):
			ev[key] = float(changed[key])
	for key in ["keep_inventory", "keep"]:
		if ev.has(key) and changed.get(key) is bool:
			ev[key] = changed[key]
	if ev.has("stats") and changed.get("stats") is Dictionary:
		for key in changed.stats:
			if ev.stats.has(key) and (changed.stats[key] is float or changed.stats[key] is int):
				ev.stats[key] = float(changed.stats[key])
	if ev.has("avatar") and changed.get("avatar") is Dictionary:
		ev.avatar = changed.avatar  # the server sanitizes it
	if ev.has("message") and changed.get("message") is String and ev.message is String:
		ev.message = changed.message
	if ev.has("position") and ev.position is Vector3 and changed.get("position") is Dictionary:
		ev.position = _vec3([changed.position], 0)


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
	if method.begins_with("entity."):
		return _call_entity(method.substr(7), a)
	match method:
		"info": api.info(_str(a, 0))
		"registerBlock": return api.register_block(_str(a, 0), _dict(a, 1))
		"registerItem": return api.register_item(_str(a, 0), _dict(a, 1))
		"registerRecipe": api.register_recipe(_dict(a, 0), _str(a, 1), _int(a, 2, 1), _dict(a, 3))
		"registerContainer": return api.register_container(_str(a, 0), _dict(a, 1))
		"registerStation": api.register_station(_str(a, 0), _dict(a, 1))
		"registerMinigame": api.register_minigame(_str(a, 0), _dict(a, 1))
		"registerMaterial": api.register_material(_str(a, 0), _dict(a, 1))
		"registerPartType": return api.register_part_type(_str(a, 0), _dict(a, 1))
		"registerAssembly": return api.register_assembly(_str(a, 0), _dict(a, 1))
		"getStation": return api.get_station(_block_pos(a, 0))
		"openContainer":
			var viewer = _any_ref(a, 0)
			return api.open_container(viewer, _block_pos(a, 1)) if viewer != null else false
		"containerItems":
			var c = api.get_container(_block_pos(a, 0))
			return [] if c == null else range(c.size()).map(func(i): return c.get_item(i))
		"setContainerItem":
			var c = api.get_container(_block_pos(a, 0))
			if c != null:
				c.set_item(_int(a, 1), _int(a, 2), _int(a, 3), _dict(a, 4))
		"addToContainer":
			var c = api.get_container(_block_pos(a, 0))
			return _int(a, 2) if c == null else c.add(_int(a, 1), _int(a, 2), _dict(a, 3), _str(a, 4) if a.size() > 4 else "")
		"containerState":
			var c = api.get_container(_block_pos(a, 0))
			return {} if c == null else c.state
		"setContainerState":
			var c = api.get_container(_block_pos(a, 0))
			if c != null:
				c.state.clear()
				c.state.merge(_dict(a, 1))
		"setContainerProgress":
			var c = api.get_container(_block_pos(a, 0))
			if c != null:
				c.set_progress(_str(a, 1), float(a[2]) if a.size() > 2 else 0.0)
		"setFuel": api.set_fuel(_str(a, 0), float(a[1]) if a.size() > 1 else 0.0)
		"getFuel": return api.get_fuel(_int(a, 0))
		"registerProcess": api.register_process(_str(a, 0), _str(a, 1), _str(a, 2), _int(a, 3, 1), float(a[4]) if a.size() > 4 else 10.0)
		"getProcess": return api.get_process(_str(a, 0), _int(a, 1))
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
		"registerEntity": return api.register_entity(_str(a, 0), _dict(a, 1))
		"registerSound": return api.register_sound(_str(a, 0), a[1] if a.size() > 1 and (a[1] is Array or a[1] is String) else [], _dict(a, 2))
		"playSound": api.play_sound(_str(a, 0), _vec3(a, 1), float(a[2]) if a.size() > 2 else 1.0, float(a[3]) if a.size() > 3 else 1.0)
		"spawnEntity": return api.spawn_entity(_str(a, 0), _vec3(a, 1), _entity_options(_dict(a, 2)))
		"spawnProjectile": return api.spawn_projectile(_str(a, 0), _vec3(a, 1), _vec3(a, 2), _any_ref(a, 3))
		"dropItem": return api.drop_item(_int(a, 0), _int(a, 1, 1), _vec3(a, 2))
		"entities": return api.get_entities(_vec3(a, 0), float(a[1]) if a.size() > 1 else 16.0, _str(a, 2))
		"addSpawnRule": api.add_spawn_rule(_dict(a, 0))
		"registerBiome": api.register_biome(_str(a, 0), _dict(a, 1))
		"registerFeature": api.register_feature(_str(a, 0), _dict(a, 1))
		"registerStructureTemplate": return api.register_structure_template(_str(a, 0), a[1] if a.size() > 1 and (a[1] is String or a[1] is Dictionary) else "")
		"registerStructure": api.register_structure(_str(a, 0), _dict(a, 1))
		"registerLootTable": api.register_loot_table(_str(a, 0), _dict(a, 1))
		"getBiome": return api.get_biome(_vec3(a, 0))
		"setSpawnCaps": api.set_spawn_caps(_dict(a, 0))
		"setGameplay": api.set_gameplay(_dict(a, 0))
		"registerEquipmentSlot": api.register_equipment_slot(_str(a, 0), _dict(a, 1))
		"registerStat": api.register_stat(_str(a, 0), float(a[1]) if a.size() > 1 else 0.0)
		"registerCosmetic": return api.register_cosmetic(_str(a, 0), _dict(a, 1))
		"registerCosmeticCategory": return api.register_cosmetic_category(_str(a, 0), _dict(a, 1))
		"setCosmeticsPolicy": api.set_cosmetics_policy(_dict(a, 0))
		"registerEffect": return api.register_effect(_str(a, 0), _dict(a, 1))
		"registerBlockTick":
			var tick_id := _int(a, 1, -1)
			api.register_block_tick(_str(a, 0), func(ctx): _invoke(tick_id, [ctx]), _dict(a, 2))
		"scheduleBlockTick": api.schedule_block_tick(_block_pos(a, 0), float(a[1]) if a.size() > 1 else 0.0, _dict(a, 2))
		"getLight": return api.get_light(_block_pos(a, 0))
		"getLightLevels": return api.get_light_levels(_block_pos(a, 0))
		"worldClock": return api.get_world_clock()
		"breakBlock": api.break_block(_block_pos(a, 0), a[1] if a.size() > 1 and a[1] is bool else true)
		"playEffect":
			var options := _dict(a, 2)
			if options.has("follow"):
				options.follow = _any_ref([options.follow], 0)
			if options.get("direction") is Dictionary:
				options.direction = _vec3([options.direction], 0)
			api.play_effect(_str(a, 0), _vec3(a, 1), options)
		"explode":
			var blast := _dict(a, 2)
			if blast.has("source"):
				blast.source = _any_ref([blast.source], 0)
			api.explode(_vec3(a, 0), float(a[1]) if a.size() > 1 else 3.0, blast)
		"makeNoise": api.make_noise(_vec3(a, 0), float(a[1]) if a.size() > 1 else 8.0, _any_ref(a, 2))
		"registerMobBehavior":
			var score_id := _int(a, 1, -1)
			var update_id := _int(a, 2, -1)
			var stop_id := _int(a, 3, -1)
			api.register_mob_behavior(_str(a, 0), {
				"score": func(brain): return _behavior_call(score_id, brain, 0.0),
				"update": func(brain, delta): _behavior_call(update_id, brain, delta),
				"stop": (func(brain): _behavior_call(stop_id, brain, 0.0)) if stop_id >= 0 else Callable(),
			})
		"getGameplay": return api.get_gameplay(_str(a, 0))
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
		"give": return player.give(_int(a, 1), _int(a, 2, 1), _dict(a, 3))
		"getItem": return player.get_item(_int(a, 1))
		"setItemData": player.set_item_data(_int(a, 1), _dict(a, 2))
		"selectedSlot": return player.selected_slot
		"equipmentSlot": return player.equipment_slot(_str(a, 1))
		"damageItem": player.damage_item(_int(a, 1), _int(a, 2, 1), _str(a, 3) if a.size() > 3 else "use")
		"stats": return player.get_stats()
		"getStat": return player.get_stat(_str(a, 1))
		"addModifier": player.add_modifier(_str(a, 1), _str(a, 2), float(a[3]) if a.size() > 3 else 0.0, _str(a, 4) if a.size() > 4 else "add", float(a[5]) if a.size() > 5 else 0.0)
		"removeModifier": player.remove_modifier(_str(a, 1))
		"grantCosmetic": player.grant_cosmetic(api._qualify_ref(_str(a, 1)))
		"revokeCosmetic": player.revoke_cosmetic(api._qualify_ref(_str(a, 1)))
		"hasCosmetic": return player.has_cosmetic(api._qualify_ref(_str(a, 1)))
		"cosmetics": return player.owned_cosmetics.keys()
		"avatar": return player.avatar
		"setAvatarOverride": player.set_avatar_override(_dict(a, 1))
		"refreshStats": player.refresh_stats()
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
		"health": return player.health
		"maxHealth": return player.max_health
		"isDead": return player.dead
		"setHealth": player.set_health(float(a[1]) if a.size() > 1 else player.max_health)
		"heal": player.heal(float(a[1]) if a.size() > 1 else 1.0)
		"damage": return player.damage(float(a[1]) if a.size() > 1 else 1.0, _str(a, 2) if a.size() > 2 else "magic", _any_ref(a, 3))
		"playSound": player.play_sound(_str(a, 1), float(a[2]) if a.size() > 2 else 1.0, float(a[3]) if a.size() > 3 else 1.0)
		"drop": player.drop(_int(a, 1), _int(a, 2, 1))
		"push": player.push(_vec3(a, 1))
		"setTeam": player.team = _str(a, 1)
		"knowsRecipe": return player.knows_recipe(api._qualify_ref(_str(a, 1)))
		"learnRecipe": return player.learn_recipe(api._qualify_ref(_str(a, 1)), "mod")
		"team": return player.team
		"setSpawnPoint": player.spawn_point = _vec3(a, 1) if a.size() > 1 and a[1] != null else Vector3.INF
		_: return HostError.new("unknown player method '%s'" % method)
	return null


func _call_entity(method: String, a: Array):
	var e = _entity_ref(a, 0)
	if method == "alive":
		return e != null and e.is_alive()
	if e == null:
		return HostError.new("entity is gone")
	match method:
		"type": return e.type_name
		"position": return e.position
		"setPosition": e.position = _vec3(a, 1)
		"velocity": return e.velocity
		"setVelocity": e.velocity = _vec3(a, 1)
		"push": e.push(_vec3(a, 1))
		"health": return e.health
		"maxHealth": return e.max_health
		"damage": return e.damage(float(a[1]) if a.size() > 1 else 1.0, _any_ref(a, 2), _str(a, 3) if a.size() > 3 else "magic")
		"heal": e.heal(float(a[1]) if a.size() > 1 else 1.0)
		"remove": e.remove()
		"setGoal": e.set_goal(_vec3(a, 1) if a.size() > 1 and a[1] != null else Vector3.INF)
		"target": return e.get_target()
		"setTarget": e.set_target(_any_ref(a, 1))
		"addThreat": e.add_threat(_any_ref(a, 1), float(a[2]) if a.size() > 2 else 1.0)
		"tune": e.tune(_dict(a, 1))
		"alert": e.alert(_vec3(a, 1))
		"setHome": e.set_home(_vec3(a, 1), float(a[2]) if a.size() > 2 else -1.0)
		"attack": return e.perform_attack(_str(a, 1))
		"behavior": return e.get_behavior()
		"moveTo":
			if e.brain != null:
				e.brain.move_to(_vec3(a, 1), float(a[2]) if a.size() > 2 else 1.0, float(a[3]) if a.size() > 3 else 0.8)
		"stop":
			if e.brain != null:
				e.brain.stop()
		"lookAt":
			if e.brain != null:
				e.brain.look_at(_vec3(a, 1))
		"getData":
			var own: Dictionary = e.data.get(manifest.id, {})
			return own.get(_str(a, 1), a[2] if a.size() > 2 else null)
		"setData":
			if not (e.data.get(manifest.id) is Dictionary):
				e.data[manifest.id] = {}
			e.data[manifest.id][_str(a, 1)] = a[2] if a.size() > 2 else null
		_: return HostError.new("unknown entity method '%s'" % method)
	return null


## JS mob behaviour callbacks run at the mob's think rate with (mob, context).
func _behavior_call(callback_id: int, brain, delta: float):
	if callback_id < 0:
		return 0.0
	var context := {"target": brain.target, "can_see_target": brain.can_see_target(),
		"target_distance": brain.distance_to_target() if brain.target != null else -1.0,
		"health": brain.health_fraction(), "behavior": brain.behavior, "arrived": brain.arrived(), "delta": delta}
	var reply = _invoke(callback_id, [brain.entity, context])
	return float(reply.get("value", 0.0)) if reply is Dictionary and (reply.get("value") is float or reply.get("value") is int) else 0.0


func _entity_ref(a: Array, i: int):
	var ref = a[i] if i < a.size() else null
	var id := int(ref.get("__entity", -1)) if ref is Dictionary else -1
	return _server.entities.entities.get(id)


## A player or entity reference (attackers, projectile owners), or null.
func _any_ref(a: Array, i: int):
	var ref = a[i] if i < a.size() else null
	if ref is Dictionary and ref.has("__entity"):
		return _entity_ref(a, i)
	if ref is Dictionary and ref.has("__player"):
		return _server.players.get(int(ref.__player))
	return null


func _entity_options(options: Dictionary) -> Dictionary:
	var out := {}
	if options.has("yaw"):
		out.yaw = float(options.yaw)
	if options.get("velocity") is Dictionary:
		out.velocity = _vec3([options.velocity], 0)
	if options.get("data") is Dictionary:
		out.data = {manifest.id: options.data}
	return out


# --- Conversion ---------------------------------------------------------------------------------

## Engine values -> JSON-safe values for the prelude.
func to_js(value):
	if value is Vector3i or value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z}
	if value is Object and value.get_script() == ServerPlayer:
		return {"__player": value.peer_id, "name": value.name}
	if value is Object and value.get_script() == ContainerView:
		return {"position": to_js(value.position), "type": value.type.name, "size": value.size()}
	if value is Object and value.get_script() == Entity:
		return {"__entity": value.id, "type": value.type_name, "kind": value.def.kind, "item": value.item_id, "count": value.item_count}
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
