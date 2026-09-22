extends Node
## Friends and parties through the hub (services/hub, social.rs). Signs in with the player's identity key
## (the hub's challenge, signed as "quarrowen-hub-login:<hub url>:<nonce>"), checks in every HEARTBEAT
## seconds with where the player is (`current_server`, shown to friends when "network/share_server" is
## on) and keeps the latest social state: {me, friends, incoming, outgoing, party, party_invites}.
## Lives in engine/main.gd for the whole session, so friends see you in the menu and in game.

signal state_changed(state: Dictionary)
## Something worth telling the player ("Alex wants to be your friend").
signal notice(text: String)
signal failed(error: String)

const ClientSettings = preload("res://engine/client/settings/client_settings.gd")
const HubClient = preload("res://engine/client/menu/hub_client.gd")
const Identity = preload("res://engine/shared/identity.gd")
const Protocol = preload("res://engine/shared/protocol.gd")
const NetAccess = preload("res://engine/shared/net_access.gd")

const HEARTBEAT := 20.0
const RETRY := 60.0

var player_name := "Player"
## {name, address, port, code} while playing on a server, else {}.
var current_server := {}
## For tests: sign in with this key instead of the player's identity.
var key: CryptoKey
var state := {}
var token := ""
var last_error := ""

var _timer := 0.0
var _busy := false
var _signing_in := false
var _hub := ""
var _queued: Array = []  # [path, body] asked for while signing in


static func available() -> bool:
	return HubClient.configured()


func signed_in() -> bool:
	return not token.is_empty() and _hub == HubClient.hub_url()


func _process(delta: float) -> void:
	if not available():
		return
	_timer += delta
	var wait := HEARTBEAT if last_error.is_empty() else RETRY
	if _timer >= wait and not _busy and not _signing_in:
		refresh()


## Checks in now (signing in first when needed).
func refresh() -> void:
	_timer = 0.0
	if not available():
		return
	if not signed_in():
		sign_in()
		return
	var body := {"server": current_server if not current_server.is_empty() else null,
		"share_server": ClientSettings.shared().get_value("network/share_server")}
	_call("/v1/presence", body)


func sign_in() -> void:
	if _signing_in or not available():
		return
	_signing_in = true
	_hub = HubClient.hub_url()
	token = ""
	var signing_key: CryptoKey = key if key != null else Identity.load_or_create()
	_post(_hub + "/v1/auth/challenge", {}, "", func(data, error):
		if not error.is_empty():
			_signing_in = false
			_fail(error)
			return
		var nonce := str(data.get("nonce", ""))
		var message := ("quarrowen-hub-login:%s:%s" % [_hub, nonce]).to_utf8_buffer()
		var login := {"key": Identity.public_pem(signing_key), "nonce": nonce, "hub": _hub, "name": player_name,
			"signature": Marshalls.raw_to_base64(Identity.sign(signing_key, message))}
		_post(_hub + "/v1/auth/login", login, "", func(result, login_error):
			_signing_in = false
			if not login_error.is_empty():
				_queued.clear()
				_fail(login_error)
				return
			token = str(result.get("token", ""))
			refresh()
			for q in _queued:
				_call(q[0], q[1])
			_queued.clear()))


func request_friend(code: String) -> void:
	_call("/v1/friends/request", {"code": code.strip_edges()})


func respond_friend(player_id: String, accept: bool) -> void:
	_call("/v1/friends/respond", {"id": player_id, "accept": accept})


func cancel_request(player_id: String) -> void:
	_call("/v1/friends/cancel", {"id": player_id})


func remove_friend(player_id: String) -> void:
	_call("/v1/friends/remove", {"id": player_id})


func invite_to_party(player_id: String) -> void:
	_call("/v1/party/invite", {"id": player_id})


func respond_party(party_id: String, accept: bool) -> void:
	_call("/v1/party/respond", {"party_id": party_id, "accept": accept})


func leave_party() -> void:
	_call("/v1/party/leave", {})


func kick(player_id: String) -> void:
	_call("/v1/party/kick", {"id": player_id})


func promote(player_id: String) -> void:
	_call("/v1/party/promote", {"id": player_id})


## The party leader's server, when someone else leads and shares it ({} otherwise).
func leader_server() -> Dictionary:
	var party = state.get("party")
	if not (party is Dictionary) or str(party.get("leader", "")) == str(state.get("me", {}).get("id", "")):
		return {}
	for m in party.get("members", []):
		if m.id == party.leader and m.get("server") is Dictionary:
			return m.server
	return {}


