# Guidebook and tutorials

Part of the [Mod API reference](../mod-api.md). Mod API 1.0.0 · game 0.42.0


### `api.register_guide_chapter`

GDScript: `api.register_guide_chapter(chapter_name: String, def := {}) -> bool`

JavaScript: `api.registerGuideChapter(chapterName, def)`

A guidebook chapter: {title, icon (item name), order, description}. Names without ":" are this mod's.

```gdscript
api.register_guide_chapter("proving", {"title": "The Proving Ground", "order": 1})
```

**See also:** `add_chapter`, `item`, `qualified`

### `api.register_guide_page`

GDScript: `api.register_guide_page(page_name: String, def: Dictionary) -> bool`

JavaScript: `api.registerGuidePage(pageName, def)`

A guidebook page (see engine/shared/guide_registry.gd): {chapter, title, icon, order, unlock: {item (a
name or a list of names, any of which opens it) |
recipe | entity | flag | page}, hint, keywords, blocks: [{type: text | heading | items | recipe |
entity | image | tip | link | keys, ...}]}. Item, entity, page and flag names without ":" are this
mod's; image blocks take a texture path in this mod.

```gdscript
api.register_guide_page("what", {"chapter": "proving", "title": "What this is",
	"content": [{"type": "text", "text": "A mod that exists to be tested."}]})
```

**See also:** `add_page`, `qualified`, `register_asset`

### `api.open_guide`

GDScript: `api.open_guide(player, page := "") -> void`

JavaScript: `api.openGuide(player, page)`

Opens the guidebook for a player at a page ("" = where they left off).

**See also:** `open`, `qualified`

### `api.set_guide_flag`

GDScript: `api.set_guide_flag(player, flag: String, on := true) -> void`

JavaScript: `api.setGuideFlag(player, flag, on)`

Guide flags unlock pages with `unlock: {flag}` (names without ":" are this mod's). Saved per player.

**See also:** `qualified`, `set_flag`

### `api.has_guide_flag`

GDScript: `api.has_guide_flag(player, flag: String) -> bool`

JavaScript: `api.hasGuideFlag(player, flag)`

Whether a player has a guide flag (see set_guide_flag).

**See also:** `has_flag`, `qualified`

### `api.unlock_guide_page`

GDScript: `api.unlock_guide_page(player, page: String, notify := true) -> bool`

JavaScript: `api.unlockGuidePage(player, page, notify)`

Unlocks a guide page for a player whatever its condition. Returns true if it was locked.

**See also:** `qualified`, `unlock`

### `api.is_guide_page_unlocked`

GDScript: `api.is_guide_page_unlocked(player, page: String) -> bool`

JavaScript: `api.isGuidePageUnlocked(player, page)`

Whether a guide page is open to a player.

**See also:** `is_unlocked`, `qualified`

### `api.register_tutorial`

GDScript: `api.register_tutorial(tutorial_name: String, def: Dictionary) -> bool`

JavaScript: `api.registerTutorial(tutorialName, def)`

A tutorial: guided goals completed by real actions (see engine/server/tutorials.gd for goal types):
{title, description, order, auto_start, reward: [[item, count]], steps: [{title, text, icon, goal: {type,
target, count, ...}, hint: {block | entity | position} or false, page, reward}]}. Names without ":" are
this mod's.

```gdscript
api.register_tutorial("basics", {"display_name": "Basics", "auto_start": true, "order": 1,
	"modes": ["survival"], "steps": [
	{"title": "Find a rock", "goal": {"type": "break", "target": ["proving:rock"]}},
	{"title": "Hold four", "goal": {"type": "have", "target": ["proving:rock"], "count": 4}},
	{"title": "Say when", "goal": {"type": "manual"}}]})
```

**See also:** `add_handler`, `announce`, `qualified`

### `api.register_tip`

GDScript: `api.register_tip(tip_name: String, def: Dictionary) -> bool`

JavaScript: `api.registerTip(tipName, def)`

A one-time contextual tip: {text, icon, page (guide page to read more), trigger: a goal}.

```gdscript
api.register_tip("basics", {"text": "Rock is the thing to dig", "trigger": {"type": "night"}})
```

**See also:** `add_handler`, `qualified`

### `api.start_tutorial`

GDScript: `api.start_tutorial(player, tutorial_name: String) -> bool`

JavaScript: `api.startTutorial(player, tutorialName)`

Starts (or restarts) a tutorial for a player. Returns false if it does not exist.

**See also:** `qualified`, `start`

### `api.stop_tutorial`

GDScript: `api.stop_tutorial(player) -> void`

JavaScript: `api.stopTutorial(player)`

Stops the player's running tutorial; it will not start by itself again.

**See also:** `step`, `stop`

### `api.advance_tutorial`

GDScript: `api.advance_tutorial(player) -> void`

JavaScript: `api.advanceTutorial(player)`

Completes the player's current tutorial step (for "manual" goals).

**See also:** `advance`

### `api.get_tutorial_state`

GDScript: `api.get_tutorial_state(player) -> Dictionary`

JavaScript: `api.getTutorialState(player)`

{active, step, progress, done: [ids]} for a player.

**See also:** `now`, `state_of`

### `api.show_tip`

GDScript: `api.show_tip(player, tip_name: String) -> bool`

JavaScript: `api.showTip(player, tipName)`

Shows a registered tip now (even if seen before).

**See also:** `icon_of`, `key_name`, `library`, `node_key`, `qualified`, `state_of`
