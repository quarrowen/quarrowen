extends RefCounted
## Server-side cheat checks. The server already decides movement (clients only send inputs), reach, break
## times and rates; these checks notice clients that keep pushing past those limits and act on it.
##
## Each check keeps a score per player that rises with every suspicious event and decays over time, so lag
## spikes and the odd early click fade away while sustained cheating builds up. Past WARN the moderators are told
## (once per rise); past KICK the player is kicked, unless the mode is "log", they have "anticheat.bypass"
## (admins do) or a mod cancels the cheat_detected event.
##
## Checks: timer (inputs faster than the game runs), reach (edits or attacks well out of reach), fast_break
## (blocks broken sooner than possible), attack_rate (hits faster than the weapon allows), bad_packet
## (malformed input packets), flood (messages far beyond what a client sends).

const CHECKS := {
	"timer": {"decay": 20.0, "warn": 60.0, "kick": 300.0, "label": "moving faster than the game runs (sped-up inputs)"},
	"reach": {"decay": 0.5, "warn": 5.0, "kick": 20.0, "label": "reaching far beyond arm's length"},
	"fast_break": {"decay": 0.5, "warn": 8.0, "kick": 30.0, "label": "breaking blocks faster than possible"},
	"attack_rate": {"decay": 1.0, "warn": 10.0, "kick": 40.0, "label": "attacking faster than the weapon allows"},
	"bad_packet": {"decay": 1.0, "warn": 20.0, "kick": 60.0, "label": "sending malformed data"},
	"flood": {"decay": 150.0, "warn": 600.0, "kick": 2500.0, "label": "flooding the server with messages"},
}
## Inputs a client may send per server tick on average (a little over one, for clock drift).
const INPUT_RATE := 1.05
const INPUT_BURST := 4.0
## Messages per second from one client before they are dropped and count as flooding.
const FLOOD_LIMIT := 400

var mode := "kick"  # kick | log | off

var _server
var _scores := {}  # peer -> {check: score}
var _warned := {}  # peer -> {check: true} while above WARN
var _recent: Array = []  # [{time, player, check, score, detail}] newest last
var _flood_window := 0
var _flood_counts := {}  # peer -> messages this second


func _init(game_server) -> void:
	_server = game_server


## Adds to a check's score for a player. `detail` explains this event (shown to moderators).
func record(p, check: String, amount := 1.0, detail := "") -> void:
	if mode == "off" or p == null or not CHECKS.has(check):
		return
	var scores: Dictionary = _scores.get(p.peer_id, {})
	var score := float(scores.get(check, 0.0)) + amount
	scores[check] = score
	_scores[p.peer_id] = scores
	var def: Dictionary = CHECKS[check]
	var warned: Dictionary = _warned.get(p.peer_id, {})
	if score >= float(def.warn) and not warned.has(check):
		warned[check] = true
		_warned[p.peer_id] = warned
		_flag(p, check, score, detail, false)
	if score >= float(def.kick) and not warned.has(check + ":kick") and not p.get_meta("anticheat_kicked", false):
		warned[check + ":kick"] = true
		_flag(p, check, score, detail, true)


func score(p, check: String) -> float:
	return float(_scores.get(p.peer_id, {}).get(check, 0.0)) if p != null else 0.0


func update(delta: float) -> void:
	for peer_id in _scores.keys():
		var scores: Dictionary = _scores[peer_id]
		for check: String in scores.keys():
			var def: Dictionary = CHECKS[check]
			var value := maxf(0.0, float(scores[check]) - float(def.decay) * delta)
			if value <= 0.0:
				scores.erase(check)
			else:
				scores[check] = value
			if value < float(def.warn) * 0.5 and _warned.get(peer_id, {}).has(check):
				_warned[peer_id].erase(check)
				_warned[peer_id].erase(check + ":kick")
		if scores.is_empty():
			_scores.erase(peer_id)


## Counts a message from a peer (every client RPC). Returns false when it should be dropped.
func allow_message(peer_id: int) -> bool:
	var second := int(Time.get_ticks_msec() / 1000.0)
	if second != _flood_window:
		_flood_window = second
		_flood_counts.clear()
	var count := int(_flood_counts.get(peer_id, 0)) + 1
	_flood_counts[peer_id] = count
	if count <= FLOOD_LIMIT:
		return true
	var p = _server.players.get(peer_id)
	if p != null:
		record(p, "flood", 1.0, "%d messages in a second" % count)
	return false


func player_left(peer_id: int) -> void:
	_scores.erase(peer_id)
	_warned.erase(peer_id)
	_flood_counts.erase(peer_id)


## [{time, player, check, score, detail, action}] newest first (for /anticheat and the dashboard).
func recent() -> Array:
	var out := _recent.duplicate()
	out.reverse()
	return out


func _flag(p, check: String, value: float, detail: String, kick_level: bool) -> void:
	var def: Dictionary = CHECKS[check]
	var exempt: bool = _server.has_permission(p, "anticheat.bypass")
	var action := "warned"
	if kick_level:
		if mode != "kick" or exempt:
			action = "logged"
		else:
			var ev: Dictionary = _server.emit("cheat_detected", {"player": p, "check": check, "score": value, "detail": detail, "cancelled": false})
			if ev.cancelled:
				action = "ignored by a mod"
			else:
				action = "kicked"
				p.set_meta("anticheat_kicked", true)
				if p._online():
					_server.kick(p.peer_id, "Anti-cheat: %s" % def.label)
	elif not exempt:
		_server.emit("cheat_detected", {"player": p, "check": check, "score": value, "detail": detail, "cancelled": false})
	_recent.append({"time": int(Time.get_unix_time_from_system()), "player": p.name, "check": check, "score": snappedf(value, 0.1), "detail": detail, "action": action})
	if _recent.size() > 100:
		_recent.pop_front()
	var text := "[anti-cheat] %s %s: %s%s (%s)" % [p.name, action, def.label, " - " + detail if not detail.is_empty() else "", check]
	_server.dev_log.add("warn", "server", text)
	for other in _server.players.values():
		if other != p and _server.has_permission(other, "moderation.alerts"):
			other.send_message(text)
