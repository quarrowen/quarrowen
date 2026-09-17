extends RefCounted
## Runtime block table. The server builds it from mod registrations; clients rebuild it from the
## plain-data copy the server sends. Block ids are u16: 0 is air, 65535 marks unloaded chunks.

const AIR := 0
const UNLOADED := 65535
const MAX_BLOCKS := 65535
## Lookup tables are indexed directly by block id.
const LUT_SIZE := 65536
const MAX_NAME_LENGTH := 64

enum Render { INVISIBLE, OPAQUE, CUTOUT, TRANSLUCENT, MODEL, PLANT }

const RENDER_NAMES := {
	"invisible": Render.INVISIBLE,
	"opaque": Render.OPAQUE,
	"cutout": Render.CUTOUT,
	"translucent": Render.TRANSLUCENT,
	"model": Render.MODEL,
	"plant": Render.PLANT,  # two crossed quads (grass, flowers, crops, saplings); not solid by default
}

## Fields sent to clients. Anything else in a definition (e.g. drops) stays on the server.
const NETWORK_FIELDS := ["name", "display_name", "render", "solid", "liquid", "cull_same", "breakable", "placeable",
	"textures", "light", "interactive", "model", "orientation", "connect_group", "model_arm", "sway", "sounds",
	"hardness", "tier", "tool", "replaceable", "shape", "facing_blocks"]

## Blocks that do not fill their cell. The shape decides both what is drawn and what a player or a mob
## walks into, so the two can never disagree; every shape is a list of boxes in block space (0..1).
## Stairs face a direction, so each facing is its own shape (and its own block id): no per-block state
## has to reach the mesher or the physics.
enum Shape { FULL, SLAB_BOTTOM, SLAB_TOP, STAIRS_NORTH, STAIRS_EAST, STAIRS_SOUTH, STAIRS_WEST, FENCE,
	DOOR_NORTH, DOOR_EAST, DOOR_SOUTH, DOOR_WEST, PANE_X, PANE_Z,
	FENCE_POST, FENCE_N, FENCE_E, FENCE_NE, FENCE_S, FENCE_NS, FENCE_ES, FENCE_NES, FENCE_W, FENCE_NW, FENCE_EW, FENCE_NEW, FENCE_SW, FENCE_NSW, FENCE_ESW, FENCE_NESW }
