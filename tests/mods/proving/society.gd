extends RefCounted
## People and the things between them: characters, shops, ledgers, objectives, companies, plots, tags.

var api
var ids: Dictionary


func setup(mod_api, id_table: Dictionary) -> void:
	api = mod_api
	ids = id_table
	# A permission a mod defines and checks itself, and a stat items can modify. Both are registries
	# nothing else here was using, which is exactly how they went uncovered. (2026-09-22)
	api.register_permission("proving.prove", "May prove things", ["moderator"])
	api.register_stat("proving:resolve", 1.0)
	api.register_ledger("coins", {"display_name": "Coins", "min": 0})
	api.register_ledger("standing", {"display_name": "Standing", "levels": [10, 30, 60]})
	# `page` on the objective and on one step: the step's wins while they are on it, so this covers both
	# halves of the rule rather than only the one that is easier to assert.
	api.register_objective("errand", {"display_name": "An Errand", "page": "what",
		"steps": [{"text": "Go and see", "page": "errand"}, {"text": "Come back", "count": 2}]})
	# `order` puts a story's spine above its errands: given second and listed first.
	api.register_objective("daily", {"display_name": "A Daily Thing", "repeatable": true,
		"order": -1, "steps": [{"text": "Again"}]})
	api.register_shop("stall", {"display_name": "The Stall", "offers": [
		{"item": "proving:token", "count": 2, "price": 5, "ledger": "coins", "stock": 3, "restock": 30.0},
		{"item": "proving:rock", "count": 4, "cost": [{"item": "proving:token", "count": 1}]},
		{"item": "proving:plain", "price": 1, "ledger": "coins", "sells": true}]})
	# Every kind of option a conversation can have: one that moves along, one that hands over an
	# objective, one that opens the stall, one that opens the book at a page, and one the mod answers
	# itself.
	api.register_character("keeper", {"display_name": "The Keeper", "color": "#ffd166", "lines": {
		"start": {"text": "You again.", "options": [
			{"text": "What have you got?", "sells": "stall"},
			{"text": "Anything to do?", "gives": "errand"},
			{"text": "Where do I read about this?", "reads": "errand"},
			{"text": "Who are you?", "goes_to": "who"},
			{"text": "Nothing", "does": "wave"}]},
		"who": {"text": "The keeper of this place.", "options": [{"text": "I see", "goes_to": "start"}]},
		"settled": {"text": "Settled in, then."}}})
	api.on("character_choice", func(ev):
		if ev.choice == "wave":
			api.add_balance(ev.player, "coins", 1.0))
	# Tags, which several of the above can refer to.
	api.tag("currency", ["proving:token"])
	api.tag("stone_like", ["proving:rock", "proving:plain", "proving:step"])
