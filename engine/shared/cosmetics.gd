extends RefCounted
## Cosmetics: how a player looks, separate from what they wear for protection.
##
## A player's avatar is plain data:
##   {skin: "#rrggbb", body: {head, torso, arms, legs: "#rrggbb"} (optional per-part colors),
##    wear: {category: {id, color}}, show_armor: {head|chest|legs|feet: bool}}
## An empty avatar means "the default look for this name" (see default_avatar).
##
## Cosmetics are data too, so they can be made without art tools, and they come from two places:
##   built-in ("builtin:*"): part of the engine, usable on any server that allows them (portable)
##   server cosmetics: registered by mods with api.register_cosmetic, owned per player on that server
## A cosmetic def draws with any mix of:
##   paint:  [{region, rows [from, to], sides [...], color, shade}] fills areas of the 64x64 skin layout
##           region: head, torso, arm_r, arm_l, leg_r, leg_l or their *_overlay (the outer layer)
##           sides: any of front, back, left, right, top, bottom (default: all); color "" = the tint
##   pixels: {rows: 8 strings of 8 characters, palette: {char: "#rrggbb" | "tint" | "skin"}} the face
##   texture: a 64x64 skin-layout layer (asset), multiplied by the tint when `tint` is true
##   boxes:  [{from [x,y,z], size [w,h,d], color, shade}] a voxel accessory in skin pixels, placed at the
##           category's attachment point (+y up, -z forward)
##   model:  a glTF accessory (asset) with model_transform {position, rotation, scale}
## plus: category, display_name, color (default tint), covers (armor slots it replaces when shown),
## unlocked (server cosmetics: false = only players granted it may wear it), description.
##
## Armor versus cosmetics, per armor slot: a worn cosmetic that covers the slot hides that armor piece
## unless the player turned show_armor on for the slot. Servers can force either way (policy.armor).

const BUILTIN_PREFIX := "builtin:"
const ARMOR_SLOTS := ["head", "chest", "legs", "feet"]
const PAINT_REGIONS := ["head", "torso", "arm_r", "arm_l", "leg_r", "leg_l",
	"head_overlay", "torso_overlay", "arm_r_overlay", "arm_l_overlay", "leg_r_overlay", "leg_l_overlay"]
const SIDES := ["front", "back", "left", "right", "top", "bottom"]
const BODY_PARTS := ["head", "torso", "arms", "legs"]
const MAX_CATEGORIES := 32
const MAX_COSMETICS := 2048
const MAX_OPS := 64

## Categories in drawing order: layers of later categories paint over earlier ones.
const DEFAULT_CATEGORIES := [
	{"name": "skin", "display_name": "Skin"},  # a whole painted skin (player creations), under everything
	{"name": "face", "display_name": "Face", "attach": "face"},
	{"name": "pants", "display_name": "Pants"},
	{"name": "shoes", "display_name": "Shoes"},
	{"name": "shirt", "display_name": "Shirt"},
	{"name": "jacket", "display_name": "Jacket"},
	{"name": "hair", "display_name": "Hair", "attach": "hair"},
	{"name": "hat", "display_name": "Hat", "attach": "hat", "covers": ["head"]},
	{"name": "glasses", "display_name": "Glasses", "attach": "face"},
	{"name": "back", "display_name": "Back", "attach": "back"},
]

const DEFAULT_POLICY := {
	"allow_builtin": true,  # players may wear built-in cosmetics (their portable look)
	"allow_colors": true,  # players may recolor tintable cosmetics and pick skin colors
	"armor": "player",  # "player": per-slot choice; "armor": armor always shows; "cosmetics": cosmetics always win
	"blocked": [],  # cosmetic ids or category names nobody may wear here
	"uniform": {},  # avatar data laid over everyone's avatar (e.g. {wear: {shirt: {id, color}}})
}