const SHAPE_NAMES := {
	"full": Shape.FULL, "slab": Shape.SLAB_BOTTOM, "slab_bottom": Shape.SLAB_BOTTOM, "slab_top": Shape.SLAB_TOP,
	"stairs_north": Shape.STAIRS_NORTH, "stairs_east": Shape.STAIRS_EAST, "stairs_south": Shape.STAIRS_SOUTH,
	"stairs_west": Shape.STAIRS_WEST, "fence": Shape.FENCE,
	"door_north": Shape.DOOR_NORTH, "door_east": Shape.DOOR_EAST, "door_south": Shape.DOOR_SOUTH,
	"door_west": Shape.DOOR_WEST, "pane_x": Shape.PANE_X, "pane_z": Shape.PANE_Z,
	"fence_post": Shape.FENCE_POST,
	"fence_n": Shape.FENCE_N,
	"fence_e": Shape.FENCE_E,
	"fence_ne": Shape.FENCE_NE,
	"fence_s": Shape.FENCE_S,
	"fence_ns": Shape.FENCE_NS,
	"fence_es": Shape.FENCE_ES,
	"fence_nes": Shape.FENCE_NES,
	"fence_w": Shape.FENCE_W,
	"fence_nw": Shape.FENCE_NW,
	"fence_ew": Shape.FENCE_EW,
	"fence_new": Shape.FENCE_NEW,
	"fence_sw": Shape.FENCE_SW,
	"fence_nsw": Shape.FENCE_NSW,
	"fence_esw": Shape.FENCE_ESW,
	"fence_nesw": Shape.FENCE_NESW,
}
## The boxes each shape fills: [x0, y0, z0, x1, y1, z1] in block space. Stairs are the bottom slab plus the
## half that stands up, named after the side that half is on: north stairs are high at north (-z), so you
## climb them walking north. Placing a stairs block picks the variant that climbs away from the player.
const SHAPE_BOXES := {
	Shape.FULL: [[0.0, 0.0, 0.0, 1.0, 1.0, 1.0]],
	Shape.SLAB_BOTTOM: [[0.0, 0.0, 0.0, 1.0, 0.5, 1.0]],
	Shape.SLAB_TOP: [[0.0, 0.5, 0.0, 1.0, 1.0, 1.0]],
	Shape.STAIRS_NORTH: [[0.0, 0.0, 0.0, 1.0, 0.5, 1.0], [0.0, 0.5, 0.0, 1.0, 1.0, 0.5]],
	Shape.STAIRS_EAST: [[0.0, 0.0, 0.0, 1.0, 0.5, 1.0], [0.5, 0.5, 0.0, 1.0, 1.0, 1.0]],
	Shape.STAIRS_SOUTH: [[0.0, 0.0, 0.0, 1.0, 0.5, 1.0], [0.0, 0.5, 0.5, 1.0, 1.0, 1.0]],
	Shape.STAIRS_WEST: [[0.0, 0.0, 0.0, 1.0, 0.5, 1.0], [0.0, 0.5, 0.0, 0.5, 1.0, 1.0]],
	# A fence is a post you cannot walk through and cannot jump over (its box is taller than the block).
	Shape.FENCE: [[0.375, 0.0, 0.375, 0.625, 1.5, 0.625]],
	# A door is a thin panel against one side of its cell, named after the side it is on. Opening one does
	# not need shapes of its own: an open door is the same panel against the next side round, so a mod
	# swaps to the block whose shape says so (see mods/base/openings.gd).
	Shape.DOOR_NORTH: [[0.0, 0.0, 0.0, 1.0, 1.0, 0.1875]],
	Shape.DOOR_EAST: [[0.8125, 0.0, 0.0, 1.0, 1.0, 1.0]],
	Shape.DOOR_SOUTH: [[0.0, 0.0, 0.8125, 1.0, 1.0, 1.0]],
	Shape.DOOR_WEST: [[0.0, 0.0, 0.0, 0.1875, 1.0, 1.0]],
	# A pane stands in the middle of its cell: glass, bars, a shutter. Named for the axis it runs along.
	Shape.PANE_X: [[0.4375, 0.0, 0.0, 0.5625, 1.0, 1.0]],
	Shape.PANE_Z: [[0.0, 0.0, 0.4375, 1.0, 1.0, 0.5625]],
	# A fence that knows its neighbours: the post, plus a rail towards each side it joins on to. Which of
	# the sixteen a fence is gets worked out when anything next to it changes (engine/server/connect.gd).
	Shape.FENCE_POST: [[0.375, 0, 0.375, 0.625, 1.5, 0.625]],
	Shape.FENCE_N: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.4375, 0.375, 0, 0.5625, 1.3125, 0.375]],
	Shape.FENCE_E: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.625, 0.375, 0.4375, 1, 1.3125, 0.5625]],
	Shape.FENCE_NE: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.4375, 0.375, 0, 0.5625, 1.3125, 0.375], [0.625, 0.375, 0.4375, 1, 1.3125, 0.5625]],
	Shape.FENCE_S: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.4375, 0.375, 0.625, 0.5625, 1.3125, 1]],
	Shape.FENCE_NS: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.4375, 0.375, 0, 0.5625, 1.3125, 0.375], [0.4375, 0.375, 0.625, 0.5625, 1.3125, 1]],
	Shape.FENCE_ES: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.625, 0.375, 0.4375, 1, 1.3125, 0.5625], [0.4375, 0.375, 0.625, 0.5625, 1.3125, 1]],
	Shape.FENCE_NES: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.4375, 0.375, 0, 0.5625, 1.3125, 0.375], [0.625, 0.375, 0.4375, 1, 1.3125, 0.5625], [0.4375, 0.375, 0.625, 0.5625, 1.3125, 1]],
	Shape.FENCE_W: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0, 0.375, 0.4375, 0.375, 1.3125, 0.5625]],
	Shape.FENCE_NW: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.4375, 0.375, 0, 0.5625, 1.3125, 0.375], [0, 0.375, 0.4375, 0.375, 1.3125, 0.5625]],
	Shape.FENCE_EW: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.625, 0.375, 0.4375, 1, 1.3125, 0.5625], [0, 0.375, 0.4375, 0.375, 1.3125, 0.5625]],
	Shape.FENCE_NEW: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.4375, 0.375, 0, 0.5625, 1.3125, 0.375], [0.625, 0.375, 0.4375, 1, 1.3125, 0.5625], [0, 0.375, 0.4375, 0.375, 1.3125, 0.5625]],
	Shape.FENCE_SW: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.4375, 0.375, 0.625, 0.5625, 1.3125, 1], [0, 0.375, 0.4375, 0.375, 1.3125, 0.5625]],
	Shape.FENCE_NSW: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.4375, 0.375, 0, 0.5625, 1.3125, 0.375], [0.4375, 0.375, 0.625, 0.5625, 1.3125, 1], [0, 0.375, 0.4375, 0.375, 1.3125, 0.5625]],
	Shape.FENCE_ESW: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.625, 0.375, 0.4375, 1, 1.3125, 0.5625], [0.4375, 0.375, 0.625, 0.5625, 1.3125, 1], [0, 0.375, 0.4375, 0.375, 1.3125, 0.5625]],
	Shape.FENCE_NESW: [[0.375, 0, 0.375, 0.625, 1.5, 0.625], [0.4375, 0.375, 0, 0.5625, 1.3125, 0.375], [0.625, 0.375, 0.4375, 1, 1.3125, 0.5625], [0.4375, 0.375, 0.625, 0.5625, 1.3125, 1], [0, 0.375, 0.4375, 0.375, 1.3125, 0.5625]],
}

