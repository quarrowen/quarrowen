extends RefCounted
## Player creations on a server: what players bring (skins, accessories, models), where they are kept,
## who may wear them, and sending them to the clients that need to draw them.
##
## Flow:
##   1. A client wearing its own creations offers their manifests (c_ugc_offer). The server answers with
##      the ids it still needs (s_ugc_request); ones it has, blocked or not allowed get a status.
##   2. The client uploads each payload in pieces (c_ugc_upload). The server checks the per-player limits,
##      validates the content (engine/shared/creations.gd) and stores it in <world>/ugc/.
##   3. With policy.accept "auto" (or "trusted" for admins and trusted players) a creation is approved at
##      once; "approval" keeps it pending until an admin approves it (see moderation); "off" refuses uploads.
##   4. Approved creations become cosmetics on this server. The author may always wear theirs; others
##      may wear them from the server library when policy.library is on (or when a mod grants them).
##   5. Clients that see a creation they do not have ask for it (c_ugc_fetch) and get the manifest and
##      payload (s_ugc_defs, s_ugc_piece), which they validate and cache.
## Moderation: players report creations they see (report); enough reports (policy.report_hide) hide a
## creation until an admin looks at it. Admins approve, reject (hidden, the author may fix and re-upload),
## remove (blocked for good), trust creators (their uploads skip the queue under "trusted") and ban them
## from uploading (their creations are hidden too). In game: /ugc and the Creations review panel; on
## the web: the dashboard's Creations tab; for mods: api.ugc_*.
## Events: ugc_uploaded {player, creation, cancelled, reason} (cancel to refuse), ugc_status {id, status,
## reason, by}, ugc_reported {player, id, reason, reports, cancelled}.

const Creations = preload("res://engine/shared/creations.gd")
const Cosmetics = preload("res://engine/shared/cosmetics.gd")

const PIECE_SIZE := 32 * 1024
const SEND_BYTES_PER_TICK := 256 * 1024
## **A ceiling across everybody, not only per peer.** Each peer was allowed a quarter of a megabyte a
## tick - about 15 MB/s - with nothing above it, so sixteen players asking for creations at once was
## 240 MB/s of upstream. On a home line that is the game unplayable for everyone; on a metered box it
## is a bill. The per-peer budget is what keeps one person from starving the others; this is what
## keeps the server from starving itself. (2026-09-25)
const SEND_BYTES_PER_TICK_ALL := 1024 * 1024
const UPLOAD_BYTES_PER_SECOND := 512 * 1024
const MAX_PENDING_UPLOADS := 4
const STATUSES := ["pending", "approved", "rejected", "removed"]

const DEFAULT_POLICY := {
	"enabled": true,
	"accept": "auto",  # auto | trusted | approval | off
	"kinds": ["skin", "accessory", "model"],
	"library": true,  # players may wear other players' approved creations
	"max_per_player": 32,  # stored creations per author
	"max_bytes_per_player": 4 * 1024 * 1024,
	"report_hide": 3,  # reports from different players that hide an approved creation until reviewed (0 = never)
}
const REPORT_REASONS := ["inappropriate", "offensive", "copied", "spam", "other"]

var policy := DEFAULT_POLICY.duplicate(true)
## id -> {manifest, status, reason, uploaded_by (player id), uploaded_at, size}
var store := {}
## Content ids refused for good (removed creations), id -> reason.
var blocked := {}
## Player ids that may not upload, player id -> reason.
var banned_creators := {}
## Player ids whose uploads are approved at once under "trusted".
var trusted := {}

## Goes up whenever creations, reports, trust or bans change (the dashboard reloads its list).
var revision := 0
var _server
var _dir := ""
var _uploads := {}  # peer id -> {id -> {manifest, bytes: PackedByteArray, total}}
var _upload_budget := {}  # peer id -> bytes left this second
var _budget_time := 0.0
var _send := {}  # peer id -> [[id, offset]]
var _payloads := {}  # id -> PackedByteArray (a small cache)


func _init(game_server) -> void:
	_server = game_server


# --- Storage ----------------------------------------------------------------------------------------

