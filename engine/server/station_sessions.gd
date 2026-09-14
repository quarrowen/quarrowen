extends RefCounted
## Co-op crafting at stations: everyone with a station's crafting screen open shares a session.
##   presence: who is there and which recipe they are looking at
##   tray: shared slots on the station; each stack remembers who put it in. You may take back your
##         own stacks; the station's owner and their team may take anything (servers can change this
##         with the `tray_access` gameplay rule: "contributors" | "anyone")
##   jobs: recipes with a `time` are crafted over time in a queue; each extra player at the station
##         speeds them up (+50% per helper, up to 2.5x), times the station's speed bonus
##   projects: big recipes marked `project` that anyone contributes ingredients to over days; the
##         station records who gave what and hands the list to `project_completed`
## State lives in the station block's data under "coop", so it is saved with the world.

const TRAY_SLOTS := 9
const HELPER_BONUS := 0.5
const MAX_SPEEDUP := 2.5
const SYNC_INTERVAL := 0.25

var _server
var _sessions := {}  # Vector3i -> {peer id: {recipe}}
var _dirty := {}  # Vector3i -> true
var _timer := 0.0


func _init(game_server) -> void:
	_server = game_server


## The co-op state of a station: {owner, owner_name, owner_team, tray: [...], jobs: [...], project: {}}.
func coop(pos: Vector3i) -> Dictionary:
	var data: Dictionary = _server.get_block_data(pos)
	if data.is_empty():
		_server.set_block_data(pos, data)
		data = _server.get_block_data(pos)
	if not (data.get("coop") is Dictionary):
		data.coop = {}
	var c: Dictionary = data.coop
	for key in ["tray", "jobs"]:
		if not (c.get(key) is Array):
			c[key] = []
	if not (c.get("project") is Dictionary):
		c.project = {}
	return c


## Records who placed a station (they own its tray).
func claim(pos: Vector3i, p) -> void:
	var c := coop(pos)
	c.owner = p.player_id
	c.owner_name = p.name
	c.owner_team = p.team


func join(p, pos: Vector3i) -> void:
	leave(p)
	if not _sessions.has(pos):
		_sessions[pos] = {}
	_sessions[pos][p.peer_id] = {"recipe": -1}
	_dirty[pos] = true


func leave(p) -> void:
	for pos: Vector3i in _sessions.keys():
		if _sessions[pos].erase(p.peer_id):
			_dirty[pos] = true
			if _sessions[pos].is_empty():
				_sessions.erase(pos)


func viewing(p, recipe: int) -> void:
	for pos: Vector3i in _sessions:
		if _sessions[pos].has(p.peer_id):
			_sessions[pos][p.peer_id].recipe = recipe
			_dirty[pos] = true


func members(pos: Vector3i) -> Array:
	var out := []
	for peer_id: int in _sessions.get(pos, {}):
		var p = _server.players.get(peer_id)
		if p != null and not p.dead:
			out.append(p)
	return out


## How much faster timed crafts go with `helpers` players present.
static func speedup(helpers: int, station_speed: float) -> float:
	return minf(1.0 + HELPER_BONUS * maxi(helpers - 1, 0), MAX_SPEEDUP) * (1.0 + station_speed)


# --- Tray ---------------------------------------------------------------------------------------

func may_take(p, c: Dictionary, stack: Dictionary) -> bool:
	if p.inventory.creative or String(_server.gameplay.get("tray_access", "contributors")) == "anyone":
		return true
	if stack.get("by", "") == p.player_id or String(c.get("owner", "")).is_empty() or c.get("owner", "") == p.player_id:
		return true
	return not p.team.is_empty() and p.team == String(c.get("owner_team", ""))


