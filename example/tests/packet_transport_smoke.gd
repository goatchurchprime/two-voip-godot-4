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


func make_opus_packets(stream_count: int, encode_base64: bool,
		first_frame: int = 0, packet_count: int = 2) -> Array[PackedByteArray]:
	var encoder := TwovoipOpusEncoder.new()
	assert(encoder.initialize(48000, 48000, 1,
			TwovoipOpusEncoder.DENOISER_DISABLED,
			TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	var packets: Array[PackedByteArray] = []
	for packet_offset in range(packet_count):
		var frame_count = first_frame + packet_offset
		assert(encoder.push_input_chunk(make_mono(frame_count * 0.25)) == 960)
		var prefix := TwoVoipPacket.make_sequence_chunk_prefix()
		TwoVoipPacket.set_sequence_chunk_prefix(prefix, frame_count, stream_count)
		packets.append(TwoVoipPacket.encode_audio_packet(
				encoder.encode_chunk(prefix, 0), encode_base64))
	return packets


func run_speaker_episode(speaker: Node, stream_count: int, encode_base64: bool) -> void:
	var header := TwoVoipPacket.make_header(
			TwoVoipPacket.TYPE_START, 960, 48000, 1,
			TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 0,
			1700000000000000, 12000, encode_base64)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	assert(speaker.audio_packets_base64 == encode_base64)
	var early_hash_responses: Array[Array] = []
	speaker.hash_response_ready.connect(func(packet):
		early_hash_responses.append(TwoVoipPacket.decode_control_packet(packet)), CONNECT_ONE_SHOT)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(
			TwoVoipPacket.make_hash_request(stream_count, 0, 1920)))
	assert(early_hash_responses.size() == 1)
	assert(int(early_hash_responses[0][TwoVoipPacket.HashResponseField.HASH]) == -1)
	var source_reference := AudioStreamPlaybackOpus.new()
	assert(source_reference.initialize(48000, 1, 960) == OK)
	var sent_sum_squares = 0.0
	for packet in make_opus_packets(stream_count, encode_base64):
		var original_packet = TwoVoipPacket.decode_audio_packet(packet, encode_base64)
		assert(source_reference.push_opus_packet(
				original_packet, TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, 0) == 960)
		sent_sum_squares += source_reference.get_tail_sum_squares(960)
		speaker.receive_audio_packet(packet)
	assert(early_hash_responses.size() == 1)
	assert(speaker.opusframecount == 2)
	assert(speaker.source_next_frame_time_usec == 1700000000000000)
	assert(speaker.source_packet_first_frame_time_usec == 1700000000020000)
	assert(speaker.audio_stream_playback_opus != null)
	assert(speaker.decoded_frame_max_values.size() >= 2)
	assert(speaker.get_frame_max(0) > 0.0)
	assert(speaker.get_incoming_bitrate() == 12000)
	assert(speaker.get_playout_lag_time() >= 0.0)
	assert(speaker.timing_meter.offset_sample_count == 2)
	assert(speaker.playbackstartframenumber == 0)
	var hash_responses: Array[Array] = []
	speaker.hash_response_ready.connect(func(packet):
		hash_responses.append(TwoVoipPacket.decode_control_packet(packet)), CONNECT_ONE_SHOT)
	var hash_request = TwoVoipPacket.make_hash_request(stream_count, 0, 1920)
	assert(TwoVoipPacket.hash_request_is_valid(hash_request))
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(hash_request))
	assert(hash_responses.size() == 1)
	assert(TwoVoipPacket.hash_response_is_valid(hash_responses[0]))
	assert(int(hash_responses[0][TwoVoipPacket.HashResponseField.HASH]) ==
			source_reference.get_frame_hash(0, 1920))
	var sent_rms = sqrt(sent_sum_squares/1920)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_footer(stream_count - 1, 2, 0.04, 12.54, sent_rms)))
	assert(speaker.inopusstream)
	var footer := TwoVoipPacket.make_footer(stream_count, 2, 0.04, 12.54, sent_rms)
	var returned_footer = speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(footer))
	assert(returned_footer[TwoVoipPacket.FooterField.RMS] == sent_rms)
	assert(returned_footer[TwoVoipPacket.FooterField.RMS] == speaker.outputrms)
	assert(not speaker.inopusstream)


