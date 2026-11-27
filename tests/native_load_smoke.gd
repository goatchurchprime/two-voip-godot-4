extends SceneTree


func _initialize() -> void:
	if ClassDB.class_exists("TwovoipOpusEncoder"):
		push_error("TwoVoIP native smoke test: retired TwovoipOpusEncoder is still registered")
		quit(1)
		return
	if ClassDB.class_exists("TwoVoipEchoCanceler"):
		push_error("TwoVoIP native smoke test: removed TwoVoipEchoCanceler is still registered")
		quit(1)
		return
	if not ClassDB.class_exists("TwoVoipConditioner") or not ClassDB.class_exists("TwoVoipWebRTCConditioner"):
		push_error("TwoVoIP native smoke test: conditioner classes are not registered")
		quit(1)
		return
	if not ClassDB.class_exists("TwoVoipOpusEncoder"):
		push_error("TwoVoIP native smoke test: TwoVoipOpusEncoder is not registered")
		quit(1)
		return

	var encoder: Variant = ClassDB.instantiate("TwoVoipOpusEncoder")
	if encoder == null:
		push_error("TwoVoIP native smoke test: could not instantiate TwoVoipOpusEncoder")
		quit(1)
		return

	# A clean headless checkout has no editor-generated global class cache, so
	# load the GDScript side of the version contract explicitly.
	var two_voip: Variant = load("res://addons/twovoip/two_voip.gd")
	if two_voip == null or not two_voip.native_version_is_compatible():
		quit(1)
		return

	print("TwoVoIP %s native smoke test: loaded current encoder and conditioner API" % two_voip.get_version_info())
	quit(0)
