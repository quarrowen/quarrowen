extends RefCounted
## Content-addressed cache for server assets. Files are named by their SHA-256, so assets shared
## between servers are downloaded once and a server can never overwrite another server's files.

const DIR := "user://cache/assets"


static func is_valid_hash(hash: String) -> bool:
	if hash.length() != 64:
		return false
	for c in hash:
		if not (c in "0123456789abcdef"):
			return false
	return true


static func has(hash: String) -> bool:
	return is_valid_hash(hash) and FileAccess.file_exists(_path(hash))


static func read(hash: String) -> PackedByteArray:
	if not is_valid_hash(hash):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(_path(hash))


static func store(hash: String, bytes: PackedByteArray) -> bool:
	if not is_valid_hash(hash) or sha256(bytes) != hash:
		return false
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(_path(hash), FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	return true


static func sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


static func _path(hash: String) -> String:
	return "%s/%s.bin" % [DIR, hash]
