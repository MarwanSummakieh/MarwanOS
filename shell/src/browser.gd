extends Node

signal opened()
signal closed()

const BrowserScreen = preload("res://src/browser_screen.gd")
var _screen: Control = null


func is_open() -> bool:
	return is_instance_valid(_screen)


func open() -> void:
	if is_open() or Launcher.is_busy() or Files.is_open() or Settings.is_open() \
			or Power.is_open() or Info.is_open() or WindowsInstall.is_open():
		return
	_screen = BrowserScreen.new()
	_screen.closed.connect(_finish, CONNECT_ONE_SHOT)
	opened.emit()
	get_tree().root.add_child(_screen)
	_screen.open_url("https://duckduckgo.com", "Search the web")
	ShellLog.info("browser opened")


func _finish() -> void:
	_finish_deferred.call_deferred()


func _finish_deferred() -> void:
	if is_instance_valid(_screen):
		_screen.get_parent().remove_child(_screen)
		_screen.queue_free()
	_screen = null
	closed.emit()
