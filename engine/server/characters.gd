extends RefCounted
## People who stand somewhere, have a name and a face, hold a conversation and offer something.
##
## Bramble was written by hand: thirty lines of building a panel, a label per sentence, a button, and a
## branch on her own state to decide which sentence. Every mod that wanted a person to talk to would
## have written that again, slightly differently, and a child would have met three characters with
## three different-looking conversations.
##
##     api.register_character("bramble", {"display_name": "Bramble", "color": "#ffd166",
##         "lines": {
##             "start": {"text": "Oh - somebody. I saw your fire from the ridge.",
##                 "options": [{"text": "Come with me", "does": "recruit"},
##                             {"text": "Who are you?", "goes_to": "who"}]},
##             "who": {"text": "Bramble. I mend things, mostly.",
##                 "options": [{"text": "I see", "goes_to": "start"}]}}})
##
##     api.talk_to(player, "bramble", {"entity": e, "line": "settled"})
##
## **What the engine knows**: a conversation is lines with options, a player is somewhere in it, and
## choosing an option either moves to another line or means something. **What it does not know**: what
## any of it means. `does` fires `character_choice` and the mod takes it from there - recruiting,
## marrying, opening a gate, whatever this particular person is for.
##
## Two of those got shortcuts, because they are what characters are overwhelmingly *for*: `gives`
## names an objective and `sells` names a shop, both engine capabilities already. Making a mod catch
## an event and call one function to hand over a quest would have been ceremony around the common case.
##
##     {"text": "I'll take the job", "gives": "deliver_the_post"}
##     {"text": "What have you got?", "sells": "bramble_wares"}
##
## **Which line to open on is the mod's too.** Bramble says something different once she has somewhere
## to live, and that is a fact about her story, not about conversations. The mod passes the line; the
## engine does not learn what "settled" means.

const ModApi = preload("res://engine/server/mod_api.gd")

const KEY := "_met"
const MAX_LINES := 64
const MAX_OPTIONS := 6

var server

## Name -> {name, display_name, color, lines: {id: {text, options}}, owner}
var kinds := {}
## peer id -> {character, entity, line} for whoever is mid-conversation.
var _talking := {}


func _init(game_server) -> void:
	server = game_server


func register(character_name: String, def: Dictionary, owner := "engine") -> bool:
	if character_name.is_empty() or kinds.has(character_name):
		push_error("Invalid or duplicate character '%s'" % character_name)
		return false
	var lines := {}
	var source = def.get("lines")
	if not (source is Dictionary) or (source as Dictionary).is_empty():
		push_error("Character '%s' has nothing to say" % character_name)
		return false
	for id in (source as Dictionary).keys():
		if lines.size() >= MAX_LINES:
			break
		var entry = source[id]
		if not (entry is Dictionary):
			continue
		var options := []
		for option in (entry.get("options", []) if entry.get("options") is Array else []):
			if not (option is Dictionary) or options.size() >= MAX_OPTIONS:
				continue
			options.append({"text": String(option.get("text", "...")),
				"goes_to": String(option.get("goes_to", "")), "does": String(option.get("does", "")),
				# Quests and shops are engine capabilities already, and asking every mod to catch an
				# event and call one function would be ceremony around the two things characters are
				# actually for. Anything else is still `does`.
				"gives": ModApi.qualified(String(option.get("gives", "")), owner),
				"sells": ModApi.qualified(String(option.get("sells", "")), owner)})
		lines[String(id)] = {"text": String(entry.get("text", "")), "options": options}
	kinds[character_name] = {"name": character_name, "owner": owner,
		"display_name": String(def.get("display_name", character_name.capitalize())),
		"color": String(def.get("color", "#ffd166")), "lines": lines}
	return true


## Opens a conversation. `options.line` is where to start - the mod's choice, because which line a
## person opens on is a fact about their story and not about conversations. `options.entity` is who is
## speaking, so a choice can say which one it was.
func talk(player, character_name: String, options := {}) -> bool:
	var kind: Dictionary = kinds.get(character_name, {})
	if player == null or kind.is_empty():
		return false
	var line := String(options.get("line", "start"))
	if not (kind.lines as Dictionary).has(line):
		line = "start"
		if not (kind.lines as Dictionary).has(line):
			return false
	var entity = options.get("entity")
	_talking[player.peer_id] = {"character": character_name, "line": line,
		"entity": int(entity.id) if entity != null and entity.get("id") is int else 0}
	_remember(player, character_name)
	_show(player, kind, line)
	return true


## Whether this player has ever spoken to them, which is most of what "we have met" needs.
func has_met(player, character_name: String) -> bool:
	return player != null and (player.data.get(KEY, {}) as Dictionary).has(character_name)


func _remember(player, character_name: String) -> void:
	if not (player.data.get(KEY) is Dictionary):
		player.data[KEY] = {}
	player.data[KEY][character_name] = int((player.data[KEY] as Dictionary).get(character_name, 0)) + 1


## One conversation, drawn the same way for every character in every mod - which is the point. A child
## who has learned to talk to one person has learned to talk to all of them.
func _show(player, kind: Dictionary, line_id: String) -> void:
	var line: Dictionary = kind.lines[line_id]
	var children: Array = [{"type": "label", "text": String(kind.display_name), "size": 20, "color": String(kind.color)},
		{"type": "label", "text": String(line.text)}, {"type": "spacer", "size": 6}]
	for i in (line.options as Array).size():
		var option: Dictionary = line.options[i]
		children.append({"type": "button", "text": String(option.text), "action": "say:%s:%d" % [line_id, i]})
	children.append({"type": "button", "text": "Goodbye", "action": "close"})
	player.show_ui("engine:talk", {"anchor": "center", "modal": true, "children": children})


## A button was pressed. Returns true if it was one of ours, so the caller knows whether to look
## further.
func on_action(player, action: String) -> bool:
	if not action.begins_with("say:"):
		return false
	var parts := action.split(":")
	if parts.size() != 3:
		return false
	var state: Dictionary = _talking.get(player.peer_id, {})
	var kind: Dictionary = kinds.get(String(state.get("character", "")), {})
	if kind.is_empty() or String(state.get("line", "")) != parts[1]:
		return true  # a stale panel: swallowed rather than acted on
	var line: Dictionary = kind.lines.get(parts[1], {})
	var index := int(parts[2])
	if line.is_empty() or index < 0 or index >= (line.options as Array).size():
		return true
	var option: Dictionary = line.options[index]
	if not String(option.gives).is_empty():
		server.objectives.give(player, String(option.gives))
	if not String(option.does).is_empty():
		# The engine has no idea what "recruit" means, and is not about to find out.
		server.emit("character_choice", {"player": player, "character": kind.name,
			"entity": int(state.get("entity", 0)), "line": parts[1], "choice": String(option.does)})
	var shop := String(option.sells)
	if not shop.is_empty():
		# The stall replaces the conversation rather than sitting on top of it: two modal panels at
		# once is how a child ends up unable to close either.
		_talking.erase(player.peer_id)
		player.hide_ui("engine:talk")
		server.shops.show(player, shop)
		return true
	var goes_to := String(option.goes_to)
	if goes_to.is_empty() or not (kind.lines as Dictionary).has(goes_to):
		_talking.erase(player.peer_id)
		player.hide_ui("engine:talk")
		return true
	state.line = goes_to
	_show(player, kind, goes_to)
	return true


func player_left(peer_id: int) -> void:
	_talking.erase(peer_id)