const SKIN_TONES := ["#f5ccaa", "#e8b48c", "#d29b72", "#b07a52", "#8c5a3a", "#6b4128", "#4a2c1c"]
const HAIR_COLORS := ["#1f1a17", "#3b2618", "#6a4428", "#a8743e", "#d8b36a", "#b0452a", "#9a9a9a", "#e8e8e8"]
const CLOTHING_COLORS := ["#d94c4c", "#e8913a", "#e8cf4a", "#5aa84e", "#3d9c9c", "#4a78d0", "#3b4f7a",
	"#8a58c8", "#d86ca8", "#f0f0f0", "#8a8a8a", "#2a2a2a", "#7a5232"]

const _FACE_PALETTE := {"W": "#ffffff", "I": "tint", "m": "#8a4a40", "b": "#3a2a1a", "f": "skin", "d": "#202020", "s": "#e89a8a"}

const BUILTIN := [
	# Faces: the head's front 8x8. I = eye color (tint).
	{"name": "smile", "category": "face", "display_name": "Smile", "color": "#3050c0",
		"pixels": {"rows": ["........", "........", "........", ".WI..IW.", "........", "..m..m..", "...mm...", "........"]}},
	{"name": "grin", "category": "face", "display_name": "Grin", "color": "#3a8a40",
		"pixels": {"rows": ["........", "........", ".bb..bb.", ".WI..IW.", "........", ".mmmmmm.", "..mWWm..", "........"]}},
	{"name": "calm", "category": "face", "display_name": "Calm", "color": "#6a4428",
		"pixels": {"rows": ["........", "........", "........", ".WI..IW.", "........", "........", "..mmmm..", "........"]}},
	{"name": "wink", "category": "face", "display_name": "Wink", "color": "#3050c0",
		"pixels": {"rows": ["........", "........", "........", ".WI..bb.", "........", "..m..m..", "...mm...", "........"]}},
	{"name": "freckles", "category": "face", "display_name": "Freckles", "color": "#3a8a40",
		"pixels": {"rows": ["........", "........", "........", ".WI..IW.", "f.f..f.f", "..m..m..", "...mm...", "........"]}},
	{"name": "surprised", "category": "face", "display_name": "Surprised", "color": "#6a4428",
		"pixels": {"rows": ["........", "........", ".b....b.", ".WI..IW.", "........", "...mm...", "...mm...", "........"]}},
	{"name": "blush", "category": "face", "display_name": "Blush", "color": "#8a58c8",
		"pixels": {"rows": ["........", "........", "........", ".WI..IW.", "ss....ss", "..m..m..", "...mm...", "........"]}},
	{"name": "cool", "category": "face", "display_name": "Determined", "color": "#202020",
		"pixels": {"rows": ["........", "........", ".bbb.bbb", ".WI..IW.", "........", "........", "..mmm...", "........"]}},

	# Hair: painted on the head's outer layer, some with voxel extras.
	{"name": "short_hair", "category": "hair", "display_name": "Short", "color": "#3b2618", "paint": [
		{"region": "head_overlay", "rows": [0, 2]},
		{"region": "head_overlay", "rows": [2, 5], "sides": ["back"]},
		{"region": "head_overlay", "rows": [2, 3], "sides": ["left", "right"]}]},
	{"name": "long_hair", "category": "hair", "display_name": "Long", "color": "#6a4428", "paint": [
		{"region": "head_overlay", "rows": [0, 2]},
		{"region": "head_overlay", "rows": [2, 8], "sides": ["back", "left", "right"]},
		{"region": "torso_overlay", "rows": [0, 4], "sides": ["back"]}]},
	{"name": "bob_hair", "category": "hair", "display_name": "Bob", "color": "#1f1a17", "paint": [
		{"region": "head_overlay", "rows": [0, 3]},
		{"region": "head_overlay", "rows": [3, 6], "sides": ["back", "left", "right"]}]},
	{"name": "spiky_hair", "category": "hair", "display_name": "Spiky", "color": "#d8b36a", "paint": [
		{"region": "head_overlay", "rows": [0, 2]},
		{"region": "head_overlay", "rows": [2, 4], "sides": ["back"]}],
		"boxes": [{"from": [-3.5, 4, -3], "size": [2, 2, 2]}, {"from": [1.5, 4, -3], "size": [2, 2, 2]},
			{"from": [-1, 4, -1.5], "size": [2, 3, 2]}, {"from": [-3, 4, 1.5], "size": [2, 2, 2]}, {"from": [1, 4, 1.5], "size": [2, 2.5, 2]}]},
	{"name": "ponytail", "category": "hair", "display_name": "Ponytail", "color": "#b0452a", "paint": [
		{"region": "head_overlay", "rows": [0, 2]},
		{"region": "head_overlay", "rows": [2, 5], "sides": ["back"]}],
		"boxes": [{"from": [-1, 1, 4], "size": [2, 2, 1.5]}, {"from": [-1, -4, 4.8], "size": [2, 5, 1.5], "shade": 0.92}]},
	{"name": "mohawk", "category": "hair", "display_name": "Mohawk", "color": "#5aa84e",
		"boxes": [{"from": [-1, 4, -4], "size": [2, 2.5, 8]}]},

	# Shirts and pants: the body's inner layer.
	{"name": "tshirt", "category": "shirt", "display_name": "T-shirt", "color": "#4a78d0", "paint": [
		{"region": "torso", "rows": [0, 12]}, {"region": "arm_r", "rows": [0, 4]}, {"region": "arm_l", "rows": [0, 4]}]},
	{"name": "long_sleeve", "category": "shirt", "display_name": "Long sleeve", "color": "#d94c4c", "paint": [
		{"region": "torso", "rows": [0, 12]}, {"region": "arm_r", "rows": [0, 11]}, {"region": "arm_l", "rows": [0, 11]}]},
	{"name": "tank_top", "category": "shirt", "display_name": "Tank top", "color": "#f0f0f0", "paint": [
		{"region": "torso", "rows": [0, 12]}]},
	{"name": "striped_shirt", "category": "shirt", "display_name": "Striped", "color": "#3d9c9c", "paint": [
		{"region": "torso", "rows": [0, 12]}, {"region": "arm_r", "rows": [0, 4]}, {"region": "arm_l", "rows": [0, 4]},
		{"region": "torso", "rows": [2, 3], "sides": ["front", "back", "left", "right"], "color": "#f0f0f0"},
		{"region": "torso", "rows": [5, 6], "sides": ["front", "back", "left", "right"], "color": "#f0f0f0"},
		{"region": "torso", "rows": [8, 9], "sides": ["front", "back", "left", "right"], "color": "#f0f0f0"},
		{"region": "arm_r", "rows": [2, 3], "sides": ["front", "back", "left", "right"], "color": "#f0f0f0"},
		{"region": "arm_l", "rows": [2, 3], "sides": ["front", "back", "left", "right"], "color": "#f0f0f0"}]},
	{"name": "jeans", "category": "pants", "display_name": "Jeans", "color": "#3b4f7a", "paint": [
		{"region": "leg_r", "rows": [0, 12]}, {"region": "leg_l", "rows": [0, 12]},
		{"region": "torso", "rows": [10, 12], "shade": 0.85}]},
	{"name": "shorts", "category": "pants", "display_name": "Shorts", "color": "#7a5232", "paint": [
		{"region": "leg_r", "rows": [0, 5]}, {"region": "leg_l", "rows": [0, 5]},
		{"region": "torso", "rows": [10, 12], "shade": 0.85}]},
	{"name": "cargo_pants", "category": "pants", "display_name": "Cargo pants", "color": "#5a6a3a", "paint": [
		{"region": "leg_r", "rows": [0, 12]}, {"region": "leg_l", "rows": [0, 12]},
		{"region": "leg_r", "rows": [5, 8], "sides": ["right"], "shade": 0.8},
		{"region": "leg_l", "rows": [5, 8], "sides": ["left"], "shade": 0.8},
		{"region": "torso", "rows": [10, 12], "shade": 0.85}]},
	{"name": "sneakers", "category": "shoes", "display_name": "Sneakers", "color": "#f0f0f0", "paint": [
		{"region": "leg_r", "rows": [10, 12]}, {"region": "leg_l", "rows": [10, 12]},
		{"region": "leg_r", "rows": [11, 12], "sides": ["front", "back", "left", "right", "bottom"], "color": "#303030"},
		{"region": "leg_l", "rows": [11, 12], "sides": ["front", "back", "left", "right", "bottom"], "color": "#303030"}]},
	{"name": "boots", "category": "shoes", "display_name": "Boots", "color": "#7a5232", "paint": [
		{"region": "leg_r", "rows": [8, 12]}, {"region": "leg_l", "rows": [8, 12]},
		{"region": "leg_r", "rows": [11, 12], "shade": 0.6}, {"region": "leg_l", "rows": [11, 12], "shade": 0.6}]},

	# Jackets: the body's outer layer, drawn slightly larger than the body.
	{"name": "hoodie", "category": "jacket", "display_name": "Hoodie", "color": "#8a8a8a", "paint": [
		{"region": "torso_overlay", "rows": [0, 12]},
		{"region": "arm_r_overlay", "rows": [0, 10]}, {"region": "arm_l_overlay", "rows": [0, 10]},
		{"region": "torso_overlay", "rows": [7, 10], "sides": ["front"], "shade": 0.85}]},
	{"name": "vest", "category": "jacket", "display_name": "Vest", "color": "#2a2a2a", "paint": [
		{"region": "torso_overlay", "rows": [0, 10], "sides": ["back", "left", "right", "top"]},
		{"region": "torso_overlay", "rows": [0, 10], "sides": ["front"], "shade": 0.9}]},
	{"name": "coat", "category": "jacket", "display_name": "Long coat", "color": "#7a5232", "paint": [
		{"region": "torso_overlay", "rows": [0, 12]},
		{"region": "arm_r_overlay", "rows": [0, 11]}, {"region": "arm_l_overlay", "rows": [0, 11]},
		{"region": "leg_r_overlay", "rows": [0, 5], "sides": ["back", "right", "front"]},
		{"region": "leg_l_overlay", "rows": [0, 5], "sides": ["back", "left", "front"]}]},

	# Hats: voxel accessories on top of the head. They replace a helmet unless armor is shown.
	{"name": "cap", "category": "hat", "display_name": "Cap", "color": "#d94c4c", "boxes": [
		{"from": [-4.5, -1.5, -4.5], "size": [9, 2.5, 9]}, {"from": [-4, -1.5, -8], "size": [8, 0.75, 3.5], "shade": 0.85}]},
	{"name": "top_hat", "category": "hat", "display_name": "Top hat", "color": "#2a2a2a", "boxes": [
		{"from": [-6, 0, -6], "size": [12, 1, 12]}, {"from": [-4, 1, -4], "size": [8, 7, 8]},
		{"from": [-4.2, 1, -4.2], "size": [8.4, 1.5, 8.4], "color": "#b03030"}]},
	{"name": "beanie", "category": "hat", "display_name": "Beanie", "color": "#e8913a", "boxes": [
		{"from": [-4.5, -3, -4.5], "size": [9, 4, 9]}, {"from": [-4.6, -3, -4.6], "size": [9.2, 1.2, 9.2], "shade": 0.8},
		{"from": [-1, 1, -1], "size": [2, 2, 2], "color": "#f0f0f0"}]},
	{"name": "crown", "category": "hat", "display_name": "Crown", "color": "#e8c040", "boxes": [
		{"from": [-4.5, 0, -4.5], "size": [9, 2, 1]}, {"from": [-4.5, 0, 3.5], "size": [9, 2, 1]},
		{"from": [-4.5, 0, -3.5], "size": [1, 2, 7]}, {"from": [3.5, 0, -3.5], "size": [1, 2, 7]},
		{"from": [-4.5, 2, -4.5], "size": [1, 1.5, 1]}, {"from": [3.5, 2, -4.5], "size": [1, 1.5, 1]},
		{"from": [-4.5, 2, 3.5], "size": [1, 1.5, 1]}, {"from": [3.5, 2, 3.5], "size": [1, 1.5, 1]},
		{"from": [-0.5, 2, -4.5], "size": [1, 1.5, 1]}, {"from": [-0.75, 0.5, -4.8], "size": [1.5, 1, 0.5], "color": "#d02040"}]},
	{"name": "wizard_hat", "category": "hat", "display_name": "Wizard hat", "color": "#6a3aa8", "boxes": [
		{"from": [-6, 0, -6], "size": [12, 1, 12]}, {"from": [-4, 1, -4], "size": [8, 3, 8]},
		{"from": [-3, 4, -2.5], "size": [6, 3, 6]}, {"from": [-2, 7, -1.5], "size": [4, 3, 4]},
		{"from": [-1, 10, -0.5], "size": [2, 2, 2]}, {"from": [-4.1, 1, -4.1], "size": [8.2, 1, 8.2], "color": "#e8c040"}]},
	{"name": "headband", "category": "hat", "display_name": "Headband", "color": "#d94c4c", "covers": [], "boxes": [
		{"from": [-4.4, -2.5, -4.4], "size": [8.8, 1.2, 8.8]}]},

	# Glasses: on the front of the face, eye height.
	{"name": "glasses", "category": "glasses", "display_name": "Glasses", "color": "#303030", "boxes": [
		{"from": [-3.8, -1.5, -0.6], "size": [3, 2, 0.5]}, {"from": [0.8, -1.5, -0.6], "size": [3, 2, 0.5]},
		{"from": [-0.8, -0.3, -0.6], "size": [1.6, 0.5, 0.5]},
		{"from": [-3.3, -1, -0.7], "size": [2, 1, 0.2], "color": "#b8e0f0"}, {"from": [1.3, -1, -0.7], "size": [2, 1, 0.2], "color": "#b8e0f0"}]},
	{"name": "shades", "category": "glasses", "display_name": "Shades", "color": "#151515", "boxes": [
		{"from": [-4.2, -1.5, -0.6], "size": [8.4, 2, 0.5]}]},
	{"name": "eyepatch", "category": "glasses", "display_name": "Eye patch", "color": "#151515", "boxes": [
		{"from": [0.8, -1.5, -0.6], "size": [3, 2.5, 0.5]}, {"from": [-4.3, 0.5, -0.5], "size": [8.6, 0.6, 0.4]}]},

	# Back accessories.
	{"name": "cape", "category": "back", "display_name": "Cape", "color": "#b03030", "boxes": [
		{"from": [-4.5, -12, 0.2], "size": [9, 17, 0.8]}, {"from": [-4.5, 4, 0.2], "size": [9, 1, 1.2], "color": "#e8c040"}]},
	{"name": "backpack", "category": "back", "display_name": "Backpack", "color": "#7a5232", "boxes": [
		{"from": [-3.5, -6, 0], "size": [7, 9, 3]}, {"from": [-2.5, -5, 3], "size": [5, 3, 1], "shade": 0.85},
		{"from": [-3.6, 1, 0], "size": [7.2, 1, 3.1], "shade": 0.7}]},
	{"name": "wings", "category": "back", "display_name": "Wings", "color": "#f0f0f0", "boxes": [
		{"from": [-12, -4, 1], "size": [10, 8, 0.6]}, {"from": [2, -4, 1], "size": [10, 8, 0.6]},
		{"from": [-10, -7, 1], "size": [7, 3, 0.6], "shade": 0.9}, {"from": [3, -7, 1], "size": [7, 3, 0.6], "shade": 0.9}]},
]

