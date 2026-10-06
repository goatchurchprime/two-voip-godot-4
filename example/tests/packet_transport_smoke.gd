extends SceneTree

const ClockSync = preload("res://addons/twovoip/voiphelper/two_voip_clock_sync.gd")


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


func run_clock_sync_arithmetic() -> void:
	var same_clock: Dictionary = ClockSync.calculate_exchange(
			1000000, 1010000, 1011000, 1021000)
	assert(int(same_clock.remote_minus_local_usec) == 0)
	assert(int(same_clock.offset_lower_usec) == -10000)
	assert(int(same_clock.offset_upper_usec) == 10000)
	assert(int(same_clock.round_trip_usec) == 20000)
	var remote_ahead: Dictionary = ClockSync.calculate_exchange(
			1000000, 1110000, 1111000, 1021000)
	assert(int(remote_ahead.remote_minus_local_usec) == 100000)
	assert(int(remote_ahead.offset_lower_usec) == 90000)
	assert(int(remote_ahead.offset_upper_usec) == 110000)
	assert(int(remote_ahead.uncertainty_usec) == 10000)
	# The ACK gives the responder the same four timestamps. The two speaker
	# mappings must therefore be exact opposites, not separately estimated.
	var initiator_local_minus_responder := \
			-int(remote_ahead.remote_minus_local_usec)
	var responder_local_minus_initiator := \
			int(remote_ahead.remote_minus_local_usec)
	assert(initiator_local_minus_responder \
			== -responder_local_minus_initiator)
	# Asymmetric paths widen and bias the midpoint, but the true offset remains
	# inside the non-negative-delay interval.
	var asymmetric: Dictionary = ClockSync.calculate_exchange(
			1000000, 1105000, 1106000, 1021000)
	assert(int(asymmetric.offset_lower_usec) <= 100000)
	assert(int(asymmetric.offset_upper_usec) >= 100000)
	assert(int(asymmetric.remote_minus_local_usec) == 95000)
	assert(ClockSync.calculate_exchange(100, 200, 150, 300).is_empty())


func reset_test_source_clock(speaker: Node) -> void:
	# Most transport tests synthesize mutually independent source nodes and emit
	# future-timestamped packets immediately rather than pacing them in real time.
	speaker.source_clock_offset_bound_valid = false
	speaker.source_clock_offset_estimate_usec = 0
	speaker.source_clock_offset_lower_bound_usec = 0
	speaker.source_clock_offset_upper_bound_usec = 0
	speaker.source_clock_offset_uncertainty_usec = 0
	speaker.source_clock_probe_rtt_usec = 0
	speaker.source_clock_probe_valid = false
	speaker.source_clock_revision_reason = "uninitialized"
	speaker.source_clock_offset_observation_count = 0
	speaker.source_clock_offset_revision_count = 0
	speaker.source_clock_reference_deviation_usec = 0
	speaker.source_clock_reference_max_deviation_usec = 0
	speaker.source_clock_reference_large_change_count = 0
	speaker.source_clock_last_revision_usec = 0
	# These test episodes deliberately model unrelated machines on one speaker.
	# Production episodes retain both offsets across START/END boundaries.
	speaker.playout_timeline_base_offset_usec = 0
	speaker.playout_timeline_base_offset_valid = false
	speaker.playout_timeline_candidate_deviation_usec = 0
	speaker.playout_timeline_max_deviation_usec = 0


