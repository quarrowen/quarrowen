extends RefCounted
## The room the lava rises in: a square pit with pillars at different heights to climb between.
##
## **Built in code rather than saved as a structure**, because it is a shape with a *rule* - the
## pillars have to be reachable from one another as the lava comes up, and that is arithmetic rather
## than decoration. A saved room would also be the same room every time, and this one is laid out from
## the instance's seed so a second round is not a memory test.

const HALF := 11
const FLOOR_Y := 60
## The lava stops here, and so does the round. Twenty-two blocks of climbing, which at one block every
## eight seconds is about three minutes of game before the timer would have ended it anyway.
const ROOF_Y := 82

var api
var _ids: Dictionary


func setup(mod_api, ids: Dictionary) -> void:
	api = mod_api
	_ids = ids


## Walls, a floor, and something to stand on.
func build(instance: String) -> void:
	# Walls first, so a child who runs at the edge meets one rather than the void. Two blocks above the
	# roof, because the last thing anybody does in this game is stand on the very top.
	for y in range(FLOOR_Y, ROOF_Y + 3):
		api.fill(Vector3i(-HALF, y, -HALF), Vector3i(HALF, y, -HALF), _ids.platform, instance)
		api.fill(Vector3i(-HALF, y, HALF), Vector3i(HALF, y, HALF), _ids.platform, instance)
		api.fill(Vector3i(-HALF, y, -HALF), Vector3i(-HALF, y, HALF), _ids.platform, instance)
		api.fill(Vector3i(HALF, y, -HALF), Vector3i(HALF, y, HALF), _ids.platform, instance)
	api.fill(Vector3i(-HALF, FLOOR_Y, -HALF), Vector3i(HALF, FLOOR_Y, HALF), _ids.platform, instance)
	_pillars(instance)


## Pillars to climb, at heights that always leave somewhere to go.
##
## **Laid out from the instance's own seed**, so the same door gives a different room each time - which
## is most of why anybody plays a short game twice. The engine hands each instance a seed for exactly
## this.
func _pillars(instance: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(instance)
	# A ring of them rather than a scatter: a scatter leaves gaps a child cannot cross and clumps that
	# make the game trivial, and a ring is always walkable round.
	for i in 12:
		var angle := TAU * float(i) / 12.0
		var at := Vector3i(roundi(cos(angle) * (HALF - 3)), FLOOR_Y, roundi(sin(angle) * (HALF - 3)))
		# Staggered heights: every other one is taller, so there is always a step up somewhere near.
		var top := FLOOR_Y + 3 + (i % 3) * 4 + rng.randi_range(0, 3)
		api.fill(at, Vector3i(at.x, mini(top, ROOF_Y - 2), at.z), _ids.platform, instance)
		# A cap one wider, so standing on a pillar is standing on something rather than balancing.
		var cap := mini(top, ROOF_Y - 2)
		api.fill(Vector3i(at.x - 1, cap, at.z - 1), Vector3i(at.x + 1, cap, at.z + 1), _ids.platform, instance)
	# And a low island in the middle to start on, so nobody spawns in mid-air.
	api.fill(Vector3i(-2, FLOOR_Y + 1, -2), Vector3i(2, FLOOR_Y + 1, 2), _ids.platform, instance)


## Brings the lava up to a level, as one layer. **A layer at a time rather than a flowing source**:
## liquid spreading from a corner would take longer to cross the room than the round lasts, and a child
## watching a puddle creep is a child who has stopped playing.
func flood(instance: String, level: int) -> void:
	api.fill(Vector3i(-HALF + 1, level, -HALF + 1), Vector3i(HALF - 1, level, HALF - 1), _ids.lava, instance)