func _call(path: String, body: Dictionary) -> void:
	if not signed_in():
		if path != "/v1/presence":
			_queued.append([path, body])
		sign_in()
		return
	_busy = true
	_post(_hub + path, body, token, func(data, error):
		_busy = false
		if error == "not signed in":
			token = ""
			if path != "/v1/presence":
				_queued.append([path, body])
			sign_in()
			return
		if not error.is_empty():
			_fail(error)
			return
		last_error = ""
		if data.get("result", "") == "friends":
			notice.emit("You are now friends")
		elif data.get("result", "") == "requested":
			notice.emit("Friend request sent")
		_apply(data))


func _apply(data: Dictionary) -> void:
	var before := state
	state = _clean(data)
	if not before.is_empty():
		var had: Array = before.get("incoming", []).map(func(r): return r.id)
		for r in state.incoming:
			if not had.has(r.id):
				notice.emit("%s wants to be your friend" % r.name)
		var had_invites: Array = before.get("party_invites", []).map(func(i): return i.party_id)
		for i in state.party_invites:
			if not had_invites.has(i.party_id):
				notice.emit("%s invited you to their party" % i.leader_name)
		var friends_before := {}
		for f in before.get("friends", []):
			friends_before[f.id] = f
		for f in state.friends:
			if friends_before.has(f.id) and f.online and not friends_before[f.id].online:
				notice.emit("%s is online" % f.name)
	state_changed.emit(state)


## Keeps only the expected fields, with sane types and lengths.
static func _clean(data: Dictionary) -> Dictionary:
	var person := func(p) -> Dictionary:
		if not (p is Dictionary):
			return {}
		var server = p.get("server")
		return {"id": str(p.get("id", "")).left(64), "name": str(p.get("name", "")).left(16), "online": bool(p.get("online", false)),
			"in_my_party": bool(p.get("in_my_party", false)),
			"server": {"name": str(server.get("name", "")).left(64), "address": str(server.get("address", "")).left(253),
				"port": clampi(int(server.get("port", 0)), 0, 65535), "code": str(server.get("code", "")).left(16)} if server is Dictionary else null}
	var list := func(key_name: String) -> Array:
		return (data.get(key_name, []) as Array).slice(0, 500).map(person).filter(func(p): return not p.is_empty()) if data.get(key_name) is Array else []
	var me: Dictionary = data.get("me", {}) if data.get("me") is Dictionary else {}
	var party = null
	if data.get("party") is Dictionary:
		var p: Dictionary = data.party
		party = {"id": str(p.get("id", "")), "leader": str(p.get("leader", "")),
			"members": (p.get("members", []) as Array).slice(0, 16).map(person) if p.get("members") is Array else [],
			"invited": (p.get("invited", []) as Array).slice(0, 16).map(person) if p.get("invited") is Array else []}
	var invites := []
	for i in (data.get("party_invites", []) if data.get("party_invites") is Array else []).slice(0, 20):
		if i is Dictionary:
			invites.append({"party_id": str(i.get("party_id", "")), "leader": str(i.get("leader", "")), "leader_name": str(i.get("leader_name", "")).left(16),
				"members": int(i.get("members", 0))})
	return {"me": {"id": str(me.get("id", "")), "name": str(me.get("name", "")).left(16), "friend_code": str(me.get("friend_code", "")).left(16)},
		"friends": list.call("friends"), "incoming": list.call("incoming"), "outgoing": list.call("outgoing"), "party": party, "party_invites": invites}


func _fail(error: String) -> void:
	last_error = error
	failed.emit(error)


func _post(url: String, body: Dictionary, bearer: String, done: Callable) -> void:
	if not NetAccess.allowed(url):
		done.call({}, "cannot reach the hub")
		return
	var http := HTTPRequest.new()
	http.timeout = 10.0
	http.body_size_limit = 1024 * 1024
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "User-Agent: Quarrowen/%s" % Protocol.GAME_VERSION])
	if not bearer.is_empty():
		headers.append("Authorization: Bearer " + bearer)
	http.request_completed.connect(func(result: int, status: int, _h: PackedStringArray, response: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			done.call({}, "cannot reach the hub")
			return
		var json := JSON.new()
		var parsed = json.data if json.parse(response.get_string_from_utf8()) == OK else null
		if status != 200:
			done.call({}, str(parsed.get("error", "hub error %d" % status)) if parsed is Dictionary else "hub error %d" % status)
		elif not (parsed is Dictionary):
			done.call({}, "the hub sent an unexpected answer")
		else:
			done.call(parsed, ""))
	if http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free()
		done.call({}, "cannot reach the hub")
