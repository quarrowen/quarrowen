extends RefCounted
## Somewhere to buy and sell: a village stall, a travelling pedlar, a vending machine in a factory.
##
## The obvious half of this is a list of prices. The half that matters is **stock**, because a shop
## with unlimited everything is not a shop, it is a creative menu with an extra step. An offer may have
## a number of them and a time to get more, and then the village blacksmith who has three swords this
## week is a different place to visit next week.
##
##     api.register_shop("bramble_wares", {"display_name": "Bramble's Wares", "offers": [
##         {"item": "rope", "count": 2, "price": 4, "ledger": "coins", "stock": 10, "restock": 600.0},
##         {"item": "apple", "price": 1, "ledger": "coins", "sells": true},
##         {"item": "lantern", "cost": [{"item": "iron_bar", "count": 2}, {"item": "coal"}]}])
##
## **Coins are not assumed.** A price is either a number out of a ledger, or a list of items, or both,
## and a game with no money at all barters perfectly well. `sells: true` turns the offer round: the
## *player* hands over the item and is paid.
##
## **The engine never invents an item.** Everything sold comes out of stock and everything bought goes
## nowhere, which is how every shop in every game works and is worth saying out loud, because the
## alternative - a shop that is a portal to an infinite warehouse - is what makes an economy collapse
## on day three.
##
## What the engine will not do: decide who may shop, set prices from supply, or haggle. A mod that
## wants a stall that shuts at night watches the clock itself.

const ModApi = preload("res://engine/server/mod_api.gd")

## Wide enough for a general store, narrow enough that the panel fits on a small screen.
const MAX_OFFERS := 24
## What `stock: -1` means, spelled out so the comparisons read as English.
const UNLIMITED := -1

var server

## Name -> {name, display_name, offers: [...], owner}
var kinds := {}
## "<shop>|<index>" -> {left, at} for offers that run out. Kept outside the definition so the
## definition stays the immutable thing a mod registered, and the running total is plainly separate.
var _stock := {}
## peer id -> shop name, for whoever has one open.
var _open := {}
## Why the last buy failed, in words a child can read.
var problem := ""


func _init(game_server) -> void:
	server = game_server


func register(shop_name: String, def: Dictionary, owner := "engine") -> bool:
	if shop_name.is_empty() or kinds.has(shop_name):
		push_error("Invalid or duplicate shop '%s'" % shop_name)
		return false
	var offers := []
	for entry in (def.get("offers", []) if def.get("offers") is Array else []):
		if not (entry is Dictionary) or offers.size() >= MAX_OFFERS:
			continue
		var offer := _read_offer(entry, owner)
		if not offer.is_empty():
			offers.append(offer)
	if offers.is_empty():
		push_error("Shop '%s' has nothing to trade" % shop_name)
		return false
	kinds[shop_name] = {"name": shop_name, "owner": owner,
		"display_name": String(def.get("display_name", shop_name.capitalize())), "offers": offers}
	return true


func _read_offer(entry: Dictionary, owner: String) -> Dictionary:
	var item := _resolve(String(entry.get("item", "")), owner)
	if item <= 0:
		push_error("Shop offer names an item that does not exist: '%s'" % entry.get("item", ""))
		return {}
	var cost := []
	for part in (entry.get("cost", []) if entry.get("cost") is Array else []):
		if not (part is Dictionary):
			continue
		var paid := _resolve(String(part.get("item", "")), owner)
		if paid > 0:
			cost.append({"item": paid, "count": maxi(int(part.get("count", 1)), 1)})
	var stock := int(entry.get("stock", UNLIMITED))
	return {"item": item, "count": maxi(int(entry.get("count", 1)), 1),
		"price": maxf(float(entry.get("price", 0.0)), 0.0),
		"ledger": ModApi.qualified(String(entry.get("ledger", "")), owner),
		"cost": cost,
		# Which way round the trade goes. `sells` reads from the player's side, which is the side
		# they are standing on.
		"sells": bool(entry.get("sells", false)),
		"stock": stock if stock >= 0 else UNLIMITED,
		"restock": maxf(float(entry.get("restock", 0.0)), 0.0)}