## Moves the stack in a backpack slot into the tray. Returns true if anything moved.
func deposit(p, pos: Vector3i, slot: int) -> bool:
	var inv = p.inventory
	if slot < 0 or slot >= inv.SIZE or inv.ids[slot] <= 0 or inv.counts[slot] <= 0 or not inv.data[slot].is_empty():
		return false
	var c := coop(pos)
	var item_name: String = _server.items.name_of(inv.ids[slot])
	var limit: int = _server.items.max_stack(inv.ids[slot])
	var left: int = inv.counts[slot]
	for stack in c.tray:
		if left > 0 and stack.item == item_name and stack.by == p.player_id and stack.count < limit:
			var n := mini(left, limit - int(stack.count))
			stack.count = int(stack.count) + n
			left -= n
	while left > 0 and c.tray.size() < TRAY_SLOTS:
		var n := mini(left, limit)
		c.tray.append({"item": item_name, "count": n, "by": p.player_id, "by_name": p.name})
		left -= n
	if left == inv.counts[slot]:
		return false
	if left <= 0:
		inv.clear_slot(slot)
	else:
		inv.counts[slot] = left
	p.sync_inventory()
	_dirty[pos] = true
	return true


func take(p, pos: Vector3i, index: int) -> bool:
	var c := coop(pos)
	if index < 0 or index >= c.tray.size() or not may_take(p, c, c.tray[index]):
		return false
	var stack: Dictionary = c.tray[index]
	var id: int = _server.items.id_of(stack.item)
	var left: int = p.inventory.add(id, int(stack.count), _server.items.max_stack(id)) if id > 0 else 0
	if left > 0:
		stack.count = left
	else:
		c.tray.remove_at(index)
	p.sync_inventory()
	_dirty[pos] = true
	return true


## Tray items this player may use: {item id: count}.
func usable_tray(p, pos: Vector3i) -> Dictionary:
	var out := {}
	var c := coop(pos)
	for stack in c.tray:
		if may_take(p, c, stack):
			var id: int = _server.items.id_of(stack.item)
			if id > 0:
				out[id] = int(out.get(id, 0)) + int(stack.count)
	return out


## Removes up to `count` of an item from the tray stacks the player may use. Returns how many.
func consume_tray(p, pos: Vector3i, item: int, count: int) -> int:
	var c := coop(pos)
	var item_name: String = _server.items.name_of(item)
	var taken := 0
	for i in range(c.tray.size() - 1, -1, -1):
		if taken >= count:
			break
		var stack: Dictionary = c.tray[i]
		if stack.item != item_name or not may_take(p, c, stack):
			continue
		var n := mini(count - taken, int(stack.count))
		stack.count = int(stack.count) - n
		taken += n
		if int(stack.count) <= 0:
			c.tray.remove_at(i)
	if taken > 0:
		_dirty[pos] = true
	return taken


# --- Jobs -----------------------------------------------------------------------------------------

func add_job(p, pos: Vector3i, index: int, times: int) -> void:
	var r: Dictionary = _server.recipes.recipes[index]
	var c := coop(pos)
	c.jobs.append({"recipe": r.id, "times": times, "by": p.player_id, "by_name": p.name, "done": 0.0,
		"total": float(r.get("time", 0.0)) * times})
	_server.emit("craft_job_started", {"player": p, "position": pos, "recipe": r.id, "times": times})
	_dirty[pos] = true


func update(delta: float) -> void:
	for pos: Vector3i in _sessions.keys():
		var present := members(pos)
		if present.is_empty():
			continue
		var c := coop(pos)
		if c.jobs.is_empty():
			continue
		var station: Dictionary = _server.stations.evaluate(pos) if Engine.get_process_frames() % 30 == 0 or not c.has("_speed") else {}
		if not station.is_empty():
			c._speed = float(station.get("speed", 0.0))
		var job: Dictionary = c.jobs[0]
		job.done = float(job.done) + delta * speedup(present.size(), float(c.get("_speed", 0.0)))
		if float(job.done) >= float(job.total):
			c.jobs.pop_front()
			_finish_job(pos, job, present.size())
		_dirty[pos] = true
	_timer += delta
	if _timer < SYNC_INTERVAL:
		return
	_timer = 0.0
	for pos: Vector3i in _dirty:
		_broadcast(pos)
	_dirty.clear()


