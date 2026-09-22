extends RefCounted
## Other companies' product names, and the handful of places they are allowed to appear.
##
## The rule is in CLAUDE.md's house style and has now been broken twice by the same person in the same
## week: once naming games while discussing a look, and once naming a documentation library while
## copying its page layout - that second one because the rule said "games", and a documentation
## library is not a game, so it read as not applying. Rewording it a third time is the response with
## the worst record of anything available, so this is a check instead. (2026-09-22)
##
## **Keeping the list in a gitignored file was considered and rejected.** It would not reach anybody
## else working on this, it would not run in CI, and it is the same kind of protection that has already
## failed twice - prose somebody has to remember. It would also hide nothing: the names are necessarily
## public in this repository already, in the trademark disclaimers that have to name a mark in order to
## disclaim it.
##
## Regenerate nothing; this either passes or names what to fix:
##   godot --headless --path . res://tools/mod_tool.tscn -- trademarks

## Matched case-insensitively against every scanned line.
##
## **Precision matters more than coverage here.** A first attempt matched a bare "forge" and reported
## eight offences that were all a blacksmith's forge or the word "forgets"; a check that cries wolf
## gets switched off. So: whole distinctive words, and phrases where the bare word is ordinary English.
const NAMES := [
	"minecraft", "mojang", "roblox", "microsoft", "msdn",
	"neoforge", "curseforge", "forgegradle", "optifine", "modrinth", "fabricmc",
	"forge mod", "forge loader", "fabric mod", "fabric loader",
	"java edition", "bedrock edition",
]

## Names that are ordinary words elsewhere, so they are matched with case and word boundaries.
const EXACT_CASE := ["Eco"]

## Where a mark may be named, because a disclaimer has to name the thing it disclaims.
##
## This list is the whole exception. Adding to it means a new place makes a trademark statement, which
## should be rare and deliberate; it is not for "this file happens to mention one".
const ALLOWED := [
	"LICENSE", "README.md", "docs/faq.md",
	"tools/make_release.sh", "tools/generate_icon.py", "tools/trademarks.gd",
	"engine/client/menu/main_menu.gd",
	"tests/trademark_test.gd",
]

## Ends a commit record in the log output. Plain text on purpose; see `offences_in_commits`.
const END := "@@quarrowen-end-of-commit@@"

const SCANNED := [".md", ".gd", ".sh", ".py", ".js", ".json", ".txt"]
## Not scanned: build output (copies of old games that predate the rule), vendored code, and anything
## generated into .godot. Relative to the root, so it works whatever path the scan is started from.
const SKIPPED_DIRS := [".git", "build", ".godot", "native/target", "addons", "services"]


## Lines naming a mark outside the places allowed to, as "path:line: term".
static func offences_in_files(root := ".") -> Array:
	var out: Array = []
	var base := root.trim_suffix("/") + "/"
	for path: String in _files(root):
		var relative: String = path.trim_prefix(base).trim_prefix("./")
		if relative in ALLOWED or _skipped(relative):
			continue
		var line_number := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			line_number += 1
			var found := _named_in(String(line))
			if not found.is_empty():
				out.append("%s:%d: %s" % [relative, line_number, found])
	out.sort()
	return out


## The same check over recent commit messages, which is where it was broken twice and where nothing was
## looking. Messages cannot be fixed after a push, so this is worth catching while it is still local.
static func offences_in_commits(count := 40) -> Array:
	var output := []
	# One record per commit, ended by a sentinel no message will contain.
	#
	# **Not a NUL separator**, which is the obvious choice and does not survive `OS.execute` - the
	# output comes back with the bytes gone, every record parses as unsplittable, and the check quietly
	# reports nothing at all. That is worse than the bug it replaced: a check that passes for the wrong
	# reason is indistinguishable from one that works, and this one was proven only by testing it again
	# after the "fix". (2026-09-22)
	if OS.execute("git", ["log", "-n", str(count), "--format=%h%n%B%n" + END], output, true) != 0:
		return []  # not a checkout, or no git: not this check's business to fail over
	var out: Array = []
	for record in String("\n".join(output)).split(END, false):
		var lines := String(record).strip_edges().split("\n")
		if lines.is_empty():
			continue
		var hash: String = String(lines[0]).strip_edges()
		for i in range(1, lines.size()):
			var found := _named_in(String(lines[i]))
			if not found.is_empty():
				out.append("commit %s: %s" % [hash, found])
				break
	out.sort()
	return out


## The mark named in this line, or "".
static func _named_in(line: String) -> String:
	var lowered := line.to_lower()
	for name: String in NAMES:
		if lowered.contains(name):
			return name
	for name: String in EXACT_CASE:
		# Word boundaries and real case, so "ecosystem" and "economy" are left alone.
		var at := line.find(name)
		while at >= 0:
			var before := line[at - 1] if at > 0 else " "
			var after := line[at + name.length()] if at + name.length() < line.length() else " "
			if not _wordish(before) and not _wordish(after):
				return name
			at = line.find(name, at + 1)
	return ""


static func _wordish(c: String) -> bool:
	return c.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_"


## Whether this path is under a directory we do not scan.
static func _skipped(relative: String) -> bool:
	for dir: String in SKIPPED_DIRS:
		if relative == dir or relative.begins_with(dir + "/"):
			return true
	# A *.local.* file is somebody's own notes and is gitignored; it never ships.
	return relative.contains(".local.")


static func _files(root: String) -> Array:
	var out: Array = []
	var dirs: Array = [root]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for name in DirAccess.get_directories_at(dir):
			if String(name).begins_with("."):
				continue
			dirs.append(dir.path_join(name))
		for name in DirAccess.get_files_at(dir):
			for suffix: String in SCANNED:
				if String(name).ends_with(suffix):
					out.append(dir.path_join(name))
					break
	return out
