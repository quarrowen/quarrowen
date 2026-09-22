extends RefCounted
## Named music tracks. A mod registers a track; the server tells a client to play one; the client
## downloads it the first time it is asked for and crossfades it in.
##
## Music is not a long sound effect, and the differences are why this is its own registry rather than a
## flag on SoundRegistry:
##
##   - **It is big.** A track is megabytes. Its audio is registered as a *lazy* asset, so it is not part
##     of the download a player waits through to join; it arrives quietly afterwards.
##   - **There is one of it.** Sounds are a pool of voices; music is one thing playing, replaced by
##     another with a crossfade.
##   - **It has an author.** `attribution` is required. Whoever runs a server is redistributing whatever
##     a mod put in it, to their children and anyone else who joins, and a track with no recorded source
##     is one nobody can check the licence of later. A mod that omits it is refused at registration,
##     loudly, while the person who can fix it is looking.

const MAX_TRACKS := 256
const NETWORK_FIELDS := ["name", "file", "volume", "loop", "attribution"]

var defs: Array[Dictionary] = []
var ids := {}  # name -> id


## def: name, file (asset name), volume (0-2), loop (default true), attribution (required: who made it
## and under what licence). Returns the id, or -1 with an error explaining which part was wrong.
func register(def: Dictionary) -> int:
	var track_name := String(def.get("name", ""))
	if track_name.is_empty() or ids.has(track_name) or defs.size() >= MAX_TRACKS:
		push_error("Invalid or duplicate music track '%s'" % track_name)
		return -1
	var attribution := String(def.get("attribution", "")).strip_edges()
	if attribution.length() < 4:
		push_error("Music track '%s' has no attribution. Say who made it and under what licence - a server running this mod is redistributing it." % track_name)
		return -1
	var file := String(def.get("file", ""))
	if file.is_empty():
		push_error("Music track '%s' has no audio file" % track_name)
		return -1
	var d := {
		"name": track_name,
		"file": file.left(256),
		"volume": clampf(float(def.get("volume", 1.0)), 0.0, 2.0),
		"loop": bool(def.get("loop", true)),
		"attribution": attribution.left(256),
	}
	ids[track_name] = defs.size()
	defs.append(d)
	return defs.size() - 1


## The id registered under this name, or **-1 if nothing is**.
##
## -1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
## and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
## reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
## only after checking it, or use the `require_*` form at the API boundary.
func id_of(track_name: String) -> int:
	return int(ids.get(track_name, -1))


## Whether anything is registered under this id.
func is_valid(id: int) -> bool:
	return id >= 0 and id < defs.size()


## The music table as the client receives it.
func to_network() -> Array:
	var out := []
	for d in defs:
		var entry := {}
		for field in NETWORK_FIELDS:
			entry[field] = d[field]
		out.append(entry)
	return out


## Rebuilds the table on the client. False when the data is malformed.
func load_network(list) -> bool:
	defs.clear()
	ids.clear()
	if not (list is Array):
		return true  # a server with no music is not an error
	for entry in (list as Array).slice(0, MAX_TRACKS):
		if not (entry is Dictionary):
			return false
		if register(entry) < 0:
			return false
	return true


## Everything playing on this server, as lines a player can read: what it is and who made it. The
## point of making attribution required is that it can be shown, so it is shown - /music credits.
func credits() -> Array:
	var out := []
	for d in defs:
		out.append("%s - %s" % [d.name, d.attribution])
	return out
