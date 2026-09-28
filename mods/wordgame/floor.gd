extends RefCounted
## The four coloured squares, and the room they sit in.
##
## **Colour is the label**, because the world has no text in it. `base`'s sixteen hues were named to be
## sayable by a child, so "stand on crimson" is an instruction rather than a puzzle - and four that
## nobody would confuse across a room, which rules out the greys and the near neighbours.

## Four: enough to be a real choice, few enough that reading them all fits in one line of a title and a
## child can see every square from the middle without turning round.
const PADS := 4
const FLOOR_Y := 64
## Half-width of a square, and how far out from the middle they sit.
const PAD := 3
const REACH := 7

## The four, deliberately far apart in hue: a red, a yellow, a blue and a green read as four different
## things at a glance and under any light.
const HUES := ["crimson", "straw", "sky", "forest"]

var api
var _ids := {}


func setup(mod_api) -> void:
	api = mod_api
	for hue in HUES:
		_ids[hue] = api.require_block("base:cloth_%s" % hue)
	_ids.edge = api.require_block("base:stone")


static func colour_name(pad: int) -> String:
	return String(HUES[pad % HUES.size()]).capitalize()


## The room: a wall round a hole, with the squares standing over it. **Nothing under them**, which is
## the whole game - a square that is taken away leaves the drop it was covering.
func build(instance: String) -> void:
	for y in range(FLOOR_Y - 1, FLOOR_Y + 8):
		api.fill(Vector3i(-REACH - 4, y, -REACH - 4), Vector3i(REACH + 4, y, -REACH - 4), _ids.edge, instance)
		api.fill(Vector3i(-REACH - 4, y, REACH + 4), Vector3i(REACH + 4, y, REACH + 4), _ids.edge, instance)
		api.fill(Vector3i(-REACH - 4, y, -REACH - 4), Vector3i(-REACH - 4, y, REACH + 4), _ids.edge, instance)
		api.fill(Vector3i(REACH + 4, y, -REACH - 4), Vector3i(REACH + 4, y, REACH + 4), _ids.edge, instance)
	# A ledge to start on in the middle, so nobody begins the round already standing on an answer.
	api.fill(Vector3i(-1, FLOOR_Y, -1), Vector3i(1, FLOOR_Y, 1), _ids.edge, instance)
	reset(instance)


## Puts all four squares back for the next question.
func reset(instance: String) -> void:
	for pad in PADS:
		var at := _centre(pad)
		api.fill(Vector3i(at.x - PAD, FLOOR_Y, at.z - PAD), Vector3i(at.x + PAD, FLOOR_Y, at.z + PAD),
			_ids[HUES[pad]], instance)


## Takes one away, and whoever is standing on it goes with it.
func clear_pad(instance: String, pad: int) -> void:
	var at := _centre(pad)
	api.fill(Vector3i(at.x - PAD, FLOOR_Y, at.z - PAD), Vector3i(at.x + PAD, FLOOR_Y, at.z + PAD), 0, instance)


## Which square a position is over, or -1. **Asked of the geometry rather than of a region**, because
## the question here is "where are they *at this instant*", and a region answers "when did they cross a
## line" - the right tool for a doorway and the wrong one for a snapshot.
static func pad_under(position: Vector3) -> int:
	for pad in PADS:
		var at := _centre(pad)
		if absf(position.x - float(at.x)) <= float(PAD) + 0.5 and absf(position.z - float(at.z)) <= float(PAD) + 0.5:
			return pad
	return -1


static func _centre(pad: int) -> Vector3i:
	var angle := TAU * float(pad) / float(PADS)
	return Vector3i(roundi(cos(angle) * REACH), FLOOR_Y, roundi(sin(angle) * REACH))
