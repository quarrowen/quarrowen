extends RefCounted
## Roles and permissions. Every player has the default role (member unless --default-role says otherwise)
## plus any assigned roles; a role grants permissions and can inherit another role's.
##
## Permissions are dotted names: "build", "interact", "chat", "creative", "ugc.review", "allowlist.manage",
## "dev.tools", "moderation.alerts", "roles.manage", "roles.owner", "admin", "command.<name>" for commands
## registered as admin-only, and anything mods register. "*" grants everything, "ugc.*" a whole group, and a
## leading "-" denies ("-build"); a denial anywhere in a player's roles wins over grants.
##
## Built-in roles can be edited (their changes are saved); custom roles are created with /role create.
## Saved in world.json: roles {name: {permissions, inherits, tag, color, priority}} and player_roles {id: [names]}.

## The six roles every server starts with, in order of how much they may do.
##
## Each carries a `description`: one plain sentence saying **who the role is for**, which is a different
## question from what it may do. A list of permissions answers "what happens if I give somebody this",
## and a person deciding between "builder" and "moderator" for their child's friend is not asking that.
## The permission list was always shown and the sentence never was. (2026-09-22)
const BUILTIN := {
	"owner": {"permissions": ["*"], "inherits": "", "tag": "Owner", "color": "#ffb020", "priority": 100,
		"description": "Whoever runs the server. Can do everything, including making somebody else an owner."},
	"admin": {"permissions": ["*", "-roles.owner"], "inherits": "", "tag": "Admin", "color": "#ff6b6b", "priority": 90,
		"description": "A grown-up helping run the place. Everything an owner can do except handing out the owner role."},
	"moderator": {"permissions": ["command.kick", "command.players", "command.tp", "command.clearmobs", "command.ugc", "ugc.review",
		"command.allow", "allowlist.manage", "moderation.alerts", "command.transfer"], "inherits": "builder", "tag": "Mod", "color": "#6bb8ff", "priority": 50,
		"description": "Keeps the peace: can kick, teleport, manage who is allowed in, and review what players have made. Cannot change the world's settings."},
	"builder": {"permissions": ["command.struct", "structures"], "inherits": "member", "tag": "Builder", "color": "#8fd88f", "priority": 30,
		"description": "A trusted player who may also save and stamp structures. For somebody building a lot."},
	"member": {"permissions": ["build", "interact", "chat", "creative"], "inherits": "visitor", "tag": "", "color": "", "priority": 10,
		"description": "An ordinary player: builds, uses things, talks. This is what new players get."},
	"visitor": {"permissions": ["chat", "interact"], "inherits": "", "tag": "Guest", "color": "#aaaaaa", "priority": 0,
		"description": "Can look around, use doors and chests, and talk - but cannot build. For somebody you do not know yet."},
}
const MAX_ROLES := 64
const MAX_PERMISSIONS := 128

## Known permissions and what they mean (built-in and mod-registered), for /role info and the admin panel.
var descriptions := {
	"*": "everything",
	"admin": "counts as an admin for mods and alerts",
	"build": "break and place blocks",
	"interact": "use doors, chests, stations and other blocks",
	"chat": "talk in chat",
	"creative": "switch to creative mode",
	"fly": "fly in survival (creative mode always allows it)",
	"structures": "save and place structures",
	"ugc.review": "review, approve and remove player creations",
	"allowlist.manage": "add and remove players on the allowlist",
	"moderation.alerts": "see reports and error alerts",
	"dev.tools": "the developer tools (F8)",
	"roles.manage": "give and take roles (below their own)",
	"roles.owner": "give the owner role and edit roles",
	"command.<name>": "an admin-only command",
}
var default_role := "member"

var _server


func _init(game_server) -> void:
	_server = game_server


func _meta() -> Dictionary:
	var meta: Dictionary = _server._meta
	if not (meta.get("roles") is Dictionary):
		meta.roles = {}
	if not (meta.get("player_roles") is Dictionary):
		meta.player_roles = {}
	return meta


## Applies the admins named in the server's configuration as owners, every start: the config is the
## authority on who runs the server, so it is reapplied rather than migrated once.
func apply_config_admins(config_admins: Dictionary) -> void:
	var meta := _meta()
	for key: String in config_admins:
		var id: String = key if key.length() == 32 and key.is_valid_hex_number() else str(meta.names.get(key, ""))
		if not id.is_empty():
			give(id, "owner")


# --- Roles ----------------------------------------------------------------------------------------

func role_names() -> Array:
	var names := BUILTIN.keys()
	for name: String in _meta().roles:
		if not names.has(name):
			names.append(name)
	names.sort_custom(func(a, b): return int(role(a).priority) > int(role(b).priority))
	return names


## A role's definition (saved changes over the built-in one), or {}.
func role(role_name: String) -> Dictionary:
	var saved = _meta().roles.get(role_name)
	if saved is Dictionary:
		var out: Dictionary = BUILTIN.get(role_name, {"permissions": [], "inherits": "", "tag": "", "color": "", "priority": 20, "description": ""}).duplicate(true)
		out.merge(saved, true)
		return out
	return BUILTIN.get(role_name, {}).duplicate(true)


