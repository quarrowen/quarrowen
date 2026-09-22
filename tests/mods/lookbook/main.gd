extends "res://engine/server/mod.gd"
## A landscape whose only job is to be photographed.
##
## Deciding what 1.0 should look like from prose does not work: the person deciding is not an artist,
## and neither a description nor a palette swatch tells you what a world feels like to stand in. So
## this builds one view, always the same one, and `tools/look_lab.gd` repaints the blocks underneath
## it. Two renders then differ only by the thing being decided. (2026-09-21)
##
## It uses **base's own blocks and the engine's biome generator**, so what is in the picture is what
## 1.0 would really ship rather than a mock-up of it. The trees are declared here rather than in
## `base` only because `base` has none yet - they belong to it after the Phase 4 re-scope.
##
## Not shipped, and not a game anybody plays.


func setup(api) -> void:
	api.set_server_info({"name": "Lookbook", "motd": "A view to decide by."})
	api.set_gameplay({"keep_inventory": true, "natural_regeneration": true})
	api.register_feature("broadleaf", {"type": "tree", "trunk": "base:birch_log",
		"leaves": "base:birch_leaves", "height": [5, 8], "shape": "round"})
	api.register_feature("conifer", {"type": "tree", "trunk": "base:spruce_log",
		"leaves": "base:spruce_leaves", "height": [7, 11], "shape": "cone"})
	api.register_feature("rock", {"type": "boulder", "block": "base:stone", "radius": [1, 2]})
	# Model trees, six of them: three silhouettes at two sizes, each its own canopy block, picked at
	# random per tree along with a trunk height.
	#
	# **A wood where every tree is the same tree is the thing that reads as generated.** One shape
	# repeated across a hillside looks like wallpaper however good the shape is - the eye picks up the
	# repetition long before it judges the silhouette. Varying shape, size, trunk height and the green
	# itself costs nothing at runtime: they are all still one model instance per tree. (2026-09-22)
	if OS.get_environment("QW_LOOK_CUBE_TREES") != "1":
		var only := String(OS.get_environment("QW_LOOK_TREE"))
		for shape in ["round", "spire", "clump"]:
			if not only.is_empty() and shape != only:
				continue
			for size in 2:
				var name := "%s_%d" % [shape, size]
				api.register_block("canopy_" + name, {"display_name": "Canopy", "render": "model",
					"model": "models/tree_%s.glb" % name, "drops": "", "hardness": 0.2})
				_canopies.append(api.require_block("lookbook:canopy_" + name))
		_canopy = "models"
		api.register_feature("modeltree", func(writer, origin: Vector3i, rng):
			var trunk: int = api.require_block("base:birch_log")
			var head: int = _canopies[rng.randi() % _canopies.size()]
			# Taller trunks under the bigger canopies, or a large head sits on the ground.
			var height: int = 2 + (rng.randi() % 4)
			# Writer.set_block takes separate coordinates, not a Vector3i.
			for dy in height:
				writer.set_block(origin.x, origin.y + dy, origin.z, trunk)
			writer.set_block(origin.x, origin.y + height, origin.z, head))
	# One biome, not a world tour. Comparing two looks means comparing the same hillside twice, and
	# terrain that wanders into a desert in one render and a forest in the other compares nothing.
	api.register_biome("vale", {
		"climate": {"temperature": 0.1, "humidity": 0.3},
		# Land above the water, which needs saying: `height.base` defaults to 52 and the sea here is
		# at 62, so without this the whole map generated ten blocks under water and the first renders
		# were of an empty ocean. Rolling rather than flat, with peaks for a horizon. (2026-09-21)
		"height": {"base": 70.0, "variation": 7.0, "peaks": 14.0},
		"surface": {"top": "base:grass", "filler": "base:dirt", "beach": "base:sand",
			"underwater": "base:gravel", "stone": "base:stone", "water": "base:water"},
		# The *resolved* choice, not the environment variable. Reading the variable here meant the
		# canopy block was registered and then never placed, so a build with no variables set grew
		# cube trees while claiming to grow models. (2026-09-21)
		"features": ([{"feature": "modeltree", "per_chunk": 1.0}] if not _canopy.is_empty()
			else [{"feature": "broadleaf", "per_chunk": 0.7}, {"feature": "conifer", "per_chunk": 0.35}])
			+ [{"feature": "rock", "per_chunk": 0.4}],
		"plants": [{"block": "base:tall_grass", "chance": 0.22, "on": ["base:grass"]},
			{"block": "base:fern", "chance": 0.05, "on": ["base:grass"]}],
	})
	api.use_biome_generator({"sea_level": 62})
	# A lake worth looking at, so the water shader has something to mirror.
	api.add_generation_pass(Lake.new(api.require_block("base:water"), api.require_block("base:sand")))
	# Slab twins for the surface materials, so the smoothing pass has something to swap to. They live
	# here rather than in `base` only because base has slabs for stone and planks and not for ground.
	for material in [["grass", "base:grass"], ["dirt", "base:dirt"], ["sand", "base:sand"]]:
		api.register_block("%s_slab" % material[0], {"display_name": "%s Slab" % String(material[0]).capitalize(),
			"shape": "slab", "textures": api.block_textures(String(material[1])), "full_block": String(material[1])})
	if OS.get_environment("QW_LOOK_SHAPE") == "1":
		api.add_generation_pass(Smooth.new({
			api.require_block("base:grass"): api.require_block("lookbook:grass_slab"),
			api.require_block("base:dirt"): api.require_block("lookbook:dirt_slab"),
			api.require_block("base:sand"): api.require_block("lookbook:sand_slab"),
		}))
	# The viewpoint is *found*, not guessed. The first attempt spawned at a fixed height and dropped
	# the camera onto a bare stone mountaintop, so the picture was a grey quarry - which compares two
	# palettes about as well as photographing them in the dark. (2026-09-21)
	api.set_spawn_handler(func(_player): return _viewpoint(api))
	# Lights, on demand, for photographing the dark. A command rather than scenery because where they
	# want to be depends on where the camera ends up, and the viewpoint is worked out at spawn.
	# A hut on stilts out in the lake, for judging what water does with a built thing standing in it.
	# A reflection of a hillside is forgiving - the shapes are soft and a smeared one still reads. A
	# roofline is not: it is straight, and either the mirror holds it or it does not. (2026-09-22)
	api.register_command("hut", "Build a stilt hut out in the water", func(player, _args):
		var post: int = api.require_block("base:birch_log")
		var floor_block: int = api.require_block("base:planks")
		var wall: int = api.require_block("base:planks")
		var roof: int = api.require_block("base:cobblestone")
		var torch: int = api.require_block("base:torch")
		# Out where the water is, not at the player's feet.
		var facing: Vector3 = api.look_direction(player)
		var centre := Vector3i(Vector3(player.position) + facing * 22.0)
		var water_top := 62
		var deck := water_top + 3
		for dx in range(-4, 5):
			for dz in range(-4, 5):
				var at := Vector3i(centre.x + dx, deck, centre.z + dz)
				api.set_block(at, floor_block)
				# Stilts on the corners and every other step, down into the bed.
				if absi(dx) == 4 or absi(dz) == 4:
					if (dx + dz) % 2 == 0:
						for y in range(water_top - 6, deck):
							api.set_block(Vector3i(at.x, y, at.z), post)
		# Walls with a gap for a doorway, and a flat roof: a silhouette with straight edges is the
		# point, not architecture.
		for h in 4:
			for dx in range(-3, 4):
				for dz in range(-3, 4):
					if absi(dx) != 3 and absi(dz) != 3:
						continue
					if h < 3 and dx == 0 and dz == -3:
						continue
					api.set_block(Vector3i(centre.x + dx, deck + 1 + h, centre.z + dz), wall)
		for dx in range(-4, 5):
			for dz in range(-4, 5):
				api.set_block(Vector3i(centre.x + dx, deck + 5, centre.z + dz), roof)
		api.set_block(Vector3i(centre.x, deck + 6, centre.z), torch)
		api.set_block(Vector3i(centre.x - 3, deck + 1, centre.z - 4), torch)
		api.set_block(Vector3i(centre.x + 3, deck + 1, centre.z - 4), torch)
		player.send_message("Hut at %s." % centre))
	api.register_command("lights", "Set torches out in front of you", func(player, _args):
		var torch: int = api.require_block("base:torch")
		var stand: int = api.require_block("base:cobblestone")
		var at: Vector3 = player.position
		var facing: Vector3 = api.look_direction(player)
		var placed := 0
		# A line of them running away from the camera, each on its own post so the light is above the
		# ground and casts something rather than sitting in the grass.
		# Starting a few paces out: the first post at arm's length fills the frame, and one standing in
		# the shallows keeps the water above it, which reads as a glass box round the torch.
		for step in range(6, 34, 4):
			var spot := Vector3i(at + facing * float(step))
			var y: int = api.surface_y(spot.x, spot.z)
			# Not in the water: a torch is not a lighthouse.
			if y <= 0 or api.get_block(Vector3i(spot.x, y, spot.z)) == api.block("base:water"):
				continue
			for h in 2:
				api.set_block(Vector3i(spot.x, y + 1 + h, spot.z), stand)
			api.set_block(Vector3i(spot.x, y + 3, spot.z), torch)
			placed += 1
		player.send_message("Set out %d torches." % placed))


