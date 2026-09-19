extends RefCounted
## Finds power networks: connected groups of cables and machines. Networks are cached and rebuilt
## lazily after invalidate(); scans never load chunks.
##
## Two ways of being joined, and a network may use both. **Touching** - a cable laid against a machine -
## is the cheap early one anybody can do. **Strung** - a cable spooled between two poles across a
## valley - uses the engine's links, and is how a base stops being a paved trench. A network walks
## through either without caring which. (2026-09-19)

const SKY_CHECK_INTERVAL := 40  # rebuilds between re-checking solar sky access

var api
var ids: Dictionary
var _networks: Array = []
var _by_position := {}  # Vector3i -> network index
var _dirty := true
var _sky_cache := {}  # Vector3i -> bool

const DIRECTIONS := [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]


func _init(mod_api, block_ids: Dictionary) -> void:
	api = mod_api
	ids = block_ids


func is_network_block(block: int) -> bool:
	# A pole carries power like a cable does - it is what a strung cable is fixed to, and a pole that
	# did not conduct would make the whole thing decorative.
	return block in [ids.cable, ids.pole, ids.generator, ids.solar, ids.battery, ids.lamp, ids.lamp_on, ids.miner]


func invalidate() -> void:
	_dirty = true


func networks() -> Array:
	if _dirty:
		_rebuild()
	return _networks


func network_at(pos: Vector3i) -> Dictionary:
	networks()
	var index: int = _by_position.get(pos, -1)
	return _networks[index] if index >= 0 else {}


func stored(network: Dictionary) -> float:
	var total := 0.0
	for pos: Vector3i in network.get("batteries", []):
		total += float(api.get_block_data(pos).get("energy", 0.0))
	return total


func sees_sky(pos: Vector3i) -> bool:
	if not _sky_cache.has(pos):
		_sky_cache[pos] = api.sees_sky(pos)
	return _sky_cache[pos]


func _rebuild() -> void:
	_dirty = false
	_sky_cache.clear()
	var previous_output := {}
	for network in _networks:
		for pos in network.machines:
			previous_output[pos] = network.last_produced
	_networks.clear()
	_by_position.clear()
	# Machines carry block data, so they are the seeds; cables are discovered by walking from them.
	for seed: Vector3i in api.find_block_data():
		if _by_position.has(seed) or not is_network_block(api.get_loaded_block(seed)):
			continue
		var network := {"generators": [], "solars": [], "batteries": [], "lamps": [], "miners": [],
			"machines": [], "cable_count": 0, "machine_count": 0, "last_produced": previous_output.get(seed, 0.0)}
		var index := _networks.size()
		var queue: Array[Vector3i] = [seed]
		_by_position[seed] = index
		while not queue.is_empty():
			var pos: Vector3i = queue.pop_back()
			var block: int = api.get_loaded_block(pos)
			_classify(network, pos, block)
			for dir in DIRECTIONS:
				var next: Vector3i = pos + dir
				if _by_position.has(next):
					continue
				if is_network_block(api.get_loaded_block(next)):
					_by_position[next] = index
					queue.append(next)
			# And anything strung to this block from somewhere else entirely.
			for id in api.links_at(pos):
				var info: Dictionary = api.link_info(id)
				if info.is_empty():
					continue
				var far: Vector3i = info.b.position if info.a.position == pos else info.a.position
				if _by_position.has(far) or not is_network_block(api.get_loaded_block(far)):
					continue
				_by_position[far] = index
				queue.append(far)
		_networks.append(network)


func _classify(network: Dictionary, pos: Vector3i, block: int) -> void:
	match block:
		ids.cable, ids.pole:
			network.cable_count += 1
			return
		ids.generator: network.generators.append(pos)
		ids.solar: network.solars.append(pos)
		ids.battery: network.batteries.append(pos)
		ids.lamp, ids.lamp_on: network.lamps.append(pos)
		ids.miner: network.miners.append(pos)
	network.machines.append(pos)
	network.machine_count += 1
