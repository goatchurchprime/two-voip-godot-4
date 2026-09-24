extends SceneTree


func _initialize() -> void:
	call_deferred("run_tests")


func make_mono(phase: float) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(960)
	for i in range(960):
		var sample := 0.1 * sin(phase + TAU * 440.0 * i / 48000.0)
		frames[i] = Vector2(sample, sample)
	return frames


func make_opus_packets(stream_count: int, encode_base64: bool) -> Array[PackedByteArray]:
	var encoder := TwovoipOpusEncoder.new()
	assert(encoder.initialize(48000, 48000, 1,
			TwovoipOpusEncoder.DENOISER_DISABLED,
			TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	var packets: Array[PackedByteArray] = []
	for frame_count in range(2):
		assert(encoder.process_chunk(make_mono(frame_count * 0.25)) == 960)
		var prefix := TwoVoipPacket.make_timestamped_chunk_prefix()
		prefix[0] = frame_count % 256
		prefix[1] = (int(frame_count / 256) & 127) + (stream_count % 2) * 128
		TwoVoipPacket.set_chunk_first_frame_time_usec(prefix, 1700000000000000 + frame_count * 20000)
		packets.append(TwoVoipPacket.encode_audio_packet(
				encoder.encode_chunk(prefix, 0), encode_base64))
	return packets


func run_speaker_episode(speaker: Node, stream_count: int, encode_base64: bool) -> void:
	var header := TwoVoipPacket.make_header(
			TwoVoipPacket.TYPE_START, 960, 48000, 1,
			TwoVoipPacket.TIMESTAMPED_CHUNK_PREFIX_SIZE, stream_count, 0,
			1700000000000000, encode_base64)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	assert(speaker.audio_packets_base64 == encode_base64)
	for packet in make_opus_packets(stream_count, encode_base64):
		speaker.receive_audio_packet(packet)
	assert(speaker.opusframecount == 2)
	assert(speaker.source_first_frame_time_usec == 1700000000000000)
	assert(speaker.source_packet_first_frame_time_usec == 1700000000020000)
	assert(speaker.audio_stream_playback_opus != null)
	var footer := TwoVoipPacket.make_footer(stream_count, 2, 0.04, 12.54)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(footer))
	assert(not speaker.inopusstream)


func run_tests() -> void:
	var binary_header := TwoVoipPacket.make_header(
			TwoVoipPacket.TYPE_START, 960, 48000, 1,
			TwoVoipPacket.TIMESTAMPED_CHUNK_PREFIX_SIZE, 7, 0,
			1700000000000000, false)
	assert(TwoVoipPacket.header_is_valid(binary_header))
	assert(binary_header[TwoVoipPacket.HeaderField.VERSION] == TwoVoipPacket.WIRE_VERSION)
	assert(binary_header[TwoVoipPacket.HeaderField.AUDIO_ENCODING] == TwoVoipPacket.ENCODING_BINARY)
	var control_wire := TwoVoipPacket.encode_control_packet(binary_header)
	assert(TwoVoipPacket.is_control_packet(control_wire))
	var decoded_header := TwoVoipPacket.decode_control_packet(control_wire)
	assert(TwoVoipPacket.header_is_valid(decoded_header))
	assert(int(decoded_header[TwoVoipPacket.HeaderField.OPUS_FRAME_SIZE]) == 960)
	assert(int(decoded_header[TwoVoipPacket.HeaderField.FIRST_FRAME_TIME_USEC]) == 1700000000000000)
	assert(decoded_header[TwoVoipPacket.HeaderField.AUDIO_ENCODING] == TwoVoipPacket.ENCODING_BINARY)

	var ordinary_audio := PackedByteArray([3, 4, 5, 6])
	var ordinary_wire := TwoVoipPacket.encode_audio_packet(ordinary_audio, false)
	assert(ordinary_wire == ordinary_audio)
	assert(not TwoVoipPacket.is_control_packet(ordinary_wire))
	assert(TwoVoipPacket.decode_audio_packet(ordinary_wire, false) == ordinary_audio)

	# This raw packet would look exactly like a JSON string array without the
	# transport escape. The trailing zero must be removed before libopus sees it.
	var ambiguous_audio := PackedByteArray([91, 34, 17, 93])
	var escaped_wire := TwoVoipPacket.encode_audio_packet(ambiguous_audio, false)
	assert(escaped_wire == PackedByteArray([91, 34, 17, 93, 0]))
	assert(not TwoVoipPacket.is_control_packet(escaped_wire))
	assert(TwoVoipPacket.decode_audio_packet(escaped_wire, false) == ambiguous_audio)

	var base64_header := TwoVoipPacket.make_header(
			TwoVoipPacket.TYPE_MID, 960, 48000, 1,
			TwoVoipPacket.TIMESTAMPED_CHUNK_PREFIX_SIZE, 7, 42,
			1700000000000000, true)
	assert(TwoVoipPacket.header_is_valid(base64_header))
	assert(TwoVoipPacket.header_uses_base64(base64_header))
	var base64_wire := TwoVoipPacket.encode_audio_packet(ambiguous_audio, true)
	assert(not TwoVoipPacket.is_control_packet(base64_wire))
	assert(TwoVoipPacket.decode_audio_packet(base64_wire, true) == ambiguous_audio)

	var timestamped_prefix := TwoVoipPacket.make_timestamped_chunk_prefix()
	TwoVoipPacket.set_chunk_first_frame_time_usec(timestamped_prefix, 1700000000123456)
	assert(TwoVoipPacket.get_chunk_first_frame_time_usec(timestamped_prefix) == 1700000000123456)

	var footer := TwoVoipPacket.make_footer(7, 43, 0.86, 13.36)
	assert(TwoVoipPacket.footer_is_valid(footer))
	var decoded_footer := TwoVoipPacket.decode_control_packet(
			TwoVoipPacket.encode_control_packet(footer))
	assert(TwoVoipPacket.footer_is_valid(decoded_footer))
	assert(int(decoded_footer[TwoVoipPacket.FooterField.OPUS_FRAME_COUNT]) == 43)

	var player := AudioStreamPlayer.new()
	get_root().add_child(player)
	var speaker := Node.new()
	speaker.set_script(preload("res://addons/twovoip/voiphelper/two_voip_speaker.gd"))
	player.add_child(speaker)
	run_speaker_episode(speaker, 8, false)
	run_speaker_episode(speaker, 9, true)
	player.stop()
	player.queue_free()
	await process_frame
	speaker = null
	player = null
	await create_timer(0.1).timeout

	print("Packet transport smoke passed: arrays, raw escape, base64 and speaker episodes")
	quit()
