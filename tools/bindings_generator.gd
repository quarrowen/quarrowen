extends RefCounted
## Builds engine/server/js/bindings.json: the table that lets a scripting language reach `mod_api.gd`
## without anybody hand-writing a case for each function.
##
## The two APIs drifted to 139 of 262 because every capability cost a binding in each language and the
## second one got forgotten (2026-09-20). Generating the table means a new `api.*` function is reachable
## from JavaScript the moment it exists, and it is what makes a third language - Lua was the question
## that started this - a runtime and a prelude rather than another 600 lines to keep in step.
##
## The table says only what a *caller* cannot work out from JSON: which argument is a player reference,
## which is a callback, and what a missing argument should default to. Everything else the accessors in
## `js_mod.gd` already coerce.
##
## Hand-written bindings win. Anything already in the prelude keeps its own entry - some of them rename
## (`registerLootTable` asks for `registerLoot`), some take their arguments in a friendlier order, and
## a generated table should not quietly replace a decision somebody made on purpose.

const DocsGenerator = preload("res://tools/docs_generator.gd")
const MOD_API := "res://engine/server/mod_api.gd"
const OUT := "res://engine/server/js/bindings.json"

## Types a value cannot cross JSON as: these need a GDScript object on the other side, so the functions
## that take one stay GDScript-only and are listed in unbound.txt with everybody else.
const CANNOT_CROSS := ["Object"]


static func build() -> Dictionary:
	var out := {}
	var refused := {}
	for fn in DocsGenerator.parse_gdscript(FileAccess.get_file_as_string(MOD_API), ""):
		if String(fn.signature).ends_with("(property)"):
			continue
		var args = _args(String(fn.signature))
		if args is String:
			refused[String(fn.name)] = args
			continue
		out[DocsGenerator.camel(String(fn.name))] = {"gd": String(fn.name), "args": args}
	return {"methods": out, "refused": refused}


## [{kind, default}] for each parameter, or a sentence saying why this function cannot be generated.
static func _args(signature: String):
	var inside := signature.substr(signature.find("(") + 1)
	inside = inside.substr(0, inside.rfind(")")) if inside.rfind(")") >= 0 else inside
	var out := []
	for part in _split_top_level(inside):
		var text: String = part.strip_edges()
		if text.is_empty():
			continue
		var name: String = text.get_slice(":", 0).get_slice("=", 0).strip_edges()
		var kind := ""
		var fallback = null
		if text.contains(":="):
			fallback = _literal(text.get_slice(":=", 1).strip_edges())
			kind = _kind_of_literal(text.get_slice(":=", 1).strip_edges())
		elif text.contains(":"):
			var declared: String = text.get_slice(":", 1).get_slice("=", 0).strip_edges()
			if CANNOT_CROSS.has(declared):
				return "takes a %s, which needs a GDScript object on the other side" % declared
			kind = _kind_of_type(declared)
			if text.contains("="):
				fallback = _literal(text.get_slice("=", 1).strip_edges())
		else:
			# Untyped by convention here. Two names mean something particular: `player` is always a
			# player, and `target` is whichever of a player or a creature was passed - conditions apply
			# to both, and sending the raw {__player: 3} through would hand mod_api.gd a dictionary
			# where it expected somebody. The rest are genuinely Variant.
			match name:
				"player": kind = "player"
				"target": kind = "ref"
				_: kind = "any"
		if kind.is_empty():
			return "argument '%s' has a type this does not know how to convert" % name
		var arg := {"kind": kind}
		if fallback != null:
			arg["default"] = fallback
		out.append(arg)
	return out


static func _kind_of_type(declared: String) -> String:
	match declared:
		"String": return "str"
		"int": return "int"
		"float": return "float"
		"bool": return "bool"
		"Dictionary": return "dict"
		"Array": return "arr"
		"Vector3": return "vec3"
		"Vector3i": return "vec3i"
		"Callable": return "callback"
		"Variant": return "any"
	return ""


static func _kind_of_literal(literal: String) -> String:
	if literal.begins_with("\""): return "str"
	if literal.begins_with("{"): return "dict"
	if literal.begins_with("["): return "arr"
	if literal in ["true", "false"]: return "bool"
	if literal.begins_with("Vector3i"): return "vec3i"
	if literal.begins_with("Vector3"): return "vec3"
	if literal.is_valid_int(): return "int"
	if literal.is_valid_float(): return "float"
	return "any"


## The default as data. A named constant (Vector3i.UP) has no JSON form, so it is written as the value
## it stands for rather than as the name.
static func _literal(text: String):
	if text.begins_with("\""):
		return text.trim_prefix("\"").trim_suffix("\"")
	if text == "true":
		return true
	if text == "false":
		return false
	if text.begins_with("{") or text.begins_with("["):
		return JSON.parse_string(text)
	if text.begins_with("Vector3i.") or text.begins_with("Vector3."):
		match text.get_slice(".", 1):
			"UP": return {"x": 0, "y": 1, "z": 0}
			"DOWN": return {"x": 0, "y": -1, "z": 0}
			"ZERO": return {"x": 0, "y": 0, "z": 0}
			"ONE": return {"x": 1, "y": 1, "z": 1}
		return null
	if text.is_valid_int():
		return int(text)
	if text.is_valid_float():
		return float(text)
	return null


static func _split_top_level(text: String) -> Array:
	var out := []
	var depth := 0
	var current := ""
	var quoted := false
	for i in text.length():
		var c := text[i]
		if c == "\"":
			quoted = not quoted
		if not quoted:
			if c in "([{":
				depth += 1
			elif c in ")]}":
				depth -= 1
			elif c == "," and depth == 0:
				out.append(current)
				current = ""
				continue
		current += c
	if not current.strip_edges().is_empty():
		out.append(current)
	return out


static func write() -> int:
	var table := build()
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(table, "\t", true) + "\n")
	file.close()
	return (table.methods as Dictionary).size()
