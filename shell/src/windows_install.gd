extends Node

signal changed()
signal opened()
signal closed()

const InstallScreen = preload("res://src/windows_install_screen.gd")
const ACTIVE := ["queued", "downloading", "verifying", "installing"]
var helper := "/usr/lib/marwanos/windows/manager.py"
var local_jobs: Array = []
var _local_signature := ""
var _local_libraries: Array = []
var _local_launch := ""
var snapshot: Dictionary = {}
var available := false
var home := ""
var message := ""
var _screen: Control = null
var _signature := ""
var _pending_until := 0


func _ready() -> void:
	if not OS.get_environment("MARWANOS_WINDOWS_HELPER").is_empty():
		helper = OS.get_environment("MARWANOS_WINDOWS_HELPER")
	home = OS.get_environment("MARWANOS_WINDOWS_HOME")
	if home.is_empty():
		home = OS.get_environment("HOME").path_join(".local/share/marwanos/windows")
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()
	Launcher.launch_finished.connect(_local_finished)


func is_open() -> bool:
	return is_instance_valid(_screen)


func is_busy() -> bool:
	return not _local_launch.is_empty() or (available and ACTIVE.has(str(snapshot.get("status", "")))) or Time.get_ticks_msec() < _pending_until


func local_install(path: String, portable: bool = false) -> void:
	if is_busy() or Launcher.is_busy():
		message = "Finish the current installation first."
		changed.emit()
		return
	if not FileAccess.file_exists(helper):
		message = "Windows setup needs the updated system helper. Update this machine to continue."
		changed.emit()
		return
	_local_launch = "local-%d-%d" % [Time.get_ticks_usec(), randi()]
	message = ""
	Launcher.launch({"id": _local_launch, "title": "Setup: " + path.get_file(),
		"exec": [helper, "portable" if portable else "setup", _local_launch, path],
		"stop_exec": [helper, "stop", _local_launch], "input_mode": "pointer",
		"window_deadline": 600.0, "state": "installed", "icon": ""})


func _local_finished(entry: Dictionary) -> void:
	if str(entry.get("id", "")) != _local_launch or _local_launch.is_empty():
		return
	var key := _local_launch
	_local_launch = ""
	_poll_local()
	if not FileAccess.file_exists(home.path_join("jobs/" + key + ".json")):
		message = "Windows setup could not start. Check the system helper and try again."
	changed.emit()


func register_local(key: String, choice: String) -> void:
	if OS.create_process(helper, ["register", key, choice]) <= 0:
		message = "Could not add this program. Try again."
		changed.emit()


func _json_files(directory: String) -> Array:
	var result: Array = []
	if not DirAccess.dir_exists_absolute(directory):
		return result
	for name in DirAccess.get_files_at(directory):
		if not name.ends_with(".json"):
			continue
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(name)))
		if value is Dictionary:
			result.append(value)
	return result


func _poll_local() -> void:
	var jobs := _json_files(home.path_join("jobs"))
	var apps: Array = []
	for app in _json_files(home.path_join("apps")):
		if FileAccess.file_exists(str(app.get("executable", ""))):
			apps.append(app)
	var signature := JSON.stringify([jobs, apps])
	if signature != _local_signature:
		_local_signature = signature
		local_jobs = jobs
		_local_libraries = apps
		changed.emit()


func open() -> void:
	if is_open() or Launcher.is_busy() or Settings.is_open() or Power.is_open() or Info.is_open() or Files.is_open() or Browser.is_open():
		return
	_screen = InstallScreen.new()
	_screen.closed.connect(_finish, CONNECT_ONE_SHOT)
	opened.emit()
	get_tree().root.add_child(_screen)
	ShellLog.info("Windows installation screen opened")


func _finish() -> void:
	_finish_deferred.call_deferred()


func _finish_deferred() -> void:
	if is_instance_valid(_screen):
		_screen.get_parent().remove_child(_screen)
		_screen.queue_free()
	_screen = null
	closed.emit()


func install(recipe_id: String, source_id: String = "download") -> void:
	if is_busy():
		return
	_request({"verb": "install", "recipe_id": recipe_id, "source_id": source_id})


func cancel() -> void:
	if not ACTIVE.has(str(snapshot.get("status", ""))):
		return
	_request({"verb": "cancel", "job_id": str(snapshot.get("job_id", ""))})


func _request(request: Dictionary) -> void:
	if not available:
		message = "Installation is unavailable. Try again in a moment."
		changed.emit()
		return
	var directory := home.path_join("requests")
	var path := directory.path_join("%d-%d.json" % [Time.get_ticks_usec(), randi()])
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		message = "Could not start the request. Try again."
		changed.emit()
		return
	file.store_string(JSON.stringify(request))
	file.close()
	FileAccess.set_unix_permissions(path + ".tmp", 384)
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		DirAccess.remove_absolute(path + ".tmp")
		message = "Could not start the request. Try again."
	else:
		_pending_until = Time.get_ticks_msec() + 10000
		message = "Cancelling installation…" if request["verb"] == "cancel" else "Starting installation…"
		ShellLog.info("Windows request: %s" % JSON.stringify(request))
	changed.emit()


func _poll() -> void:
	_poll_local()
	var value: Variant = null
	var path := home.path_join("state.json")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			value = JSON.parse_string(file.get_as_text())
	var next: Dictionary = value if value is Dictionary else {}
	var age := Time.get_unix_time_from_system() - float(next.get("heartbeat", 0))
	var live := age >= -5 and age < 15
	next.erase("heartbeat")
	var signature := JSON.stringify(next) + str(live)
	var pending_expired := _pending_until > 0 and Time.get_ticks_msec() >= _pending_until
	if signature == _signature and not pending_expired:
		return
	_signature = signature
	snapshot = next
	available = live
	_pending_until = 0
	message = ""
	changed.emit()


func library() -> Array:
	var entries: Variant = snapshot.get("library", [])
	var result: Array = entries.duplicate() if entries is Array else []
	for app in _local_libraries:
		var found := false
		for entry in result:
			if entry.get("id") == app.get("id"):
				found = true
		if not found:
			result.append(app)
	return result