func run_mid_join_and_gap(speaker: Node, stream_count: int) -> void:
	const first_frame := 43
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var header := TwoVoipPacket.make_header(
			TwoVoipPacket.TYPE_START, 960, 48000, 1,
			TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, first_frame,
			next_frame_time_usec, 12000, false)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	assert(speaker.opusframecount == first_frame)
	assert(speaker.episodefirstframenumber == first_frame * 960)
	assert(speaker.playbackstartframenumber <= speaker.episodefirstframenumber)

	# A mid update three frames ahead substitutes for three deliberately omitted
	# source packets. A fresh mid join above truncates instead of inserting all
	# forty-three preceding frames.
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(
			TwoVoipPacket.make_mid(stream_count, first_frame + 3,
					next_frame_time_usec + 60000, 16000)))
	assert(speaker.opusframecount == first_frame + 3)
	assert(speaker.tailframenumber == (first_frame + 3) * 960)
	var tail_after_mid: int = speaker.tailframenumber
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(
			TwoVoipPacket.make_mid(stream_count, first_frame + 3,
					next_frame_time_usec + 60000, 16000)))
	assert(speaker.tailframenumber == tail_after_mid)
	assert(speaker.source_bitrate == 16000)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(
			TwoVoipPacket.make_mid(stream_count, first_frame + 8,
					next_frame_time_usec + 60000, 16000)))
	assert(speaker.rejected_mid_count == 1)
	assert(speaker.opusframecount == first_frame + 3)
	assert(speaker.source_next_frame_count == first_frame + 3)
	assert(speaker.timing_meter._get_frame_kind(first_frame * 960) \
			== speaker.timing_meter.FRAME_KIND_SOURCE_GAP)
	assert(speaker.decoded_frame_max_values[
			first_frame % speaker.decoded_frame_max_values.size()] \
			== speaker.DISPLAY_SOURCE_GAP)
	for packet in make_opus_packets(stream_count, false, first_frame + 3):
		speaker.receive_audio_packet(packet)
	assert(speaker.opusframecount == first_frame + 5)
	assert(speaker.timing_meter._get_frame_kind((first_frame + 3) * 960) \
			== speaker.timing_meter.FRAME_KIND_AUDIO)
	assert(speaker.decoded_frame_max_values[
			(first_frame + 3) % speaker.decoded_frame_max_values.size()] >= 0.0)
	assert(speaker.source_packet_first_frame_time_usec == next_frame_time_usec + 80000)
	assert(speaker.last_mid_to_audio_usec >= 0)
	var footer := TwoVoipPacket.make_footer(stream_count, first_frame + 5, 0.1, 0.0)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(footer))
	assert(not speaker.inopusstream)


func run_counter_wrap(speaker: Node, stream_count: int) -> void:
	const first_frame := 127
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var header := TwoVoipPacket.make_header(TwoVoipPacket.TYPE_START, 960, 48000, 1, TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, first_frame, next_frame_time_usec, 12000, false)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	for packet in make_opus_packets(stream_count, false, first_frame):
		speaker.receive_audio_packet(packet)
	assert(speaker.opusframecount == first_frame + 2)
	assert(speaker.source_packet_first_frame_time_usec == next_frame_time_usec + 20000)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_footer(stream_count, first_frame + 2, 0.04, 0.0)))


