class_name TwoVoip
extends RefCounted

const VERSION := "7.0.0"

static func get_version_info() -> String:
	var native := TwovoipOpusEncoder.new()
	return native.get_version_info() if native.has_method("get_version_info") else "missing"

static func native_version_is_compatible() -> bool:
	var native_version := get_version_info()
	if native_version != VERSION:
		push_error("TwoVoIP version mismatch: GDScript %s, GDExtension %s" % [VERSION, native_version])
		return false
	return true
