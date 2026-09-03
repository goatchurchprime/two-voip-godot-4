@tool
extends EditorPlugin

const AUTOLOAD_NAME = "AutoVoip"
const AUTOLOAD_PATH = "res://addons/twovoip_autoload/auto_voip.gd"

const METADATA_RPC_SETTING_NAME = "audio/auto_voip/metadata_rpc_channel"
const OPUS_RPC_SETTING_NAME = "audio/auto_voip/opus_rpc_channel"


func _enable_plugin() -> void:
	if not ProjectSettings.has_setting(METADATA_RPC_SETTING_NAME):
		ProjectSettings.set_setting(METADATA_RPC_SETTING_NAME, 0)
	if not ProjectSettings.has_setting(OPUS_RPC_SETTING_NAME):
		ProjectSettings.set_setting(OPUS_RPC_SETTING_NAME, 0)

	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
	if not ProjectSettings.has_setting(METADATA_RPC_SETTING_NAME):
		ProjectSettings.set_setting(METADATA_RPC_SETTING_NAME, null)
	if not ProjectSettings.has_setting(OPUS_RPC_SETTING_NAME):
		ProjectSettings.set_setting(OPUS_RPC_SETTING_NAME, null)