func _finish_job(pos: Vector3i, job: Dictionary, helpers: int) -> void:
	var index: int = _server.recipes.index_of(String(job.recipe))
	if index < 0:
		return
	var r: Dictionary = _server.recipes.recipes[index]
	var total: int = int(r.count) * int(job.times)
	var owner = null
	for p in _server.players.values():
		if p.player_id == job.by:
			owner = p
	var at := Vector3(pos) + Vector3(0.5, 1.1, 0.5)
	if owner != null and owner.state.position.distance_to(at) <= 32.0:
		var left: int = owner.inventory.add(r.output, total, _server.items.max_stack(r.output))
		if left > 0:
			owner.drop(r.output, left)
		owner.sync_inventory()
	else:
		var c := coop(pos)
		c.tray.append({"item": _server.items.name_of(r.output), "count": total, "by": job.by, "by_name": job.by_name})
	_server.play_effect("engine:craft", at, {"scale": 0.8})
	_server.play_sound_at("engine:craft", at, 0.9, 1.0)
	_server.emit("item_crafted", {"player": owner, "item": r.output, "count": total, "recipe": r.id, "helpers": helpers})
	_server.emit("craft_job_finished", {"player_id": job.by, "position": pos, "recipe": r.id, "times": job.times, "helpers": helpers})


# --- Projects -------------------------------------------------------------------------------------

func start_project(p, pos: Vector3i, index: int) -> bool:
	var c := coop(pos)
	if not c.project.is_empty() or index < 0 or index >= _server.recipes.recipes.size():
		return false
	var r: Dictionary = _server.recipes.recipes[index]
	if not r.get("project", false):
		return false
	c.project = {"recipe": r.id, "delivered": {}, "contributors": {}, "started_by": p.name}
	_dirty[pos] = true
	return true


## Delivers whatever the project still needs from the player's inventory. Returns items delivered.
func contribute(p, pos: Vector3i) -> int:
	var c := coop(pos)
	if c.project.is_empty():
		return 0
	var index: int = _server.recipes.index_of(String(c.project.recipe))
	if index < 0:
		return 0
	var r: Dictionary = _server.recipes.recipes[index]
	var delivered := 0
	for id: int in r.inputs:
		var item_name: String = _server.items.name_of(id)
		var missing: int = int(r.inputs[id]) - int(c.project.delivered.get(item_name, 0))
		var n := mini(missing, p.inventory.count_of(id))
		if n <= 0:
			continue
		p.inventory.remove(id, n)
		c.project.delivered[item_name] = int(c.project.delivered.get(item_name, 0)) + n
		delivered += n
		var entry: Dictionary = c.project.contributors.get(p.player_id, {"name": p.name, "items": 0})
		entry.items = int(entry.items) + n
		c.project.contributors[p.player_id] = entry
		_server.emit("project_contributed", {"player": p, "position": pos, "recipe": r.id, "item": id, "count": n})
	if delivered > 0:
		p.sync_inventory()
		_dirty[pos] = true
		if project_fraction(c.project, r) >= 1.0:
			_complete_project(pos, c, r)
	return delivered


static func project_fraction(project: Dictionary, r: Dictionary) -> float:
	var need := 0
	var have := 0
	for id: int in r.inputs:
		need += int(r.inputs[id])
	for item_name in project.get("delivered", {}):
		have += int(project.delivered[item_name])
	return float(have) / maxf(need, 1)


func _complete_project(pos: Vector3i, c: Dictionary, r: Dictionary) -> void:
	var project: Dictionary = c.project
	c.project = {}
	var at := Vector3(pos) + Vector3(0.5, 1.2, 0.5)
	_server.entities.drop_item(r.output, int(r.count), at, Vector3(0, 3.0, 0), 0.5)
	_server.play_effect("engine:sparkle", at, {"scale": 2.0, "color": "#ffe08a"})
	_server.play_effect("engine:craft", at, {"scale": 1.5})
	_server.play_sound_at("engine:discover", at, 1.0, 1.0)
	var names := PackedStringArray()
	for pid in project.contributors:
		names.append(String(project.contributors[pid].name))
	_server.broadcast_chat("Project complete: %s (thanks to %s)" % [_server.items.display_name(r.output), ", ".join(names)])
	_server.emit("project_completed", {"position": pos, "recipe": r.id, "item": r.output, "contributors": project.contributors})
	_dirty[pos] = true