## Face order used by `textures`: +X, -X, +Y (top), -Y (bottom), +Z, -Z.
const FACE_COUNT := 6

var defs: Array[Dictionary] = []
var ids := {}  # name -> id

var solid_lut := PackedByteArray()
## Which shape each block fills its cell with (Shape); FULL for almost everything.
var shape_lut := PackedByteArray()
var opaque_lut := PackedByteArray()
var render_lut := PackedByteArray()
var cull_same_lut := PackedByteArray()
var liquid_lut := PackedByteArray()
var breakable_lut := PackedByteArray()
var placeable_lut := PackedByteArray()
var targetable_lut := PackedByteArray()
var emission_lut := PackedByteArray()
var interactive_lut := PackedByteArray()
var sway_lut := PackedByteArray()
## Blocks mobs never path into or onto (e.g. lava, spikes). Server-side only.
var hazard_lut := PackedByteArray()


func _init() -> void:
	register({"name": "engine:air", "display_name": "Air", "render": "invisible"})


## Server-only keys: drops, hazard, support ("solid" or [block names] the block must stand on; it breaks
## when that block goes away and cannot be placed elsewhere).
## Definition keys: name, display_name, render ("opaque" | "cutout" | "translucent" | "invisible" | "plant"),
## solid, liquid, cull_same, breakable, placeable, textures as a String (all faces), a Dictionary
## {all, side, top, bottom} or an Array of 6 names, light (0-15 emitted), interactive (right-click
## fires block_interact instead of placing), model (glTF asset name, with render "model"),
## orientation ("none" | "horizontal": the block state stores a facing 0-3 set on placement so the
## model faces the player), connect_group and model_arm (a model with an arm is centred on the block
## and draws the arm toward each neighbour sharing its connect_group, e.g. cables into machines).
## Returns the id, or -1 on error.
## `replace`: an existing block of that name gets the new definition in place (same id; mod reloads).
func register(def: Dictionary, replace := false) -> int:
	var block_name := String(def.get("name", ""))
	if block_name.is_empty() or block_name.length() > MAX_NAME_LENGTH or (ids.has(block_name) and not replace):
		push_error("Invalid or duplicate block name '%s'" % block_name)
		return -1
	if defs.size() >= MAX_BLOCKS:
		push_error("Block limit (%d) reached registering '%s'" % [MAX_BLOCKS, block_name])
		return -1
	var d := def.duplicate(true)
	var render: int = RENDER_NAMES.get(String(def.get("render", "opaque")), Render.OPAQUE) \
		if def.get("render") is String else clampi(int(def.get("render", Render.OPAQUE)), 0, Render.PLANT)
	var liquid := bool(def.get("liquid", false))
	d.name = block_name
	d.display_name = String(def.get("display_name", block_name.get_slice(":", 1).capitalize())).left(MAX_NAME_LENGTH)
	d.render = render
	d.liquid = liquid
	d.solid = bool(def.get("solid", render != Render.INVISIBLE and render != Render.PLANT and not liquid))
	d.replaceable = bool(def.get("replaceable", false))  # placing a block here replaces it (tall grass)
	d.cull_same = bool(def.get("cull_same", render == Render.TRANSLUCENT))
	d.breakable = bool(def.get("breakable", render != Render.INVISIBLE and not liquid))
	d.placeable = bool(def.get("placeable", d.breakable))
	d.textures = expand_textures(def.get("textures"))
	d.light = clampi(int(def.get("light", 0)), 0, 15)
	d.interactive = bool(def.get("interactive", false))
	d.model = String(def.get("model", "")).left(256)
	d.orientation = 1 if def.get("orientation") in ["horizontal", 1] else 0
	d.shape = SHAPE_NAMES.get(String(def.get("shape", "full")), Shape.FULL) if def.get("shape") is String \
		else clampi(int(def.get("shape", Shape.FULL)), 0, Shape.FENCE_NESW)
	## Blocks whose shape faces a direction (stairs) name their four variants here, one per facing; placing
	## this block places the one that faces the player. Each variant drops the block that is carried.
	d.facing_blocks = (def.get("facing_blocks") as Array).map(func(n): return String(n)) \
		if def.get("facing_blocks") is Array and (def.facing_blocks as Array).size() == 4 else []
	d.connect_group = String(def.get("connect_group", "")).left(64)
	d.model_arm = String(def.get("model_arm", "")).left(256)
	## Foliage that sways in the wind (visual only).
	d.sway = bool(def.get("sway", false))
	d.hazard = bool(def.get("hazard", false))
	## Mining: seconds by hand ~ hardness * 1.5 (0 = instant), tool tier needed for drops, effective tool type.
	d.hardness = clampf(float(def.get("hardness", 0.5)), 0.0, 1000.0)
	d.tier = clampi(int(def.get("tier", 0)), 0, 100)
	d.tool = String(def.get("tool", "")).left(32)
	## Sound names per action: {"break": "base:stone", "place": ..., "step": ...}.
	d.sounds = {}
	if def.get("sounds") is Dictionary:
		for action in ["break", "place", "step"]:
			if def.sounds.get(action) is String:
				d.sounds[action] = String(def.sounds[action]).left(128)
	if ids.has(block_name):
		var existing: int = ids[block_name]
		d.id = existing
		defs[existing].clear()
		defs[existing].merge(d)  # in place: whoever holds the old definition sees the new one
		_rebuild_luts()
		return existing
	var id := defs.size()
	d.id = id
	defs.append(d)
	ids[block_name] = id
	_rebuild_luts()
	return id


