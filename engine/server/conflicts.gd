extends RefCounted
## Two mods quietly standing on each other, found before a player notices.
##
## This is the complaint we were least protected from. In the genre's usual arrangement, combining mods
## produces duplicate ores, biomes that never generate, and chunk decoration fighting over the same
## space - and the pack author's job is to notice and turn things off by hand. Nothing *tells* them.
## Our `excludes` and tags let an author resolve a clash; until now nothing noticed one. (2026-09-22)
##
## **It reports, it does not resolve.** Every one of these can be deliberate: a mod may well want a
## second kind of copper, or a biome deliberately close to another. Refusing to start would be wrong,
## and silently merging them would be worse. So this is a warning with both names in it, and the fix is
## whichever of `excludes`, a rename or a climate nudge the author meant.
##
## Only things the engine can actually know are checked. It cannot tell that "Ruddy Stone" and "Red
## Rock" are the same idea; it can tell that two mods registered blocks with the same display name,
## that two ore passes put different blocks in the ground that drop the same item, and that two biomes
## sit so close in climate space that one of them will hardly ever be chosen.

const BlockRegistry = preload("res://engine/shared/block_registry.gd")

## How close two biomes may sit in climate space before one of them stops appearing. The generator
## picks the nearest biome by temperature, humidity, weirdness and peaks, so two points this close are
## effectively one biome with a coin flip deciding the name.
const BIOME_TOO_CLOSE := 0.08

var server


func _init(game_server) -> void:
	server = game_server


## Everything worth telling somebody about: [{kind, detail, mods}], sorted for a stable report.
func find() -> Array:
	var out: Array = []
	_same_display_name(out)
	_duplicate_ores(out)
	_crowded_biomes(out)
	out.sort_custom(func(a, b): return String(a.detail) < String(b.detail))
	return out


## Two mods registering a block or item a player would read as the same thing.
##
## Display names rather than ids, because ids are namespaced and never collide - which is exactly why
## this goes unnoticed. A player holding "Copper Ore" and "Copper Ore" has no way to tell which is
## which, and no recipe will accept the wrong one.
func _same_display_name(out: Array) -> void:
	var seen := {}
	for id in server.registry.defs.size():
		if id == BlockRegistry.AIR:
			continue
		_note_name(seen, out, String(server.registry.defs[id].display_name), String(server.registry.defs[id].name), "block")
	for def: Dictionary in server.items.defs:
		_note_name(seen, out, String(def.get("display_name", "")), String(def.get("name", "")), "item")


func _note_name(seen: Dictionary, out: Array, display: String, full: String, kind: String) -> void:
	if display.is_empty() or not full.contains(":"):
		return
	var mod := full.get_slice(":", 0)
	var key := kind + "/" + _comparable(display)
	if not seen.has(key):
		seen[key] = [mod, full]
		return
	if seen[key][0] == mod:
		return  # one mod naming two of its own things alike is its business
	out.append({"kind": "name", "mods": [seen[key][0], mod],
		"detail": "%s and %s are both called \"%s\"; a player cannot tell them apart" % [seen[key][1], full, display]})


## A display name reduced to what a player would actually hear.
##
## Case-insensitive, because "Copper Ore" and "copper ore" are the same thing said twice. Also
## whitespace-collapsed and stripped of punctuation, because "Copper  Ore" and "Copper-Ore" are too -
## and a near-miss is *worse* than an exact match, since the two entries then sort apart in a list and
## look deliberate. (user, 2026-09-22: "copper ore vs Copper ore?")
##
## Deliberately stops there. No stemming, no plurals, no edit distance: "Copper Ore" and "Ore of
## Copper" are beyond what this can judge, and a check that guesses produces reports nobody trusts -
## which is how the first version of the trademark check died with eight false positives.
static func _comparable(display: String) -> String:
	var out := ""
	var last_space := true
	for c in display.to_lower():
		if c in "abcdefghijklmnopqrstuvwxyz0123456789":
			out += c
			last_space = false
		elif not last_space:
			out += " "
			last_space = true
	return out.strip_edges()


## Two ore passes putting different blocks in the ground that drop the same item.
##
## The duplicate-ore complaint, exactly: both mods generate their own copper, the world gets twice as
## much of it, and the player has two blocks that do the same thing.
func _duplicate_ores(out: Array) -> void:
	var by_item := {}
	for r in server.realms.values():
		for pass_object in r.generation_passes:
			var ore = pass_object.get("ore") if pass_object is Dictionary else (pass_object.ore if "ore" in pass_object else null)
			if ore == null or not server.registry.is_valid(int(ore)):
				continue
			var block := String(server.registry.defs[int(ore)].name)
			for drop in server._default_drops(int(ore)):
				if not (drop is Array) or (drop as Array).is_empty():
					continue
				var item := int(drop[0])
				if not by_item.has(item):
					by_item[item] = {}
				by_item[item][block] = true
	for item: int in by_item:
		var blocks: Array = (by_item[item] as Dictionary).keys()
		var mods := {}
		for block: String in blocks:
			mods[block.get_slice(":", 0)] = true
		if mods.size() < 2:
			continue
		blocks.sort()
		out.append({"kind": "ore", "mods": mods.keys(),
			"detail": "%s both generate in the ground and drop %s; the world gets twice as much of it"
				% [" and ".join(blocks), server.items.name_of(item)]})


## Biomes sitting so close together that the generator will hardly ever choose one of them.
func _crowded_biomes(out: Array) -> void:
	for r in server.realms.values():
		var generator = r.get("biome_generator") if r is Dictionary else (r.biome_generator if "biome_generator" in r else null)
		if generator == null or not ("biomes" in generator):
			continue
		var biomes: Array = generator.biomes
		for i in biomes.size():
			for j in range(i + 1, biomes.size()):
				var a: Dictionary = biomes[i]
				var b: Dictionary = biomes[j]
				if String(a.name).get_slice(":", 0) == String(b.name).get_slice(":", 0):
					continue
				if bool(a.get("ocean", false)) != bool(b.get("ocean", false)):
					continue
				var apart := Vector4(float(a.t) - float(b.t), float(a.h) - float(b.h),
					float(a.w) - float(b.w), float(a.p) - float(b.p)).length()
				if apart > BIOME_TOO_CLOSE:
					continue
				out.append({"kind": "biome", "mods": [String(a.name).get_slice(":", 0), String(b.name).get_slice(":", 0)],
					"detail": "%s and %s sit %.3f apart in climate; whichever loses will hardly ever appear"
						% [a.name, b.name, apart]})