## A spot on grass, a little above the sea, with water in view: the frame that shows the most at once.
##
## Scanned rather than hardcoded because terrain comes from a seed, and a coordinate that happens to
## be a good view today stops being one the moment anything about generation changes.
## Worked out once and kept. It was being recomputed on every join, and a scan that asks for tens of
## thousands of surface heights - each of which may generate a chunk - took long enough that the
## screenshot client gave up waiting and photographed its own loading screen. (2026-09-21)
var _found := Vector3.INF
## Which canopy model the trees use ("" for the built-in cube trees).
var _canopy := ""
## The canopy block ids a tree may be built with.
var _canopies: Array[int] = []


func _viewpoint(api) -> Vector3:
	if _found != Vector3.INF:
		return _found
	if OS.get_environment("QW_LOOK_SHORE") == "1":
		_found = _shoreline(api)
		return _found
	var best := Vector3(8.5, 80.0, 8.5)
	var best_score := -1.0
	for x in range(-96, 97, 24):
		for z in range(-96, 97, 24):
			var y: int = api.surface_y(x, z)
			# Above the water but not up in the stone: a shoreline vantage, not a summit.
			if y < 64 or y > 78:
				continue
			# `surface_y` gives the topmost *solid* block, not the air above it - reading y - 1 here
			# found dirt every time, so the search never matched grass and every render fell back to
			# the same stone default. (2026-09-21)
			if api.get_block(Vector3i(x, y, z)) != api.block("base:grass"):
				continue
			# Standing in a clearing, not against a trunk. The first good render had a tree filling
			# half the frame: a vantage point is no use if something is parked in front of the lens.
			var blocked := false
			for dx in range(-6, 7, 2):
				for dz in range(-6, 7, 2):
					for dy in [1, 2, 3]:
						if api.get_block(Vector3i(x + dx, y + dy, z + dz)) != 0:
							blocked = true
			if blocked:
				continue
			# How much water is in view from here, and how far the eye can travel before the ground
			# rises again - between them, a view rather than a hollow.
			var water := 0.0
			var openness := 0.0
			for dx in range(-40, 41, 16):
				for dz in range(-40, 41, 16):
					var h: int = api.surface_y(x + dx, z + dz)
					if h <= 62:
						water += 1.0
					openness += maxf(0.0, float(y - h)) * 0.05
			var score := water + openness + float(y - 62) * 0.6
			if score > best_score:
				best_score = score
				best = Vector3(x + 0.5, y + 3.0, z + 0.5)
	_found = best
	return best


