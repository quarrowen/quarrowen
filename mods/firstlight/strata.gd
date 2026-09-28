extends RefCounted
## One floor of the descent: a slab of deepstone with rooms cut out of it.
##
## **Solid first, then carved.** The alternative - building walls around empty air - is fewer blocks and
## it is wrong: an instance has no world generator, so anything that is not built is void, and the first
## person to mine through a wall falls out of the floor. Carving means a wall has rock behind it, which is
## also what makes digging your own way between two rooms a thing you can choose to do.
##
## **The layout is a depth-first walk over a grid**, not a scatter of rooms joined by lines. A walk gives
## two properties worth having for free: every room is reachable without checking, and the room it ends
## in is a long way round from the room it started in - so the way down is not next to the way up.
##
## **Laid out from the instance id and the depth.** Each floor is its own instance, so this is stable
## while you are standing in it and different the next time anybody comes down.

## Cells across and deep, the distance between their centres, and the half-width of a room. A room is
## 9x9 inside an 11-block pitch, so there are two blocks of rock between neighbours - thin enough to dig
## through on purpose, thick enough that you do not do it by accident.
const GRID := 5
const CELL := 11
const ROOM := 4
## Half-width of a corridor: 3 wide, which is room to back away from something in.
const HALL := 1
const FLOOR_Y := 40
## Head room. Four is enough to jump in and low enough to feel like it is underground.
const HEIGHT := 4
## Half-width of the two pads, so each is 3x3 and hard to miss.
const PAD := 1
## Where the middle of the grid sits, so the floor is centred on the origin.
const OFFSET := (GRID - 1) * CELL / 2

## What a floor may nest, shallowest band first. **A floor draws from every band up to its own**, so a
## deep floor still has goblins in it: a ladder that replaces its rungs reads as a different game every
## few floors rather than as the same game getting harder.
const NESTS := [
	["base:mirelet"],
	["base:goblin", "base:spider"],
	["base:clatterjack"],
	["base:dustling"],
	["base:night_stalker"],
	["base:hollow_piper"],
]
## Floors per band, so the ladder above spans about eighteen floors and then stops getting worse - the
## pressure after that is the number of nests and the dark, which keep going.
const BAND := 3

var api
var _ids := {}


func setup(mod_api) -> void:
	api = mod_api
	_ids.rock = api.require_block("base:deepstone")
	_ids.air = 0
	_ids.lamp = api.require_block("base:sunstone_block")
	_ids.up = api.require_block("base:sunstone_ore")
	_ids.down = api.require_block("base:blackglass")
	_ids.nest = api.require_block("base:spawner")
	_ids.hoard = api.require_block("simple_machines:chest")


