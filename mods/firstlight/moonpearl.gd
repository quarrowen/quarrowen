extends RefCounted
## What the Moonpearl Charm does after dark: monsters notice you later.
##
## **The charm is a noun and this is the rule** - `simple_gear` says a bead on a cord exists and what
## it costs; this says what the night does with it. Another game may decide a moonpearl is only worth
## selling. (the user chose "build a real night effect" over a stat, 2026-09-24)
##
## **There is no stealth stat in the engine and there should not be one.** A number on a player that
## only one curio in one game reads is the engine having an opinion about content. What the engine has
## instead is `mob_target`, which is cancellable - so "it did not notice you" is a refusal rather than
## a statistic, and any mod can express its own version without a new field.
##
## The effect is *distance*, not chance. A monster that rolls a die each time you meet is a monster a
## child cannot learn; one that simply does not see you until you are close is a rule they can plan
## around, and the moment it does see you is the moment it was always going to.

## Inside this, the charm is worth nothing - they are on top of you and the dark is not hiding you.
## Chosen to be shorter than the distance at which a player can see a monster coming, so the charm
## buys you the choice of whether to meet it rather than the right to walk through it.
const NOTICES_WITHIN := 7.0
## How often the charm is checked against the sky. Cheap, and nothing here needs to be prompt: dusk
## takes minutes and putting a necklace on is not an emergency.
const CHECK_SECONDS := 2.0
## Dark enough to count. The same threshold the reed uses, so "after dark" means one thing in this
## game rather than two.
const DARK_BELOW := 0.3

var api
var _charm := 0
## Player id -> true while the dark is not paying attention. **A set here rather than a condition**:
## the engine refuses a condition that neither changes a stat nor runs a timer, and it is right to -
## that guard catches a mod that filled one in halfway. This mark genuinely does neither; what it
## does is make a handler say no. Recomputed every couple of seconds, so it needs no saving and
## cannot drift. (2026-09-24)
var _unnoticed := {}


func setup(mod_api) -> void:
	api = mod_api
	_charm = api.require_item("simple_gear:moonpearl_charm")
	api.every(CHECK_SECONDS, func(): _watch())
	api.on("mob_target", func(ev):
		if ev.get("target") == null or ev.entity == null:
			return
		# A mob can take against another mob, and that target has no player_id to ask about.
		if not ("player_id" in ev.target) or not _unnoticed.has(str(ev.target.player_id)):
			return
		if ev.entity.position.distance_to(ev.target.position) > NOTICES_WITHIN:
			ev.cancelled = true)


## Gives and takes the mark as the sky and the necklace change. Wholesale each time rather than on the
## two events that could change it (`equipment_changed` and the clock), because those two can disagree
## - putting the charm on at dawn and taking it off at dusk leaves an event-driven version wrong in
## both directions, and this costs one loop over the players every two seconds.
func _watch() -> void:
	var dark: bool = api.get_daylight() < DARK_BELOW
	for p in api.players():
		var id := str(p.player_id)
		var should: bool = dark and api.worn(p, "trinket") == _charm
		var has: bool = _unnoticed.has(id)
		if should and not has:
			_unnoticed[id] = true
			p.send_message("The dark settles around you and stops paying attention.")
		elif has and not should:
			_unnoticed.erase(id)