## Slabs where the ground steps up by one, so a hillside is a ramp rather than a staircase.
##
## **This is the lever that actually matters.** Five texture styles all read as the same game, because
## what says "voxel game" is not the pixels - it is that every slope is a flight of one-block stairs
## and every tree is a cube of leaves. Halving the step is a small change to the world and a large one
## to the picture. (2026-09-21: the user found every texture style still read as the genre's
## best-known game)
class Smooth:
	extends RefCounted

	const Chunk = preload("res://engine/shared/chunk.gd")

	var swap := {}  # full block id -> its bottom-slab id

	func _init(pairs: Dictionary) -> void:
		swap = pairs

	# Runs on a worker thread; touches only this chunk and the table built at construction.
	func decorate(chunk, _seed_value: int) -> void:
		var heights := {}
		for x in Chunk.SIZE_X:
			for z in Chunk.SIZE_Z:
				heights[Vector2i(x, z)] = _top(chunk, x, z)
		for x in Chunk.SIZE_X:
			for z in Chunk.SIZE_Z:
				var y: int = heights[Vector2i(x, z)]
				if y <= 0:
					continue
				# Only where the ground really does step down beside it. A column level with its
				# neighbours is flat ground and should stay a full block, or the whole world sinks
				# half a metre and nothing looks smoother for it.
				var lowest := y
				for n in [Vector2i(x - 1, z), Vector2i(x + 1, z), Vector2i(x, z - 1), Vector2i(x, z + 1)]:
					if heights.has(n):
						lowest = mini(lowest, int(heights[n]))
				if y - lowest != 1:
					continue
				var id: int = chunk.blocks.decode_u16(Chunk.index(x, y, z) << 1)
				if swap.has(id):
					chunk.blocks.encode_u16(Chunk.index(x, y, z) << 1, int(swap[id]))

	func _top(chunk, x: int, z: int) -> int:
		for y in range(Chunk.SIZE_Y - 1, 0, -1):
			if chunk.blocks.decode_u16(Chunk.index(x, y, z) << 1) != 0:
				return y
		return 0