func load_store(save_dir: String) -> void:
	_dir = save_dir.path_join("ugc")
	DirAccess.make_dir_recursive_absolute(_dir)
	var index = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join("index.json"))) if FileAccess.file_exists(_dir.path_join("index.json")) else null
	if index is Dictionary:
		for id in (index.get("store") if index.get("store") is Dictionary else {}):
			var entry = index.store[id]
			if entry is Dictionary and Creations.is_id(str(id)) and entry.get("manifest") is Dictionary:
				store[str(id)] = entry
		blocked = index.get("blocked") if index.get("blocked") is Dictionary else {}
		banned_creators = index.get("banned_creators") if index.get("banned_creators") is Dictionary else {}
		trusted = index.get("trusted") if index.get("trusted") is Dictionary else {}
		if index.get("policy") is Dictionary:
			set_policy(index.policy)


func save_index() -> void:
	revision += 1
	if _dir.is_empty():
		return
	var f := FileAccess.open(_dir.path_join("index.json"), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"version": 1, "store": store, "blocked": blocked, "banned_creators": banned_creators, "trusted": trusted, "policy": policy}))
	f.close()


func _payload_path(id: String) -> String:
	var entry: Dictionary = store.get(id, {})
	return _dir.path_join(id.replace(":", "_") + "." + Creations.payload_extension(str(entry.get("manifest", {}).get("kind", ""))))


func payload(id: String) -> PackedByteArray:
	if _payloads.has(id):
		return _payloads[id]
	if not store.has(id) or not FileAccess.file_exists(_payload_path(id)):
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(_payload_path(id))
	if _payloads.size() > 64:
		_payloads.clear()
	_payloads[id] = bytes
	return bytes


func set_policy(values: Dictionary) -> void:
	for key in values:
		if not DEFAULT_POLICY.has(key):
			continue
		match key:
			"accept":
				policy.accept = values.accept if values.accept in ["auto", "trusted", "approval", "off"] else "approval"
			"kinds":
				policy.kinds = (values.kinds as Array).filter(func(k): return k in Creations.KINDS) if values.kinds is Array else policy.kinds
			"max_per_player", "max_bytes_per_player", "report_hide":
				policy[key] = maxi(0, int(values[key]))
			_:
				policy[key] = bool(values[key])
	save_index()


# --- Wearing ----------------------------------------------------------------------------------------

func is_approved(id: String) -> bool:
	return store.get(id, {}).get("status", "") == "approved"


## Whether a player may wear a creation here.
func can_wear(p, id: String) -> bool:
	if not policy.enabled or not is_approved(id) or blocked.has(id):
		return false
	var entry: Dictionary = store[id]
	return entry.manifest.author == p.player_id or policy.library or p.owned_cosmetics.has(id)


## Registers approved creations as cosmetics so avatars can use them.
func ensure_registered(ids: Array) -> void:
	for id in ids:
		id = str(id)
		if Creations.is_id(id) and is_approved(id) and _server.cosmetics.get_def(id).is_empty():
			_server.cosmetics.register(Creations.to_cosmetic(store[id].manifest, payload(id)))


## Creation ids worn in an avatar dictionary.
static func worn_ids(avatar) -> Array:
	var out := []
	if avatar is Dictionary and avatar.get("wear") is Dictionary:
		for cat_name in avatar.wear:
			var entry = avatar.wear[cat_name]
			if entry is Dictionary and Creations.is_id(str(entry.get("id", ""))):
				out.append(str(entry.id))
	return out


# --- Uploads ----------------------------------------------------------------------------------------

## A client offers creations it wears. Returns {request: [ids], status: {id: [status, reason]}}.
func offer(p, manifests: Array) -> Dictionary:
	var request := []
	var statuses := {}
	for m in manifests.slice(0, 16):
		if not (m is Dictionary) or not Creations.is_id(str(m.get("id", ""))):
			continue
		var id := str(m.id)
		var refusal := _refusal(p, m)
		if not refusal.is_empty():
			statuses[id] = ["refused", refusal]
		elif store.has(id):
			statuses[id] = [store[id].status, str(store[id].get("reason", ""))]
		else:
			var pending: Dictionary = _uploads.get(p.peer_id, {})
			if pending.size() < MAX_PENDING_UPLOADS:
				pending[id] = {"manifest": m, "bytes": PackedByteArray(), "total": 0}
				_uploads[p.peer_id] = pending
				request.append(id)
	if p._online():
		if not request.is_empty():
			Net.s_ugc_request.rpc_id(p.peer_id, PackedStringArray(request))
		for id in statuses:
			Net.s_ugc_status.rpc_id(p.peer_id, id, statuses[id][0], statuses[id][1])
	return {"request": request, "status": statuses}