var categories: Array[Dictionary] = []
var defs := {}  # name -> def
var policy := DEFAULT_POLICY.duplicate(true)


func _init() -> void:
	for c in DEFAULT_CATEGORIES:
		register_category(c)
	for def in BUILTIN:
		var d: Dictionary = def.duplicate(true)
		d.name = BUILTIN_PREFIX + d.name
		register(d)


static func is_builtin(cosmetic_name: String) -> bool:
	return cosmetic_name.begins_with(BUILTIN_PREFIX)


## def: name, display_name, attach (attachment point for boxes/models), covers (armor slots its
## cosmetics replace by default). Returns false when invalid or full.
func register_category(def: Dictionary) -> bool:
	var cat_name := str(def.get("name", "")).left(32)
	if cat_name.is_empty() or categories.size() >= MAX_CATEGORIES or category(cat_name) != {}:
		return false
	categories.append({"name": cat_name, "display_name": str(def.get("display_name", cat_name.capitalize())).left(32),
		"attach": str(def.get("attach", "")).left(32), "covers": _slots(def.get("covers", []))})
	return true


func category(cat_name: String) -> Dictionary:
	for c in categories:
		if c.name == cat_name:
			return c
	return {}


## Registers (or replaces) a cosmetic. Returns its name, or "" when invalid.
func register(def: Dictionary) -> String:
	var cosmetic_name := str(def.get("name", "")).left(96)
	var cat := category(str(def.get("category", "")))
	if cosmetic_name.is_empty() or not cosmetic_name.contains(":") or cat.is_empty() or (defs.size() >= MAX_COSMETICS and not defs.has(cosmetic_name)):
		return ""
	var d := {
		"name": cosmetic_name,
		"category": cat.name,
		"display_name": str(def.get("display_name", cosmetic_name.get_slice(":", 1).capitalize())).left(48),
		"description": str(def.get("description", "")).left(160),
		"color": clean_color(def.get("color"), "#ffffff"),
		"tint": bool(def.get("tint", true)),
		"covers": _slots(def.get("covers")) if def.get("covers") is Array else cat.covers.duplicate(),
		"unlocked": bool(def.get("unlocked", true)),
		"texture": str(def.get("texture", "")).left(256),
		"model": str(def.get("model", "")).left(256),
		"model_transform": _transform(def.get("model_transform")),
		"paint": _paint(def.get("paint")),
		"pixels": _pixels(def.get("pixels")),
		"boxes": _boxes(def.get("boxes")),
	}
	defs[cosmetic_name] = d
	return cosmetic_name


