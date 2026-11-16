extends SceneTree


func _initialize() -> void:
	if not ClassDB.class_exists("TwovoipOpusEncoder"):
		push_error("TwoVoIP native smoke test: TwovoipOpusEncoder is not registered")
		quit(1)
		return

	var encoder: Variant = ClassDB.instantiate("TwovoipOpusEncoder")
	if encoder == null:
		push_error("TwoVoIP native smoke test: could not instantiate TwovoipOpusEncoder")
		quit(1)
		return

	# A clean headless checkout has no editor-generated global class cache, so
	# load the GDScript side of the version contract explicitly.
	var two_voip: Variant = load("res://addons/twovoip/two_voip.gd")
	if two_voip == null or not two_voip.native_version_is_compatible():
		quit(1)
		return

	# Godot's editor reads registered properties while generating extension docs.
	# Merely constructing the object does not exercise those getters.
	var current_chunk: PackedVector2Array = encoder.get("current_chunk")
	if not current_chunk.is_empty():
		push_error("TwoVoIP native smoke test: an uninitialized encoder returned audio")
		quit(1)
		return

	print("TwoVoIP %s native smoke test: loaded and read uninitialized encoder properties" % two_voip.get_version_info())
	quit(0)