func _resolve(item_name: String, owner: String) -> int:
	if item_name.is_empty():
		return 0
	return server.items.id_of(ModApi.qualified(item_name, owner))


## How many of this offer are left, refilling first if it is time. Unlimited offers say -1.
func left_of(shop_name: String, index: int) -> int:
	var kind: Dictionary = kinds.get(shop_name, {})
	if kind.is_empty() or index < 0 or index >= (kind.offers as Array).size():
		return 0
	var offer: Dictionary = kind.offers[index]
	if int(offer.stock) == UNLIMITED:
		return UNLIMITED
	var key := "%s|%d" % [shop_name, index]
	var state = _stock.get(key)
	if not (state is Dictionary):
		return int(offer.stock)
	# Refilling on the way past rather than on a timer: a shop nobody visits costs nothing, and a
	# village of forty stalls would otherwise be forty things ticking for no one.
	if float(offer.restock) > 0.0 and Time.get_unix_time_from_system() - float(state.at) >= float(offer.restock):
		_stock.erase(key)
		return int(offer.stock)
	return int(state.left)


## What a player would see: [{index, item, name, count, price, ledger, cost, sells, left, can}].
func offers_for(player, shop_name: String) -> Array:
	var kind: Dictionary = kinds.get(shop_name, {})
	var out := []
	for i in (kind.get("offers", []) as Array).size():
		var offer: Dictionary = kind.offers[i]
		var costs := []
		for part in (offer.cost as Array):
			costs.append({"item": int(part.item), "name": server.items.display_name(int(part.item)),
				"count": int(part.count)})
		out.append({"index": i, "item": int(offer.item), "name": server.items.display_name(int(offer.item)),
			"count": int(offer.count), "price": float(offer.price), "ledger": String(offer.ledger),
			"cost": costs, "sells": bool(offer.sells), "left": left_of(shop_name, i),
			"can": _can(player, kind, i).is_empty()})
	return out


## Why this trade cannot happen, or "" if it can. One function so the button's greying-out and the
## refusal message can never disagree, which is the bug where a child clicks something that says it
## will work and is told it will not.
func _can(player, kind: Dictionary, index: int) -> String:
	if player == null:
		return "Nobody is here."
	var offer: Dictionary = kind.offers[index]
	var count := int(offer.count)
	if bool(offer.sells):
		if player.count_of(int(offer.item)) < count:
			return "You have no %s to sell." % server.items.display_name(int(offer.item))
		return ""
	var left := left_of(String(kind.name), index)
	if left != UNLIMITED and left <= 0:
		return "Sold out. Come back later."
	if float(offer.price) > 0.0 and not String(offer.ledger).is_empty():
		if server.ledgers.value_of(player, String(offer.ledger)) < float(offer.price):
			return "You cannot afford that."
	for part in (offer.cost as Array):
		if player.count_of(int(part.item)) < int(part.count):
			return "You need %d %s." % [int(part.count), server.items.display_name(int(part.item))]
	# Refused rather than dropped at their feet: goods on the floor get missed or despawn, and the
	# coin is gone either way (see ServerPlayer.give).
	if not player.has_room(int(offer.item), count):
		return "Your pack is full."
	return ""


## Does the trade. Everything is checked before anything moves, so a failure halfway leaves a player
## with neither the coin nor the goods - which has happened in enough games to be worth the care.
func trade(player, shop_name: String, index: int) -> bool:
	problem = ""
	var kind: Dictionary = kinds.get(shop_name, {})
	if kind.is_empty() or index < 0 or index >= (kind.offers as Array).size():
		problem = "That is not for sale."
		return false
	problem = _can(player, kind, index)
	if not problem.is_empty():
		return false
	var offer: Dictionary = kind.offers[index]
	var count := int(offer.count)
	if bool(offer.sells):
		if not player.take(int(offer.item), count):
			problem = "You have no %s to sell." % server.items.display_name(int(offer.item))
			return false
		if float(offer.price) > 0.0 and not String(offer.ledger).is_empty():
			server.ledgers.add(player, String(offer.ledger), float(offer.price))
		for part in (offer.cost as Array):
			player.give(int(part.item), int(part.count))
	else:
		# Take payment first. If the pack turns out to be full the goods are dropped rather than lost,
		# but an unpaid-for purchase would be a way to print items.
		if float(offer.price) > 0.0 and not String(offer.ledger).is_empty():
			if not server.ledgers.spend(player, String(offer.ledger), float(offer.price)):
				problem = "You cannot afford that."
				return false
		for part in (offer.cost as Array):
			if not player.take(int(part.item), int(part.count)):
				problem = "You need %d %s." % [int(part.count), server.items.display_name(int(part.item))]
				return false
		_spend_stock(shop_name, index)
		player.give(int(offer.item), count)
	server.emit("shop_traded", {"player": player, "shop": shop_name, "index": index,
		"item": int(offer.item), "count": count, "sold": bool(offer.sells)})
	return true


