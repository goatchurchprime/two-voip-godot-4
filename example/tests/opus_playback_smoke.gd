extends SceneTree


func make_mono(count: int) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in range(count):
		var sample := 0.1 * sin(TAU * 440.0 * i / 48000.0)
		frames[i] = Vector2(sample, sample)
	return frames


func peak(frames: PackedVector2Array) -> float:
	var result := 0.0
	for frame in frames:
		result = max(result, max(abs(frame.x), abs(frame.y)))
	return result


func drain_episode(playback: AudioStreamPlaybackOpus) -> bool:
	var heard_audio := false
	for iteration in range(64):
		var frames := playback.mix_audio(1.0, 256)
		heard_audio = heard_audio or peak(frames) > 0.0
		if not playback.is_playing():
			return heard_audio
	assert(false, "Opus episode did not finish draining")
	return false


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	var encoder := TwovoipOpusEncoder.new()
	assert(encoder.initialize(48000, 48000, 1, TwovoipOpusEncoder.DENOISER_DISABLED, TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	assert(encoder.set_bitrate(12000) == OK)
	assert(encoder.set_complexity(5) == OK)
	assert(encoder.set_signal_type(TwovoipOpusEncoder.SIGNAL_VOICE) == OK)
	assert(encoder.process_chunk(make_mono(960)) == 960)
	var packet := encoder.encode_chunk()
	assert(not packet.is_empty())

	# A playback can also be used as a source-side reference decoder without an
	# AudioStreamPlayer. Its decoded history continues around the same PCM ring.
	var reference := AudioStreamPlaybackOpus.new()
	var comparison := AudioStreamPlaybackOpus.new()
	assert(reference.initialize(48000, 1, 960, 0.01) == OK)
	assert(comparison.initialize(48000, 1, 960, 0.01) == OK)
	var first_packet_hash := -1
	var decoded_frame_count := 0
	for packet_index in range(110):
		var decoded_frames := reference.push_opus_packet(packet, 0, 0)
		assert(decoded_frames == 960)
		decoded_frame_count += decoded_frames
		assert(comparison.push_opus_packet(packet, 0, 0) == 960)
		if packet_index == 0:
			first_packet_hash = reference.get_frame_hash(0, 960)
	assert(decoded_frame_count == 105600)
	assert(reference.queue_length_frames() == 96000)
	assert(reference.get_overflow_frames() == 9600)
	assert(reference.get_frame_hash(decoded_frame_count - 48000, 48000) == comparison.get_frame_hash(decoded_frame_count - 48000, 48000))
	assert(reference.get_frame_hash(0, 960) == -1)
	assert(reference.get_frame_hash(decoded_frame_count - 96001, 96001) == -1)
	assert(reference.get_tail_max(960) > 0.0)

	var stream := AudioStreamOpus.new()
	var playback: AudioStreamPlaybackOpus = stream.instantiate_playback()
	playback.start()
	assert(playback.initialize(48000, 1, 960, 0.01, 0.0, 2.0) == OK)

	assert(playback.push_opus_packet(packet, 0, 0) == 960)
	assert(playback.queue_length_frames() == 960)
	assert(playback.available_space_frames() == 95040)
	assert(playback.get_overflow_frames() == 0)
	assert(playback.get_decode_errors() == 0)

	var short_encoder := TwovoipOpusEncoder.new()
	assert(short_encoder.initialize(48000, 48000, 1, TwovoipOpusEncoder.DENOISER_DISABLED, TwovoipOpusEncoder.AGC_DISABLED, 480) == OK)
	assert(short_encoder.process_chunk(make_mono(480)) == 480)
	assert(playback.push_opus_packet(short_encoder.encode_chunk(), 0, 0) < 0)
	assert(playback.get_decode_errors() == 1)
	assert(playback.push_opus_packet(PackedByteArray(), 0, 0) < 0)
	assert(playback.get_decode_errors() == 2)
	assert(playback.get_last_decode_error() < 0)
	assert(playback.get_skips(true) == playback.get_overflow_frames())
	assert(playback.get_skips(false) == playback.get_underflow_frames())
	assert(playback.get_frame_hash(0, 960) == first_packet_hash)
	assert(playback.finish_episode() == 960)
	assert(drain_episode(playback))

	var first_episode: AudioStreamPlaybackOpus = stream.instantiate_playback()
	var second_episode: AudioStreamPlaybackOpus = stream.instantiate_playback()
	first_episode.start()
	second_episode.start()
	assert(first_episode.initialize(48000, 1, 960, 0.1, 0.0, 2.0) == OK)
	assert(second_episode.initialize(48000, 1, 960, 0.1, 0.0, 2.0) == OK)
	assert(first_episode.push_opus_packet(packet, 0, 0) == 960)
	assert(second_episode.push_opus_packet(packet, 0, 0) == 960)
	assert(first_episode.finish_episode() == 960)
	assert(second_episode.finish_episode() == 960)
	assert(drain_episode(first_episode))
	assert(second_episode.queue_length_frames() == 960)
	assert(drain_episode(second_episode))

	var player := AudioStreamPlayer.new()
	get_root().add_child(player)
	player.stream = stream
	player.max_polyphony = 3
	player.play()
	var player_episode_one: AudioStreamPlaybackOpus = player.get_stream_playback()
	assert(player_episode_one.initialize(48000, 1, 960, 0.1, 0.0, 2.0) == OK)
	player.play()
	var player_episode_two: AudioStreamPlaybackOpus = player.get_stream_playback()
	assert(player_episode_two != player_episode_one)
	assert(player_episode_two.initialize(48000, 1, 960, 0.1, 0.0, 2.0) == OK)
	assert(player_episode_one.is_playing())
	assert(player_episode_two.is_playing())
	assert(player_episode_one.finish_episode() == 0)
	assert(player_episode_two.finish_episode() == 0)
	drain_episode(player_episode_one)
	drain_episode(player_episode_two)
	player.stop()
	player.queue_free()
	player_episode_one = null
	player_episode_two = null
	first_episode = null
	second_episode = null
	playback = null
	reference = null
	comparison = null
	stream = null
	short_encoder = null
	encoder = null
	create_timer(0.1).timeout.connect(finish_tests, CONNECT_ONE_SHOT)


func finish_tests() -> void:
	print("Opus playback smoke passed: decode, Speex output, independent episodes and player polyphony")
	quit()