func _refusal(p, m: Dictionary) -> String:
	var id := str(m.id)
	if not policy.enabled or policy.accept == "off":
		return "this server does not accept player creations"
	if blocked.has(id):
		return "this creation was removed from this server"
	if store.has(id):
		return ""
	if banned_creators.has(p.player_id):
		return "you may not upload creations here"
	# **A creation's name is text other children read**, shown under their avatar and in the library,
	# and it went past the chat filter that every other player-written string goes through. A server
	# that filters chat and refuses a rude player name was still letting one through on a hat.
	# (2026-09-25)
	if _server.gameplay.chat_filter and not _server.chat_filter.is_clean(str(m.get("name", ""))):
		return "please give it a different name"
	if str(m.get("author", "")) != p.player_id:
		# Says what it compared. "Only the author" with nothing else is impossible to act on when you are
		# the author: an empty field and a mismatched one read exactly the same. (playtest, 2026-09-18)
		var claimed := str(m.get("author", ""))
		_server.dev_log.add("warn", "server", "%s offered creation %s made by '%s', but they are '%s'"
			% [p.name, id, claimed if not claimed.is_empty() else "(nobody)", p.player_id])
		if claimed.is_empty():
			return "this creation has no author recorded, so it cannot be brought to a server"
		return "only the author can bring a creation to a server"
	if not str(m.get("kind", "")) in policy.kinds:
		return "this server does not accept %ss" % m.get("kind", "creation")
	var count := 0
	var bytes := 0
	for entry in store.values():
		if entry.uploaded_by == p.player_id and entry.status != "removed":
			count += 1
			bytes += int(entry.size)
	if count >= int(policy.max_per_player):
		return "you have reached this server's limit of %d creations" % policy.max_per_player
	if bytes >= int(policy.max_bytes_per_player):
		return "you have used this server's space for creations"
	return ""


## A piece of an upload. Completes (validates and stores) when the last piece arrives.
func upload_piece(p, id: String, offset: int, total: int, bytes: PackedByteArray) -> void:
	var pending: Dictionary = _uploads.get(p.peer_id, {})
	var upload: Dictionary = pending.get(id, {})
	if upload.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _budget_time >= 1.0:
		_budget_time = now
		_upload_budget.clear()
	var left := int(_upload_budget.get(p.peer_id, UPLOAD_BYTES_PER_SECOND)) - bytes.size()
	_upload_budget[p.peer_id] = left
	if left < 0 or total > Creations.MAX_MODEL_BYTES or bytes.size() > PIECE_SIZE or offset != upload.bytes.size() or (upload.total != 0 and total != upload.total):
		pending.erase(id)
		_status(p, id, "refused", "the upload was too fast or out of order")
		return
	upload.total = total
	upload.bytes.append_array(bytes)
	if upload.bytes.size() < total:
		return
	pending.erase(id)
	_complete(p, upload.manifest, upload.bytes)


