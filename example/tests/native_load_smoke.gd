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

	print("TwoVoIP native smoke test: loaded and instantiated TwovoipOpusEncoder")
	quit(0)
