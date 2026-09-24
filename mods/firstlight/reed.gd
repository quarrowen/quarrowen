extends RefCounted
## The Hollow Reed: play it after dark and something rare answers.
##
## **Why this exists at all is a design fix, not a flourish.** Act 11 asks the player to see off one
## of the creatures the whole server is told about, and those spawn at roughly four ten-thousandths
## per attempt. As a surprise you stumble into at midnight that rarity is exactly right; as a
## *required step* it meant a child could be stuck on act 11 for hours with nothing they could do
## about it. A required step gated on a dice roll is not difficulty, it is waiting. (2026-09-24)
##
## So the reed makes it deterministic without making it free: you have to own one, which means you
## already met something rare and it dropped one; you have to be outside, at night, away from where
## you sleep; and what comes is chosen by the world rather than by you.
##
## `base` owns the reed - it is a noun, and the Hollow Piper drops it. What *playing* it does is a
## rule, so it lives here. Another game may decide a reed is something you sell.

## One at a time. Two of these at once is not twice the story, it is a mess in the dark.
const QUIET_SECONDS := 240.0

var api
var _reed := 0
var _last_played := {}  # player id -> seconds, against _elapsed
## Seconds since the world started, counted here. The mod API exposes the time *of day*, which runs
## on the world clock and is useless for "was this played recently" - the same reason wick.gd keeps
## its own.
var _elapsed := 0.0


func setup(mod_api) -> void:
	api = mod_api
	# The id, not the name: `item_use` carries what the player is holding as an id, and resolving it
	# once here is both faster and the documented way (`require_item` rather than `item`, so a missing
	# reed says so at load instead of becoming a -1 that matches nothing).
	_reed = api.require_item("base:hollow_reed")
	api.every(5.0, func(): _elapsed += 5.0)
	api.on("item_use", func(ev):
		if ev.player != null and int(ev.get("item", -1)) == _reed:
			_play(ev.player))


## What the reed answers with: one of the rare creatures that could have spawned here anyway.
##
## **Asked of the registry rather than listed here**, so a rare creature added later can be called
## without this file hearing about it - the same argument as `api.notable_of` in act 11's handler. A
## hardcoded list of "the rare ones" stops being right the moment anybody adds a fifth.
func _callable_ones() -> Array:
	var out := []
	for type_name in api.entity_types():
		if not api.notable_of(String(type_name)).is_empty():
			out.append(String(type_name))
	return out


func _play(player) -> void:
	var id := str(player.player_id)
	var now: float = _elapsed
	if now - float(_last_played.get(id, -QUIET_SECONDS)) < QUIET_SECONDS:
		player.send_message("The reed is still warm. Give it a while.")
		return
	# Daylight rather than the clock phase: dusk under a storm is darker than midnight in clear air,
	# and the player is judging it by what they can see, so the game should too.
	if api.get_daylight() > 0.3:
		player.send_message("You blow across the reed. It makes a thin, silly noise, and nothing else.")
		return
	if player.position.y < 50.0:
		player.send_message("The note dies against the stone. Whatever this is for, it is not for down here.")
		return
	var choices := _callable_ones()
	if choices.is_empty():
		return
	_last_played[id] = now
	player.send_message("You blow across the reed. The note goes further than it should, and does not come back.")
	# Behind and to one side, far enough to be a shape before it is a fight - the whole point is that
	# you hear it coming. Spawning it in front would make the reed a trap rather than a summons.
	var away := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf_range(18.0, 26.0)
	var at: Vector3 = player.position + away
	at.y = float(api.surface_y(int(at.x), int(at.z)) + 1)
	var called: String = choices[randi() % choices.size()]
	if api.spawn_entity(called, at) == null:
		# Nowhere to stand is an ordinary outcome underground or over water, not an error. The cooldown
		# is deliberately *not* reset: a player who could retry instantly would stand there spamming it.
		player.send_message("Something stirs a long way off, and thinks better of it.")
