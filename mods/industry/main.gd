extends "res://engine/server/mod.gd"
## Industry: an energy system in the spirit of modded Minecraft power mods.
##
## Machines are 3D model blocks with block data (energy buffers, fuel, stored items). Anything
## touching a cable or another machine joins a network; every 0.25 s each network pools what its
## generators produce, feeds consumers (lamps, miners) and banks the surplus in batteries.
## Right-click a machine for a live panel. Try /industry kit, /industry demo, and /time night.

const Power = preload("power.gd")

const TICK := 0.25
const UI_ID := "industry:machine"
const UI_REFRESH := 0.5
const UI_RANGE := 8.0
const NETWORK_REBUILD_INTERVAL := 5.0

const GENERATOR_OUTPUT := 40.0  # FE per second while burning
const SOLAR_OUTPUT := 15.0  # FE per second at full daylight with open sky
const BATTERY_CAPACITY := 20000.0
const LAMP_DRAW := 4.0  # FE per second
const MINER_BUFFER := 2000.0
const MINER_COST := 120.0  # FE per block
const MINER_INTERVAL := 0.5
const FUEL := {"base:coal": 40.0, "base:coal_ore": 40.0, "base:log": 15.0, "base:planks": 6.0}  # seconds of burn

var api
var ids := {}
var power: Power
var _ui_viewers := {}  # peer_id -> Vector3i being viewed
var _ui_timer := 0.0
var _rebuild_timer := 0.0


func setup(mod_api) -> void:
	api = mod_api
	ids.cable = api.register_block("cable", {
		"display_name": "Energy Cable",
		"model": "models/cable_core.glb",
		"model_arm": "models/cable_arm.glb",
		"connect_group": "power",
		"textures": "textures/cable.png",
	})
	ids.generator = _machine("coal_generator", "Coal Generator")
	ids.solar = _machine("solar_panel", "Solar Panel")
	ids.battery = _machine("battery", "Battery")
	ids.miner = _machine("miner", "Auto Miner")
	ids.lamp = api.register_block("lamp", {"display_name": "Electric Lamp", "model": "models/lamp.glb",
		"textures": "textures/lamp_icon.png", "connect_group": "power"})
	ids.lamp_on = api.register_block("lamp_on", {"display_name": "Electric Lamp (on)", "model": "models/lamp.glb",
		"textures": "textures/lamp_icon.png", "light": 15, "drops": "industry:lamp", "placeable": false, "connect_group": "power"})
	_register_recipes()
	power = Power.new(api, ids)

	api.on("block_placed", _on_placed)
	api.on("block_broken", _on_broken)
	api.on("block_interact", _on_interact)
	api.on("ui_action", _on_ui_action)
	api.on("player_leave", func(ev): _ui_viewers.erase(ev.player.peer_id))
	api.on("player_join", func(ev): ev.player.send_message("Industry is installed: /industry kit for machines, /industry demo for a showcase."))
	api.every(TICK, _tick)
	preload("guide.gd").new().setup(api)
	api.register_command("industry", "kit | demo - machines and a showcase build", _cmd_industry)


func _machine(block_name: String, display: String) -> int:
	return api.register_block(block_name, {
		"display_name": display,
		"model": "models/%s.glb" % block_name,
		"textures": "textures/%s_icon.png" % block_name,
		"interactive": true,
		"orientation": "horizontal",
		"connect_group": "power",
	})


func _register_recipes() -> void:
	api.register_recipe({"base:iron_ore": 1, "base:coal": 1}, "industry:cable", 8)
	api.register_recipe({"base:cobblestone": 8, "base:iron_ore": 1}, "industry:coal_generator")
	api.register_recipe({"base:glass": 3, "base:iron_ore": 1}, "industry:solar_panel")
	api.register_recipe({"base:iron_ore": 2, "base:coal": 2}, "industry:battery")
	api.register_recipe({"base:glass": 1, "base:iron_ore": 1}, "industry:lamp", 2)
	api.register_recipe({"base:iron_ore": 4, "base:cobblestone": 2}, "industry:miner")


# --- World events -------------------------------------------------------------------------------

func _on_placed(ev: Dictionary) -> void:
	if not power.is_network_block(ev.block):
		return
	var initial = _initial_data(ev.block)
	if initial != null:
		api.set_block_data(ev.position, initial)
	power.invalidate()


