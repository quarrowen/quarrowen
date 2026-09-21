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
