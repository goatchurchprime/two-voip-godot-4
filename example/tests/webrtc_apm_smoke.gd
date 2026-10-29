extends SceneTree


func _initialize() -> void:
	var encoder := TwovoipOpusEncoder.new()
	if not encoder.has_method("webrtc_apm_smoke_test"):
		push_error("TwoVoIP was not built with webrtc_apm=yes")
		quit(1)
		return
	if not encoder.webrtc_apm_smoke_test():
		push_error("WebRTC APM failed to process mono 48 kHz 10 ms render/capture frames with noise suppression")
		quit(1)
		return

	assert(encoder.initialize(48000, 48000, 1, TwovoipOpusEncoder.DENOISER_WEBRTC,
			TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	var noise_state := 1
	var changed := false
	for chunk in range(30):
		var frames := PackedVector2Array()
		frames.resize(960)
		for frame in range(frames.size()):
			noise_state = (noise_state * 1103515245 + 12345) & 0x7fffffff
			var sample := (noise_state / float(0x7fffffff) - 0.5) * 0.1
			frames[frame] = Vector2(sample, sample)
		assert(encoder.push_input_chunk(frames) == frames.size())
		var before := encoder.get_current_chunk()
		assert(encoder.denoise_chunk(0) == OK)
		var after := encoder.get_current_chunk()
		for frame in range(after.size()):
			if not is_equal_approx(before[frame].x, after[frame].x):
				changed = true
				break
	assert(changed)
	print("WebRTC APM 2.1 smoke test: live mono 48 kHz noise suppression passed")
	quit(0)
