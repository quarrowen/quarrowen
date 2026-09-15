extends RefCounted
## A simple chat filter for family and school servers (the `chat_filter` gameplay rule, --chat-filter=on):
## masks common swear words and slurs in chat, including spaced-out and look-alike spellings ("f u c k",
## "sh1t"). Servers add their own words, one per line, in <world>/chat_filter.txt. It is a courtesy, not a
## guarantee: determined players can get around any word list.

const EXTRA_FILE := "chat_filter.txt"

## Kept short and common; whole words and obvious stems only, so ordinary words are not caught.
const WORDS := [
	"fuck", "fucker", "fucking", "motherfucker", "shit", "shitty", "bullshit", "bitch", "bastard", "asshole",
	"dick", "dickhead", "cock", "cunt", "pussy", "twat", "wanker", "prick", "slut", "whore", "crap",
	"damn", "piss", "bollocks", "retard", "retarded", "fag", "faggot", "nigger", "nigga", "kys",
]
const LOOK_ALIKES := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i"}

var words := {}  # normalized word -> true


func _init() -> void:
	for w in WORDS:
		words[w] = true


## Adds the world's own words (one per line; # starts a comment).
func load_extra(world_dir: String) -> void:
	var path := world_dir.path_join(EXTRA_FILE)
	if not FileAccess.file_exists(path):
		return
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var w := _normalize(line.get_slice("#", 0).strip_edges())
		if w.length() >= 2:
			words[w] = true


## The text with filtered words replaced by asterisks (same length, first letter kept).
func clean(text: String) -> String:
	var out := text
	# Whole words, compared after undoing look-alikes and repeated letters ("shiiit").
	var regex := RegEx.create_from_string("[\\p{L}\\p{N}@$!]+")
	for m in regex.search_all(text):
		var token := m.get_string()
		if _matches(token):  # masks keep the length, so later match positions stay valid
			out = out.substr(0, m.get_start()) + _mask(token) + out.substr(m.get_end())
	# Spaced or dotted letters: "f u c k", "s.h.i.t".
	var spaced := RegEx.create_from_string("(?<![\\p{L}\\p{N}])(?:[\\p{L}\\p{N}@$!][ ._\\-*]){2,}[\\p{L}\\p{N}@$!](?![\\p{L}\\p{N}])")
	for m in spaced.search_all(out):
		var joined := m.get_string().replace(" ", "").replace(".", "").replace("_", "").replace("-", "").replace("*", "")
		if _matches(joined):
			out = out.substr(0, m.get_start()) + _mask(m.get_string()) + out.substr(m.get_end())
	return out


func is_clean(text: String) -> bool:
	return clean(text) == text


func _matches(token: String) -> bool:
	var n := _normalize(token)
	return words.has(n) or words.has(_squeeze(n))


static func _normalize(token: String) -> String:
	var out := ""
	for ch in token.to_lower():
		out += LOOK_ALIKES.get(ch, ch)
	return out


## "shiiiit" -> "shit"
static func _squeeze(word: String) -> String:
	var out := ""
	for ch in word:
		if out.is_empty() or out[out.length() - 1] != ch:
			out += ch
	return out


static func _mask(token: String) -> String:
	var out := token.substr(0, 1)
	for i in range(1, token.length()):
		out += " " if token[i] == " " else "*"
	return out
