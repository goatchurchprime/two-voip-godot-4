@tool
extends EditorPlugin

const AUTOLOAD_NAME = "AutoVoip"
const AUTOLOAD_PATH = "res://addons/twovoip_autoload/auto_voip.gd"


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