func run_startup_padding_arithmetic(speaker: Node) -> void:
	reset_test_source_clock(speaker)
	var source_usec := 1700000000000000
	var start_arrival_usec := source_usec + 250000
	assert(speaker.observe_source_clock_reference(
			start_arrival_usec, source_usec, 0) == 0)
	# A later episode may measure a slightly different reference, but that is an
	# observation only. It must not tune the persistent offset behind our backs.
	assert(speaker.observe_source_clock_reference(
			start_arrival_usec + 5000, source_usec, 0, true) == 5000)
	assert(speaker.source_clock_offset_estimate_usec == 250000)
	assert(speaker.source_clock_offset_revision_count == 1)
	assert(speaker.source_clock_reference_deviation_usec == 5000)
	# Audio observations measure arrival using the selected clock mapping; they
	# never revise that mapping themselves.
	for packet_index in range(8):
		speaker.observe_source_clock_timing(
				source_usec + 260000 - packet_index * 1000, source_usec)
	assert(speaker.source_clock_offset_estimate_usec == 250000)
	speaker.set_source_clock_estimate(0, -1000, 1000, 2000, "test clock pong")
	assert(speaker.source_clock_probe_valid)
	assert(speaker.source_clock_offset_estimate_usec == 0)
	assert(speaker.source_clock_offset_uncertainty_usec == 1000)
	# Reset before testing the ordinary startup calculation below.
	reset_test_source_clock(speaker)
	assert(speaker.observe_source_clock_reference(
			start_arrival_usec, source_usec, 0) == 0)
	# START is followed by a normally acquired first packet 96 ms later. Its
	# complete source-to-receiver journey is retained instead of being forced to
	# the nominal 30 ms acquisition estimate.
	var first_arrival_timeline_usec: int = speaker.observe_source_clock_timing(
			start_arrival_usec + 96000, source_usec)
	assert(first_arrival_timeline_usec == 96000)
	var expected_padding_frames := roundi(maxf(0.0,
			speaker.audio_buffer_lag_time_target - speaker.audioserveroutputlatency \
			- 0.096) * speaker.opus_sample_rate)
	assert(speaker.calculate_initial_playout_padding_frames(0.096) \
			== expected_padding_frames)
	# With ordinary 20 ms packet cadence, consumption and packet insertion then
	# cancel exactly. The PCM tail remains one chunk before packet availability.
	var queue_ms: float = expected_padding_frames * 1000.0 / speaker.opus_sample_rate
	queue_ms -= 20.0
	queue_ms += 40.0 # The initial two-packet batch is decoded together.
	for _packet_index in range(2, 10):
		queue_ms -= 20.0
		queue_ms += 20.0
	var packet_arrival_timeline_ms := 96.0
	var pcm_tail_timeline_ms: float = 600.0 - queue_ms
	assert(is_equal_approx(
			packet_arrival_timeline_ms - pcm_tail_timeline_ms, 20.0))


func run_speaker_episode(speaker: Node, stream_count: int, encode_base64: bool) -> void:
	reset_test_source_clock(speaker)
	var header := TwoVoipPacket.make_header(
			TwoVoipPacket.TYPE_START, 960, 48000, 1,
			TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 0,
			1700000000000000, 12000, encode_base64)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	assert(speaker.audio_packets_base64 == encode_base64)
	assert(not speaker.initial_playout_timeline_started)
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
	var expected_padding_frames := roundi(maxf(0.0,
			speaker.audio_buffer_lag_time_target - speaker.audioserveroutputlatency \
			- speaker.initial_start_arrival_timeline_usec / 1000000.0) * 48000.0)
	assert(speaker.playback_padding_end_frame - speaker.playbackstartframenumber \
			== expected_padding_frames)
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
	assert(speaker.playbackstartframenumber < 0)
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
	reset_test_source_clock(speaker)
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
	assert(speaker.mid_time_error_count == 1)
	assert(speaker.opusframecount == first_frame + 8)
	assert(speaker.source_next_frame_count == first_frame + 8)
	assert(speaker.source_next_frame_time_usec == next_frame_time_usec + 160000)
	assert(speaker.timing_meter._get_frame_kind(first_frame * 960) \
			== speaker.timing_meter.FRAME_KIND_SOURCE_GAP)
	assert(speaker.decoded_frame_max_values[
			first_frame % speaker.decoded_frame_max_values.size()] \
			== speaker.DISPLAY_SOURCE_GAP)
	for packet in make_opus_packets(stream_count, false, first_frame + 8):
		speaker.receive_audio_packet(packet)
	assert(speaker.opusframecount == first_frame + 10)
	assert(speaker.timing_meter._get_frame_kind((first_frame + 8) * 960) \
			== speaker.timing_meter.FRAME_KIND_AUDIO)
	assert(speaker.decoded_frame_max_values[
			(first_frame + 8) % speaker.decoded_frame_max_values.size()] >= 0.0)
	for frame in range(first_frame, first_frame + 10):
		assert(speaker.decoded_frame_max_values[
				frame % speaker.decoded_frame_max_values.size()] != speaker.DISPLAY_FEC)
	assert(speaker.source_packet_first_frame_time_usec == next_frame_time_usec + 180000)
	assert(speaker.last_mid_to_audio_usec >= 0)
	var footer := TwoVoipPacket.make_footer(stream_count, first_frame + 10, 0.2, 0.0)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(footer))
	assert(not speaker.inopusstream)


