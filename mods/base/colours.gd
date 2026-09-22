extends RefCounted
## The colour sets: sixteen hues, as woven cloth and as painted plaster.
##
## **Colour is what a child builds with.** Asked how to spend Phase 4's block budget (user,
## 2026-09-23), the answer was colour-led rather than material-led: one block per shape and material
## class proves the *engine's* range and leaves a builder short of choices, and choices are what a
## building game is made of.
##
## Two sets rather than one twice the size, because a wall of cloth and a wall of plaster read
## differently from across a room - soft and woven against flat and painted - so a build can carry
## texture as well as hue. They are deliberately the *same* sixteen hues: a builder who has found a
## colour they like should be able to have it in either material without hunting for the near match.
##
## The names are plain enough for an eight-year-old to say and distinct enough to search: no two begin
## with the same letter except the greys, which are ordered light to dark and read as a set.

## [id, colour]. The id is also the texture name, so `tools/generate_textures.gd` reads this table
## rather than keeping a second copy of it - a second copy being how the hue in the name and the hue
## on the block come to disagree.
const COLOURS := [
	["white", Color(0.93, 0.93, 0.91)],
	["bone", Color(0.83, 0.80, 0.72)],
	["ash", Color(0.62, 0.62, 0.63)],
	["slate", Color(0.35, 0.37, 0.41)],
	["black", Color(0.13, 0.13, 0.15)],
	["crimson", Color(0.66, 0.16, 0.18)],
	["amber", Color(0.85, 0.48, 0.15)],
	["straw", Color(0.87, 0.76, 0.30)],
	["moss", Color(0.55, 0.68, 0.26)],
	["forest", Color(0.22, 0.45, 0.24)],
	["teal", Color(0.18, 0.55, 0.55)],
	["sky", Color(0.47, 0.71, 0.88)],
	["indigo", Color(0.24, 0.30, 0.62)],
	["plum", Color(0.46, 0.26, 0.55)],
	["rose", Color(0.84, 0.55, 0.65)],
	["cocoa", Color(0.40, 0.28, 0.20)],
]


func setup(api, sounds: Dictionary) -> void:
	var soft: Dictionary = sounds.get("dirt", {})
	var hard: Dictionary = sounds.get("stone", {})
	for entry in COLOURS:
		var id: String = entry[0]
		var label: String = id.capitalize()
		# Cloth is soft: quick to break, no tool wanted, and it muffles a footstep.
		api.register_block("cloth_%s" % id, {
			"display_name": "%s Cloth" % label, "textures": "textures/cloth_%s.png" % id,
			"sounds": soft, "hardness": 0.8, "group": "Cloth"})
		# Plaster is a wall: slower, and a pickaxe is the right tool for it.
		api.register_block("plaster_%s" % id, {
			"display_name": "%s Plaster" % label, "textures": "textures/plaster_%s.png" % id,
			"sounds": hard, "hardness": 1.1, "tool": "pickaxe", "tier": 0, "group": "Plaster"})