func cancel_project(p, pos: Vector3i) -> bool:
	var c := coop(pos)
	if c.project.is_empty() or not (p.inventory.creative or String(c.get("owner", "")).is_empty() or c.owner == p.player_id):
		return false
	# Everything delivered goes into the tray, credited to whoever gave the most.
	var top := ""
	var top_items := -1
	for pid in c.project.contributors:
		if int(c.project.contributors[pid].items) > top_items:
			top = pid
			top_items = int(c.project.contributors[pid].items)
	for item_name in c.project.delivered:
		c.tray.append({"item": item_name, "count": int(c.project.delivered[item_name]), "by": top,
			"by_name": c.project.contributors.get(top, {}).get("name", "")})
	c.project = {}
	_dirty[pos] = true
	return true


# --- Network --------------------------------------------------------------------------------------

## What session members see: players and the recipes they look at, tray, jobs with speed, project.
func view(pos: Vector3i) -> Dictionary:
	var c := coop(pos)
	var present := members(pos)
	var players := []
	for p in present:
		players.append({"name": p.name, "recipe": int(_sessions.get(pos, {}).get(p.peer_id, {}).get("recipe", -1))})
	var tray := []
	for stack in c.tray:
		tray.append({"item": _server.items.id_of(stack.item), "count": stack.count, "by_name": stack.get("by_name", ""), "by": stack.get("by", "")})
	var jobs := []
	for job in c.jobs:
		jobs.append({"recipe": _server.recipes.index_of(String(job.recipe)), "times": job.times, "by_name": job.by_name,
			"fraction": clampf(float(job.done) / maxf(float(job.total), 0.001), 0.0, 1.0)})
	var project := {}
	if not c.project.is_empty():
		var index: int = _server.recipes.index_of(String(c.project.recipe))
		var delivered := {}
		for item_name in c.project.delivered:
			delivered[_server.items.id_of(item_name)] = c.project.delivered[item_name]
		var contributors := []
		for pid in c.project.contributors:
			contributors.append({"name": c.project.contributors[pid].name, "items": c.project.contributors[pid].items})
		contributors.sort_custom(func(a, b): return int(a.items) > int(b.items))
		project = {"recipe": index, "delivered": delivered, "contributors": contributors,
			"fraction": project_fraction(c.project, _server.recipes.recipes[index]) if index >= 0 else 0.0}
	return {"position": pos, "players": players, "tray": tray, "jobs": jobs, "project": project,
		"owner": c.get("owner_name", ""), "speedup": speedup(present.size(), float(c.get("_speed", 0.0))), "invites": _server.skill.invites_at(pos)}


func mark(pos: Vector3i) -> void:
	_dirty[pos] = true


func _broadcast(pos: Vector3i) -> void:
	var v := view(pos)
	for p in members(pos):
		if p._online():
			Net.s_station_session.rpc_id(p.peer_id, v)
	# Everyone nearby sees a project's progress above the station.
	var label := ""
	if not v.project.is_empty() and v.project.recipe >= 0:
		label = "%s  %d%%" % [_server.items.display_name(_server.recipes.recipes[v.project.recipe].output), roundi(v.project.fraction * 100)]
	elif not v.jobs.is_empty() and v.jobs[0].recipe >= 0:
		label = "Crafting %s  %d%%" % [_server.items.display_name(_server.recipes.recipes[v.jobs[0].recipe].output), roundi(v.jobs[0].fraction * 100)]
	for p in _server.players.values():
		if p._online() and p.state.position.distance_to(Vector3(pos)) <= 48.0:
			Net.s_station_label.rpc_id(p.peer_id, pos, label)