func run_counter_wrap(speaker: Node, stream_count: int) -> void:
	reset_test_source_clock(speaker)
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
	reset_test_source_clock(speaker)
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
	reset_test_source_clock(speaker)
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


func run_initial_lead_trim(speaker: Node, stream_count: int) -> void:
	reset_test_source_clock(speaker)
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var header := TwoVoipPacket.make_header(
			TwoVoipPacket.TYPE_START, 960, 48000, 1,
			TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 0,
			next_frame_time_usec, 12000, false, 40)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	assert(speaker.initial_wire_packets_to_skip > 0)
	var skipped_frames: int = speaker.initial_wire_packets_to_skip
	for packet in make_opus_packets(stream_count, false, 0, 41):
		speaker.receive_audio_packet(packet)
	var initial_playback_start: int = speaker.playbackstartframenumber
	var expected_padding_frames := roundi(maxf(0.0,
			speaker.audio_buffer_lag_time_target - speaker.audioserveroutputlatency \
			- speaker.initial_start_arrival_timeline_usec / 1000000.0) * 48000.0)
	assert(speaker.playback_padding_end_frame - initial_playback_start \
			== expected_padding_frames)
	assert(speaker.timing_meter._get_frame_kind(initial_playback_start) \
			== speaker.timing_meter.FRAME_KIND_SOURCE_GAP)
	assert(speaker.initial_wire_packets_to_skip == 0)
	assert(speaker.source_next_frame_count == skipped_frames)
	assert(speaker.opusframecount == 41)
	assert(speaker.dropped_packet_count == 0)
	assert(speaker.initial_playout_padding_aligned)
	# The lead boundary audits the START calculation. It must not insert a
	# second padding block or move the playback origin.
	assert(speaker.playbackstartframenumber == initial_playback_start)
	assert(speaker.timing_meter.tail_alignment_sample_count > 0)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(
			TwoVoipPacket.make_footer(stream_count, 41, 0.82, 0.0)))


func run_receiver_clock_stall_recovery(speaker: Node, stream_count: int) -> void:
	reset_test_source_clock(speaker)
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var header := TwoVoipPacket.make_header(TwoVoipPacket.TYPE_START, 960, 48000, 1, TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 0, next_frame_time_usec, 12000, false)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	for packet in make_opus_packets(stream_count, false, 0, 2):
		speaker.receive_audio_packet(packet)
	var uninterrupted_playback: AudioStreamPlaybackOpus = speaker.audio_stream_playback_opus
	# Model a local pause in which monotonic time advanced but the speaker frame
	# did not. The next packet retains both playback and the wire episode, and
	# turns the lost local time into explicit recovery debt.
	speaker.playback_clock_anchor_ticks_usec -= 200000
	for packet in make_opus_packets(stream_count, false, 2, 1):
		speaker.receive_audio_packet(packet)
	assert(speaker.audio_stream_playback_opus == uninterrupted_playback)
	assert(speaker.playback_restart_count == 0)
	assert(speaker.playback_clock_stall_count == 1)
	assert(speaker.playback_clock_stall_total_usec \
			> speaker.PLAYBACK_CLOCK_STALL_TOLERANCE_USEC)
	assert(speaker.playout_delay_extension_usec \
			>= speaker.playback_clock_stall_total_usec)
	assert(speaker.playout_delay_extension_usec == roundi(
			uninterrupted_playback.get_playout_recovery_remaining_frames() \
			* 1000000.0 / speaker.opus_sample_rate))
	assert(speaker.inopusstream)
	assert(speaker.opusframecount == 3)
	assert("local playback pause" in speaker.timing_meter.diagnostic_trigger)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_footer(stream_count, 2, 0.04, 0.0)))


