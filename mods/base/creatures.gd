extends RefCounted
## The things that live in the world. Fauna is a noun, so it belongs here - what a sheep *is*, not
## whether the game you are playing lets one be sheared.
##
## `base` had no entities at all until 2026-09-23: they went with the games that were deleted, and a
## world you can build in but where nothing moves is a diorama. Thirteen of them, from the models kept
## back because no script can regenerate them.
##
## **On names, which took some care.** Real animals keep their real names, because a child has to
## recognise a sheep and nobody owns sheep. The invented ones are Quarrowen's own and are deliberately
## not the shapes this genre has made standard - the blob is a marsh creature called a Mirelet, the
## dried-out wanderer is a Dustling, the bowman is a Clatterjack. The Night Stalker, Boomshroom and
## Colossus were this project's inventions already.
##
## **Registered, never spawned.** Not one spawn rule lives here, and the reason is the same one that
## moved the world generator out of `base` earlier the same day: spawn rules attach to the **realm**,
## so a rule written here fires in every world built on `base` - including the Proving Ground's flat
## test world, where mobs appeared, dirtied chunks continuously and stopped a save queue ever
## draining. A pack of nouns that quietly populates every world is not a pack of nouns. What lives
## where is a decision for a game; see `mods/creative/`.



func setup(api) -> void:
	_farm(api)
	_wild(api)
	_monsters(api)


## What a meadow has in it. All four are the same shape of creature - wanders, panics, breeds when fed,
## drops something - and differ only in numbers and what they give you, which is the point: a mod that
## adds a fifth writes one dictionary.
func _farm(api) -> void:
	api.register_entity("pig", {"kind": "mob", "display_name": "Pig", "model": "models/pig.glb",
		"width": 0.9, "height": 0.9, "health": 10, "speed": 2.0, "category": "animal", "persistent": true,
		"breeding": {"items": ["base:wheat"], "cooldown": 30.0},
		"drops": [["base:apple", 0, 0.0]],
		"ai": {"preset": "passive", "wander_radius": 8}})
	api.register_entity("sheep", {"kind": "mob", "display_name": "Sheep", "model": "models/sheep.glb",
		"width": 0.9, "height": 1.2, "health": 10, "speed": 1.9, "category": "animal", "persistent": true,
		"breeding": {"items": ["base:wheat"], "cooldown": 30.0},
		# Wool is cloth, and `base` already has sixteen colours of it. A white one, because dyeing is a
		# rule and belongs to whatever game wants to write it.
		"drops": [["base:cloth_white", 1]],
		"ai": {"preset": "passive", "wander_radius": 8}})
	api.register_entity("cow", {"kind": "mob", "display_name": "Cow", "model": "models/cow.glb",
		"width": 1.0, "height": 1.4, "health": 12, "speed": 1.8, "category": "animal", "persistent": true,
		"breeding": {"items": ["base:wheat"], "cooldown": 40.0},
		"ai": {"preset": "passive", "wander_radius": 8}})
	api.register_entity("chicken", {"kind": "mob", "display_name": "Chicken", "model": "models/chicken.glb",
		"width": 0.5, "height": 0.7, "health": 4, "speed": 1.6, "category": "animal", "persistent": true,
		"breeding": {"items": ["base:wheat_seeds"], "cooldown": 30.0},
		"ai": {"preset": "passive", "wander_radius": 10}})