func _complete(p, manifest: Dictionary, bytes: PackedByteArray) -> void:
	var id := str(manifest.id)
	var refusal := _refusal(p, manifest)
	var checked := Creations.validate(manifest, bytes)
	if refusal.is_empty() and not checked.ok:
		refusal = checked.error
	if refusal.is_empty() and store.has(id):
		return
	if not refusal.is_empty():
		_status(p, id, "refused", refusal)
		return
	var clean: Dictionary = checked.manifest
	clean.author_name = p.name  # the uploader is the author (checked above)
	var ev: Dictionary = _server.emit("ugc_uploaded", {"player": p, "creation": clean.duplicate(), "cancelled": false, "reason": ""})
	if ev.cancelled:
		_status(p, id, "refused", str(ev.get("reason", "")) if not str(ev.get("reason", "")).is_empty() else "refused by the server")
		return
	var status := "approved" if policy.accept == "auto" or (policy.accept == "trusted" and (trusted.has(p.player_id) or _server.is_admin(p))) else "pending"
	store[id] = {"manifest": clean, "status": status, "reason": "", "uploaded_by": p.player_id, "uploaded_at": int(Time.get_unix_time_from_system()), "size": bytes.size()}
	var f := FileAccess.open(_payload_path(id), FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()
	save_index()
	_server.dev_log.add("info", "server", "%s uploaded %s \"%s\" (%s, %d KB)" % [p.name, clean.kind, clean.name, status, bytes.size() / 1024])
	_status(p, id, status, "")
	if status == "approved":
		_after_approval(id)


func _status(p, id: String, status: String, reason: String) -> void:
	if p._online():
		Net.s_ugc_status.rpc_id(p.peer_id, id, status, reason)
	_server.emit("ugc_status", {"id": id, "status": status, "reason": reason})


## Players waiting to wear this creation get it now.
func _after_approval(id: String) -> void:
	ensure_registered([id])
	for p in _server.players.values():
		if worn_ids(p.requested_avatar).has(id):
			_server.reapply_requested_avatar(p)


## Changes a creation's status (moderation). "removed" also blocks the content for good.
func set_status(id: String, status: String, reason := "", by := "") -> bool:
	if not store.has(id) or not status in STATUSES:
		return false
	store[id].status = status
	store[id].reason = reason
	store[id].reviewed_by = by
	if status == "approved":
		store[id].reports = []  # reviewed: old reports are settled
	if status == "removed":
		blocked[id] = reason
		DirAccess.remove_absolute(_payload_path(id))
		_payloads.erase(id)
	if status != "approved":
		_server.cosmetics.defs.erase(id)
		for p in _server.players.values():
			if worn_ids(p.avatar).has(id):
				_server.reapply_requested_avatar(p)
	save_index()
	var author = _server.players.values().filter(func(p): return p.player_id == store[id].uploaded_by)
	for p in author:
		if p._online():
			Net.s_ugc_status.rpc_id(p.peer_id, id, status, reason)
	_server.emit("ugc_status", {"id": id, "status": status, "reason": reason, "by": by})
	if status == "approved":
		_after_approval(id)
	return true


# --- Serving ----------------------------------------------------------------------------------------

## A client asks for creations it needs to draw (or browse).
func fetch(p, ids: PackedStringArray) -> void:
	var defs := []
	var queue: Array = _send.get(p.peer_id, [])
	var moderator: bool = _server.has_permission(p, "ugc.review")
	for id in ids.slice(0, 32):
		# Moderators may look at creations waiting for review.
		if not store.has(id) or blocked.has(id) or not (is_approved(id) or (moderator and store[id].status != "removed")):
			continue
		defs.append(store[id].manifest)
		if not queue.any(func(q): return q[0] == id):
			queue.append([id, 0])
	_send[p.peer_id] = queue
	if not defs.is_empty() and p._online():
		Net.s_ugc_defs.rpc_id(p.peer_id, defs)


func update(_delta: float) -> void:
	# Shared out in the order peers happen to be in, which is fair enough for something that only
	# matters when many people arrive together: everybody gets served, the worst case is that the
	# last one waits a tick longer.
	var shared := SEND_BYTES_PER_TICK_ALL
	for peer_id in _send.keys():
		if shared <= 0:
			break
		var p = _server.players.get(peer_id)
		var queue: Array = _send[peer_id]
		if p == null or queue.is_empty():
			_send.erase(peer_id)
			continue
		var budget := mini(SEND_BYTES_PER_TICK, shared)
		while budget > 0 and not queue.is_empty():
			var item: Array = queue[0]
			var bytes := payload(item[0])
			if bytes.is_empty():
				queue.pop_front()
				continue
			var piece := bytes.slice(item[1], item[1] + PIECE_SIZE)
			Net.s_ugc_piece.rpc_id(peer_id, item[0], item[1], bytes.size(), piece)
			item[1] += piece.size()
			budget -= piece.size()
			shared -= piece.size()
			if item[1] >= bytes.size():
				queue.pop_front()
	for peer_id in _uploads.keys():
		if not _server.players.has(peer_id):
			_uploads.erase(peer_id)


## Approved creations others may wear, newest first: [{manifest..., uses}] filtered by kind/category/text.
func library(query := {}, offset := 0, count := 48) -> Dictionary:
	var text := str(query.get("text", "")).to_lower()
	var list := store.values().filter(func(e): return e.status == "approved" and not blocked.has(e.manifest.id) \
		and (str(query.get("category", "")).is_empty() or e.manifest.category == query.category) \
		and (text.is_empty() or e.manifest.name.to_lower().contains(text) or str(e.manifest.author_name).to_lower().contains(text)))
	list.sort_custom(func(a, b): return int(a.uploaded_at) > int(b.uploaded_at))
	return {"total": list.size(), "items": list.slice(offset, offset + count).map(func(e): return e.manifest)}


# --- Moderation -------------------------------------------------------------------------------------

## A player reports a creation. Returns "" or why it was not accepted.
func report(p, id: String, reason: String, details := "") -> String:
	if not store.has(id):
		return "that creation is not on this server"
	var entry: Dictionary = store[id]
	var reports: Array = entry.get("reports", [])
	if reports.any(func(r): return r.by == p.player_id):
		return "you already reported it"
	if entry.manifest.author == p.player_id:
		return "that is your own creation"
	reason = reason if reason in REPORT_REASONS else "other"
	var ev: Dictionary = _server.emit("ugc_reported", {"player": p, "id": id, "reason": reason, "details": details.left(200),
		"reports": reports.size() + 1, "cancelled": false})
	if ev.cancelled:
		return ""
	reports.append({"by": p.player_id, "name": p.name, "reason": reason, "details": details.left(200), "at": int(Time.get_unix_time_from_system())})
	entry.reports = reports
	_server.dev_log.add("warn", "server", "%s reported %s \"%s\" (%s): %d report%s" % [p.name, entry.manifest.kind, entry.manifest.name, reason,
		reports.size(), "" if reports.size() == 1 else "s"])
	if int(policy.report_hide) > 0 and reports.size() >= int(policy.report_hide) and entry.status == "approved":
		set_status(id, "pending", "hidden after %d reports, waiting for review" % reports.size(), "reports")
	else:
		save_index()
	_server.tell_moderators("A creation was reported: \"%s\" by %s (%s). /ugc list reported" % [entry.manifest.name, entry.manifest.author_name, reason])
	return ""


func clear_reports(id: String) -> void:
	if store.has(id):
		store[id].reports = []
		save_index()


## Creations for review: filter pending | reported | approved | rejected | removed | all, newest first.
func review_list(filter := "pending", text := "") -> Array:
	var needle := text.to_lower()
	var out := []
	for id in store:
		var e: Dictionary = store[id]
		var reports: int = e.get("reports", []).size()
		var keep: bool = filter == "all" or e.status == filter or (filter == "reported" and reports > 0 and e.status != "removed")
		if not keep or (not needle.is_empty() and not (e.manifest.name.to_lower().contains(needle) or str(e.manifest.author_name).to_lower().contains(needle))):
			continue
		var item := e.duplicate(true)
		item.id = id
		item.author_trusted = trusted.has(e.uploaded_by)
		item.author_banned = banned_creators.has(e.uploaded_by)
		out.append(item)
	out.sort_custom(func(a, b): return a.get("reports", []).size() > b.get("reports", []).size() if filter == "reported" else int(a.uploaded_at) > int(b.uploaded_at))
	return out


## Finds a creation by id or a unique start of it ("3f2a", "ugc:3f2a"). "" when none or ambiguous.
func resolve_id(text: String) -> String:
	var needle := text if text.begins_with(Creations.PREFIX) else Creations.PREFIX + text
	if store.has(needle):
		return needle
	var matches := store.keys().filter(func(k): return k.begins_with(needle))
	return matches[0] if matches.size() == 1 else ""


func set_trusted(player_id: String, on: bool) -> void:
	if on:
		trusted[player_id] = true
	else:
		trusted.erase(player_id)
	save_index()


## Bans (or unbans) a creator from uploading. Banning also hides their creations (rejected); unbanning
## leaves them hidden until approved again.
func set_banned(player_id: String, on: bool, reason := "", by := "") -> void:
	if on:
		banned_creators[player_id] = reason
		for id in store.keys():
			if store[id].uploaded_by == player_id and store[id].status in ["approved", "pending"]:
				set_status(id, "rejected", "creator banned%s" % (": " + reason if not reason.is_empty() else ""), by)
	else:
		banned_creators.erase(player_id)
	save_index()


func player_left(peer_id: int) -> void:
	_uploads.erase(peer_id)
	_send.erase(peer_id)
	_upload_budget.erase(peer_id)
