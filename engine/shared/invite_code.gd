extends RefCounted
## Invite codes: a short, readable way to share a server address. An IPv4 address and port pack into
## 6 bytes, written as 10 Crockford base32 characters with a check character: "QW-7ZK3M-Q8D1A-4".
## Anything else (host names, IPv6) is shared as a plain "host:port" text, which `parse` also accepts.
## Servers listed on a hub also have a short hub code, "QW-ABC-123": `parse` returns {hub_code} for those,
## to be resolved through the hub (engine/client/menu/hub_client.gd).

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const PREFIX := "QW-"
## A code read aloud and typed back in often arrives with a space where the hyphen was.
const OLD_PREFIXES := ["QW "]
const DEFAULT_PORT := 24565


## The code for an IPv4 address, or "" when the address is not IPv4.
static func encode(address: String, port: int) -> String:
	var parts := address.split(".")
	if parts.size() != 4 or not address.is_valid_ip_address():
		return ""
	var value := 0
	for p in parts:
		value = (value << 8) | (int(p) & 255)
	value = (value << 16) | (port & 65535)
	var chars := ""
	for i in 10:
		chars = ALPHABET[value & 31] + chars
		value >>= 5
	return "%s%s-%s-%s" % [PREFIX, chars.substr(0, 5), chars.substr(5, 5), ALPHABET[_check(chars)]]


## What someone shares: an invite code when possible, else "address:port".
static func share_text(address: String, port: int) -> String:
	var code := encode(address, port)
	if not code.is_empty():
		return code
	return address if port == DEFAULT_PORT else "%s:%d" % [address, port]


## {address, port} from a code or "host[:port]" text, or {error}.
static func parse(text: String) -> Dictionary:
	var t := text.strip_edges()
	if t.is_empty():
		return {"error": "enter an address or invite code"}
	var upper := t.to_upper()
	var prefix := PREFIX if upper.begins_with(PREFIX) else ""
	if prefix.is_empty():
		for old in OLD_PREFIXES:
			if upper.begins_with(old):
				prefix = old
				break
	if not prefix.is_empty():
		var chars := upper.substr(prefix.length()).replace("-", "").replace(" ", "")
		# Crockford: accept look-alikes.
		chars = chars.replace("O", "0").replace("I", "1").replace("L", "1")
		if chars.length() == 6:
			for c in chars:
				if not ALPHABET.contains(c):
					return {"error": "that invite code has a wrong character"}
			return {"hub_code": "%s%s-%s" % [PREFIX, chars.substr(0, 3), chars.substr(3)]}  # a hub code: ask the hub
		if chars.length() != 11:
			return {"error": "that invite code is not complete"}
		for c in chars:
			if not ALPHABET.contains(c):
				return {"error": "that invite code has a wrong character"}
		if ALPHABET[_check(chars.substr(0, 10))] != chars[10]:
			return {"error": "that invite code has a typo"}
		var value := 0
		for i in 10:
			value = (value << 5) | ALPHABET.find(chars[i])
		var port := value & 65535
		value >>= 16
		return {"address": "%d.%d.%d.%d" % [(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255], "port": port}
	var address := t
	var port := DEFAULT_PORT
	if t.begins_with("["):  # [ipv6]:port
		var close := t.find("]")
		if close < 0:
			return {"error": "that address is not valid"}
		address = t.substr(1, close - 1)
		if t.length() > close + 2 and t[close + 1] == ":":
			port = int(t.substr(close + 2))
	elif t.count(":") == 1:
		address = t.get_slice(":", 0)
		var port_text := t.get_slice(":", 1)
		if not port_text.is_valid_int():
			return {"error": "the port must be a number"}
		port = int(port_text)
	if port < 1 or port > 65535:
		return {"error": "the port must be between 1 and 65535"}
	if address.is_empty() or address.contains(" ") or address.contains("/"):
		return {"error": "that address is not valid"}
	return {"address": address, "port": port}


static func _check(chars: String) -> int:
	var sum := 0
	for i in chars.length():
		sum = (sum * 31 + ALPHABET.find(chars[i]) + i) % 32
	return sum


## The first private IPv4 address of this computer (to invite people on the same network), or "".
static func local_address() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and int(a.get_slice(".", 1)) >= 16 and int(a.get_slice(".", 1)) <= 31):
			return a
	return ""