func run_small_packet_reordering(speaker: Node, stream_count: int) -> void:
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var header := TwoVoipPacket.make_header(TwoVoipPacket.TYPE_START, 960, 48000, 1, TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 0, next_frame_time_usec, 12000, false)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	var packets := make_opus_packets(stream_count, false, 0, 3)
	speaker.receive_audio_packet(packets[1])
	speaker.receive_audio_packet(packets[1])
	assert(speaker.opusframequeuecount == 1)
	assert(speaker.duplicate_packet_count == 1)
	speaker.receive_audio_packet(packets[0])
	speaker.receive_audio_packet(packets[2])
	assert(speaker.opusframecount == 3)
	assert(speaker.opusframequeuecount == 0)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_footer(stream_count, 3, 0.06, 0.0)))


func run_receiver_playback_restart(speaker: Node, stream_count: int) -> void:
	var previous_stale_timeout: float = speaker.stale_episode_timeout
	speaker.stale_episode_timeout = 0.01
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var header := TwoVoipPacket.make_header(TwoVoipPacket.TYPE_START, 960, 48000, 1, TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 0, next_frame_time_usec, 12000, false)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	for packet in make_opus_packets(stream_count, false, 0, 2):
		speaker.receive_audio_packet(packet)
	var interrupted_playback: AudioStreamPlaybackOpus = speaker.audio_stream_playback_opus
	for mix_index in range(400):
		interrupted_playback.mix_audio(1.0, 256)
		if not interrupted_playback.is_playing():
			break
	assert(not interrupted_playback.is_playing())
	speaker._physics_process(0.0)
	assert(speaker.audio_stream_playback_opus == null)
	assert(speaker.inopusstream)

	# Later packets from the same wire episode provision a replacement playback
	# while retaining the absolute packet sequence established by START/MID.
	for packet in make_opus_packets(stream_count, false, 2, 2):
		speaker.receive_audio_packet(packet)
	assert(speaker.audio_stream_playback_opus != null)
	assert(speaker.audio_stream_playback_opus != interrupted_playback)
	assert(speaker.audio_stream_playback_opus.is_playing())
	assert(speaker.inopusstream)
	assert(speaker.opusframecount == 4)
	assert(speaker.playback_restart_count == 1)
	assert("starvation" in speaker.timing_meter.diagnostic_trigger)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_footer(stream_count, 4, 0.08, 0.0)))
	speaker.stale_episode_timeout = previous_stale_timeout


func run_receiver_clock_stall_restart(speaker: Node, stream_count: int) -> void:
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var header := TwoVoipPacket.make_header(TwoVoipPacket.TYPE_START, 960, 48000, 1, TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 0, next_frame_time_usec, 12000, false)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	var interrupted_playback: AudioStreamPlaybackOpus = speaker.audio_stream_playback_opus
	# Model a local pause in which monotonic time advanced but the speaker frame
	# did not. The next packet must replace only local playback, not the episode.
	speaker.playback_clock_anchor_ticks_usec -= 200000
	for packet in make_opus_packets(stream_count, false, 0, 2):
		speaker.receive_audio_packet(packet)
	assert(speaker.audio_stream_playback_opus != interrupted_playback)
	assert(speaker.playback_restart_count == 1)
	assert(speaker.inopusstream)
	assert(speaker.opusframecount == 2)
	assert("clock stalled" in speaker.timing_meter.diagnostic_trigger)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_footer(stream_count, 2, 0.04, 0.0)))


