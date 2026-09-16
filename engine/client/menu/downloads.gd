extends Node
## One HTTPRequest and two awaitable calls, shared by everything in the menu that fetches from the
## project's own site: the update check and the mod list.
##
## Nothing here decides *what* may be fetched. Callers check the address against Updater.url_allowed and
## the bytes against a checksum they already have - a download is only ever trusted because the manifest
## or the mod index said what it should be.

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 30.0
	add_child(_http)


## GETs a small text file (a manifest, an index). "" if anything went wrong.
func fetch(url: String) -> String:
	_http.cancel_request()
	_http.download_file = ""
	if _http.request(url) != OK:
		return ""
	var result: Array = await _http.request_completed
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		return ""
	return (result[3] as PackedByteArray).get_string_from_utf8()


## GETs a file, through a file on disk so a large zip is not held in memory twice. Empty if it failed.
func download(url: String, into_dir: String) -> PackedByteArray:
	_http.cancel_request()
	var dir := ProjectSettings.globalize_path(into_dir)
	var path := dir.path_join("download-%d.part" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	_http.download_file = path
	if _http.request(url) != OK:
		_http.download_file = ""
		return PackedByteArray()
	var result: Array = await _http.request_completed
	_http.download_file = ""
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		DirAccess.remove_absolute(path)
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	return bytes