func _on_broken(ev: Dictionary) -> void:
	if power.is_network_block(ev.block):
		power.invalidate()
	# Engine already cleared the block data; close panels looking at it.
	for peer_id: int in _ui_viewers.keys():
		if _ui_viewers[peer_id] == ev.position:
			_close_ui(peer_id)


func _initial_data(block: int):
	match block:
		ids.generator: return {"burn": 0.0}
		ids.battery: return {"energy": 0.0}
		ids.miner: return {"energy": 0.0, "depth": 0, "stored": {}, "enabled": true, "cooldown": 0.0, "status": "Idle"}
		ids.solar, ids.lamp: return {}
	return null


# --- Simulation ---------------------------------------------------------------------------------

func _tick() -> void:
	_rebuild_timer += TICK
	if _rebuild_timer >= NETWORK_REBUILD_INTERVAL:
		# Picks up machines in chunks that loaded since the last rebuild.
		_rebuild_timer = 0.0
		power.invalidate()
	var daylight: float = api.get_daylight()
	for network in power.networks():
		_simulate(network, daylight)
	_ui_timer += TICK
	if _ui_timer >= UI_REFRESH:
		_ui_timer = 0.0
		_refresh_panels()


func _simulate(network: Dictionary, daylight: float) -> void:
	var produced := 0.0
	for pos: Vector3i in network.generators:
		var data: Dictionary = api.get_block_data(pos)
		if data.get("burn", 0.0) > 0.0:
			data.burn = maxf(0.0, data.burn - TICK)
			produced += GENERATOR_OUTPUT * TICK
	for pos: Vector3i in network.solars:
		if power.sees_sky(pos):
			produced += SOLAR_OUTPUT * daylight * TICK
	network.last_produced = produced / TICK

	var batteries: Array = network.batteries.map(func(p): return api.get_block_data(p))
	var pool := produced
	# Consumers draw from fresh production first, then from batteries.
	for pos: Vector3i in network.lamps:
		var need := LAMP_DRAW * TICK
		var from_pool := minf(need, pool)
		pool -= from_pool
		var got := from_pool + _draw_batteries(need - from_pool, batteries)
		var lit := got >= need * 0.999
		var current: int = api.get_loaded_block(pos)
		if lit and current == ids.lamp:
			api.set_block(pos, ids.lamp_on, true)
		elif not lit and current == ids.lamp_on:
			api.set_block(pos, ids.lamp, true)
	for pos: Vector3i in network.miners:
		var data: Dictionary = api.get_block_data(pos)
		var want := minf(MINER_BUFFER - float(data.get("energy", 0.0)), MINER_COST)
		if want > 0.0:
			var from_pool := minf(want, pool)
			pool -= from_pool
			data.energy = float(data.get("energy", 0.0)) + from_pool + _draw_batteries(want - from_pool, batteries)
		_run_miner(pos, data)
	# Surplus charges batteries.
	for data: Dictionary in batteries:
		var space := BATTERY_CAPACITY - float(data.get("energy", 0.0))
		var put := minf(space, pool)
		data.energy = float(data.get("energy", 0.0)) + put
		pool -= put


## Takes up to `amount` from batteries. Returns energy obtained.
func _draw_batteries(amount: float, batteries: Array) -> float:
	var got := 0.0
	for data: Dictionary in batteries:
		if got >= amount:
			break
		var take := minf(amount - got, float(data.get("energy", 0.0)))
		data.energy = float(data.get("energy", 0.0)) - take
		got += take
	return got


func _run_miner(pos: Vector3i, data: Dictionary) -> void:
	data.cooldown = maxf(0.0, float(data.get("cooldown", 0.0)) - TICK)
	if not data.get("enabled", true):
		data.status = "Paused"
		return
	if data.cooldown > 0.0:
		return
	if float(data.energy) < MINER_COST:
		data.status = "Waiting for power"
		return
	var depth := int(data.get("depth", 0))
	# Skip air and liquids until a minable block is found.
	while true:
		depth += 1
		var target := pos + Vector3i(0, -depth, 0)
		if target.y < 0:
			data.status = "Finished"
			data.depth = depth - 1
			return
		var block: int = api.get_block(target)
		if block == 0 or api.block_name(block) == "base:water":
			continue
		if block == ids.miner or not api.is_breakable(block):
			data.status = "Blocked at depth %d" % depth
			data.depth = depth - 1
			return
		api.set_block(target, 0)
		var stored: Dictionary = data.get("stored", {})
		for drop in api.get_drops(block):
			var key: String = api.item_name(drop[0])
			stored[key] = int(stored.get(key, 0)) + int(drop[1])
		data.stored = stored
		data.energy = float(data.energy) - MINER_COST
		data.depth = depth
		data.cooldown = MINER_INTERVAL
		data.status = "Mining (depth %d)" % depth
		return


