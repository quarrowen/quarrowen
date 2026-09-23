extends "res://engine/server/mod.gd"
## The verbs. `base` says what a world is made of; this says what you can do with it.
##
## Workbenches, furnaces, containers, cooking and signals - every block here exists to *act* on
## something `base` registered. The line was settled on 21 September 2026 and this pack is one half of
## making it real: **a creative game takes `base` alone, ships zero recipes, and everything still
## exists and works.** Nothing in here is required for a world to be a world.
##
## Refer to these as `simple_machines:<name>`. Sounds come from `base`, qualified, because a mod's own
## bare name would resolve to this mod and find nothing.
##
## **The guide is here under protest.** It is game content - it teaches crafting, survival and
## workshops - and its real home is the guided game, which does not exist yet. It could not stay in
## `base`, because a page about the crafting table has to name the crafting table and `base` may not
## depend on this pack. Move it the moment there is a game to move it into. (2026-09-23)

const Stations = preload("stations.gd")
const Cooking = preload("cooking.gd")
const Signals = preload("signals.gd")
const Guide = preload("guide.gd")

var stations := Stations.new()
var cooking := Cooking.new()
var signals := Signals.new()
var guide := Guide.new()


func setup(api) -> void:
	# `base`'s sounds, named in full. A bare "stone" here would qualify to `simple_machines:stone`,
	# which is not an error and is not a sound either - it is silence, found weeks later.
	var stone := {"break": "base:stone", "place": "base:stone", "step": "base:stone_step"}
	var wood := {"break": "base:wood", "place": "base:wood", "step": "base:wood_step"}
	stations.setup(api, {"wood": wood, "stone": stone})
	cooking.setup(api, {"stone": stone, "wood": wood})
	signals.setup(api, {"stone": stone})
	guide.setup(api)