func get_def(cosmetic_name: String) -> Dictionary:
	return defs.get(cosmetic_name, {})


## Cosmetics of a category in registration order.
func in_category(cat_name: String) -> Array:
	return defs.values().filter(func(d): return d.category == cat_name)


func set_policy(values: Dictionary) -> void:
	for key in values:
		if not DEFAULT_POLICY.has(key):
			continue
		match key:
			"armor":
				policy.armor = values.armor if values.armor in ["player", "armor", "cosmetics"] else "player"
			"blocked":
				policy.blocked = (values.blocked as Array).map(func(v): return str(v)).slice(0, 256) if values.blocked is Array else []
			"uniform":
				policy.uniform = sanitize_avatar(values.uniform, Callable(), true) if values.uniform is Dictionary else {}
			_:
				policy[key] = bool(values[key])


func is_blocked(cosmetic_name: String) -> bool:
	var d := get_def(cosmetic_name)
	return policy.blocked.has(cosmetic_name) or (not d.is_empty() and policy.blocked.has(d.category))


# --- Avatars --------------------------------------------------------------------------------------

## Cleans avatar data from a client, a mod or a file. `can_wear(id) -> bool` filters cosmetics the
## player may not wear. With `keep_removals`, wear entries with an empty id survive (uniforms use them
## to take a category off).
func sanitize_avatar(avatar, can_wear := Callable(), keep_removals := false) -> Dictionary:
	var out := {}
	if not (avatar is Dictionary):
		return out
	if avatar.has("skin") and is_color(avatar.skin):
		out.skin = clean_color(avatar.skin, "#e8b48c")
	if avatar.get("body") is Dictionary:
		var body := {}
		for part in BODY_PARTS:
			if is_color(avatar.body.get(part)):
				body[part] = clean_color(avatar.body[part], "#e8b48c")
		if not body.is_empty():
			out.body = body
	if avatar.get("wear") is Dictionary:
		var wear := {}
		for cat_name in avatar.wear:
			var entry = avatar.wear[cat_name]
			if not (cat_name is String) or category(cat_name).is_empty() or not (entry is Dictionary):
				continue
			var id := str(entry.get("id", ""))
			if id.is_empty():
				if keep_removals:
					wear[cat_name] = {"id": ""}
				continue
			var d := get_def(id)
			if d.is_empty() or d.category != cat_name or (can_wear.is_valid() and not can_wear.call(id)):
				continue
			wear[cat_name] = {"id": id, "color": clean_color(entry.get("color"), d.color)}
		if not wear.is_empty():
			out.wear = wear
	if avatar.get("show_armor") is Dictionary:
		var show := {}
		for slot in ARMOR_SLOTS:
			if avatar.show_armor.get(slot) is bool:
				show[slot] = avatar.show_armor[slot]
		if not show.is_empty():
			out.show_armor = show
	return out


