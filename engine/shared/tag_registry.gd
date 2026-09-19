extends RefCounted
## Named groups of blocks and items: "any log", "any ore", "anything a pipe may carry".
##
## The engine keeps the groups and never learns what any of them mean. A mod says what is in one; a
## recipe, a filter or a machine asks what is in one.
##
## **The point is not saving typing.** It is that a group belongs to everybody: a mod adding cherry
## trees can put its wood into `base:logs`, and every recipe the base game already wrote for logs then
## accepts it, without the base game knowing that mod exists. Doing it any other way means the base
## game has to be edited every time somebody adds a tree, which is the same as saying nobody may.
##
##     api.tag("logs", ["base:oak_log"])            # in base: defines base:logs
##     api.tag("base:logs", ["cherry:cherry_log"])  # in another mod: adds to base:logs
##
## A bare name is your own mod's, the same as everywhere else in the API. Writing the whole thing is
## always allowed and always means exactly what it says, so a mod that would rather not rely on that
## can simply never use the short form.

## Tag name -> {member name: true}. Members are kept by *name* rather than by id because ids move
## whenever a mod is added, and a tag outlives the run that defined it.
var members := {}


## Adds names to a tag, creating it if need be. Returns the number actually added.
func add(tag_name: String, names: Array) -> int:
	if not members.has(tag_name):
		members[tag_name] = {}
	var added := 0
	for entry in names:
		var name := String(entry)
		if name.is_empty() or members[tag_name].has(name):
			continue
		members[tag_name][name] = true
		added += 1
	return added


## The names in a tag, or an empty array. A tag nobody defined is empty rather than an error: a mod
## that works with another one when it is installed should not have to guard every call.
func names_in(tag_name: String) -> Array:
	return members.get(tag_name, {}).keys()


func has(tag_name: String, name: String) -> bool:
	return members.get(tag_name, {}).has(name)


func exists(tag_name: String) -> bool:
	return members.has(tag_name)


## Every tag something is in. Walks all of them, so it is for tools and questions rather than for
## anything on the hot path.
func tags_of(name: String) -> Array:
	var out := []
	for tag_name: String in members:
		if members[tag_name].has(name):
			out.append(tag_name)
	out.sort()
	return out


## The namespaces tags have been written for ("base", "cherry"), for warning about ones that no
## installed mod owns.
func namespaces() -> Array:
	var out := {}
	for tag_name: String in members:
		var parts := tag_name.split(":", true, 1)
		if parts.size() == 2:
			out[parts[0]] = true
	return out.keys()
