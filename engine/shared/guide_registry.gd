extends RefCounted
## The in-game guidebook: chapters and pages registered by mods, sent to clients with the content.
##
## Chapter: {id, title, icon (item name), order, description}
## Page: {id, chapter, title, icon (item name), order, unlock, hint, blocks, keywords}
##   unlock: {} (always) or one of {item: name} (picked up or held), {recipe: id} (known),
##           {entity: name} (seen nearby), {biome: name} (visited), {flag: name} (set by mods or tutorials), {page: id} (after
##           another page); locked pages show their title as "???" with `hint` (or a hint made from the
##           condition) saying what reveals them.
##   blocks, drawn top to bottom:
##     {type: "text", text}              paragraphs; [b]bold[/b], [i]italic[/i], [color=#hex] work
##     {type: "heading", text}
##     {type: "items", items: [names]}   a row of item icons with names (click one to look up recipes)
##     {type: "recipe", output: name}    the live recipe card(s) that make an item
##     {type: "entity", entity: name}    a turning 3D portrait of a mob
##     {type: "image", asset}            a picture (texture asset name)
##     {type: "tip", text}               a highlighted tip box
##     {type: "link", page, text}        a button to another page
##     {type: "keys", action, text}      "Press <key> to ..." using the player's key binding

const BLOCK_TYPES := ["text", "heading", "items", "recipe", "entity", "image", "tip", "link", "keys"]
const MAX_TEXT := 4000

var chapters: Array[Dictionary] = []
var pages: Array[Dictionary] = []
var _chapter_index := {}
var _page_index := {}


func add_chapter(def: Dictionary) -> bool:
	var id := str(def.get("id", ""))
	if id.is_empty():
		return false
	var c := {"id": id, "title": str(def.get("title", id.get_slice(":", 1).capitalize())).left(64), "icon": str(def.get("icon", "")).left(128),
		"order": float(def.get("order", 100.0)), "description": str(def.get("description", "")).left(300)}
	if _chapter_index.has(id):
		chapters[_chapter_index[id]] = c
	else:
		_chapter_index[id] = chapters.size()
		chapters.append(c)
	return true


func add_page(def: Dictionary) -> bool:
	var id := str(def.get("id", ""))
	if id.is_empty():
		return false
	var blocks := []
	for b in (def.get("blocks") if def.get("blocks") is Array else []):
		if b is Dictionary and str(b.get("type", "")) in BLOCK_TYPES:
			var clean := {}
			for key in b:
				var v = b[key]
				clean[str(key)] = str(v).left(MAX_TEXT) if v is String else v
			blocks.append(clean)
	var unlock: Dictionary = {}
	if def.get("unlock") is Dictionary:
		for key in ["item", "recipe", "entity", "biome", "flag", "page"]:
			if def.unlock.has(key):
				unlock = {key: str(def.unlock[key])}
				break
	var p := {"id": id, "chapter": str(def.get("chapter", "")), "title": str(def.get("title", id.get_slice(":", 1).capitalize())).left(64),
		"icon": str(def.get("icon", "")).left(128), "order": float(def.get("order", 100.0)), "unlock": unlock, "hint": str(def.get("hint", "")).left(200), "blocks": blocks,
		"keywords": str(def.get("keywords", "")).left(300)}
	if _page_index.has(id):
		pages[_page_index[id]] = p
	else:
		_page_index[id] = pages.size()
		pages.append(p)
	return true


func get_page(id: String) -> Dictionary:
	return pages[_page_index[id]] if _page_index.has(id) else {}


func get_chapter(id: String) -> Dictionary:
	return chapters[_chapter_index[id]] if _chapter_index.has(id) else {}


## Pages of a chapter in order.
func chapter_pages(chapter_id: String) -> Array:
	var out := pages.filter(func(p): return p.chapter == chapter_id)
	out.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else a.title < b.title)
	return out


func sorted_chapters() -> Array:
	var out := chapters.duplicate()
	out.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else a.title < b.title)
	return out


## Plain searchable text of a page (title, keywords and text blocks).
static func page_text(page: Dictionary) -> String:
	var parts := PackedStringArray([page.title, page.keywords])
	for b in page.blocks:
		for key in ["text", "items", "output", "entity"]:
			if b.has(key):
				parts.append(str(b[key]))
	return " ".join(parts).to_lower()


func to_network() -> Dictionary:
	return {"chapters": chapters, "pages": pages}


func load_network(data) -> void:
	if not (data is Dictionary):
		return
	for c in (data.get("chapters") if data.get("chapters") is Array else []):
		if c is Dictionary:
			add_chapter(c)
	for p in (data.get("pages") if data.get("pages") is Array else []):
		if p is Dictionary:
			add_page(p)