func exists(role_name: String) -> bool:
	return BUILTIN.has(role_name) or _meta().roles.has(role_name)


func create(role_name: String, inherits := "member") -> String:
	var clean := role_name.to_lower().strip_edges()
	if not clean.is_valid_identifier():
		return "role names are letters, digits and _"
	if exists(clean):
		return "there is already a role called %s" % clean
	if _meta().roles.size() >= MAX_ROLES:
		return "too many roles"
	if not inherits.is_empty() and not exists(inherits):
		return "there is no role called %s" % inherits
	_meta().roles[clean] = {"permissions": [], "inherits": inherits, "tag": clean.capitalize(), "color": "", "priority": 20}
	return ""


func delete(role_name: String) -> String:
	if BUILTIN.has(role_name):
		return "built-in roles cannot be deleted (reset them with /role reset)"
	if not _meta().roles.has(role_name):
		return "there is no role called %s" % role_name
	_meta().roles.erase(role_name)
	for id: String in _meta().player_roles:
		_meta().player_roles[id].erase(role_name)
	return ""


## Adds ("build") or denies ("-build") a permission on a role; `remove` takes an entry away instead.
func set_permission(role_name: String, permission: String, remove := false) -> String:
	if not exists(role_name):
		return "there is no role called %s" % role_name
	var def := role(role_name)
	var perms: Array = def.permissions.duplicate()
	var clean := permission.strip_edges().to_lower()
	if clean.is_empty() or clean.length() > 64:
		return "that is not a permission"
	if remove:
		perms.erase(clean)
	else:
		perms.erase(clean.trim_prefix("-") if clean.begins_with("-") else "-" + clean)
		if not perms.has(clean):
			if perms.size() >= MAX_PERMISSIONS:
				return "that role has too many permissions"
			perms.append(clean)
	_save_role(role_name, {"permissions": perms})
	return ""


func set_look(role_name: String, tag: String, color: String) -> void:
	_save_role(role_name, {"tag": tag.left(12), "color": color if color.is_empty() or Color.html_is_valid(color) else ""})


func reset(role_name: String) -> void:
	if BUILTIN.has(role_name):
		_meta().roles.erase(role_name)


func _save_role(role_name: String, changes: Dictionary) -> void:
	var saved: Dictionary = _meta().roles.get(role_name, {})
	saved.merge(changes, true)
	_meta().roles[role_name] = saved


# --- Players --------------------------------------------------------------------------------------

## A player's roles: assigned ones plus the default role.
func roles_of(player_id: String) -> Array:
	var assigned: Array = _meta().player_roles.get(player_id, [])
	var out := assigned.filter(func(r): return exists(r))
	if not out.has(default_role) and exists(default_role):
		out.append(default_role)
	out.sort_custom(func(a, b): return int(role(a).priority) > int(role(b).priority))
	return out


func give(player_id: String, role_name: String) -> bool:
	if player_id.is_empty() or not exists(role_name):
		return false
	var list: Array = _meta().player_roles.get(player_id, [])
	if list.has(role_name):
		return false
	list.append(role_name)
	_meta().player_roles[player_id] = list
	return true


func take(player_id: String, role_name: String) -> bool:
	var list: Array = _meta().player_roles.get(player_id, [])
	if not list.has(role_name):
		return false
	list.erase(role_name)
	if list.is_empty():
		_meta().player_roles.erase(player_id)
	return true


## Every permission entry a player's roles give, following inheritance.
func entries_of(player_id: String) -> Array:
	var out := []
	var seen := {}
	var todo := roles_of(player_id)
	while not todo.is_empty():
		var r: String = todo.pop_front()
		if seen.has(r) or not exists(r):
			continue
		seen[r] = true
		var def := role(r)
		out.append_array(def.permissions)
		if not str(def.inherits).is_empty():
			todo.append(def.inherits)
	return out


func has(player_id: String, permission: String) -> bool:
	return allows(entries_of(player_id), permission)


## Whether a set of entries grants a permission: a matching denial wins; "*" and "group.*" match.
static func allows(entries: Array, permission: String) -> bool:
	var granted := false
	for entry: String in entries:
		var deny := entry.begins_with("-")
		var pattern := entry.trim_prefix("-")
		if _matches(pattern, permission):
			if deny:
				return false
			granted = true
	return granted


static func _matches(pattern: String, permission: String) -> bool:
	if pattern == "*" or pattern == permission:
		return true
	return pattern.ends_with(".*") and permission.begins_with(pattern.trim_suffix("*"))


## The highest role with a tag, for chat: {tag, color} or {}.
func badge(player_id: String) -> Dictionary:
	for r in roles_of(player_id):
		var def := role(r)
		if not str(def.tag).is_empty():
			return {"tag": def.tag, "color": def.color, "role": r}
	return {}


## The highest priority among a player's roles (a manager can only hand out roles below their own).
func rank(player_id: String) -> int:
	var best := -1
	for r in roles_of(player_id):
		best = maxi(best, int(role(r).priority))
	return best
