extends RefCounted
## What the block turns into, phase by phase. Kept out of `main.gd` because this is the *content* of the
## game and that is the *mechanism*: the tables get read and argued about, the mechanism does not.
##
## Every name is checked against what the world actually has before it is used (`_pick`), so a table may
## safely name something from an optional pack - `simple_machines` blocks simply never come up when it
## is not installed.
##
## **Danger arrives late on purpose.** A creature on a two-by-two platform has nowhere to run, and the
## first phases are played by somebody with no gear and no room; Meadow spawns nothing that fights back
## and Caves barely does. By the Depths a child has a platform, tools and a reason to be wary. (the
## user, 2026-09-27: gentle early, sharper later)

const PHASES := [
	{
		"name": "Meadow",
		"says": "Soil, and something growing in it",
		"sound": "engine:level_up",
		"blocks": [["base:dirt", 5], ["base:grass", 4], ["base:log", 2], ["base:leaves", 2], ["base:sand", 1]],
		"mobs": [["base:chicken", 2], ["base:pig", 2], ["base:sheep", 1]],
		"mob_chance": 0.05, "crate_chance": 0.04,
		"crate": [["base:apple", 3], ["base:wheat_seeds", 2], ["simple_gear:stick", 4], ["base:stick", 4]],
		"jackpot": [["base:hay_bale", 2], ["base:planks", 1]],
	},
	{
		"name": "Caves",
		"says": "Stone, and the first metal in it",
		"sound": "engine:discover",
		"blocks": [["base:stone", 6], ["base:cobblestone", 4], ["base:coal_ore", 2], ["base:iron_ore", 1],
			["base:gravel", 2]],
		"mobs": [["base:dustling", 2], ["base:mirelet", 1]],
		"mob_chance": 0.06, "crate_chance": 0.05,
		"crate": [["base:torch", 4], ["base:coal", 3], ["base:iron_ingot", 1]],
		"jackpot": [["base:iron_ore", 3], ["base:glass", 1]],
	},
	{
		"name": "The Depths",
		"says": "Colder, and something moves down here",
		"sound": "engine:crit",
		"blocks": [["base:deepstone", 5], ["base:iron_ore", 2], ["base:copper_ore", 2], ["base:cobalt_ore", 1],
			["base:blackglass", 1], ["base:gravel", 1]],
		"mobs": [["base:night_stalker", 2], ["base:clatterjack", 2], ["base:spider", 1], ["base:goblin", 1]],
		"mob_chance": 0.09, "crate_chance": 0.06,
		"crate": [["base:cobalt_ingot", 1], ["base:copper_ingot", 2], ["base:glass", 3]],
		"jackpot": [["base:cobalt_ore", 3], ["base:blackglass", 2]],
	},
	{
		"name": "Overgrown",
		"says": "Something has taken the stone back",
		"sound": "engine:breed",
		"blocks": [["base:grass", 4], ["base:log", 3], ["base:leaves", 4], ["base:fern", 2],
			["base:tall_grass", 2], ["base:sapling", 1], ["base:sand", 1]],
		"mobs": [["base:wolf", 2], ["base:boomshroom", 1], ["base:cow", 2], ["base:palemoth", 2]],
		"mob_chance": 0.09, "crate_chance": 0.06,
		"crate": [["base:sapling", 2], ["base:apple", 4], ["base:hollow_reed", 2], ["base:bread", 2]],
		"jackpot": [["base:sunstone_ore", 1], ["base:brick", 2]],
	},
	{
		# **The reason to build a factory**, which the roadmap has wanted a game to supply since the
		# packs were split. Quickstone and copper arriving by the crate is what makes `simple_machines`
		# worth the trouble; it is content answering a content question, not new engine work.
		"name": "The Works",
		"says": "Quickstone. Something could be made of this",
		"sound": "engine:craft",
		"blocks": [["base:stone", 4], ["simple_machines:quickstone", 3], ["base:copper_ore", 3],
			["base:iron_ore", 2], ["base:gold_ore", 1], ["base:cobblestone", 2]],
		"mobs": [["base:mirelet", 2], ["base:wisp", 1], ["base:clatterjack", 1]],
		"mob_chance": 0.08, "crate_chance": 0.08,
		"crate": [["base:copper_ingot", 3], ["base:iron_ingot", 2], ["base:gold_ingot", 1]],
		"jackpot": [["simple_machines:forge", 1], ["simple_machines:anvil", 1], ["simple_machines:chest", 2]],
	},
	{
		"name": "Glow",
		"says": "Light, where there has never been any",
		"sound": "engine:discover",
		"blocks": [["base:sunstone_ore", 3], ["base:deepstone", 4], ["base:gold_ore", 2],
			["base:blackglass", 2], ["base:glass", 2]],
		"mobs": [["base:hollow_piper", 2], ["base:wisp", 2], ["base:barrow_warden", 1]],
		"mob_chance": 0.10, "crate_chance": 0.07,
		"crate": [["base:sunstone", 2], ["base:gold_ingot", 2], ["base:emberheart", 1]],
		"jackpot": [["base:sunstone_block", 2], ["simple_machines:quicklamp", 1]],
	},
]
