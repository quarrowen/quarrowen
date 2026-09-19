extends RefCounted
## Crafting stations that grow: tiers upgraded with kits, workshop blocks placed nearby, and
## multiblock structures.
##
## Station def (api.register_station):
##   title
##   tiers: [{block, title, kit}]   the station's blocks by tier (1, 2, ...); `kit` is the item that
##          upgrades the previous tier into this one (used on the station screen)
##   workshop: {radius, upgrades: [{block, title, max, grants}]}   blocks near the station add grants
##   grants (base, per tier or per upgrade): {features: [...], tier, speed, quality, pull_radius, hints}
##   multiblock: {core, pattern: [layers bottom to top, rows separated by "|"], legend: {char: block}, title}
##          the core block must sit in a structure matching the pattern (rotated in any of four
##          directions); "C" marks the core, "." any block, " " air
## Recipes ask for stations with `station`, `tier` (minimum) and `needs` ([features]).

const VoxelWorld = preload("res://engine/shared/voxel_world.gd")

const DEFAULT_RADIUS := 4
const MAX_RADIUS := 8

var defs := {}  # station name -> def
var _server


func _init(game_server) -> void:
	_server = game_server


func register(station_name: String, def: Dictionary) -> void:
	var d := {"name": station_name, "title": str(def.get("title", station_name.get_slice(":", station_name.count(":")).capitalize())),
		"tiers": [], "grants": _grants(def.get("grants")), "workshop": {"radius": DEFAULT_RADIUS, "upgrades": []}, "multiblock": {}}
	for t in (def.get("tiers") if def.get("tiers") is Array else []):
		if t is Dictionary:
			d.tiers.append({"block": _server.registry.id_of(str(t.get("block", ""))), "title": str(t.get("title", "")),
				"kit": _server.items.id_of(str(t.get("kit", ""))) if t.has("kit") else 0, "grants": _grants(t.get("grants"))})
	var w = def.get("workshop")
	if w is Dictionary:
		d.workshop.radius = clampi(int(w.get("radius", DEFAULT_RADIUS)), 1, MAX_RADIUS)
		for u in (w.get("upgrades") if w.get("upgrades") is Array else []):
			if u is Dictionary and _server.registry.id_of(str(u.get("block", ""))) > 0:
				var block: int = _server.registry.id_of(str(u.block))
				d.workshop.upgrades.append({"block": block, "title": str(u.get("title", _server.registry.defs[block].display_name)),
					"max": clampi(int(u.get("max", 1)), 1, 16), "grants": _grants(u.get("grants"))})
	var m = def.get("multiblock")
	if m is Dictionary and m.get("pattern") is Array and m.get("legend") is Dictionary:
		var legend := {}
		for ch in m.legend:
			legend[str(ch)] = _server.registry.id_of(str(m.legend[ch]))
		d.multiblock = {"core": _server.registry.id_of(str(m.get("core", ""))), "pattern": (m.pattern as Array).map(func(l): return str(l)),
			"legend": legend, "title": str(m.get("title", d.title))}
	defs[station_name] = d


## Station name of a block: from a registered station's tiers or multiblock core, or the block's own
## `station` key. "" when the block is not a station.
func station_of_block(block: int) -> String:
	if not _server.registry.is_valid(block):
		return ""
	return str(_server.registry.defs[block].get("station", ""))


## Everything about the station at a position: {name, title, tier, tier_title, features, speed,
## quality, pull_radius, hints, detected: [...], available: [...], next: {...}, structure: {...}}.
func evaluate(pos: Vector3i) -> Dictionary:
	var block: int = _server.world.get_block_v(pos)
	var station_name := station_of_block(block)
	if station_name.is_empty():
		return {}
	var def: Dictionary = defs.get(station_name, {})
	var info := {"name": station_name, "title": def.get("title", _server.registry.defs[block].display_name), "position": pos,
		"tier": 1, "tier_index": 1, "tier_title": _server.registry.defs[block].display_name, "features": [], "speed": 0.0, "quality": 0.0,
		"pull_radius": 0, "hints": 0, "detected": [], "available": [], "next": {}, "structure": {}}
	var tiers: Array = def.get("tiers", [])
	for i in tiers.size():
		if tiers[i].block == block:
			info.tier = i + 1
			info.tier_index = i + 1
			if not tiers[i].title.is_empty():
				info.tier_title = tiers[i].title
			for j in i + 1:
				_apply(info, tiers[j].grants)
			if i + 1 < tiers.size():
				var n: Dictionary = tiers[i + 1]
				info.next = {"tier": i + 2, "title": n.title if not n.title.is_empty() else _server.registry.defs[n.block].display_name,
					"kit": n.kit, "grants": _describe(n.grants)}
	_apply(info, def.get("grants", {}))
	if not def.get("workshop", {}).get("upgrades", []).is_empty():
		var counts := _count_nearby(pos, def.workshop.radius, def.workshop.upgrades.map(func(u): return u.block))
		for u in def.workshop.upgrades:
			var n := mini(int(counts.get(u.block, 0)), u.max)
			var entry := {"block": u.block, "title": u.title, "count": n, "max": u.max, "grants": _describe(u.grants)}
			if n > 0:
				for k in n:
					_apply(info, u.grants)
				info.detected.append(entry)
			else:
				info.available.append(entry)
	if not def.get("multiblock", {}).is_empty():
		var missing := structure_missing(pos, def.multiblock)
		info.structure = {"title": def.multiblock.title, "formed": missing.is_empty(), "missing": missing.size()}
	info.features = info.features.duplicate()
	return info


