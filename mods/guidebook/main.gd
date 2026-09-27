extends "res://engine/server/mod.gd"
## The Survival Guide: the book that explains the other packs.
##
## **Its own mod, because it is the only shape that is honest.** The guide teaches wood, then the
## crafting table, then armour and the Toolsmith's Bench - so it names content from `base`,
## `simple_machines` *and* `simple_gear`. It cannot live in any one of them without that pack
## depending on a pack above it: it started in `base`, moved to `simple_machines` on 2026-09-23 and
## immediately made `simple_machines` name `simple_gear:iron_pickaxe`, which the validator caught.
## A thing that documents three packs depends on three packs. (2026-09-23)
##
## **It stays here, and that question is now closed.** (2026-09-27) The note this paragraph replaces
## said it was here "under protest" and would move into a guided game as soon as one existed. One does -
## `firstlight` - and moving it there would have been wrong, for a reason that only became visible once
## there were three games to look at rather than none:
##
## - Every page in this mod is about `base`, `simple_machines` or `simple_gear`. **Not one is about
##   Firstlight.** There is nothing in here a game owns.
## - It documents nouns, and the line this project draws is that `base` owns nouns and a game owns
##   rules. A reference to the nouns sits on the noun side of that line.
## - Inside `firstlight` the page ids become `firstlight:*`, and then `creative` and `oneblock` - which
##   use the very same three packs - can only have a guidebook by depending on a *game*. A game
##   depending on a game is the thing the split was done to avoid.
##
## So the honest shape was the one it already had, and the original reasoning was right for a reason it
## had not quite named: **a library is what you call content that is not any one game's.** What is still
## true is the narrower complaint underneath it - the book explains three packs and nothing explains
## `firstlight` itself, whose subjects (the lantern, the ruin, the Colossus) have no pages at all. That
## is a gap in the *writing* and not in where the file lives.

const Guide = preload("guide.gd")

var guide := Guide.new()


func setup(api) -> void:
	guide.setup(api)