func run_receiver_input_starvation_extends_playout(speaker: Node, stream_count: int) -> void:
	reset_test_source_clock(speaker)
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var header := TwoVoipPacket.make_header(TwoVoipPacket.TYPE_START, 960, 48000, 1, TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 0, next_frame_time_usec, 12000, false)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	for packet in make_opus_packets(stream_count, false, 0, 2):
		speaker.receive_audio_packet(packet)
	var starved_playback: AudioStreamPlaybackOpus = speaker.audio_stream_playback_opus
	# Consume the initial reserve and continue mixing silence without reaching
	# the stale-episode timeout. This models an interrupted receiver input while
	# its independent audio thread keeps running.
	for mix_index in range(200):
		starved_playback.mix_audio(1.0, 256)
	assert(starved_playback.is_playing())
	assert(starved_playback.get_underflow_frames() > speaker.playback_underflow_baseline)
	for packet in make_opus_packets(stream_count, false, 2, 1):
		speaker.receive_audio_packet(packet)
	assert(speaker.audio_stream_playback_opus == starved_playback)
	assert(speaker.playback_restart_count == 0)
	assert(speaker.inopusstream)
	assert(speaker.opusframecount == 3)
	assert(speaker.playout_delay_extension_usec > 0)
	assert(speaker.get_effective_playout_lag_target() > speaker.audio_buffer_lag_time_target)
	assert("input starvation" in speaker.timing_meter.diagnostic_trigger)
	assert(starved_playback.get_playout_recovery_remaining_frames() > 0)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(TwoVoipPacket.make_footer(stream_count, 2, 0.04, 0.0)))


func run_receiver_gap_recovers_playout(speaker: Node, stream_count: int) -> void:
	reset_test_source_clock(speaker)
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var header := TwoVoipPacket.make_header(TwoVoipPacket.TYPE_START, 960, 48000, 1,
			TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 0,
			next_frame_time_usec, 12000, false)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	for packet in make_opus_packets(stream_count, false, 0, 2):
		speaker.receive_audio_packet(packet)
	assert(speaker.playout_recovery_target_frames \
			== speaker.playback_padding_end_frame - speaker.playbackstartframenumber)
	speaker.playingrecording = true # Tight-loop mixing has no wall-clock timeline.
	var playback: AudioStreamPlaybackOpus = speaker.audio_stream_playback_opus
	for mix_index in range(200):
		playback.mix_audio(1.0, 256)
	assert(playback.get_underflow_frames() > 0)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(
			TwoVoipPacket.make_mid(stream_count, 40,
					next_frame_time_usec + 800000, 12000)))
	var extension_before_recovery: int = speaker.playout_delay_extension_usec
	assert(extension_before_recovery > 0)
	speaker.timing_meter.update_display(0.0)
	var deadline: ColorRect = speaker.timing_meter.get_node(
			"Display/OutputClip/AudibleDeadline")
	var deadline_before_recovery: float = deadline.position.x
	playback.mix_audio(1.0, 256)
	speaker._physics_process(0.0)
	speaker.timing_meter.update_display(0.0)
	assert(playback.get_silence_recovery_frames() > 0)
	assert(speaker.playout_delay_extension_usec < extension_before_recovery)
	assert(speaker.playout_delay_extension_usec == roundi(
			playback.get_playout_recovery_remaining_frames() \
			* 1000000.0 / speaker.opus_sample_rate))
	assert(deadline.position.x < deadline_before_recovery)
	speaker.playingrecording = false
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(
			TwoVoipPacket.make_footer(stream_count, 40, 0.8, 0.0)))