## Animals that can look after themselves. Both are `neutral`: they leave you alone until you do not.
func _wild(api) -> void:
	api.register_entity("wolf", {"kind": "mob", "display_name": "Wolf", "model": "models/wolf.glb",
		"width": 0.7, "height": 0.9, "health": 14, "speed": 3.4, "category": "animal", "persistent": true,
		# Tameable, because a child with a dog is a different game from a child without one, and the
		# engine already has the capability. What it does once tamed is the game's business.
		"taming": {"items": ["base:apple"], "chance": 0.35, "follow_distance": 3.0, "teleport_distance": 16.0},
		"nameplate": {"show_health": true},
		"ai": {"preset": "neutral", "aggression": 0.6, "wander_radius": 14}})
	api.register_entity("spider", {"kind": "mob", "display_name": "Spider", "model": "models/spider.glb",
		"width": 1.1, "height": 0.7, "health": 12, "speed": 3.0, "category": "monster",
		# Wide and low, and it climbs a step it has no business climbing - which is most of what makes
		# a spider feel like a spider rather than a fast pig.
		"ai": {"preset": "neutral", "aggression": 0.5, "step_up": 2, "wander_radius": 12}})


## The night shift. Named and shaped as this world's own; see the note at the top of the file.
func _monsters(api) -> void:
	api.register_entity("dustling", {"kind": "mob", "display_name": "Dustling", "model": "models/zombie.glb",
		"width": 0.7, "height": 1.8, "health": 18, "speed": 1.9, "category": "monster",
		# Slow, patient and it hunts in company: the threat is being surrounded, not being outrun.
		"ai": {"preset": "hostile", "aggression": 0.7, "courage": 1.0, "pack": true, "sight_range": 18.0}})
	api.register_entity("clatterjack", {"kind": "mob", "display_name": "Clatterjack", "model": "models/skeleton.glb",
		"width": 0.7, "height": 1.8, "health": 14, "speed": 2.2, "category": "monster",
		# Keeps its distance and shoots, so the answer is cover rather than running at it.
		"ai": {"preset": "archer"}})
	api.register_entity("mirelet", {"kind": "mob", "display_name": "Mirelet", "model": "models/slime.glb",
		"width": 0.8, "height": 0.8, "health": 8, "speed": 1.4, "category": "monster",
		# A marsh thing. Weak, slow and never alone, which is a different problem from a strong one.
		"ai": {"preset": "hostile", "aggression": 0.5, "courage": 1.0, "intelligence": 0.2,
			"jump": true, "wander_radius": 6}})
	api.register_entity("night_stalker", {"kind": "mob", "display_name": "Night Stalker",
		"model": "models/night_stalker.glb",
		"width": 0.8, "height": 2.2, "health": 26, "speed": 3.6, "category": "monster",
		# Fast, brave and it sees a long way. The one you do not want to meet in the open.
		"ai": {"preset": "hostile", "aggression": 0.85, "courage": 1.0, "intelligence": 0.8,
			"sight_range": 28.0}})
	api.register_entity("boomshroom", {"kind": "mob", "display_name": "Boomshroom",
		"model": "models/boomshroom.glb",
		"width": 0.8, "height": 1.4, "health": 10, "speed": 1.6, "category": "monster",
		# It walks up to you and goes off. The explosion itself is a rule - whether it breaks blocks is
		# the `mob_griefing` setting - so all this says is that the creature exists and is nervous.
		"ai": {"preset": "hostile", "aggression": 0.9, "courage": 1.0, "intelligence": 0.3}})
	api.register_entity("goblin", {"kind": "mob", "display_name": "Goblin", "model": "models/goblin.glb",
		"width": 0.6, "height": 1.2, "health": 12, "speed": 3.2, "category": "monster",
		# Quick, cowardly, and it runs when it is losing - which teaches a child that not everything
		# fights to the death.
		"ai": {"preset": "hostile", "aggression": 0.6, "courage": 0.3, "agility": 0.7}})
	# A boss is an event a game arranges, not weather - and like everything here it is registered only.
	# because the model and the creature are nouns and a game should not have to invent them.
	api.register_entity("colossus", {"kind": "mob", "display_name": "Ancient Colossus",
		"model": "models/colossus.glb",
		"width": 1.2, "height": 7.2, "health": 300, "speed": 2.4, "category": "monster",
		"nameplate": {"show_health": true},
		"ai": {"preset": "boss"}})