func run_receiver_input_starvation_extends_playout(speaker: Node, stream_count: int) -> void:
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var header := TwoVoipPacket.make_header(TwoVoipPacket.TYPE_START, 960, 48000, 1, TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 0, next_frame_time_usec, 12000, false)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	var starved_playback: AudioStreamPlaybackOpus = speaker.audio_stream_playback_opus
	# Consume the initial reserve and continue mixing silence without reaching
	# the stale-episode timeout. This models an interrupted receiver input while
	# its independent audio thread keeps running.
	for mix_index in range(200):
		starved_playback.mix_audio(1.0, 256)
	assert(starved_playback.is_playing())
	assert(starved_playback.get_underflow_frames() > speaker.playback_underflow_baseline)
	for packet in make_opus_packets(stream_count, false, 0, 2):
		speaker.receive_audio_packet(packet)
	assert(speaker.audio_stream_playback_opus == starved_playback)
	assert(speaker.playback_restart_count == 0)
	assert(speaker.inopusstream)
	assert(speaker.opusframecount == 2)
	assert(speaker.playout_delay_extension_usec > 0)
	assert(speaker.get_effective_playout_lag_target() > speaker.audio_buffer_lag_time_target)
	assert("extend playout" in speaker.timing_meter.diagnostic_trigger)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_footer(stream_count, 2, 0.04, 0.0)))


func run_receiver_backlog_restart(speaker: Node, stream_count: int) -> void:
	# Model packets released after a local pause. Their source time is old, so a
	# replacement playback must not add a fresh target delay.
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0) - 10000000
	var header := TwoVoipPacket.make_header(TwoVoipPacket.TYPE_START, 960, 48000, 1, TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 0, next_frame_time_usec, 12000, false)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	for packet in make_opus_packets(stream_count, false, 0, 160):
		speaker.receive_audio_packet(packet)
	assert(speaker.inopusstream)
	assert(speaker.opusframecount == 160)
	assert(speaker.playback_restart_count > 0)
	assert(speaker.audio_stream_playback_opus.is_playing())
	assert(speaker.audio_stream_playback_opus.queue_length_frames() <= 3 * 48000)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_footer(stream_count, 160, 3.2, 0.0)))


func run_mid_restarts_playback(speaker: Node, stream_count: int) -> void:
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var header := TwoVoipPacket.make_header(TwoVoipPacket.TYPE_START, 960, 48000, 1, TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 5, next_frame_time_usec, 12000, false)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	speaker.audio_stream_playback_opus.stop()
	speaker.audio_stream_playback_opus = null
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_mid(stream_count, 10, next_frame_time_usec + 100000, 12000)))
	assert(speaker.source_next_frame_count == 10)
	assert(speaker.opusframecount == 10)
	assert(speaker.inopusstream)
	assert(speaker.audio_stream_playback_opus != null)
	assert(speaker.audio_stream_playback_opus.is_playing())
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_footer(stream_count, 10, 0.1, 0.0)))


