extends "res://engine/server/mod.gd"
## The Survival Guide: the book that explains the other packs.
##
## **Its own mod, because it is the only shape that is honest.** The guide teaches wood, then the
## crafting table, then armour and the Toolsmith's Bench - so it names content from `base`,
## `simple_machines` *and* `simple_gear`. It cannot live in any one of them without that pack
## depending on a pack above it: it started in `base`, moved to `simple_machines` on 2026-09-23 and
## immediately made `simple_machines` name `simple_gear:iron_pickaxe`, which the validator caught.
## A thing that documents three packs depends on three packs. (2026-09-23)
##
## This is still game content, and when there is a guided game to own it, it moves there or that game
## simply depends on this.

const Guide = preload("guide.gd")

var guide := Guide.new()


func setup(api) -> void:
	guide.setup(api)
