extends RefCounted
## The fourteen acts of Firstlight, and the five side tasks, as data.
##
## Separate from `story.gd` on purpose: that file is the machinery and this one is the writing, and
## the writing is the part somebody will want to change at nine at night without reading a handler.
## Every `goal` here is read by `story.gd`; nothing in this file knows how an objective works.
##
## **The arc.** You wake in a meadow with a man who keeps lights and cannot fight. The lights have
## been going out because something under the world woke up, and the nights have been getting fuller
## ever since. Acts 1-6 are an ordinary survival opening given a name; 7-10 arm you and take you under
## as far as the world goes; 11-14 are the part only this game has. Nothing here threatens anybody
## the player loves, there is no villain, and the Colossus is not killed - it is put back to sleep,
## which is what Wick has wanted for a very long time and has never been brave enough to do alone.
##
## **`said` is what Wick says when he hands it over**, in his voice: warm, a little apologetic, never
## grand. `text` is what the task list shows, which is flatter on purpose - a list is read at a
## glance and does not want a personality.
##
## Counts are deliberately small. A child's attention is the scarcest resource in this game, and
## "mine twenty stone" is a sentence; "mine two hundred stone" is a job.

## `on` is the event kind story.gd watches; `is`/`any` name blocks or items; `below` is a depth;
## `name` is a multiblock's. A goal with no test at all counts anything of that kind.
const ACTS := [
	{"id": "act_waking", "name": "Waking",
		"said": "Wood first. Everything starts with wood, I find.",
		"description": "Wick keeps the lights, and the lights have been going out.",
		"steps": [
			{"text": "Gather six logs", "count": 6,
				"goal": {"on": "break", "any": ["base:log", "base:birch_log", "base:spruce_log", "base:acacia_log"]}},
			{"text": "Put down a crafting table",
				"goal": {"on": "place", "is": "simple_machines:crafting_table"}},
			{"text": "Make a wooden pickaxe",
				"goal": {"on": "craft", "is": "simple_gear:wooden_pickaxe"}}]},

	{"id": "act_roof", "name": "A Roof Before Dark",
		"said": "Walls. Any walls. I'd rather be embarrassed by a hole in a hill than out in it.",
		"steps": [
			{"text": "Build yourself somewhere: place twenty blocks", "count": 20, "goal": {"on": "place"}},
			{"text": "Live through a night", "goal": {"on": "night"}}]},

	{"id": "act_hearth", "name": "Something Hot",
		"said": "You'll want a fire. Cold food is food, but it isn't much of a morning.",
		"steps": [
			{"text": "Put down a furnace", "goal": {"on": "place", "is": "simple_machines:furnace"}},
			{"text": "Cook three things", "count": 3,
				"goal": {"on": "craft", "any": ["base:cooked_porkchop", "base:cooked_beef", "base:cooked_chicken", "base:bread"]}},
			{"text": "Eat something", "goal": {"on": "eat"}}]},

	{"id": "act_stone", "name": "Stone",
		"said": "Wood wears out. Stone is the next honest thing.",
		"steps": [
			{"text": "Mine twenty stone", "count": 20, "goal": {"on": "break", "is": "base:stone"}},
			{"text": "Make a stone pickaxe", "goal": {"on": "craft", "is": "simple_gear:stone_pickaxe"}}]},

	{"id": "act_iron", "name": "Iron",
		"said": "Iron's in the dark bits of the stone. You'll know it when you see it - it looks like it's hiding.",
		"steps": [
			{"text": "Mine five iron ore", "count": 5,
				"goal": {"on": "break", "any": ["base:iron_ore", "base:deep_iron_ore"]}},
			{"text": "Smelt five iron", "count": 5, "goal": {"on": "craft", "is": "base:iron_ingot"}},
			# Not decoration: without this the chain never asks for a tier 3 pickaxe at all, and act 8's
			# cobalt ore is tier 3. Found by `story_probe`, which walks the acts carrying a running tool
			# tier - not by reading them, where it is invisible.
			{"text": "Make an iron pickaxe", "goal": {"on": "craft", "is": "simple_gear:iron_pickaxe"}}]},

	# The act the whole lantern capability was built for, and the one Wick has been waiting to ask for.
	{"id": "act_lantern", "name": "A Light to Carry",
		"said": "Now this one's mine, really. A light you can take with you. I've wanted to give somebody one of these for years.",
		"steps": [
			{"text": "Make a hand lantern", "goal": {"on": "craft", "is": "simple_gear:hand_lantern"}}]},

	# **Armed before deep, and cobalt before deepstone.** Both orderings are load-bearing and the second
	# one was wrong: "mine ten deepstone" sat here at act 7 and deepstone is tier 4, which only a cobalt
	# pickaxe lifts - so the chain asked for something the gear it had granted could not do, and would
	# have stopped dead on a child who followed it exactly. Cobalt *ore* is tier 3, so an iron pickaxe
	# reaches it where a cave has opened the deep up; deepstone itself has to wait for the pick it is
	# the reason for. (2026-09-24)
	{"id": "act_armed", "name": "Armed",
		"said": "I'd feel better if you had something sharp. And something between you and everything else.",
		"steps": [
			{"text": "Make an iron sword", "goal": {"on": "craft", "is": "simple_gear:iron_sword"}},
			{"text": "Make an iron chestplate", "goal": {"on": "craft", "is": "simple_gear:iron_chestplate"}}]},

	{"id": "act_down", "name": "Down",
		"said": "Down, then. I'll be behind you, being no help whatsoever.",
		"steps": [
			{"text": "Get deep underground", "goal": {"on": "depth", "below": 30.0}},
			{"text": "Find five cobalt ore", "count": 5, "goal": {"on": "break", "is": "base:cobalt_ore"}}]},

	{"id": "act_cobalt", "name": "Cobalt",
		"said": "That blue stuff. Nothing else will get through the floor of the world, and the floor is where we're going.",
		"steps": [
			{"text": "Smelt three cobalt", "count": 3, "goal": {"on": "craft", "is": "base:cobalt_ingot"}},
			{"text": "Make a cobalt pickaxe", "goal": {"on": "craft", "is": "simple_gear:cobalt_pickaxe"}}]},

	{"id": "act_deep", "name": "The Floor of the World",
		"said": "There. Hear how quiet it's got? We're under everything now.",
		"steps": [
			{"text": "Mine ten deepstone", "count": 10, "goal": {"on": "break", "is": "base:deepstone"}}]},

	# **Not left to the dice.** Rare creatures spawn at roughly four ten-thousandths per attempt, which
	# is right for a surprise and wrong for a step you cannot finish without. The Hollow Reed makes it
	# deterministic without making it free - see reed.gd. (the user, 2026-09-24)
	{"id": "act_hunt", "name": "The Ones Worth Hunting",
		"said": "When the whole world stops to tell you something's out there - that's one of them. If you have a reed, play it after dark. Something always answers.",
		"description": "Play a hollow reed at night, or wait for one to find you.",
		"steps": [
			{"text": "See off something the world was warned about", "goal": {"on": "notable"}}]},

	# Eight ore makes exactly the two blocks the ruin is missing, with nothing left over - see the
	# recipe in colossus.gd for why it is four-to-one and not the conventional nine.
	{"id": "act_sunstone", "name": "Sunstone",
		"said": "There's a stone down there that keeps a bit of the sun in it. That's what the old lights were made of.",
		"steps": [
			{"text": "Mine eight sunstone ore", "count": 8, "goal": {"on": "break", "is": "base:sunstone_ore"}},
			{"text": "Make two sunstone blocks", "count": 2, "goal": {"on": "craft", "is": "base:sunstone_block"}}]},

	{"id": "act_altar", "name": "The Old Light",
		"said": "Somebody built one of these long before either of us. Two of its corners are still standing. Put the other two back.",
		"description": "A ruined altar in the deep, two corners short of whole.",
		"steps": [
			{"text": "Find the ruin and set its missing corners", "goal": {"on": "built", "name": "firstlight:altar"}}]},

	{"id": "act_firstlight", "name": "Firstlight",
		"said": "Right. I've been not doing this for a very long time. Let's go and not do it together.",
		"description": "Put the thing under the world back to sleep.",
		"steps": [
			{"text": "Light the altar and let the Colossus rest", "goal": {"on": "built", "name": "firstlight:altar_lit"}}]},
]