func run_input_gap_detection() -> void:
	var mic := Node.new()
	mic.set_script(preload("res://addons/twovoip/voiphelper/two_voip_mic.gd"))
	mic.opusencoder = TwovoipOpusEncoder.new()
	assert(mic.opusencoder.initialize(48000, 48000, 1, TwovoipOpusEncoder.DENOISER_DISABLED, TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	mic.currentlytalking = true
	mic.opusstreamcount = 12
	mic.opusframecount = 30
	mic.frame0usec = 1700000000000000
	mic.input_gap_threshold = 0.05
	mic.input_chunk_first_frame_times_usec.resize(10)
	var emitted_packets: Array[PackedByteArray] = []
	mic.transmit_audio_packet.connect(func(packet): emitted_packets.append(packet))
	mic.detect_audio_input_gap(1700000000660000)
	assert(mic.input_chunk_number == 2)
	assert(mic.get_input_chunk_first_frame_time_usec(0) == 1700000000640000)
	assert(mic.opusencoder.push_input_chunk(make_mono(0.0)) == 960)
	mic.input_chunk_number += 1
	mic.input_chunk_first_frame_times_usec[mic.input_chunk_number] = 1700000000660000
	mic.processopuschunk(0)
	assert(mic.opusframecount == 34)
	assert(emitted_packets.size() == 2)
	assert(mic.opusencoder.get_chunk_sum_squares(1) == 0.0)
	var mid := TwoVoipPacket.decode_control_packet(emitted_packets[0])
	assert(int(mid[TwoVoipPacket.MidField.NEXT_FRAME_COUNT]) == 33)
	assert(int(mid[TwoVoipPacket.MidField.NEXT_FRAME_TIME_USEC]) == 1700000000660000)
	assert(TwoVoipPacket.decode_sequence_chunk_prefix(emitted_packets[1], 33, 12) == 33)
	mic.free()


func run_mqtt_log_payload_roundtrip() -> void:
	var mqtt_network := Control.new()
	mqtt_network.set_script(preload("res://radiomqtt/MQTTnetwork.gd"))
	var payload := PackedByteArray([0, 10, 32, 127, 128, 255])
	var encoded: String = mqtt_network.encode_log_payload(payload)
	assert(encoded.begins_with("b64:"))
	assert(mqtt_network.decode_log_payload(encoded) == payload)
	assert(mqtt_network.decode_log_payload("legacy") == "legacy".to_ascii_buffer())
	mqtt_network.free()


func run_stream_start_without_history() -> void:
	var mic := Node.new()
	mic.set_script(preload("res://addons/twovoip/voiphelper/two_voip_mic.gd"))
	mic.opusencoder = TwovoipOpusEncoder.new()
	assert(mic.opusencoder.initialize(48000, 48000, 1, TwovoipOpusEncoder.DENOISER_DISABLED, TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	mic.input_chunk_first_frame_times_usec.resize(51)
	var emitted_packets: Array[PackedByteArray] = []
	mic.transmit_audio_packet.connect(func(packet): emitted_packets.append(packet))
	mic.processtalkstreamends(true)
	assert(not mic.currentlytalking)
	assert(emitted_packets.is_empty())
	assert(mic.opusencoder.push_input_chunk(make_mono(0.0)) == 960)
	mic.input_chunk_number = 0
	mic.input_chunk_first_frame_times_usec[0] = 1700000000000000
	mic.processtalkstreamends(true)
	assert(mic.currentlytalking)
	assert(mic.frame0usec == 1700000000000000)
	assert(emitted_packets.size() == 2)
	var header := TwoVoipPacket.decode_control_packet(emitted_packets[0])
	assert(int(header[TwoVoipPacket.HeaderField.NEXT_FRAME_TIME_USEC]) == 1700000000000000)
	mic.free()


func run_input_gap_restart() -> void:
	var mic := Node.new()
	mic.set_script(preload("res://addons/twovoip/voiphelper/two_voip_mic.gd"))
	mic.opusencoder = TwovoipOpusEncoder.new()
	assert(mic.opusencoder.initialize(48000, 48000, 1, TwovoipOpusEncoder.DENOISER_DISABLED, TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	mic.currentlytalking = true
	mic.opusstreamcount = 12
	mic.opusframecount = 30
	mic.frame0usec = 1700000000000000
	mic.talkingtimestart = Time.get_ticks_msec()*0.001 - 0.6
	mic.input_chunk_first_frame_times_usec.resize(10)
	mic.voxbutton = Button.new()
	mic.voxbutton.toggle_mode = true
	mic.voxbutton.button_pressed = true
	mic.pttbutton = Button.new()
	mic.pttbutton.toggle_mode = true
	mic.pttbutton.button_pressed = true
	var emitted_packets: Array[PackedByteArray] = []
	mic.transmit_audio_packet.connect(func(packet): emitted_packets.append(packet))
	mic.detect_audio_input_gap(1700000002700000)
	assert(not mic.currentlytalking)
	assert(mic.opusstreamcount == 13)
	assert(not mic.pttbutton.button_pressed)
	assert(mic.opusencoder.get_chunk_sum_squares(0) == 0.0)
	assert(emitted_packets.size() == 1)
	var footer := TwoVoipPacket.decode_control_packet(emitted_packets[0])
	assert(footer[TwoVoipPacket.FooterField.TYPE] == TwoVoipPacket.TYPE_END)
	assert(int(footer[TwoVoipPacket.FooterField.OPUS_FRAME_COUNT]) == 30)
	mic.processvox(1.0, 0.0, PackedVector2Array())
	assert(mic.pttbutton.button_pressed)
	mic.voxbutton.free()
	mic.pttbutton.free()
	mic.free()


func run_application_resume_restart() -> void:
	var mic := Node.new()
	mic.set_script(preload("res://addons/twovoip/voiphelper/two_voip_mic.gd"))
	mic.opusencoder = TwovoipOpusEncoder.new()
	assert(mic.opusencoder.initialize(48000, 48000, 1,
			TwovoipOpusEncoder.DENOISER_DISABLED,
			TwovoipOpusEncoder.AGC_DISABLED, 960) == OK)
	mic.currentlytalking = true
	mic.opusstreamcount = 20
	mic.opusframecount = 2
	mic.talkingtimestart = Time.get_ticks_msec() * 0.001 - 0.04
	var emitted_packets: Array[PackedByteArray] = []
	mic.transmit_audio_packet.connect(func(packet): emitted_packets.append(packet))
	mic._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert(mic.application_resume_pending)
	assert(mic.application_resume_count == 1)
	assert(mic.consume_application_resume())
	assert(not mic.currentlytalking)
	assert(mic.opusstreamcount == 21)
	assert(emitted_packets.size() == 1)
	var footer := TwoVoipPacket.decode_control_packet(emitted_packets[0])
	assert(footer[TwoVoipPacket.FooterField.TYPE] == TwoVoipPacket.TYPE_END)
	assert(not mic.consume_application_resume())
	mic.free()


func run_tests() -> void:
	assert(TwoVoipPacket.WIRE_VERSION == 5)
	var sequence_prefix := TwoVoipPacket.make_sequence_chunk_prefix()
	assert(sequence_prefix.size() == 1)
	TwoVoipPacket.set_sequence_chunk_prefix(sequence_prefix, 128, 7)
	assert(TwoVoipPacket.decode_sequence_chunk_prefix(sequence_prefix, 127, 7) == 128)
	assert(TwoVoipPacket.decode_sequence_chunk_prefix(sequence_prefix, 128, 7) == 128)
	assert(TwoVoipPacket.decode_sequence_chunk_prefix(sequence_prefix, 129, 7) == -1)
	TwoVoipPacket.set_sequence_chunk_prefix(sequence_prefix, 191, 7)
	assert(TwoVoipPacket.decode_sequence_chunk_prefix(sequence_prefix, 128, 7) == 191)
	TwoVoipPacket.set_sequence_chunk_prefix(sequence_prefix, 192, 7)
	assert(TwoVoipPacket.decode_sequence_chunk_prefix(sequence_prefix, 128, 7) == -1)
	assert(TwoVoipPacket.decode_sequence_chunk_prefix(sequence_prefix, 127, 8) == -1)
	var binary_header := TwoVoipPacket.make_header(
			TwoVoipPacket.TYPE_START, 960, 48000, 1,
			TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, 7, 0,
			1700000000000000, 12000, false)
	assert(TwoVoipPacket.header_is_valid(binary_header))
	assert(binary_header[TwoVoipPacket.HeaderField.VERSION] == TwoVoipPacket.WIRE_VERSION)
	assert(binary_header[TwoVoipPacket.HeaderField.AUDIO_ENCODING] == TwoVoipPacket.ENCODING_BINARY)
	var control_wire := TwoVoipPacket.encode_control_packet(binary_header)
	assert(TwoVoipPacket.is_control_packet(control_wire))
	var decoded_header := TwoVoipPacket.decode_control_packet(control_wire)
	assert(TwoVoipPacket.header_is_valid(decoded_header))
	assert(int(decoded_header[TwoVoipPacket.HeaderField.OPUS_FRAME_SIZE]) == 960)
	assert(int(decoded_header[TwoVoipPacket.HeaderField.NEXT_FRAME_COUNT]) == 0)
	assert(int(decoded_header[TwoVoipPacket.HeaderField.NEXT_FRAME_TIME_USEC]) == 1700000000000000)
	assert(int(decoded_header[TwoVoipPacket.HeaderField.OPUS_BITRATE]) == 12000)
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
			TwoVoipPacket.TYPE_START, 960, 48000, 1,
			TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, 7, 0,
			1700000000000000, 24000, true)
	assert(TwoVoipPacket.header_is_valid(base64_header))
	assert(TwoVoipPacket.header_uses_base64(base64_header))
	var base64_wire := TwoVoipPacket.encode_audio_packet(ambiguous_audio, true)
	assert(not TwoVoipPacket.is_control_packet(base64_wire))
	assert(TwoVoipPacket.decode_audio_packet(base64_wire, true) == ambiguous_audio)

	var mid := TwoVoipPacket.make_mid(7, 43, 1700000000000000, 24000)
	assert(TwoVoipPacket.mid_is_valid(mid))
	assert(mid.size() == 5)
	assert(int(mid[TwoVoipPacket.MidField.NEXT_FRAME_COUNT]) == 43)
	assert(int(mid[TwoVoipPacket.MidField.NEXT_FRAME_TIME_USEC]) == 1700000000000000)
	assert(int(mid[TwoVoipPacket.MidField.OPUS_BITRATE]) == 24000)

	var footer := TwoVoipPacket.make_footer(7, 43, 0.86, 13.36, 0.125)
	assert(TwoVoipPacket.footer_is_valid(footer))
	var decoded_footer := TwoVoipPacket.decode_control_packet(
			TwoVoipPacket.encode_control_packet(footer))
	assert(TwoVoipPacket.footer_is_valid(decoded_footer))
	assert(int(decoded_footer[TwoVoipPacket.FooterField.OPUS_FRAME_COUNT]) == 43)
	assert(float(decoded_footer[TwoVoipPacket.FooterField.RMS]) == 0.125)

	var player := AudioStreamPlayer.new()
	get_root().add_child(player)
	var speaker := Node.new()
	speaker.set_script(preload("res://addons/twovoip/voiphelper/two_voip_speaker.gd"))
	player.add_child(speaker)
	var timing_meter := preload("res://addons/twovoip/voiphelper/two_voip_timing_meter.tscn").instantiate()
	get_root().add_child(timing_meter)
	assert(timing_meter is TwoVoipTimingMeter)
	speaker.init_voip_speaker(timing_meter)
	assert(timing_meter.output_cells.size() == 52)
	assert(timing_meter.arrival_sparks.size() == ceili(
			(timing_meter.display_before_source + timing_meter.display_span)
			* speaker.opus_sample_rate / speaker.opusframesize))
	var output_clip: Control = timing_meter.get_node("Display/OutputClip")
	var arrival_graph: Control = timing_meter.get_node("Display/Arrival")
	assert(output_clip.position.x == arrival_graph.position.x)
	assert(output_clip.size.x == arrival_graph.size.x)
	timing_meter.record_packet_arrival(2000000, 1900000)
	var found_arrival_spark := false
	for density in timing_meter.arrival_spark_density:
		found_arrival_spark = found_arrival_spark or density > 0.0
	assert(found_arrival_spark)
	timing_meter._reset_offset_statistics()
	run_speaker_episode(speaker, 8, false)
	run_speaker_episode(speaker, 9, true)
	run_mid_join_and_gap(speaker, 10)
	run_counter_wrap(speaker, 11)
	run_small_packet_reordering(speaker, 12)
	run_receiver_playback_restart(speaker, 13)
	run_receiver_clock_stall_restart(speaker, 14)
	run_receiver_input_starvation_extends_playout(speaker, 15)
	run_receiver_backlog_restart(speaker, 16)
	run_mid_restarts_playback(speaker, 17)
	run_input_gap_detection()
	run_mqtt_log_payload_roundtrip()
	run_stream_start_without_history()
	run_input_gap_restart()
	run_application_resume_restart()
	timing_meter.update_display(0.0)
	assert(timing_meter.TIMING_EMPTY.a == 0.0)
	var audible_deadline: ColorRect = timing_meter.get_node("Display/OutputClip/AudibleDeadline")
	assert(audible_deadline.position.x < audible_deadline.get_parent().size.x)
	var display_width: float = audible_deadline.get_parent().size.x
	var display_duration: float = timing_meter.display_before_source \
			+ timing_meter.display_span
	assert(is_equal_approx((audible_deadline.position.x + audible_deadline.size.x) /
			display_width, (timing_meter.display_before_source \
			+ speaker.audio_buffer_lag_time_target) / display_duration))
	var source_event: ColorRect = timing_meter.get_node("Display/Arrival/SourceEvent")
	assert(source_event.position.x > 0.0)
	var acquisition: ColorRect = timing_meter.get_node("Display/Arrival/Acquisition")
	assert(acquisition.visible)
	assert(acquisition.color == timing_meter.TIMING_ACQUISITION)
	assert(audible_deadline.color == timing_meter.TIMING_AUDIBLE_DEADLINE)
	var audible_head: ColorRect = timing_meter.get_node("Display/OutputClip/AudibleHead")
	assert(is_equal_approx(audible_head.position.x + audible_head.size.x,
			audible_deadline.position.x + audible_deadline.size.x))
	var audible_level: ColorRect = timing_meter.get_node("Display/AudibleLevel")
	assert(audible_level.visible)
	assert(audible_level.position.x > audible_deadline.get_parent().position.x \
			+ audible_deadline.position.x + audible_deadline.size.x)
	assert(audible_level.size.y == timing_meter.get_node("Display/Arrival").size.y)
	var original_target: float = speaker.audio_buffer_lag_time_target
	var original_deadline_x: float = audible_deadline.position.x
	speaker.audio_buffer_lag_time_target = original_target + 0.1
	timing_meter.update_display(0.0)
	assert(audible_deadline.position.x > original_deadline_x)
	assert(is_equal_approx((audible_deadline.position.x + audible_deadline.size.x) /
			display_width, (timing_meter.display_before_source \
			+ speaker.audio_buffer_lag_time_target) / display_duration))
	speaker.audio_buffer_lag_time_target = original_target
	timing_meter.update_display(0.0)
	var active_deadline_x := audible_deadline.position.x
	var active_acquisition_x := acquisition.position.x
	var anomaly_snapshot: Dictionary = timing_meter.anomaly_snapshot(
			"test", 621.0, 29000, 1200)
	assert(anomaly_snapshot.reason == "test")
	assert(anomaly_snapshot.queue_ms == 621.0)
	assert(anomaly_snapshot.queue_frames == 29000)
	timing_meter.set_transport_context({
		"record_packet_index": 123,
		"recorded_ticks_msec": 456,
		"replay": true,
	})
	anomaly_snapshot = timing_meter.anomaly_snapshot("context test", 621.0, 29000, 1200)
	assert(anomaly_snapshot.transport_context.record_packet_index == 123)
	player.stop()
	timing_meter.update_display(0.0)
	assert(timing_meter.get_node("Display/OutputClip/AudibleHead").size.x == 0.0)
	assert(audible_level.visible)
	assert(audible_deadline.visible)
	assert(audible_deadline.position.x == active_deadline_x)
	assert(audible_deadline.color == timing_meter.TIMING_AUDIBLE_DEADLINE)
	assert(acquisition.visible)
	assert(acquisition.position.x == active_acquisition_x)
	assert(acquisition.color == timing_meter.TIMING_ACQUISITION)
	player.queue_free()
	timing_meter.queue_free()
	await process_frame
	speaker = null
	player = null
	await create_timer(0.1).timeout

	print("Packet transport smoke passed: arrays, raw escape, base64 and speaker episodes")
	quit()
