extends RefCounted
## Semantic versions ("1.4.2", "2.0.0-beta.1") and version ranges for mod dependencies.
##
## Ranges (npm-style, the common subset):
##   "1.2.3" or "=1.2.3"   exactly          "*" or ""        anything
##   "^1.2.3"              >=1.2.3 <2.0.0 (for 0.x: >=0.2.3 <0.3.0)
##   "~1.2.3"              >=1.2.3 <1.3.0
##   ">=1.2" "<2" ">1.0.0" "<=1.9"           comparisons (missing parts are 0)
##   "1.x" "1.2.x"         wildcards
##   ">=1.2 <2"            space = and       "^1.0 || ^2.0"   || = or
## Pre-releases sort before their release (1.0.0-beta < 1.0.0).

## [major, minor, patch, prerelease] or [] when not a version.
static func parse(text: String) -> Array:
	var t := text.strip_edges().trim_prefix("v")
	var pre := ""
	var build := t.find("+")
	if build >= 0:
		t = t.left(build)
	var dash := t.find("-")
	if dash >= 0:
		pre = t.substr(dash + 1)
		t = t.left(dash)
	var parts := t.split(".")
	if parts.is_empty() or parts.size() > 3:
		return []
	var nums := []
	for p in parts:
		if not p.is_valid_int() or int(p) < 0:
			return []
		nums.append(int(p))
	while nums.size() < 3:
		nums.append(0)
	nums.append(pre)
	return nums


static func is_valid(text: String) -> bool:
	var v := parse(text)
	return not v.is_empty() and text.strip_edges().trim_prefix("v").split("-")[0].split(".").size() == 3


## -1, 0 or 1.
static func compare(a: String, b: String) -> int:
	return _cmp(parse(a), parse(b))


static func _cmp(x: Array, y: Array) -> int:
	if x.is_empty() or y.is_empty():
		return 0
	for i in 3:
		if x[i] != y[i]:
			return -1 if x[i] < y[i] else 1
	if x[3] == y[3]:
		return 0
	if x[3] == "":
		return 1
	if y[3] == "":
		return -1
	return -1 if str(x[3]) < str(y[3]) else 1


## Whether `version` satisfies `range_text`.
static func satisfies(version: String, range_text: String) -> bool:
	var v := parse(version)
	if v.is_empty():
		return false
	var r := range_text.strip_edges()
	if r.is_empty() or r == "*" or r == "x":
		return true
	for alternative in r.split("||"):
		var ok := true
		for term in alternative.strip_edges().split(" ", false):
			if not _term(v, term):
				ok = false
				break
		if ok:
			return true
	return false


## Whether a range string can be understood at all ("" when fine, else the problem).
static func range_error(range_text: String) -> String:
	var r := range_text.strip_edges()
	if r.is_empty() or r == "*":
		return ""
	for alternative in r.split("||"):
		if alternative.strip_edges().is_empty():
			return "empty alternative in '%s'" % range_text
		for term in alternative.strip_edges().split(" ", false):
			var body := term.lstrip("^~<>=")
			if body.contains("x"):
				body = body.replace(".x", "").replace("x", "0")
			if body.is_empty() or parse(body).is_empty():
				return "'%s' is not a version range" % term
	return ""


static func _term(v: Array, term: String) -> bool:
	var op := ""
	for candidate in [">=", "<=", "^", "~", ">", "<", "="]:
		if term.begins_with(candidate):
			op = candidate
			break
	var body := term.substr(op.length())
	if body.contains("x") or body.contains("*"):
		# 1.x, 1.2.x: the given parts must match.
		var parts := body.split(".")
		for i in mini(parts.size(), 3):
			if parts[i] in ["x", "*", "X"]:
				return true
			if not parts[i].is_valid_int() or int(parts[i]) != v[i]:
				return false
		return true
	var given := body.split("-")[0].split(".").size()
	var t := parse(body)
	if t.is_empty():
		return false
	var c := _cmp(v, t)
	match op:
		">=": return c >= 0
		"<=": return c <= 0
		">": return c > 0
		"<": return c < 0
		"^":
			if c < 0:
				return false
			if t[0] > 0 or given == 1:
				return v[0] == t[0]
			if t[1] > 0 or given == 2:
				return v[0] == 0 and v[1] == t[1]
			return v[0] == 0 and v[1] == 0 and v[2] == t[2]
		"~":
			if c < 0:
				return false
			return v[0] == t[0] and (given == 1 or v[1] == t[1])
	# Exact (missing parts match anything: "1.2" means 1.2.x).
	if given < 3:
		return v[0] == t[0] and (given == 1 or v[1] == t[1])
	return c == 0 and v[3] == t[3]
