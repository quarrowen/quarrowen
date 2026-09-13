extends RefCounted
## Base class for server mods. A mod is a folder containing `mod.json` and a script that does
## `extends "res://engine/server/mod.gd"` and overrides `setup`.
##
## mod.json:
##   {
##     "id": "my_mod",              lowercase letters, digits, underscores; must match the folder
##     "name": "My Mod",
##     "version": "1.0.0",
##     "description": "...",
##     "depends": ["base"],         loaded first, in order
##     "game": true,                listed as a playable game in the Host menu
##     "main": "main.gd"            optional; main.gd, or main.js for JavaScript mods (see js/prelude.js)
##   }


## Called once at server start, after all dependencies have run their setup.
## Register blocks, event handlers, commands and world hooks through `api` (see mod_api.gd).
func setup(_api) -> void:
	pass
