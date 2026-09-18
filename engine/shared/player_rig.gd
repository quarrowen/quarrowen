extends RefCounted
## Player character rigs as plain data, so servers can replace the engine's default body.
##
## Units are pixels of the skin texture layout: the default body is 32 px tall and 1.8 blocks, so one
## pixel is 0.05625 blocks. Skins, clothing and armor textures use a 64x64 unfolded-box skin
## layout (skin editors work as is); a rig maps each part to a region of that layout, so outfits do
## not depend on how many parts a rig has. The default rig splits arms and legs at the elbows and
## knees for better animation; the upper part samples the top half of the limb's region and the lower
## part the bottom half.
##
## Rig def:
##   height: blocks tall (scales the model to the physics body)
##   texture_size: 64 (layers of other sizes are scaled)
##   parts: [{name, parent ("" = root), pivot [x,y,z] relative to the parent's pivot, box [x,y,z] min
##            corner relative to the pivot, size [w,h,d], uv [u,v] region origin, uv_size [w,h,d] of
##            the full region (defaults to size), slice [from,to] rows of the region height used,
##            overlay_uv [u,v] second-layer region, region: head | torso | arm_r | arm_l | leg_r | leg_l}]
##   attachments: {name: {part, position [x,y,z] relative to the part pivot, rotation [x,y,z] degrees}}
## Animation drives parts named head, torso, arm_r_upper/lower, arm_l_upper/lower, leg_r_upper/lower,
## leg_l_upper/lower when a rig has them.

const PIXEL := 1.8 / 32.0
const MAX_PARTS := 32

## Which layout regions each armor slot paints (armor textures use the same layout as skins).
const ARMOR_REGIONS := {
	"head": ["head"],
	"chest": ["torso", "arm_r", "arm_l"],
	"legs": ["legs_upper"],
	"feet": ["legs_lower"],
}

## Layout regions: [u, v, w, h, d] box unfold origins of the 64x64 skin format.
const REGIONS := {
	"head": [0, 0, 8, 8, 8], "head_overlay": [32, 0, 8, 8, 8],
	"torso": [16, 16, 8, 12, 4], "torso_overlay": [16, 32, 8, 12, 4],
	"arm_r": [40, 16, 4, 12, 4], "arm_r_overlay": [40, 32, 4, 12, 4],
	"arm_l": [32, 48, 4, 12, 4], "arm_l_overlay": [48, 48, 4, 12, 4],
	"leg_r": [0, 16, 4, 12, 4], "leg_r_overlay": [0, 32, 4, 12, 4],
	"leg_l": [16, 48, 4, 12, 4], "leg_l_overlay": [0, 48, 4, 12, 4],
}