## Given at the start alongside the chain, and none of them is ever in the way. Two repeat, because
## cooking and sleeping are things you keep doing and a task that can be done again is a small kind
## reason to keep doing them.
const SIDE := [
	{"id": "side_larder", "name": "A Full Larder", "repeatable": true,
		"description": "Wick worries about whether you have eaten.",
		"steps": [{"text": "Cook ten things", "count": 10,
			"goal": {"on": "craft", "any": ["base:cooked_porkchop", "base:cooked_beef", "base:cooked_chicken", "base:bread"]}}]},

	{"id": "side_lamplighter", "name": "Lamplighter",
		"description": "The job Wick can no longer do everywhere at once.",
		"steps": [{"text": "Put up twenty torches", "count": 20, "goal": {"on": "place", "is": "base:torch"}}]},

	{"id": "side_company", "name": "Fellow Travellers",
		"steps": [{"text": "Make a friend of an animal", "goal": {"on": "tame"}}]},

	{"id": "side_reed", "name": "The Piper's Reed",
		"description": "Something made, rather than found.",
		"steps": [{"text": "Come by a hollow reed", "goal": {"on": "carry", "is": "base:hollow_reed"}}]},

	{"id": "side_rest", "name": "Well Rested", "repeatable": true,
		"steps": [{"text": "Sleep in a bed", "goal": {"on": "night"}}]},
]


## Which goals name blocks and which name items: the event a goal waits for already says so, and
## nothing else in the table can tell `base:torch` (a block) from `base:hollow_reed` (an item).
const BLOCK_GOALS := ["break", "place"]
const ITEM_GOALS := ["craft", "carry", "eat"]


## Every block name any goal mentions. **Read off the table rather than listed beside it**, because a
## second list written by hand is a list that goes stale the first time somebody edits an act - and
## the failure would be a -1 id stored in a lookup, which this codebase has written down twice as the
## bug that presents as a player falling for ever.
static func blocks_named() -> Array:
	return _named(BLOCK_GOALS)


## Every item name any goal mentions.
static func items_named() -> Array:
	return _named(ITEM_GOALS)


static func _named(kinds: Array) -> Array:
	var found := {}
	for act in ACTS + SIDE:
		for step in act.steps:
			var goal: Dictionary = step.get("goal", {})
			if not (String(goal.get("on", "")) in kinds):
				continue
			if goal.has("is"):
				found[String(goal.is)] = true
			for name in goal.get("any", []):
				found[String(name)] = true
	return found.keys()
