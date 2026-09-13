extends RefCounted
## Runtime block table. The server builds it from mod registrations; clients rebuild it from the
## plain-data copy the server sends. Block ids are bytes: 0 is air, 255 marks unloaded chunks.

const AIR := 0
const UNLOADED := 255
const MAX_BLOCKS := 255
const MAX_NAME_LENGTH := 64

enum Render { INVISIBLE, OPAQUE, CUTOUT, TRANSLUCENT, MODEL }

const RENDER_NAMES := {
	"invisible": Render.INVISIBLE,
	"opaque": Render.OPAQUE,
	"cutout": Render.CUTOUT,
	"translucent": Render.TRANSLUCENT,
	"model": Render.MODEL,
}

## Fields sent to clients. Anything else in a definition (e.g. drops) stays on the server.
const NETWORK_FIELDS := ["name", "display_name", "render", "solid", "liquid", "cull_same", "breakable", "placeable",
	"textures", "light", "interactive", "model", "orientation", "connect_group", "model_arm", "sway"]

## Face order used by `textures`: +X, -X, +Y (top), -Y (bottom), +Z, -Z.
const FACE_COUNT := 6

var defs: Array[Dictionary] = []
var ids := {}  # name -> id

var solid_lut := PackedByteArray()
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


func _init() -> void:
	register({"name": "engine:air", "display_name": "Air", "render": "invisible"})


## Definition keys: name, display_name, render ("opaque" | "cutout" | "translucent" | "invisible"),
## solid, liquid, cull_same, breakable, placeable, textures as a String (all faces), a Dictionary
## {all, side, top, bottom} or an Array of 6 names, light (0-15 emitted), interactive (right-click
## fires block_interact instead of placing), model (glTF asset name, with render "model"),
## orientation ("none" | "horizontal": the block state stores a facing 0-3 set on placement so the
## model faces the player), connect_group and model_arm (a model with an arm is centred on the block
## and draws the arm toward each neighbour sharing its connect_group, e.g. cables into machines).
## Returns the id, or -1 on error.
func register(def: Dictionary) -> int:
	var block_name := String(def.get("name", ""))
	if block_name.is_empty() or block_name.length() > MAX_NAME_LENGTH or ids.has(block_name):
		push_error("Invalid or duplicate block name '%s'" % block_name)
		return -1
	if defs.size() >= MAX_BLOCKS:
		push_error("Block limit (%d) reached registering '%s'" % [MAX_BLOCKS, block_name])
		return -1
	var d := def.duplicate(true)
	var render: int = RENDER_NAMES.get(String(def.get("render", "opaque")), Render.OPAQUE) \
		if def.get("render") is String else clampi(int(def.get("render", Render.OPAQUE)), 0, Render.MODEL)
	var liquid := bool(def.get("liquid", false))
	d.name = block_name
	d.display_name = String(def.get("display_name", block_name.get_slice(":", 1).capitalize())).left(MAX_NAME_LENGTH)
	d.render = render
	d.liquid = liquid
	d.solid = bool(def.get("solid", render != Render.INVISIBLE and not liquid))
	d.cull_same = bool(def.get("cull_same", render == Render.TRANSLUCENT))
	d.breakable = bool(def.get("breakable", render != Render.INVISIBLE and not liquid))
	d.placeable = bool(def.get("placeable", d.breakable))
	d.textures = expand_textures(def.get("textures"))
	d.light = clampi(int(def.get("light", 0)), 0, 15)
	d.interactive = bool(def.get("interactive", false))
	d.model = String(def.get("model", "")).left(256)
	d.orientation = 1 if def.get("orientation") in ["horizontal", 1] else 0
	d.connect_group = String(def.get("connect_group", "")).left(64)
	d.model_arm = String(def.get("model_arm", "")).left(256)
	## Foliage that sways in the wind (visual only).
	d.sway = bool(def.get("sway", false))
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
	for i in 11:
		var lut := PackedByteArray()
		lut.resize(256)
		luts.append(lut)
	for d in defs:
		var id: int = d.id
		luts[0][id] = 1 if d.solid else 0
		luts[1][id] = 1 if d.render == Render.OPAQUE else 0
		luts[2][id] = d.render
		luts[3][id] = 1 if d.cull_same else 0
		luts[4][id] = 1 if d.liquid else 0
		luts[5][id] = 1 if d.breakable else 0
		luts[6][id] = 1 if d.placeable else 0
		luts[7][id] = 1 if id != AIR and not d.liquid and d.render != Render.INVISIBLE else 0
		luts[8][id] = d.light
		luts[9][id] = 1 if d.interactive else 0
		luts[10][id] = 1 if d.sway else 0
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