static func default_rig() -> Dictionary:
	return {
		"name": "engine:default",
		"height": 1.8,
		"texture_size": 64,
		"parts": [
			{"name": "torso", "parent": "", "pivot": [0, 12, 0], "box": [-4, 0, -2], "size": [8, 12, 4], "region": "torso"},
			{"name": "head", "parent": "torso", "pivot": [0, 12, 0], "box": [-4, 0, -4], "size": [8, 8, 8], "region": "head"},
			{"name": "arm_r_upper", "parent": "torso", "pivot": [6, 10, 0], "box": [-2, -4, -2], "size": [4, 6, 4], "region": "arm_r", "slice": [0, 6]},
			{"name": "arm_r_lower", "parent": "arm_r_upper", "pivot": [0, -4, 0], "box": [-2, -6, -2], "size": [4, 6, 4], "region": "arm_r", "slice": [6, 12]},
			{"name": "arm_l_upper", "parent": "torso", "pivot": [-6, 10, 0], "box": [-2, -4, -2], "size": [4, 6, 4], "region": "arm_l", "slice": [0, 6]},
			{"name": "arm_l_lower", "parent": "arm_l_upper", "pivot": [0, -4, 0], "box": [-2, -6, -2], "size": [4, 6, 4], "region": "arm_l", "slice": [6, 12]},
			{"name": "leg_r_upper", "parent": "", "pivot": [2, 12, 0], "box": [-2, -6, -2], "size": [4, 6, 4], "region": "leg_r", "slice": [0, 6]},
			{"name": "leg_r_lower", "parent": "leg_r_upper", "pivot": [0, -6, 0], "box": [-2, -6, -2], "size": [4, 6, 4], "region": "leg_r", "slice": [6, 12]},
			{"name": "leg_l_upper", "parent": "", "pivot": [-2, 12, 0], "box": [-2, -6, -2], "size": [4, 6, 4], "region": "leg_l", "slice": [0, 6]},
			{"name": "leg_l_lower", "parent": "leg_l_upper", "pivot": [0, -6, 0], "box": [-2, -6, -2], "size": [4, 6, 4], "region": "leg_l", "slice": [6, 12]},
		],
		# Accessories attach just clear of the head rather than exactly on it. The head's own mesh tops out
		# at y 8 and its overlay shell (hair, a painted skin) at 8.5, so a hat whose lowest box started at
		# 0 had faces exactly coplanar with one of them and the two fought for the same pixels - which is
		# why a hat flickered, but only when hair was worn under it. 0.6 clears both and is 0.04 blocks,
		# far too small to see. (playtest, 2026-09-18)
		"attachments": {
			"hat": {"part": "head", "position": [0, 8.6, 0], "rotation": [0, 0, 0]},
			"hair": {"part": "head", "position": [0, 4, 0], "rotation": [0, 0, 0]},
			"face": {"part": "head", "position": [0, 4, -4], "rotation": [0, 0, 0]},
			"back": {"part": "torso", "position": [0, 7, 2], "rotation": [0, 0, 0]},
			"waist": {"part": "torso", "position": [0, 1, 0], "rotation": [0, 0, 0]},
			"shoulder_r": {"part": "torso", "position": [6, 12, 0], "rotation": [0, 0, 0]},
			"shoulder_l": {"part": "torso", "position": [-6, 12, 0], "rotation": [0, 0, 0]},
			"hand_r": {"part": "arm_r_lower", "position": [0, -5, -1], "rotation": [-90, 0, 0]},
			"hand_l": {"part": "arm_l_lower", "position": [0, -5, -1], "rotation": [-90, 0, 0]},
		},
	}


## Validates a rig from a mod or the network. Returns the default rig when anything is wrong.
static func sanitize(def) -> Dictionary:
	if not (def is Dictionary) or not (def.get("parts") is Array) or def.parts.is_empty() or def.parts.size() > MAX_PARTS:
		return default_rig()
	var names := {}
	var parts := []
	for part in def.parts:
		if not (part is Dictionary) or not (part.get("name") is String) or names.has(part.name):
			return default_rig()
		var parent := String(part.get("parent", ""))
		if not parent.is_empty() and not names.has(parent):
			return default_rig()  # parents must come first
		var clean := {"name": String(part.name).left(32), "parent": parent,
			"pivot": _vec(part.get("pivot"), [0, 0, 0], 64.0), "box": _vec(part.get("box"), [0, 0, 0], 64.0),
			"size": _vec(part.get("size"), [4, 4, 4], 64.0),
			"region": String(part.get("region", "")) if String(part.get("region", "")) in ["head", "torso", "arm_r", "arm_l", "leg_r", "leg_l"] else ""}
		if part.get("slice") is Array and part.slice.size() == 2:
			clean.slice = [clampi(int(part.slice[0]), 0, 64), clampi(int(part.slice[1]), 0, 64)]
		names[clean.name] = true
		parts.append(clean)
	var attachments := {}
	if def.get("attachments") is Dictionary:
		for key in def.attachments:
			var a = def.attachments[key]
			if a is Dictionary and names.has(String(a.get("part", ""))) and attachments.size() < 32:
				attachments[String(key).left(32)] = {"part": String(a.part), "position": _vec(a.get("position"), [0, 0, 0], 64.0),
					"rotation": _vec(a.get("rotation"), [0, 0, 0], 360.0)}
	return {"name": String(def.get("name", "custom")).left(64), "height": clampf(float(def.get("height", 1.8)), 0.2, 16.0),
		"texture_size": 64, "parts": parts, "attachments": attachments}


static func _vec(value, fallback: Array, limit: float) -> Array:
	if not (value is Array) or value.size() != 3:
		return fallback
	return [clampf(float(value[0]), -limit, limit), clampf(float(value[1]), -limit, limit), clampf(float(value[2]), -limit, limit)]