func _spend_stock(shop_name: String, index: int) -> void:
	var offer: Dictionary = kinds[shop_name].offers[index]
	if int(offer.stock) == UNLIMITED:
		return
	var key := "%s|%d" % [shop_name, index]
	var left := left_of(shop_name, index)
	# `at` is set on the first sale, so restocking counts from when the shelf started emptying rather
	# than from whenever somebody last happened to buy the very last one.
	_stock[key] = {"left": maxi(left - 1, 0), "at": float(_stock.get(key, {}).get("at", Time.get_unix_time_from_system()))}


## Opens the shop panel. Drawn by the engine so every shop in every mod looks the same, which is the
## whole reason this is a capability and not thirty lines in a mod.
func show(player, shop_name: String) -> bool:
	var kind: Dictionary = kinds.get(shop_name, {})
	if player == null or kind.is_empty():
		return false
	_open[player.peer_id] = shop_name
	_draw(player, kind)
	return true


func _draw(player, kind: Dictionary) -> void:
	var children: Array = [{"type": "label", "text": String(kind.display_name), "size": 20}]
	for offer in offers_for(player, String(kind.name)):
		var price := _price_text(offer)
		var line := ""
		if bool(offer.sells):
			line = "Sell %d %s for %s" % [int(offer.count), String(offer.name), price]
		else:
			line = "%d %s for %s" % [int(offer.count), String(offer.name), price]
			if int(offer.left) != UNLIMITED:
				line += "   (%d left)" % int(offer.left)
		children.append({"type": "button", "text": line, "action": "shop:%d" % int(offer.index),
			"disabled": not bool(offer.can)})
	children.append({"type": "spacer", "size": 6})
	children.append({"type": "button", "text": "Done", "action": "close"})
	player.show_ui("engine:shop", {"anchor": "center", "modal": true, "children": children})


func _price_text(offer: Dictionary) -> String:
	var parts := []
	if float(offer.price) > 0.0 and not String(offer.ledger).is_empty():
		var ledger: Dictionary = server.ledgers.kinds.get(String(offer.ledger), {})
		parts.append("%d %s" % [int(offer.price), String(ledger.get("display_name", offer.ledger))])
	for part in (offer.cost as Array):
		parts.append("%d %s" % [int(part.count), String(part.name)])
	return " and ".join(parts) if not parts.is_empty() else "nothing"


## A button was pressed. Returns true if it was one of ours.
func on_action(player, action: String) -> bool:
	if not action.begins_with("shop:"):
		return false
	var shop_name := String(_open.get(player.peer_id, ""))
	var kind: Dictionary = kinds.get(shop_name, {})
	if kind.is_empty():
		return true
	if not trade(player, shop_name, int(action.substr(5))):
		player.send_message(problem)
	_draw(player, kind)  # prices, stock and what they can afford have all just moved
	return true


func player_left(peer_id: int) -> void:
	_open.erase(peer_id)


## Stock is saved: a village whose shelves refill every restart is a village worth restarting for.
func to_saved() -> Dictionary:
	return _stock.duplicate(true)


func load_saved(saved) -> void:
	_stock.clear()
	if not (saved is Dictionary):
		return
	for key in saved:
		var state = saved[key]
		if state is Dictionary:
			_stock[String(key)] = {"left": maxi(int(state.get("left", 0)), 0), "at": float(state.get("at", 0.0))}
