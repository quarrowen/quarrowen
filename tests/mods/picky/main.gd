extends "res://engine/server/mod.gd"
## Loads the Proving Ground and refuses three of its things, which is the whole of what `excludes` is
## for: taking most of a pack without forking it.
##
## `proving:lamp` is a plain name, `proving:slime*` a wildcard covering the liquid and its shallow
## form, and `proving:grain` is named by a recipe and by a creature's taming food - so this also tests
## that a reference to something excluded is dropped with a warning rather than an error.

var api


func setup(mod_api) -> void:
	api = mod_api
	api.set_server_info({"name": "Picky"})
	# And the other half of taking somebody else's pack: adding to it without forking it. A new attack
	# on their creature, a new drop, and a pool on their loot table.
	api.extend_entity("proving:biter", {
		"ai": {"attacks": [{"name": "kick", "type": "melee", "damage": 4.0, "range": 2.0,
			"condition": {"condition": "proving:venom", "seconds": 3.0}}]},
		"drops": [["proving:token", 2]]})
	api.extend_block("proving:crate", {"drops": [["proving:token", 1]]})
	api.extend_loot("mob:proving:grazer", {"pools": [
		{"rolls": 1, "guaranteed": true, "entries": [{"item": "proving:token", "count": [1, 1]}]}]})