## A spot on the sand with the sea in front of it, for judging water rather than land.
##
## Its own search rather than a weight on the general one: a shoreline wants the *opposite* of what a
## vista wants - low rather than high, close rather than commanding - and the clearing rule that keeps
## a tree out of a landscape shot rejects most beaches, which have trees behind them. (2026-09-21)
func _shoreline(api) -> Vector3:
	var sea: int = api.block("base:water")
	for radius in [40, 80, 140, 200]:
		for x in range(-radius, radius + 1, 6):
			for z in range(-radius, radius + 1, 6):
				var y: int = api.surface_y(x, z)
				if y < 62 or y > 66:
					continue
				var here: int = api.get_block(Vector3i(x, y, z))
				if here == sea:
					continue
				# Water within a few paces, and enough of it to be a sea rather than a puddle.
				var wet := 0
				for dx in range(-6, 7, 2):
					for dz in range(-6, 7, 2):
						if api.get_block(Vector3i(x + dx, api.surface_y(x + dx, z + dz), z + dz)) == sea:
							wet += 1
				if wet >= 6:
					return Vector3(x + 0.5, y + 2.0, z + 0.5)
	return Vector3(8.5, 66.0, 8.5)


## A lake, carved after the terrain is generated.
##
## The biome generator makes rolling land from noise, and noise does not make a body of water wide
## enough to see a reflection in - the map came out with a two-block stream and a small inlet, which
## is nothing for water to mirror. So this cuts a basin at a known place and fills it, which is also
## what a lake is: a hole with water in it. (2026-09-22)
##
## A pass rather than a biome, because a biome competes with its neighbours through climate noise and
## may simply not appear where you want it. A pass happens where it is told.
class Lake:
	extends RefCounted

	const Chunk = preload("res://engine/shared/chunk.gd")

	## Where the lake is and how big, in blocks. Near spawn so the shoreline search finds it.
	const CENTRE := Vector2(-40.0, 40.0)
	const RADIUS := 46.0
	const SURFACE := 62
	const FLOOR := 54

	var water := 0
	var sand := 0

	func _init(water_id: int, sand_id: int) -> void:
		water = water_id
		sand = sand_id

	# Runs on a worker thread; touches only this chunk.
	func decorate(chunk, _seed_value: int) -> void:
		var origin := Vector2(chunk.coord.x * Chunk.SIZE_X, chunk.coord.y * Chunk.SIZE_Z)
		# Cheap rejection: a chunk entirely outside the lake is most of them.
		if origin.distance_to(CENTRE) > RADIUS + 24.0:
			return
		for x in Chunk.SIZE_X:
			for z in Chunk.SIZE_Z:
				var here := origin + Vector2(x, z)
				var away := here.distance_to(CENTRE)
				if away > RADIUS:
					continue
				# The bed shelves rather than dropping off a cliff: a beach is where the depth tint
				# has something to shade between, and a sheer wall of water reads as a swimming pool.
				var depth := (1.0 - away / RADIUS)
				var bed := int(round(lerpf(float(SURFACE), float(FLOOR), smoothstep(0.0, 0.55, depth))))
				# Clear well above the waterline, or a tree whose ground has just been dug out from
				# under it keeps its canopy and loses its trunk, and hangs there. (2026-09-22)
				for y in range(bed, SURFACE + 26):
					var id := water if y <= SURFACE else 0
					chunk.blocks.encode_u16(Chunk.index(x, y, z) << 1, id)
				# Sand under the water and a little way up the shore.
				chunk.blocks.encode_u16(Chunk.index(x, maxi(bed - 1, 0), z) << 1, sand)
