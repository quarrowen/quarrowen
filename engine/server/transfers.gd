extends RefCounted
## Moving players between servers that trust each other: portals, /server and /transfer, and the mod API.
##
## <data dir>/network.json lists the other servers:
##   {"servers": {"sky": {"name": "Sky Islands", "address": "192.168.1.20", "port": 24567,
##     "id": "<its server id, from /network id there>",
##     "send": true,        # players may go there from here
##     "receive": true,     # players arriving from there are accepted
##     "inventory": false,  # carry inventories both ways (both servers must say so to carry anything)
##     "admit": true,       # arrivals skip this server's allowlist
##     "hop": false}}}      # everyone may use /server sky (else only portals, admins and mods)
##
## Leaving: the source signs a ticket (engine/shared/transfer_ticket.gd) and tells the client where to go.
## Arriving: the client hands the ticket over right after hello; after the login the destination checks it
## and places the player at the ticket's arrival point (named with /network arrival <id>), with what it
## carries. Portal blocks are blocks with `portal: true`; their block data {portal: {server, arrival}}.

const TransferTicket = preload("res://engine/shared/transfer_ticket.gd")

const FILE := "network.json"
const PORTAL_SECONDS := 1.2  # standing in a portal this long starts the trip
const ARRIVAL_GRACE := 5.0  # portals do not send a player back straight after arriving
const MAX_CARRY_DATA := 16 * 1024
## Where a travelling inventory is kept on the source until the player shows up somewhere (player data).
const ESCROW_KEY := "_transfer_escrow"

var servers := {}  # name -> entry
var own_id := ""
var problem := ""

var _server
var _key: Dictionary = {}
var _path := ""
var _used_nonces := {}  # nonce -> expires
var _portal_time := {}  # peer -> seconds inside a portal
var _arrived_at := {}  # peer -> ticks msec


func _init(game_server) -> void:
	_server = game_server


func setup(data_dir: String, key: Dictionary) -> void:
	_key = key
	own_id = TransferTicket.key_id(key) if not key.is_empty() else ""
	_path = data_dir.path_join(FILE)
	reload()
	_server.dev_log.add("info", "server", "Server id %s (for other servers' network.json); %d servers in this one's" % [own_id, servers.size()])


func reload() -> String:
	servers.clear()
	problem = ""
	if _path.is_empty() or not FileAccess.file_exists(_path):
		return ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if not (parsed is Dictionary) or not (parsed.get("servers") is Dictionary):
		problem = "%s is not valid JSON with a \"servers\" object" % FILE
		_server.dev_log.add("error", "server", "Network: " + problem)
		return problem
	for key: String in parsed.servers:
		var e = parsed.servers[key]
		if not (e is Dictionary):
			continue
		var entry := {"key": key.to_lower(), "name": str(e.get("name", key)).left(64), "address": str(e.get("address", "")).strip_edges(),
			"port": clampi(int(e.get("port", 24565)), 1, 65535), "id": str(e.get("id", "")).strip_edges().to_lower(),
			"send": bool(e.get("send", true)), "receive": bool(e.get("receive", true)), "inventory": bool(e.get("inventory", false)),
			"admit": bool(e.get("admit", true)), "hop": bool(e.get("hop", false))}
		if entry.address in ["127.0.0.1", "localhost", "::1"]:
			# The address is handed to the player's client, which then connects to it itself: loopback
			# there means the player's own computer. Clients work around it, but say so plainly.
			_server.dev_log.add("warn", "server", "Network: server '%s' has address %s, which is the *player's* machine. Use the address players reach this box by." % [key, entry.address])
		if entry.id.length() != 32 or not entry.id.is_valid_hex_number():
			_server.dev_log.add("warn", "server", "Network: server '%s' needs its 32-character id (/network id on that server)" % key)
			continue
		servers[entry.key] = entry
	return ""


func find(name_or_key: String) -> Dictionary:
	var k := name_or_key.to_lower()
	if servers.has(k):
		return servers[k]
	for e: Dictionary in servers.values():
		if str(e.name).to_lower() == k:
			return e
	return {}


# --- Leaving --------------------------------------------------------------------------------------