# --- Interaction & UI ---------------------------------------------------------------------------

func _on_interact(ev: Dictionary) -> void:
	if not [ids.generator, ids.solar, ids.battery, ids.miner].has(ev.block):
		return
	_ui_viewers[ev.player.peer_id] = ev.position
	_show_panel(ev.player, ev.position)


func _on_ui_action(ev: Dictionary) -> void:
	if ev.ui_id != UI_ID or not _ui_viewers.has(ev.player.peer_id):
		return
	var player = ev.player
	var pos: Vector3i = _ui_viewers[player.peer_id]
	var data: Dictionary = api.get_block_data(pos)
	match ev.action:
		"close":
			_close_ui(player.peer_id)
			return
		"fuel":
			_add_fuel(player, data)
		"collect":
			var stored: Dictionary = data.get("stored", {})
			for key: String in stored.keys():
				var left: int = player.give(api.item(key), int(stored[key]))
				if left > 0:
					stored[key] = left
				else:
					stored.erase(key)
		"toggle":
			data.enabled = not data.get("enabled", true)
	_show_panel(player, pos)


func _add_fuel(player, data: Dictionary) -> void:
	for fuel_name: String in FUEL:
		var fuel: int = api.item(fuel_name)
		if player.is_creative() or player.take(fuel, 1):
			data.burn = float(data.get("burn", 0.0)) + FUEL[fuel_name]
			player.send_message("Added %s (+%ds burn time)" % [api.item_display_name(fuel), FUEL[fuel_name]])
			return
	player.send_message("You need coal, logs or planks to fuel the generator.")


func _refresh_panels() -> void:
	for peer_id: int in _ui_viewers.keys():
		var player = null
		for p in api.get_players():
			if p.peer_id == peer_id:
				player = p
		var pos: Vector3i = _ui_viewers[peer_id]
		if player == null:
			_ui_viewers.erase(peer_id)
		elif player.get_eye_position().distance_to(Vector3(pos) + Vector3.ONE * 0.5) > UI_RANGE \
				or not [ids.generator, ids.solar, ids.battery, ids.miner].has(api.get_loaded_block(pos)):
			_close_ui(peer_id)
		else:
			_show_panel(player, pos)


func _close_ui(peer_id: int) -> void:
	_ui_viewers.erase(peer_id)
	for p in api.get_players():
		if p.peer_id == peer_id:
			p.hide_ui(UI_ID)


func _show_panel(player, pos: Vector3i) -> void:
	var block: int = api.get_loaded_block(pos)
	var data: Dictionary = api.get_block_data(pos)
	var network: Dictionary = power.network_at(pos)
	var net_line := "Network: %d machines, %d cables, producing %.0f FE/s, stored %.0f FE" % [
		network.get("machine_count", 0), network.get("cable_count", 0), network.get("last_produced", 0.0), power.stored(network)] \
		if not network.is_empty() else "Not connected to a network"
	var children := [{"type": "label", "text": api.block_display_name(block), "size": 24, "color": "#ffd166"}]
	var buttons := []
	match block:
		ids.generator:
			var burn := float(data.get("burn", 0.0))
			children.append({"type": "label", "text": "Burning: %ds left  (%s)" % [ceili(burn), "%.0f FE/s" % GENERATOR_OUTPUT if burn > 0.0 else "idle"]})
			children.append({"type": "progress", "value": minf(burn, 120.0), "max": 120.0})
			children.append({"type": "label", "text": "Fuel: coal 40s, log 15s, planks 6s", "color": "#aaaaaa"})
			buttons.append({"type": "button", "text": "Add fuel", "action": "fuel"})
		ids.solar:
			var sky: bool = power.sees_sky(pos)
			children.append({"type": "label", "text": "Output: %.1f FE/s" % (SOLAR_OUTPUT * api.get_daylight() if sky else 0.0)})
			children.append({"type": "label", "text": "Daylight %d%%%s" % [roundi(api.get_daylight() * 100), "" if sky else " - blocked from the sky!"],
				"color": "#aaaaaa" if sky else "#ff8888"})
		ids.battery:
			var energy := float(data.get("energy", 0.0))
			children.append({"type": "label", "text": "Stored: %.0f / %.0f FE" % [energy, BATTERY_CAPACITY]})
			children.append({"type": "progress", "value": energy, "max": BATTERY_CAPACITY})
		ids.miner:
			children.append({"type": "label", "text": "Status: %s" % data.get("status", "Idle")})
			children.append({"type": "label", "text": "Energy: %.0f / %.0f FE  (%.0f per block)" % [float(data.get("energy", 0.0)), MINER_BUFFER, MINER_COST]})
			children.append({"type": "progress", "value": float(data.get("energy", 0.0)), "max": MINER_BUFFER})
			var stored: Dictionary = data.get("stored", {})
			var lines := PackedStringArray()
			for key: String in stored:
				lines.append("%s x%d" % [api.item_display_name(api.item(key)), stored[key]])
			children.append({"type": "label", "text": "Collected: " + (", ".join(lines) if not lines.is_empty() else "nothing yet")})
			buttons.append({"type": "button", "text": "Collect items", "action": "collect"})
			buttons.append({"type": "button", "text": "Pause" if data.get("enabled", true) else "Resume", "action": "toggle"})
	children.append({"type": "label", "text": net_line, "color": "#8ecae6"})
	buttons.append({"type": "button", "text": "Close", "action": "close"})
	children.append({"type": "hbox", "children": buttons})
	player.show_ui(UI_ID, {"anchor": "center", "modal": true, "children": children})


