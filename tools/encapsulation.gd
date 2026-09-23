extends RefCounted
## Who reaches into a structure that another file owns.
##
## The engine keeps reimplementing its own readers. Twice now the same shape: a new subsystem needs
## something a registry already normalised, reaches straight into the registry's nested dictionaries
## instead of calling the function that reads them, and gets it subtly wrong. Weather built a particle
## emitter by hand and asked the client for a key it did not have (2026-09-19); `sources.gd` walked
## loot pools by hand and invented flat percentages while `LootRegistry.chance_of` was computing real
## ones twenty lines from where it was being written (2026-09-22).
##
## **The rule in CLAUDE.md was already there both times.** It is the guardrail that failed, so this is
## a check rather than a third paragraph. Three cheaper ideas were measured first and thrown away:
## duplicate function names (197 hits, and `register` in 28 registries is correct, not duplication),
## doc-comment similarity against `mod_api.gd` (170 hits, and `api.show_tip` resembling
## `tutorials.show_tip` is what a facade is *for*), and deriving ownership from which file builds a
## key (133 hits, almost all coincidence). None of them separated the mistake from the idiom.
##
## What does separate them is narrower: **a normalised nested shape has exactly one owner, and
## everybody else goes through a function.** `loot.gd` owns what is inside a table; `effect_registry.gd`
## owns what is inside an emitter. Reaching past the owner is not always wrong - the client has to read
## an emitter to draw it - which is why this is a ratchet and not a ban: the baseline is checked in, and
## the suite fails on anything *new*.
##
## Regenerate with: godot --headless --path . res://tools/mod_tool.tscn -- owned

const OUT := "res://engine/owned.txt"

## Nested shapes with one owner, and the file that owns each.
##
## **This list is the part that needs maintaining**, the same way `mod_reload._forget` does: a new
## registry that normalises a mod-supplied dictionary into a nested shape belongs here, or the check
## silently covers one registry fewer.
##
## Two kinds of key were tried and taken out again, and neither is worth re-adding:
##
## - **A plain member with no reader.** `realm.generation_passes` is a bare Array four files index into
##   because there is no function to call instead. Flagging it reports four things nobody can fix.
## - **A name that means different things in different registries.** `shape` is a block shape, a recipe
##   shape and a particle shape. The check matches on the name, so it cannot tell them apart and every
##   hit is a false one.
##
## What is left is the useful case: a registry took what a mod wrote, normalised it, and has a function
## that reads it back.
const OWNED := {
	"pools": "engine/server/loot.gd",
	"entries": "engine/server/loot.gd",
	"emitters": "engine/shared/effect_registry.gd",
	"drops": "engine/shared/entity_registry.gd",
	"notable": "engine/shared/entity_registry.gd",
}

const HEADER := """# Who reaches into a structure another file owns.
#
# A ratchet, not a ban. Some of these are fine - the client has to read an emitter to draw one - and
# some are the next weather bug waiting to happen. What matters is that the list may only get shorter:
# tests/gameplay_test.gd fails when a line appears that is not already here, so a new subsystem cannot
# quietly hand-roll a reader for a shape that already has one. That is how loot pools got walked by
# hand while LootRegistry.chance_of sat unused (2026-09-22), and how weather built an emitter the
# client could not read (2026-09-19).
#
# Each line is: <shape> <owner> <the file reaching in>
#
# Before adding to this file, check whether the owner already has a function that answers the
# question. It usually does, and no document lists them - which is the whole reason this exists. The
# engine's own reference page (docs/api/engine.html) is the place to look.
#
# Regenerate with: godot --headless --path . res://tools/mod_tool.tscn -- owned

"""


## Lines of "<shape> <owner> <outsider>", sorted, for every file that reaches past an owner.
static func report() -> Array:
	var out: Array = []
	for shape: String in OWNED:
		var owner: String = OWNED[shape]
		# `.shape`, `.get("shape"` and `["shape"]` - the three ways to reach a key in GDScript.
		var pattern := RegEx.create_from_string('(\\.%s\\b|\\.get\\(\\s*"%s"|\\[\\s*"%s"\\s*\\])' % [shape, shape, shape])
		for path: String in _scripts_under("res://engine"):
			var relative: String = path.trim_prefix("res://")
			if relative == owner:
				continue
			if pattern.search(FileAccess.get_file_as_string(path)) != null:
				out.append("%s %s %s" % [shape, owner, relative])
	out.sort()
	return out


## The baseline as checked in, ignoring comments and blank lines.
static func baseline() -> Array:
	var out: Array = []
	for line in FileAccess.get_file_as_string(OUT).split("\n"):
		var trimmed := String(line).strip_edges()
		if not trimmed.is_empty() and not trimmed.begins_with("#"):
			out.append(trimmed)
	return out


static func write() -> int:
	var lines: Array = report()
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(HEADER + "\n".join(lines) + "\n")
	file.close()
	return lines.size()


static func _scripts_under(root: String) -> Array:
	var out: Array = []
	var dirs: Array = [root]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for name in DirAccess.get_directories_at(dir):
			dirs.append(dir.path_join(name))
		for name in DirAccess.get_files_at(dir):
			if String(name).ends_with(".gd"):
				out.append(dir.path_join(name))
	return out