## Builds one floor and says where its landmarks are: {entry, up, down, rooms}.
func build(instance: String, depth: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([instance, depth])
	# Deeper floors are bigger, slowly, and stop growing when the grid is full. Size is the mildest of
	# the depth knobs: a longer walk is more to search, not more to survive.
	var want := clampi(5 + depth / 2, 5, GRID * GRID)
	var plan := _walk(rng, want)

	_slab(instance)
	for cell: Vector2i in plan.rooms:
		_room(instance, cell)
	for link: Array in plan.links:
		_hall(instance, link[0], link[1])

	# **You arrive beside the way up, not on it.** Standing on it is what leaving *is*, so putting the
	# arrival point there meant walking into a floor and straight back out of it in the same tick. Three
	# blocks to one side: still the first thing in front of you, and now something you step onto.
	var landing := _centre(plan.start) + Vector3i(0, 1, 0)
	var up := landing + Vector3i(3, 0, 0)
	var down := _centre(plan.end) + Vector3i(0, 1, 0)
	_pad(instance, up, _ids.up)
	_pad(instance, down, _ids.down)

	_furnish(instance, plan, depth, rng)
	return {"entry": Vector3(landing) + Vector3(0.5, 0.0, 0.5), "up": up, "down": down,
		"rooms": plan.rooms.size()}


## A depth-first walk over the grid, carrying its own stack so a dead end steps back rather than
## restarting. `rooms` is the order they were first reached, so `rooms[-1]` is the far end of the walk.
func _walk(rng: RandomNumberGenerator, want: int) -> Dictionary:
	var start := Vector2i(rng.randi_range(0, GRID - 1), rng.randi_range(0, GRID - 1))
	var stack: Array[Vector2i] = [start]
	var seen := {start: true}
	var rooms: Array[Vector2i] = [start]
	var links: Array = []
	while not stack.is_empty() and rooms.size() < want:
		var at: Vector2i = stack[stack.size() - 1]
		var options: Array[Vector2i] = []
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = at + step
			if next.x < 0 or next.y < 0 or next.x >= GRID or next.y >= GRID or seen.has(next):
				continue
			options.append(next)
		if options.is_empty():
			stack.pop_back()
			continue
		var pick: Vector2i = options[rng.randi() % options.size()]
		seen[pick] = true
		rooms.append(pick)
		links.append([at, pick])
		stack.append(pick)
	return {"rooms": rooms, "links": links, "start": start, "end": rooms[rooms.size() - 1]}


## The rock everything is cut out of. One `fill`, which is the admin path - no events, no drops, no edit
## budget - and the right tool for a room made out of nothing.
func _slab(instance: String) -> void:
	var edge := OFFSET + ROOM + 2
	api.fill(Vector3i(-edge, FLOOR_Y - 1, -edge), Vector3i(edge, FLOOR_Y + HEIGHT + 2, edge),
		_ids.rock, instance)


func _room(instance: String, cell: Vector2i) -> void:
	var at := _centre(cell)
	api.fill(Vector3i(at.x - ROOM, FLOOR_Y + 1, at.z - ROOM),
		Vector3i(at.x + ROOM, FLOOR_Y + HEIGHT, at.z + ROOM), _ids.air, instance)


## A corridor between two neighbouring cells. Carved from centre to centre, so it always meets both
## rooms squarely however the walk arrived.
func _hall(instance: String, a: Vector2i, b: Vector2i) -> void:
	var from := _centre(a)
	var to := _centre(b)
	var low := Vector3i(mini(from.x, to.x), FLOOR_Y + 1, mini(from.z, to.z))
	var high := Vector3i(maxi(from.x, to.x), FLOOR_Y + 3, maxi(from.z, to.z))
	api.fill(Vector3i(low.x - HALL, low.y, low.z - HALL), Vector3i(high.x + HALL, high.y, high.z + HALL),
		_ids.air, instance)


## The 3x3 mark you stand on, sunk into the floor so it is a floor and not a step.
func _pad(instance: String, at: Vector3i, block: int) -> void:
	api.fill(Vector3i(at.x - PAD, FLOOR_Y, at.z - PAD), Vector3i(at.x + PAD, FLOOR_Y, at.z + PAD),
		block, instance)


## Lamps, nests and hoards. Everything that makes a floor worth walking into, and everything that scales
## with depth.
func _furnish(instance: String, plan: Dictionary, depth: int, rng: RandomNumberGenerator) -> void:
	# **Deeper is darker**, which is the cheapest difficulty knob there is and the one that changes how a
	# floor is played rather than how long it takes. It also feeds itself: nests only spawn on ground
	# below light level 11, so a floor with fewer lamps has more room for monsters - and a torch you
	# bring down and place is a real decision rather than decoration.
	var lamps := maxi(1, 3 - depth / 4)
	var band := mini(depth / BAND, NESTS.size() - 1)
	var kinds: Array = []
	for i in band + 1:
		kinds.append_array(NESTS[i])
	for index in (plan.rooms as Array).size():
		var cell: Vector2i = plan.rooms[index]
		var at := _centre(cell)
		for i in lamps:
			# In the ceiling, so it lights the room without being something to trip over, and so mining
			# it out is a deliberate act with a consequence.
			var spot := Vector3i(at.x + rng.randi_range(-ROOM + 1, ROOM - 1), FLOOR_Y + HEIGHT + 1,
				at.z + rng.randi_range(-ROOM + 1, ROOM - 1))
			api.set_block(spot, _ids.lamp, instance)
		# The first room is where you arrive and the last is the way down: neither gets a nest, so
		# nobody lands in a fight they did not walk into and nobody is ambushed at the exit.
		var edge: bool = index == 0 or index == (plan.rooms as Array).size() - 1
		if not edge and rng.randf() < _nest_chance(depth):
			_nest(instance, at, kinds, rng)
		if not edge and rng.randf() < 0.45:
			_hoard(instance, at, depth, rng)


## How likely a room is to hold a nest. Climbs with depth and stops short of every room, because a floor
## where every door has something behind it stops being a decision.
func _nest_chance(depth: int) -> float:
	return minf(0.35 + float(depth) * 0.04, 0.8)


func _nest(instance: String, at: Vector3i, kinds: Array, rng: RandomNumberGenerator) -> void:
	var spot := Vector3i(at.x + rng.randi_range(-2, 2), FLOOR_Y + 1, at.z + rng.randi_range(-2, 2))
	api.set_block(spot, _ids.nest, instance)
	# The list is handed over whole and the engine settles on one per spawner, which is what its
	# `structure_seed` is for - so two nests on one floor are not always the same creature.
	api.set_block_data(spot, {"spawner": {"entity": kinds.duplicate(), "count": [1, 2],
		"max_nearby": 4, "player_range": 14.0}, "structure_seed": rng.randi()}, instance)


## A chest with a table named on it rather than items in it. **It rolls the first time somebody opens
## it**, which is how a structure's chest has always worked here - and it means the loot is decided when
## it is found rather than when the floor was laid, so a floor built and abandoned costs nothing.
func _hoard(instance: String, at: Vector3i, depth: int, rng: RandomNumberGenerator) -> void:
	var spot := Vector3i(at.x + rng.randi_range(-3, 3), FLOOR_Y + 1, at.z + rng.randi_range(-3, 3))
	api.set_block(spot, _ids.hoard, instance)
	api.set_block_data(spot, {"loot": "firstlight:descent_%d" % mini(depth / BAND, NESTS.size() - 1)},
		instance)


static func _centre(cell: Vector2i) -> Vector3i:
	return Vector3i(cell.x * CELL - OFFSET, FLOOR_Y, cell.y * CELL - OFFSET)