# --- Commands -----------------------------------------------------------------------------------

func _cmd_industry(player, args: PackedStringArray) -> void:
	var sub := args[0] if args.size() > 0 else "kit"
	# Free machines are fine in creative; in survival they would be a cheat.
	if not (player.is_admin() or (sub == "kit" and player.is_creative())):
		player.send_message("Only admins can use /industry %s here." % sub)
		return
	if sub == "demo":
		_build_demo(player)
		return
	var kit := [ids.cable, ids.generator, ids.solar, ids.battery, ids.lamp, ids.miner, api.item("base:coal"), api.block("base:log"), api.block("base:glass")]
	if player.is_creative():
		player.set_hotbar(kit)
	else:
		for block in kit:
			player.give(block, 32 if block == ids.cable else 4)
	player.send_message("Industry kit: cable, generator, solar panel, battery, lamp, auto miner, fuel. Right-click machines to open them.")


## Builds a small powered setup in front of the player: generator + solar + battery feeding a row
## of lamps and a miner through cables.
func _build_demo(player) -> void:
	var feet: Vector3 = player.position
	var forward := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
	var dir := Vector3i(roundi(forward.x), 0, roundi(forward.z)) if absf(forward.x) > absf(forward.z) else Vector3i(0, 0, roundi(forward.z))
	if dir == Vector3i.ZERO:
		dir = Vector3i(0, 0, -1)
	var side := Vector3i(-dir.z, 0, dir.x)
	var origin := Vector3i(floori(feet.x), floori(feet.y), floori(feet.z)) + dir * 3
	var floor_block: int = api.block("base:planks")
	for i in range(-1, 10):
		for j in range(-2, 3):
			var p := origin + dir * i + side * j
			api.fill(p, p + Vector3i(0, 3, 0), 0)
			api.set_block(p + Vector3i.DOWN, floor_block)
	var facing: int = api.facing_from_yaw(player.yaw)
	var place := func(p: Vector3i, block: int) -> void:
		api.set_block(p, block, false, facing if block in [ids.generator, ids.solar, ids.battery, ids.miner] else 0)
		_on_placed({"position": p, "block": block})
	for i in 9:
		place.call(origin + dir * i, ids.cable)
	place.call(origin + side, ids.generator)
	place.call(origin - side, ids.solar)
	place.call(origin + dir + side, ids.battery)
	for i in [2, 4, 6, 8]:
		place.call(origin + dir * i + side, ids.lamp)
		place.call(origin + dir * i - side, ids.lamp)
	place.call(origin + dir * 9, ids.miner)
	api.set_block(origin + dir * 9 + Vector3i.DOWN, api.block("base:stone"))
	api.get_block_data(origin + side).burn = 600.0
	api.get_block_data(origin + dir + side).energy = 5000.0
	player.send_message("Demo built: a fuelled generator and a solar panel power lamps and a miner. Try /time night.")
