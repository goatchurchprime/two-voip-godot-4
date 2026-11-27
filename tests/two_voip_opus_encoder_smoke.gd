extends SceneTree


func _initialize() -> void:
	var encoder := TwoVoipOpusEncoder.new()
	assert(encoder.initialize(48000, 2, 960) == OK)
	assert(encoder.set_bitrate(12000) == OK)
	assert(encoder.set_complexity(5) == OK)
	assert(encoder.set_signal_type(TwoVoipOpusEncoder.SIGNAL_VOICE) == OK)
	assert(encoder.set_inband_perc(-1) == OK)
	var frames := PackedVector2Array()
	frames.resize(960)
	for frame in range(frames.size()):
		var sample := 0.1 * sin(TAU * 440.0 * frame / 48000.0)
		frames[frame] = Vector2(sample, -sample)
	var prefix := PackedByteArray([23])
	var packet := encoder.encode_chunk(frames, prefix)
	assert(packet.size() > prefix.size())
	assert(packet[0] == prefix[0])
	assert(encoder.encode_chunk(frames.slice(1), prefix).is_empty())
	encoder.reset()
	print("Stateless TwoVoipOpusEncoder smoke passed")
	quit(0)