## Sends a player to another server. options: {arrival, data (a small Dictionary for mods), reason}.
## Returns "" or why not.
func transfer(p, target: String, options := {}) -> String:
	var entry := find(target)
	if entry.is_empty():
		return "there is no server called '%s' in this server's network" % target
	if not entry.send:
		return "travel to %s is not allowed from here" % entry.name
	if entry.address.is_empty():
		return "%s has no address in network.json" % entry.name
	if p.get_meta("transferring", false):
		return "already travelling"
	var data = options.get("data", {})
	if not (data is Dictionary) or JSON.stringify(data).length() > MAX_CARRY_DATA:
		return "the travel data is too large"
	var ev: Dictionary = _server.emit("player_transfer", {"player": p, "server": entry.key, "arrival": str(options.get("arrival", "")),
		"data": data, "cancelled": false, "reason": ""})
	if ev.cancelled:
		return str(ev.reason) if not str(ev.reason).is_empty() else "the trip was cancelled"
	var carry := {"data": ev.data}
	if entry.inventory:
		carry.inventory = pack_inventory(p)
		carry.health = p.health
		carry.hunger = p.hunger
	var ticket := TransferTicket.make(_key, {"player_id": p.player_id, "player_name": p.name,
		"from": {"name": _server.server_info.name}, "to": {"name": entry.name, "address": entry.address, "port": entry.port, "id": entry.id},
		"arrival": str(ev.arrival).left(64), "carry": carry})
	p.set_meta("transferring", entry.name)
	if entry.inventory:
		# The inventory now travels. This server keeps a copy aside: if the trip never finishes and the player
		# comes back here directly, they get their things back (see restore_escrow). Between two servers that
		# both carry inventories, a player could use that to copy items; that is the price of never losing them.
		p.data[ESCROW_KEY] = {"inventory": carry.inventory, "to": entry.name, "at": int(Time.get_unix_time_from_system())}
		p.inventory.clear()
	_server._store_player(p)
	if p._online():
		Net.s_transfer.rpc_id(p.peer_id, entry.address, entry.port, entry.name, ticket.ticket, ticket.signature)
	_server.dev_log.add("info", "server", "%s is travelling to %s" % [p.name, entry.name])
	# A client that does not go gets disconnected anyway.
	var peer_id: int = p.peer_id
	_server.schedule(8.0, func():
		if _server.players.has(peer_id) and _server.players[peer_id] == p:
			_server.kick(peer_id, "Travelling to %s" % entry.name), 0.0)
	return ""


## Items by name (ids differ between servers): see ServerPlayer.save_items.
func pack_inventory(p) -> Dictionary:
	return p.save_items()


## Puts a carried inventory into the player's; returns the names of items this server does not have.
func unpack_inventory(p, packed) -> Array:
	return p.load_items(packed)


# --- Arriving -------------------------------------------------------------------------------------

## A player who joined without a transfer ticket but has a travelling inventory held here: give it back.
## Arriving with a ticket (from anywhere in the network) drops the held copy instead.
func settle_escrow(p, arrived_by_ticket: bool) -> void:
	var escrow = p.data.get(ESCROW_KEY)
	if escrow == null:
		return
	p.data.erase(ESCROW_KEY)
	if arrived_by_ticket or not (escrow is Dictionary):
		return
	var missing := unpack_inventory(p, escrow.get("inventory", {}))
	p.sync_inventory()
	p.send_message("Your trip to %s did not finish, so your things are back." % str(escrow.get("to", "another server")))
	if not missing.is_empty():
		p.send_message("Some could not be restored: %s" % ", ".join(missing.slice(0, 8)))


## A joining player's ticket, checked once they have proven their identity. Returns {entry, data} for an
## accepted ticket, or {error}.
func accept(ticket: String, signature: String, player_id: String) -> Dictionary:
	var trusted := {}
	for e: Dictionary in servers.values():
		if e.receive:
			trusted[e.id] = e
	var verified := TransferTicket.verify(ticket, signature, trusted)
	if not verified.ok:
		return {"error": verified.error}
	var now := int(Time.get_unix_time_from_system())
	var error := TransferTicket.check(verified.data, player_id, own_id, now)
	if not error.is_empty():
		return {"error": error}
	for nonce: String in _used_nonces.keys():
		if int(_used_nonces[nonce]) < now:
			_used_nonces.erase(nonce)
	var nonce := str(verified.data.get("nonce", ""))
	if nonce.is_empty() or _used_nonces.has(nonce):
		return {"error": "that transfer ticket was already used"}
	_used_nonces[nonce] = int(verified.data.get("expires", now))
	return {"entry": trusted[verified.source_id], "data": verified.data}


## Where an arriving player appears: the ticket's named arrival point, or Vector3.INF (their usual place).
func arrival_position(accepted: Dictionary) -> Vector3:
	var point = _server._meta.get("arrivals", {}).get(str(accepted.data.get("arrival", "")).to_lower()) if _server._meta.get("arrivals") is Dictionary else null
	return Vector3(float(point[0]), float(point[1]), float(point[2])) if point is Array and point.size() == 3 else Vector3.INF


