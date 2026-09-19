extends SceneTree


func make_mono(count: int) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in range(count):
		var sample := 0.1 * sin(TAU * 440.0 * i / 48000.0)
		frames[i] = Vector2(sample, sample)
	return frames


func _initialize() -> void:
	var encoder := TwovoipOpusEncoder.new()
	assert(encoder.initialize(48000, 48000, 1, TwovoipOpusEncoder.DENOISER_DISABLED, TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	assert(encoder.create_opus_encoder(12000, 5, true))
	assert(encoder.process_chunk(make_mono(960)) == 960)
	var packet := encoder.encode_chunk()
	assert(not packet.is_empty())

	var stream := AudioStreamOpus.new()
	stream.opus_sample_rate = 48000
	stream.opus_channels = 1
	stream.buffer_length = 0.01 # 480 frames, deliberately smaller than one packet.
	var playback: AudioStreamPlaybackOpus = stream.instantiate_playback()
	playback.mark_end_opus_stream(true)
	var initial_underflow_frames := playback.get_underflow_frames()

	assert(playback.push_opus_packet(packet, 0, 0) == 960)
	assert(playback.queue_length_frames() == 480)
	assert(playback.available_space_frames() == 0)
	assert(playback.get_overflow_frames() == 480)
	assert(playback.get_underflow_frames() == initial_underflow_frames)
	assert(playback.get_decode_errors() == 0)

	assert(playback.push_opus_packet(PackedByteArray(), 0, 0) < 0)
	assert(playback.get_decode_errors() == 1)
	assert(playback.get_last_decode_error() < 0)
	assert(playback.get_skips(true) == playback.get_overflow_frames())
	assert(playback.get_skips(false) == playback.get_underflow_frames())

	print("Opus playback smoke passed: decode result, bounded ring and diagnostics")
	quit()
