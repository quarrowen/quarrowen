extends RefCounted
## Changing many blocks at once: a box filled, a vein mined, a sphere cleared.
##
## A mod supplies two things - **which cells** and **when** - and the engine supplies everything that
## makes doing it to a live world safe:
##
##     var cells := api.area_cells("vein", {"position": at, "player": p, "max": 64})
##     api.show_area(p, cells)                       # the preview, before they commit
##     var done := api.area_edit(p, cells, {"block": 0})
##     p.send_message("Mined %d." % done.changed)
##
## **Every cell goes through the same checks a hand-swung pick does.** Plot permission, the build
## right, breakability, the block events, the loot roll, tool wear and hunger are not re-implemented
## here: `break_block_for` and `place_block_for` on the server are the same functions
## `on_break_block` and `on_place_block` call, so a mod listening for `block_broken` hears an area
## edit exactly as it hears a pickaxe. That is the whole reason this is an engine capability rather
## than something each mod writes with `api.fill` - `fill` is admin, and admin does not ask.
##
## **Reach and mining time are the caller's, deliberately.** Swinging at one block asks "can you touch
## it" and "did you swing long enough"; a selection asks neither, because the answer is about the
## selection and not the cell. What it asks instead is whether the *player* is near the selection at
## all, which `REACH_OF_SELECTION` decides.
##
## **The budget is the one that already exists.** A cell is a fraction of an edit token rather than a
## whole one - a whole one each would make a 64-block vein cost four seconds of a player's entire
## allowance - so `CELLS_PER_TOKEN` sets the exchange rate and the normal refill rate-limits area
## edits the same way it rate-limits everything else. Nothing new to tune, and no second pool that
## somebody has to remember to drain.

const BlockRegistry = preload("res://engine/shared/block_registry.gd")
const Chunk = preload("res://engine/shared/chunk.gd")
const VoxelWorld = preload("res://engine/shared/voxel_world.gd")

## The most cells one edit may touch, whatever a mod asks for. A ceiling rather than a suggestion:
## the cost of a selection is paid on the server's tick, and one enormous one stutters everybody.
const MAX_CELLS := 4096
## Cells per edit token. At 15 tokens a second this allows roughly 480 cells a second sustained,
## which is generous for building and nowhere near enough to flatten a world before anyone notices.
const CELLS_PER_TOKEN := 32.0
## How far the player may be from the nearest cell of a selection. Larger than a hand's REACH because
## the point of an area tool is to shape something bigger than you can touch, but still bounded: an
## edit on the far side of the world is not a long arm, it is a different player's business.
const REACH_OF_SELECTION := 24.0
## Cells the preview will outline. Past this the client draws the bounding box and the count instead,
## because ten thousand wireframe cubes is not a preview, it is a white screen.
const PREVIEW_CELLS := 512

var server
## Rules a mod registered, name -> Callable(ctx) -> Array[Vector3i].
var rules := {}
## Why the last call refused, in words a player can be shown. A selection that silently does nothing
## is indistinguishable from a broken tool. (2026-09-21)
var problem := ""


func _init(game_server) -> void:
	server = game_server
	_register_builtins()


# --- Choosing the cells --------------------------------------------------------------------------

func _register_builtins() -> void:
	# The three shapes that cover almost everything. A mod wanting another registers it.
	rules["box"] = func(ctx): return _box(ctx)
	rules["sphere"] = func(ctx): return _sphere(ctx)
	rules["vein"] = func(ctx): return _vein(ctx)


## Registers a way of choosing cells. The callable is handed the context dictionary the mod passed to
## `area_cells` and returns an Array of Vector3i.
func register_rule(rule_name: String, chooser: Callable) -> void:
	if rule_name.is_empty() or not chooser.is_valid():
		push_error("register_area_rule: needs a name and a callable")
		return
	rules[rule_name] = chooser


## The cells a rule chooses, capped and de-duplicated. Always returns something a caller can loop
## over, so a mod never has to check for null.
func cells(rule_name: String, ctx: Dictionary) -> Array:
	problem = ""
	var chooser = rules.get(rule_name)
	if not (chooser is Callable):
		problem = "There is no '%s' shape." % rule_name
		push_error("area_cells: unknown rule '%s'. Registered: %s" % [rule_name, ", ".join(rules.keys())])
		return []
	var limit := clampi(int(ctx.get("max", MAX_CELLS)), 1, MAX_CELLS)
	var out: Array = chooser.call(ctx)
	if not (out is Array):
		push_error("area_cells: rule '%s' returned %s, not an Array of Vector3i" % [rule_name, type_string(typeof(out))])
		return []
	var seen := {}
	var unique: Array = []
	for cell in out:
		if not (cell is Vector3i) or seen.has(cell):
			continue
		if cell.y < 0 or cell.y >= Chunk.SIZE_Y:
			continue
		seen[cell] = true
		unique.append(cell)
		if unique.size() >= limit:
			break
	return unique


func _box(ctx: Dictionary) -> Array:
	var a = ctx.get("from")
	var b = ctx.get("to")
	if not (a is Vector3i and b is Vector3i):
		push_error("area_cells('box'): needs 'from' and 'to' as Vector3i")
		return []
	var out: Array = []
	for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
				out.append(Vector3i(x, y, z))
				if out.size() >= MAX_CELLS:
					return out
	return out