## After an arriving player spawned: give what they carried and tell mods.
func arrive(p, accepted: Dictionary) -> void:
	var entry: Dictionary = accepted.entry
	var data: Dictionary = accepted.data
	var arrival := str(data.get("arrival", ""))
	var carry = data.get("carry", {})
	var missing := []
	if carry is Dictionary and entry.inventory and carry.has("inventory"):
		missing = unpack_inventory(p, carry.inventory)
		p.health = clampf(float(carry.get("health", p.health)), 1.0, p.max_health)
		p.hunger = clampf(float(carry.get("hunger", p.hunger)), 0.0, 20.0)
		p.sync_inventory()
		_server.sync_health(p)
	_arrived_at[p.peer_id] = Time.get_ticks_msec()
	p.send_message("Welcome from %s!" % str(data.from.get("name", entry.name)))
	if not missing.is_empty():
		p.send_message("Some things could not come with you (this server does not have them): %s" % ", ".join(missing.slice(0, 8)))
	_server.emit("player_arrived", {"player": p, "from": entry.key, "arrival": arrival,
		"data": carry.get("data", {}) if carry is Dictionary and carry.get("data") is Dictionary else {}})


func set_arrival(id: String, position: Vector3) -> void:
	if not (_server._meta.get("arrivals") is Dictionary):
		_server._meta.arrivals = {}
	_server._meta.arrivals[id.to_lower().left(64)] = [snappedf(position.x, 0.01), snappedf(position.y, 0.01), snappedf(position.z, 0.01)]


# --- Portals --------------------------------------------------------------------------------------

func update(delta: float) -> void:
	# Not `servers.is_empty()` any more: a portal to another *realm* needs no network.json at all, and
	# gating on one meant a single-machine server could never have one.
	if servers.is_empty() and _server.realms.size() < 2:
		return
	for p in _server.players.values():
		if p.dead or p.get_meta("transferring", false) or Time.get_ticks_msec() - int(_arrived_at.get(p.peer_id, -100000)) < ARRIVAL_GRACE * 1000:
			continue
		var portal := portal_at(p.state.position, _server.realm_of(p))
		if portal.is_empty():
			if _portal_time.has(p.peer_id):
				_portal_time.erase(p.peer_id)
			continue
		var t := float(_portal_time.get(p.peer_id, 0.0)) + delta
		_portal_time[p.peer_id] = t
		# Another world on this server, or another server. The wait and the message are the same either
		# way, because to whoever is standing in it they are the same thing.
		var to_realm := str(portal.get("realm", ""))
		var destination: String = str(_server.realms[to_realm].display_name) if _server.realms.has(to_realm) \
			else str(find(str(portal.get("server", ""))).get("name", portal.get("server", "?")))
		if t - delta <= 0.0:
			p.show_title("", "Travelling to %s…" % destination, PORTAL_SECONDS + 0.5)
		if t >= PORTAL_SECONDS:
			_portal_time.erase(p.peer_id)
			if not to_realm.is_empty():
				# Where they arrive: the portal may say, and a mod may rewrite it (player_realm_change).
				# Otherwise the same coordinates, which is the least surprising default for a hole in
				# the ground that leads downwards.
				var at = portal.get("at")
				var arrive: Vector3 = Vector3(at[0], at[1], at[2]) if at is Array and at.size() == 3 else p.state.position
				if not _server.send_to_realm(p, to_realm, arrive):
					p.show_title("", "That way is shut", 2.5)
				_arrived_at[p.peer_id] = Time.get_ticks_msec()
				continue
			var error := transfer(p, str(portal.get("server", "")), {"arrival": str(portal.get("arrival", ""))})
			if not error.is_empty():
				p.show_title("", error, 2.5)
				_arrived_at[p.peer_id] = Time.get_ticks_msec()  # do not retry every frame


## The portal settings of a portal block at the player's feet or body, or {}.
## The portal a player is standing in, or {}. Its block data says where it goes: `server` for another
## machine, or `realm` for another world on this one. Both are portals to a player, so both are read
## here rather than growing a second block with a second timer that feels slightly different.
func portal_at(position: Vector3, into = null) -> Dictionary:
	var registry = _server.registry
	var in_realm = into if into != null else _server.realm
	for dy in [0.1, 1.0]:
		var cell := Vector3i((position + Vector3(0, dy, 0)).floor())
		var block: int = in_realm.world.get_block_v(cell)
		if registry.is_valid(block) and bool(registry.defs[block].get("portal", false)):
			var settings = _server.get_block_data(cell, in_realm).get("portal", {})
			if not (settings is Dictionary):
				continue
			if not str(settings.get("server", "")).is_empty() or not str(settings.get("realm", "")).is_empty():
				return settings
	return {}


func player_left(peer_id: int) -> void:
	_portal_time.erase(peer_id)
	_arrived_at.erase(peer_id)