func run_receiver_backlog_restart(speaker: Node, stream_count: int) -> void:
	reset_test_source_clock(speaker)
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
	reset_test_source_clock(speaker)
	var next_frame_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var header := TwoVoipPacket.make_header(TwoVoipPacket.TYPE_START, 960, 48000, 1, TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, stream_count, 5, next_frame_time_usec, 12000, false)
	speaker.receive_audio_packet(TwoVoipPacket.encode_control_packet(header))
	for packet in make_opus_packets(stream_count, false, 5, 2):
		speaker.receive_audio_packet(packet)
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
	mic.input_mix_rate = 48000
	mic.input_gap_threshold = 0.05
	mic.input_chunk_first_frame_times_usec.resize(10)
	var emitted_packets: Array[PackedByteArray] = []
	mic.transmit_audio_packet.connect(func(packet): emitted_packets.append(packet))
	var gap_plan: Dictionary = mic.plan_audio_input_gap(1700000000651556)
	assert(gap_plan.missing_frame_count == 3)
	assert(gap_plan.next_frame_time_usec == 1700000000660000)
	assert(gap_plan.discard_input_frames == 406)
	mic.apply_audio_input_gap(gap_plan)
	assert(mic.input_chunk_number == 2)
	assert(mic.get_input_chunk_first_frame_time_usec(0) == 1700000000640000)
	assert(mic.opusencoder.push_input_chunk(make_mono(0.0)) == 960)
	mic.input_chunk_number += 1
	mic.input_chunk_first_frame_times_usec[mic.input_chunk_number] = 1700000000660000
	mic.processopuschunk(0)
	assert(mic.opusframecount == 34)
	assert(mic.get_next_frame_time_usec() == 1700000000680000)
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
	assert(TwoVoipPacket.header_lead_frame_count(header) == 0)
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
	run_clock_sync_arithmetic()
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
	assert(TwoVoipPacket.header_lead_frame_count(decoded_header) == 0)
	var lead_header := TwoVoipPacket.make_header(
			TwoVoipPacket.TYPE_START, 960, 48000, 1,
			TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE, 7, 0,
			1700000000000000, 12000, false, 9)
	assert(TwoVoipPacket.header_lead_frame_count(lead_header) == 9)
	var clock_ping := TwoVoipPacket.make_clock_ping("peer:1", 1000000)
	assert(TwoVoipPacket.clock_ping_is_valid(clock_ping))
	var clock_pong := TwoVoipPacket.make_clock_pong(
			"peer:1", 1000000, 1010000, 1011000)
	assert(TwoVoipPacket.clock_pong_is_valid(clock_pong))
	var clock_ack := TwoVoipPacket.make_clock_ack(
			"peer:1", 1000000, 1010000, 1011000, 1021000)
	assert(TwoVoipPacket.clock_ack_is_valid(clock_ack))
	assert(TwoVoipPacket.clock_ack_is_valid(TwoVoipPacket.decode_control_packet(
			TwoVoipPacket.encode_control_packet(clock_ack))))

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
	var reorder_cells: HBoxContainer = timing_meter.get_node("Display/ReorderSlots")
	assert(output_clip.position.x == arrival_graph.position.x)
	assert(output_clip.size.x == arrival_graph.size.x)
	assert(output_clip.get_node("TargetDeadline") != null)
	assert(reorder_cells.get_child(0).name == "Slot3")
	assert(reorder_cells.get_child(3).name == "Slot0")
	timing_meter.record_packet_arrival(2000000, 1900000, 100000)
	var found_arrival_spark := false
	for density in timing_meter.arrival_spark_density:
		found_arrival_spark = found_arrival_spark or density > 0.0
	assert(found_arrival_spark)
	# Before playback establishes an actual source-to-speaker mapping, red uses
	# the independently drawn target rather than arrival statistics.
	speaker.playout_timeline_offset_usec = 700000
	assert(is_equal_approx(timing_meter._get_audible_timeline_ms(), 600.0))
	speaker.playout_timeline_offset_usec = 0
	timing_meter._reset_offset_statistics()
	run_startup_padding_arithmetic(speaker)
	run_speaker_episode(speaker, 8, false)
	assert(timing_meter.audible_timeline_aligned)
	# This transport smoke emits both timestamped chunks in one process turn, so
	# it deliberately cannot audit paced arrival alignment. The recorded replay
	# covers that; here we only require the passive residual measurement to run.
	assert(is_finite(timing_meter.initial_alignment_residual_ms))
	assert(timing_meter.tail_alignment_sample_count > 0)
	var aligned_timeline_ms: float = timing_meter._get_audible_timeline_ms()
	assert(absf(aligned_timeline_ms - 600.0) < 0.1)
	var established_clock_estimate_usec: int = speaker.source_clock_offset_estimate_usec
	speaker.source_clock_offset_estimate_usec -= 5000
	assert(is_equal_approx(timing_meter._get_audible_timeline_ms(),
			aligned_timeline_ms + 5.0))
	assert(is_equal_approx(timing_meter._get_target_timeline_ms(), 600.0))
	speaker.source_clock_offset_estimate_usec = established_clock_estimate_usec
	speaker.playout_timeline_offset_usec += 100000
	assert(is_equal_approx(timing_meter._get_audible_timeline_ms(),
			aligned_timeline_ms + 100.0))
	speaker.playout_timeline_offset_usec -= 100000
	speaker.playout_delay_extension_usec += 100000
	speaker.playout_timeline_offset_usec += 100000
	assert(is_equal_approx(timing_meter._get_audible_timeline_ms(),
			aligned_timeline_ms + 100.0))
	speaker.playout_delay_extension_usec -= 100000
	speaker.playout_timeline_offset_usec -= 100000
	run_speaker_episode(speaker, 9, true)
	run_mid_join_and_gap(speaker, 10)
	run_counter_wrap(speaker, 11)
	run_small_packet_reordering(speaker, 12)
	run_receiver_playback_restart(speaker, 13)
	run_initial_lead_trim(speaker, 19)
	run_receiver_clock_stall_recovery(speaker, 14)
	run_receiver_input_starvation_extends_playout(speaker, 15)
	run_receiver_gap_recovers_playout(speaker, 16)
	run_receiver_backlog_restart(speaker, 17)
	run_mid_restarts_playback(speaker, 18)
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
	var target_deadline: ColorRect = timing_meter.get_node(
			"Display/OutputClip/TargetDeadline")
	var original_target_x: float = target_deadline.position.x
	speaker.audio_buffer_lag_time_target = original_target + 0.1
	timing_meter.update_display(0.0)
	assert(is_equal_approx(audible_deadline.position.x, original_deadline_x))
	assert(target_deadline.position.x > original_target_x)
	assert(is_equal_approx((target_deadline.position.x \
			+ target_deadline.size.x / 2.0) /
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
	assert(anomaly_snapshot.buffer_left_time_ms \
			== timing_meter._get_audible_timeline_ms() - 621.0)
	var previous_capture_setting: bool = timing_meter.capture_timing_anomalies
	timing_meter.capture_timing_anomalies = false
	var previous_stream_state: bool = speaker.inopusstream
	speaker.inopusstream = true
	var previous_overflow_state: bool = timing_meter.buffer_left_overflowing
	timing_meter.buffer_left_overflowing = false
	var previous_overflow_count: int = timing_meter.buffer_left_overflow_count
	timing_meter._update_overflow(591.0, 600.0, 28000, 1200)
	assert(timing_meter.buffer_left_overflow_count == previous_overflow_count + 1)
	assert("acquisition interval" in timing_meter.diagnostic_trigger)
	var previous_timeline_offset: int = speaker.playout_timeline_offset_usec
	var previous_mismatch_count: int = timing_meter.timing_buffer_mismatch_count
	speaker.playout_timeline_offset_usec += 100000
	speaker.playingrecording = true
	timing_meter._update_usec_consistency(590.0, 28000, 1200)
	assert(timing_meter.timing_buffer_mismatch_count == previous_mismatch_count)
	speaker.playingrecording = false
	timing_meter._update_usec_consistency(590.0, 28000, 1200)
	assert(timing_meter.timing_buffer_mismatch_count == previous_mismatch_count + 1)
	assert("source usec timeline" in timing_meter.diagnostic_trigger)
	speaker.playout_timeline_offset_usec = previous_timeline_offset
	speaker.inopusstream = previous_stream_state
	timing_meter.buffer_left_overflowing = previous_overflow_state
	timing_meter.capture_timing_anomalies = previous_capture_setting
	player.stop()
	timing_meter.update_display(0.0)
	assert(timing_meter.get_node("Display/OutputClip/AudibleHead").size.x == 0.0)
	assert(not audible_level.visible)
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