## Whether the station is usable: multiblock stations must be complete.
static func usable(info: Dictionary) -> bool:
	return not info.is_empty() and (info.structure.is_empty() or info.structure.formed)


## The best rotation's missing blocks as [[position, block id], ...] (empty when the structure is
## complete). The core is the block at "C".
func structure_missing(core_pos: Vector3i, m: Dictionary) -> Array:
	var best: Array = []
	var best_count := 1 << 30
	var cells := _pattern_cells(m)
	for rotation in 4:
		var missing := []
		for cell in cells:
			var offset: Vector3i = _rotate(cell[0], rotation)
			var p := core_pos + offset
			var want: int = cell[1]
			var have: int = _server.get_block_loaded(p)
			if want == -1:
				if have == 0:
					missing.append([p, -1])
			elif have != want:
				missing.append([p, want])
		if missing.size() < best_count:
			best = missing
			best_count = missing.size()
		if best_count == 0:
			break
	return best


## [[offset from core, block id | 0 air | -1 anything solid], ...] for a multiblock pattern.
func _pattern_cells(m: Dictionary) -> Array:
	var layers: Array = m.pattern
	var core := Vector3i.ZERO
	for y in layers.size():
		var rows: PackedStringArray = str(layers[y]).split("|")
		for z in rows.size():
			var x := rows[z].find("C")
			if x >= 0:
				core = Vector3i(x, y, z)
	var cells := []
	for y in layers.size():
		var rows: PackedStringArray = str(layers[y]).split("|")
		for z in rows.size():
			for x in rows[z].length():
				var ch := rows[z][x]
				if ch == "C":
					continue
				var id: int = 0 if ch == " " else (-1 if ch == "." else int(m.legend.get(ch, 0)))
				cells.append([Vector3i(x, y, z) - core, id])
	return cells


static func _rotate(v: Vector3i, rotation: int) -> Vector3i:
	match rotation:
		1: return Vector3i(-v.z, v.y, v.x)
		2: return Vector3i(-v.x, v.y, -v.z)
		3: return Vector3i(v.z, v.y, -v.x)
	return v


## Uses the next tier's kit from the player's inventory on the station. Returns true if it upgraded.
func upgrade(p, pos: Vector3i) -> bool:
	var info := evaluate(pos)
	if info.is_empty() or info.next.is_empty():
		return false
	var def: Dictionary = defs[info.name]
	var next: Dictionary = def.tiers[info.tier_index]
	if next.kit > 0 and not p.inventory.creative:
		if not p.take(next.kit, 1):
			return false
	var into = _server.realm_of(p)
	_server.set_block_authoritative(pos, next.block, true, _server.get_block_state(pos, into), into)
	_server.play_effect("engine:sparkle", Vector3(pos) + Vector3(0.5, 0.9, 0.5), {"scale": 1.4, "color": "#ffe08a"})
	_server.play_sound_at("engine:craft", Vector3(pos) + Vector3.ONE * 0.5, 1.0, 0.8)
	_server.emit("station_upgraded", {"player": p, "position": pos, "station": info.name, "tier": info.tier + 1})
	return true


## For clients: every station's titles, tiers, upgrades and structure so recipe requirements can be
## explained anywhere.
func to_network() -> Dictionary:
	var out := {}
	for station_name in defs:
		var d: Dictionary = defs[station_name]
		out[station_name] = {"title": d.title, "tiers": d.tiers.map(func(t): return {"block": t.block, "title": t.title, "kit": t.kit, "grants": _describe(t.grants)}),
			"upgrades": d.workshop.upgrades.map(func(u): return {"block": u.block, "title": u.title, "grants": _describe(u.grants)}),
			"structure": d.multiblock.get("title", "") if not d.multiblock.is_empty() else ""}
	return out


func _count_nearby(center: Vector3i, radius: int, blocks: Array) -> Dictionary:
	var wanted := {}
	for b in blocks:
		wanted[b] = true
	var counts := {}
	for y in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var b: int = _server.world.get_block_v(center + Vector3i(x, y, z))
				if wanted.has(b):
					counts[b] = int(counts.get(b, 0)) + 1
	return counts


static func _grants(value) -> Dictionary:
	var g: Dictionary = value if value is Dictionary else {}
	return {"features": (g.get("features") as Array).map(func(f): return str(f)) if g.get("features") is Array else [],
		"tier": int(g.get("tier", 0)), "speed": float(g.get("speed", 0.0)), "quality": float(g.get("quality", 0.0)),
		"pull_radius": int(g.get("pull_radius", 0)), "hints": int(g.get("hints", 0))}


static func _apply(info: Dictionary, g: Dictionary) -> void:
	if g.is_empty():
		return
	for f in g.features:
		if not info.features.has(f):
			info.features.append(f)
	info.tier += g.tier
	info.speed += g.speed
	info.quality += g.quality
	info.pull_radius += g.pull_radius
	info.hints += g.hints


## Short human text for grants ("Metalwork, +10% quality").
static func _describe(g: Dictionary) -> String:
	var parts := PackedStringArray()
	for f in g.get("features", []):
		parts.append(str(f).capitalize())
	if g.get("tier", 0) > 0:
		parts.append("+%d tier" % g.tier)
	if g.get("speed", 0.0) > 0.0:
		parts.append("+%d%% speed" % roundi(g.speed * 100))
	if g.get("quality", 0.0) > 0.0:
		parts.append("+%d%% quality" % roundi(g.quality * 100))
	if g.get("pull_radius", 0) > 0:
		parts.append("+%d chest reach" % g.pull_radius)
	if g.get("hints", 0) > 0:
		parts.append("recipe hints")
	return ", ".join(parts)