func _sphere(ctx: Dictionary) -> Array:
	var centre = ctx.get("position")
	if not (centre is Vector3i):
		push_error("area_cells('sphere'): needs 'position' as Vector3i")
		return []
	var radius := clampf(float(ctx.get("radius", 4.0)), 0.5, 32.0)
	var r := ceili(radius)
	# Distance from the cell's middle, so the ball is not lopsided by half a block.
	var limit := radius * radius
	var out: Array = []
	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			for z in range(-r, r + 1):
				if Vector3(x, y, z).length_squared() <= limit:
					out.append(centre + Vector3i(x, y, z))
					if out.size() >= MAX_CELLS:
						return out
	return out


## Everything of the same kind joined to a starting cell: the ore vein, the tree, the patch of sand.
##
## Flood fill over the six faces rather than all twenty-six. A diagonal touch is not the same lump to
## anyone looking at it, and counting it means one buried ore joins two veins into one. (2026-09-21)
func _vein(ctx: Dictionary) -> Array:
	var start = ctx.get("position")
	if not (start is Vector3i):
		push_error("area_cells('vein'): needs 'position' as Vector3i")
		return []
	var into = _realm(ctx)
	var wanted := int(ctx.get("block", into.world.get_block_v(start)))
	if wanted == BlockRegistry.AIR or wanted == BlockRegistry.UNLOADED:
		return []
	var limit := clampi(int(ctx.get("max", 64)), 1, MAX_CELLS)
	var seen := {start: true}
	var queue: Array = [start]
	var out: Array = []
	while not queue.is_empty() and out.size() < limit:
		var at: Vector3i = queue.pop_front()
		if into.world.get_block_v(at) != wanted:
			continue
		out.append(at)
		for face in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
			var next: Vector3i = at + face
			if seen.has(next) or next.y < 0 or next.y >= Chunk.SIZE_Y:
				continue
			seen[next] = true
			queue.append(next)
	return out


func _realm(ctx: Dictionary):
	var player = ctx.get("player")
	if player != null:
		return server.realm_of(player)
	return server.realm


# --- Doing it ------------------------------------------------------------------------------------

## Applies one change to every cell a player is allowed to change.
##
## options: {block (id to set; 0 or absent breaks instead), drops (default true), realm}.
##
## Returns {changed, skipped, refused, reason}. **`skipped` is not a failure** - a selection that
## crosses into somebody's garden does the part outside it and says how much it left alone, which is
## friendlier than refusing the lot and lets a vein run up to a boundary and stop.
func apply(player, cell_list: Array, options := {}) -> Dictionary:
	problem = ""
	var result := {"changed": 0, "skipped": 0, "refused": false, "reason": ""}
	if player == null or cell_list.is_empty():
		return result
	if player.dead:
		return _refuse(result, "You cannot build while you are dead.")
	if not server._may(player, "build", ""):
		return _refuse(result, "You can't build on this server.")
	var into = server.realm_of(player)
	# One question for the whole selection, asked of the nearest cell: an area tool is meant to reach
	# further than an arm, but not across the world.
	var eye: Vector3 = player.get_eye_position()
	var nearest := INF
	for cell: Vector3i in cell_list:
		nearest = minf(nearest, eye.distance_to(Vector3(cell) + Vector3(0.5, 0.5, 0.5)))
	if nearest > REACH_OF_SELECTION:
		return _refuse(result, "That is too far away (%.0f blocks)." % nearest)
	var cost := float(cell_list.size()) / CELLS_PER_TOKEN
	if player.edit_tokens < cost:
		return _refuse(result, "Too fast - give it a moment.")
	player.edit_tokens -= cost
	var block := int(options.get("block", BlockRegistry.AIR))
	var drops := bool(options.get("drops", true))
	if block != BlockRegistry.AIR and not server.registry.is_valid(block):
		return _refuse(result, "That is not a block.")
	for cell: Vector3i in cell_list:
		# Chunks past the edge of what is loaded are not "somebody else's", they are not there: asking
		# the generator for them mid-edit would stall the tick.
		if not into.world.has_chunk(VoxelWorld.chunk_coord_at(cell.x, cell.z)):
			result.skipped += 1
			continue
		if not server.plots.may_build(player, into.id, cell):
			result.skipped += 1
			continue
		if block == BlockRegistry.AIR:
			if server.break_block_for(player, cell, into, drops):
				result.changed += 1
		elif server.place_block_for(player, cell, block, into):
			result.changed += 1
	if result.changed == 0 and result.skipped > 0:
		result.reason = "That is somebody else's ground."
		problem = result.reason
	return result


func _refuse(result: Dictionary, why: String) -> Dictionary:
	result.refused = true
	result.reason = why
	problem = why
	return result


# --- Showing it ----------------------------------------------------------------------------------

## Outlines a selection for one player, before they commit to it. `seconds` 0 leaves it up until the
## next call clears it, which is what a tool holding a selection wants.
func preview(player, cell_list: Array, options := {}) -> void:
	if player == null or not server._started:
		return
	var show := not cell_list.is_empty()
	var shown: Array = cell_list.slice(0, PREVIEW_CELLS) if show else []
	var packed := PackedVector3Array()
	for cell: Vector3i in shown:
		packed.append(Vector3(cell))
	Net.s_area_preview.rpc_id(player.peer_id, packed, String(options.get("color", "#ffcc00")),
		clampf(float(options.get("seconds", 0.0)), 0.0, 120.0), show)


## Takes the outline away.
func clear_preview(player) -> void:
	preview(player, [])

