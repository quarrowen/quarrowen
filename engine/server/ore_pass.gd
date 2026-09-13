extends RefCounted
## Generation pass that scatters veins of one block inside another (e.g. ore in stone). Created with
## ModApi.add_ore_pass; usable from GDScript and JavaScript mods. Runs on worker threads.

var ore: int
var replace: int
var veins: int
var vein_size: int
var min_y: int
var max_y: int
var chance: float
var salt: String


func _init(def: Dictionary) -> void:
	ore = int(def.ore)
	replace = int(def.replace)
	veins = clampi(int(def.get("veins", 4)), 1, 64)
	vein_size = clampi(int(def.get("size", 6)), 1, 32)
	min_y = clampi(int(def.get("min_y", 4)), 1, 126)
	max_y = clampi(int(def.get("max_y", 60)), min_y, 126)
	chance = clampf(float(def.get("chance", 1.0)), 0.0, 1.0)
	salt = String(def.get("salt", str(ore)))


func decorate(chunk, world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, salt, chunk.coord.x, chunk.coord.y])
	var blocks: PackedByteArray = chunk.blocks
	for v in veins:
		if rng.randf() > chance:
			continue
		var x := rng.randi_range(0, 15)
		var y := rng.randi_range(min_y, max_y)
		var z := rng.randi_range(0, 15)
		for n in rng.randi_range(1, vein_size):
			if x >= 0 and x < 16 and z >= 0 and z < 16 and y > 0 and y < 127:
				var at := (x + (z << 4) + (y << 8)) << 1
				if blocks.decode_u16(at) == replace:
					blocks.encode_u16(at, ore)
			match rng.randi_range(0, 5):
				0: x += 1
				1: x -= 1
				2: y += 1
				3: y -= 1
				4: z += 1
				_: z -= 1
	chunk.blocks = blocks