## `top` laid over `base`: its colors replace base colors, its wear replaces base wear per category
## (an empty id removes the category).
static func merge(base: Dictionary, top: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in ["skin"]:
		if top.has(key):
			out[key] = top[key]
	for key in ["body", "show_armor"]:
		if top.get(key) is Dictionary:
			var merged: Dictionary = out.get(key, {})
			merged.merge(top[key], true)
			out[key] = merged
	if top.get("wear") is Dictionary:
		var wear: Dictionary = out.get("wear", {})
		for cat_name in top.wear:
			if str(top.wear[cat_name].get("id", "")).is_empty():
				wear.erase(cat_name)
			else:
				wear[cat_name] = top.wear[cat_name].duplicate()
		out.wear = wear
	return out


## The look a player without avatar data gets, varied by name so players are told apart.
static func default_avatar(seed_text: String) -> Dictionary:
	var h: int = abs(hash(seed_text))
	var hair: String = ["short_hair", "bob_hair", "long_hair", "short_hair", "ponytail"][h % 5]
	var shirt: String = ["tshirt", "long_sleeve", "striped_shirt", "tshirt"][(h >> 3) % 4]
	return {
		"skin": SKIN_TONES[h % SKIN_TONES.size()],
		"wear": {
			"face": {"id": BUILTIN_PREFIX + ["smile", "grin", "calm", "freckles"][(h >> 5) % 4], "color": ["#3050c0", "#3a8a40", "#6a4428"][(h >> 7) % 3]},
			"hair": {"id": BUILTIN_PREFIX + hair, "color": HAIR_COLORS[(h >> 9) % 6]},
			"shirt": {"id": BUILTIN_PREFIX + shirt, "color": CLOTHING_COLORS[(h >> 11) % CLOTHING_COLORS.size()]},
			"pants": {"id": BUILTIN_PREFIX + "jeans", "color": ["#3b4f7a", "#2a2a2a", "#7a5232", "#5a6a3a"][(h >> 13) % 4]},
			"shoes": {"id": BUILTIN_PREFIX + "sneakers", "color": ["#f0f0f0", "#2a2a2a", "#d94c4c"][(h >> 15) % 3]},
		},
	}


## Which armor slots stay visible given the avatar's cosmetics, the player's choices and the policy.
## `armor`: {slot: item id} -> the visible subset.
func visible_armor(armor: Dictionary, avatar: Dictionary) -> Dictionary:
	if policy.armor == "armor":
		return armor.duplicate()
	var covered := {}
	for cat_name in avatar.get("wear", {}):
		for slot in get_def(str(avatar.wear[cat_name].get("id", ""))).get("covers", []):
			covered[slot] = true
	var out := {}
	for slot in armor:
		var show: bool = policy.armor == "player" and bool(avatar.get("show_armor", {}).get(slot, false))
		if not covered.has(slot) or show:
			out[slot] = armor[slot]
	return out


# --- Network --------------------------------------------------------------------------------------

## Built-in cosmetics are part of every client; only categories, server cosmetics and policy travel.
func to_network() -> Dictionary:
	var list := []
	for d in defs.values():
		if not is_builtin(d.name):
			list.append(d)
	return {"categories": categories.duplicate(true), "cosmetics": list, "policy": policy.duplicate(true)}


func load_network(data) -> bool:
	if not (data is Dictionary):
		return true  # servers without cosmetics content
	if data.get("categories") is Array:
		for c in data.categories.slice(0, MAX_CATEGORIES):
			if c is Dictionary:
				register_category(c)
	if data.get("cosmetics") is Array:
		for d in data.cosmetics.slice(0, MAX_COSMETICS):
			if d is Dictionary and not is_builtin(str(d.get("name", ""))):
				register(d)
	if data.get("policy") is Dictionary:
		set_policy(data.policy)
	return true


# --- Cleaning -------------------------------------------------------------------------------------

static func is_color(value) -> bool:
	return value is String and (value as String).length() in [4, 7] and (value as String).begins_with("#") and Color.html_is_valid(value)


static func clean_color(value, fallback: String) -> String:
	return "#" + Color.html(value).to_html(false) if is_color(value) else fallback


static func _slots(value) -> Array:
	var out := []
	for s in (value if value is Array else []):
		if str(s) in ARMOR_SLOTS and not out.has(str(s)):
			out.append(str(s))
	return out


static func _num(value, fallback: float, limit: float) -> float:
	return clampf(float(value), -limit, limit) if value is float or value is int else fallback


static func _vec(value, fallback: Array, limit: float) -> Array:
	if not (value is Array) or value.size() != 3:
		return fallback
	return [_num(value[0], fallback[0], limit), _num(value[1], fallback[1], limit), _num(value[2], fallback[2], limit)]


static func _op_color(value) -> String:
	return clean_color(value, "") if is_color(value) else ""


static func _paint(value) -> Array:
	var out := []
	for op in (value if value is Array else []).slice(0, MAX_OPS):
		if not (op is Dictionary) or not (str(op.get("region", "")) in PAINT_REGIONS):
			continue
		var rows = op.get("rows", [0, 64])
		var clean := {"region": str(op.region), "rows": [0, 64], "color": _op_color(op.get("color")),
			"shade": clampf(_num(op.get("shade"), 1.0, 4.0), 0.0, 4.0)}
		if rows is Array and rows.size() == 2:
			clean.rows = [clampi(int(rows[0]), 0, 64), clampi(int(rows[1]), 0, 64)]
		if op.get("sides") is Array:
			clean.sides = (op.sides as Array).filter(func(s): return str(s) in SIDES).map(func(s): return str(s))
		out.append(clean)
	return out


static func _pixels(value) -> Dictionary:
	if not (value is Dictionary) or not (value.get("rows") is Array) or value.rows.size() != 8:
		return {}
	var rows := []
	for row in value.rows:
		rows.append(str(row).rpad(8, ".").left(8))
	var palette := _FACE_PALETTE.duplicate()
	if value.get("palette") is Dictionary:
		for key in value.palette:
			var v := str(value.palette[key])
			if str(key).length() == 1 and (v in ["tint", "skin"] or is_color(v)):
				palette[str(key)] = v if not is_color(v) else clean_color(v, "")
	return {"rows": rows, "palette": palette}


static func _boxes(value) -> Array:
	var out := []
	for b in (value if value is Array else []).slice(0, MAX_OPS):
		if b is Dictionary:
			out.append({"from": _vec(b.get("from"), [0, 0, 0], 64.0), "size": _vec(b.get("size"), [1, 1, 1], 64.0),
				"color": _op_color(b.get("color")), "shade": clampf(_num(b.get("shade"), 1.0, 4.0), 0.0, 4.0)})
	return out


static func _transform(value) -> Dictionary:
	var t: Dictionary = value if value is Dictionary else {}
	return {"position": _vec(t.get("position"), [0, 0, 0], 64.0), "rotation": _vec(t.get("rotation"), [0, 0, 0], 360.0),
		"scale": clampf(_num(t.get("scale"), 1.0, 16.0), 0.01, 16.0)}