## Facing (0-3) for a horizontally oriented block placed by a player looking along `yaw`: the block's
## front (+Z in model space) turns toward the player.
static func facing_from_yaw(yaw: float) -> int:
	return wrapi(roundi(yaw / (PI * 0.5)), 0, 4)


## Direction the front of a block with this facing points to.
static func facing_direction(facing: int) -> Vector3i:
	return [Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(-1, 0, 0)][facing & 3]


func id_of(block_name: String) -> int:
	return ids.get(block_name, -1)


func is_valid(id: int) -> bool:
	return id >= 0 and id < defs.size()


func display_name(id: int) -> String:
	return defs[id].display_name if is_valid(id) else "?"


static func expand_textures(value) -> Array:
	var faces := ["", "", "", "", "", ""]
	if value is String:
		faces.fill(value)
	elif value is Dictionary:
		var all := String(value.get("all", ""))
		var side := String(value.get("side", all))
		faces = [side, side, String(value.get("top", all)), String(value.get("bottom", all)), side, side]
	elif value is Array and value.size() == FACE_COUNT:
		for i in FACE_COUNT:
			faces[i] = String(value[i])
	return faces


func to_network() -> Array:
	var out := []
	for d in defs:
		var entry := {}
		for field in NETWORK_FIELDS:
			entry[field] = d[field]
		out.append(entry)
	return out


## Rebuilds this (fresh) registry from server data. Returns false if the data is malformed.
func load_network(data) -> bool:
	if not (data is Array) or data.is_empty() or data.size() > MAX_BLOCKS:
		return false
	if not (data[0] is Dictionary) or data[0].get("name") != "engine:air":
		return false
	for i in range(1, data.size()):
		var entry = data[i]
		if not (entry is Dictionary) or not (entry.get("name") is String) or not (entry.get("textures") is Array):
			return false
		var clean := {}
		for field in NETWORK_FIELDS:
			if entry.has(field):
				clean[field] = entry[field]
		for tex in clean.textures:
			if not (tex is String) or tex.length() > 256:
				return false
		if register(clean) != i:
			return false
	return true


func _rebuild_luts() -> void:
	var luts: Array[PackedByteArray] = []
	for i in 13:
		var lut := PackedByteArray()
		lut.resize(LUT_SIZE)
		luts.append(lut)
	for d in defs:
		var id: int = d.id
		luts[0][id] = 1 if d.solid else 0
		luts[1][id] = 1 if d.render == Render.OPAQUE and int(d.get("shape", Shape.FULL)) == Shape.FULL else 0
		luts[2][id] = d.render
		luts[3][id] = 1 if d.cull_same else 0
		luts[4][id] = 1 if d.liquid else 0
		luts[5][id] = 1 if d.breakable else 0
		luts[6][id] = 1 if d.placeable else 0
		luts[7][id] = 1 if id != AIR and not d.liquid and d.render != Render.INVISIBLE else 0
		luts[8][id] = d.light
		luts[9][id] = 1 if d.interactive else 0
		luts[10][id] = 1 if d.sway else 0
		luts[11][id] = 1 if d.get("hazard", false) else 0
		luts[12][id] = int(d.get("shape", Shape.FULL))
	luts[0][UNLOADED] = 1
	luts[1][UNLOADED] = 1
	solid_lut = luts[0]
	opaque_lut = luts[1]
	render_lut = luts[2]
	cull_same_lut = luts[3]
	liquid_lut = luts[4]
	breakable_lut = luts[5]
	placeable_lut = luts[6]
	targetable_lut = luts[7]
	emission_lut = luts[8]
	interactive_lut = luts[9]
	sway_lut = luts[10]
	hazard_lut = luts[11]
	shape_lut = luts[12]
