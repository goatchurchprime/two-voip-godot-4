extends Node

signal hash_response_ready(packet: PackedByteArray)

var audioplayeropus = null
var audiostreamopus : AudioStreamOpus = null
var audio_stream_playback_opus : AudioStreamPlaybackOpus = null

# Consider looking at netem for simulating network traffic
# https://man7.org/linux/man-pages/man8/tc-netem.8.html

#frametimems = opusframesize*1000.0/opusframesize
var audioserveroutputlatency = AudioServer.get_output_latency()
@export var audio_buffer_lag_time_target = 0.6
@export var audio_buffer_length = 3.0
@export_range(1.0, 2.0, 0.01) var maximum_playout_recovery_speed = 1.08
@export var maximum_simultaneous_episodes = 3
@export var stale_episode_timeout = 4.0

var lenchunkprefix = TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE
var opusstreamcount = 0
var inopusstream = false
var audio_packets_base64 = false
var opusframecount = 0
var outputsumsquares : float = 0.0
var outputrms : float = 0.0
var opusframesize = 960
var tailframenumber = 0
var playbackstartframenumber = 0
var episodefirstframenumber = 0
var source_next_frame_count: int = 0
var source_next_frame_time_usec: int = 0
var source_packet_first_frame_time_usec: int = 0
var source_bitrate = 0
const Noutoforderqueue = 4
const Npacketinitialbatching = 2
var outoforderchunkqueue = [ ]
var opusframequeuecount = 0
var preheader_audio_packets: Array[Dictionary] = []
var preheader_wrong_parity_discard_count = 0
const PREHEADER_PACKET_LIMIT := TwoVoipPacket.CHUNK_SEQUENCE_MODULUS / 2
var opus_sample_rate = 48000
var opus_channels = 2
var runninglagtimeminimum = -1.0
var decoded_frame_max_values := PackedFloat32Array()
var playback_padding_end_frame = 0
var playback_restart_count = 0
var playback_clock_anchor_ticks_usec = 0
var playback_clock_anchor_speaker_frame = 0
var playback_clock_stall_count = 0
var playback_clock_stall_total_usec = 0
var playback_clock_last_stall_usec = 0
var playback_underflow_baseline = 0
var silence_recovery_baseline = 0
var speedup_recovery_baseline = 0
var playout_recovery_target_frames = 0
var playout_delay_extension_usec = 0
var playout_timeline_offset_usec = 0
var playout_timeline_base_offset_usec = 0
var playout_timeline_base_offset_valid := false
var playout_timeline_candidate_deviation_usec := 0
var playout_timeline_max_deviation_usec := 0
var dropped_packet_count = 0
var duplicate_packet_count = 0
var missing_packet_count = 0
var fec_recovery_count = 0
var loss_silence_count = 0
var mid_time_error_count = 0
var delayed_mid_audio_count = 0
var pending_mid_frame_count = -1
var pending_mid_arrival_usec = 0
var last_mid_to_audio_usec = -1
var source_clock_offset_estimate_usec := 0
var source_clock_offset_lower_bound_usec := 0
var source_clock_offset_upper_bound_usec := 0
var source_clock_offset_uncertainty_usec := 0
var source_clock_probe_rtt_usec := 0
var source_clock_probe_valid := false
var source_clock_unix_estimate_usec := 0
var source_clock_unix_estimate_valid := false
var source_clock_estimate_minus_unix_usec := 0
var source_clock_last_selected_timeline_usec := 0
var source_clock_last_unix_timeline_usec := 0
var source_clock_pre_send_packet_count := 0
var source_clock_revision_reason := "uninitialized"
var source_clock_offset_bound_valid := false
var source_clock_offset_observation_count := 0
var source_clock_offset_revision_count := 0
var source_clock_reference_deviation_usec := 0
var source_clock_reference_max_deviation_usec := 0
var source_clock_reference_large_change_count := 0
var source_clock_last_revision_usec := 0
const PLAYBACK_CLOCK_STALL_TOLERANCE_USEC := 80000
const SOURCE_CLOCK_REFERENCE_TUNING_TOLERANCE_USEC := 10000
const SOURCE_CLOCK_REFERENCE_DEBUG_TOLERANCE_USEC := 50000
const DISPLAY_EMPTY := -1.0
const DISPLAY_RESERVE := -2.0
const DISPLAY_SOURCE_GAP := -3.0
const DISPLAY_FEC := -4.0
const DISPLAY_LOSS := -5.0

var timing_meter: TwoVoipTimingMeter = null
var initial_playout_padding_aligned := false
var initial_playout_declared_lead_frame_count := 0
var initial_playout_lead_frame_count := 0
var initial_playout_lead_end_frame_count := 0
var initial_playout_skipped_frame_count := 0
var initial_wire_packets_to_skip := 0
var initial_start_arrival_timeline_usec := 0
var initial_source_clock_offset_revision_count := 0
var initial_playout_timeline_started := false
var initial_packet_arrival_timeline_usec := 0
var replaying_transport := false

func _ready():
	audioplayeropus = get_parent().findaudioplayer() if get_parent().has_method("findaudioplayer") else get_parent()
	if audioplayeropus.has_method("set_stream"):
		audiostreamopus = AudioStreamOpus.new()
		audioplayeropus.set_stream(audiostreamopus)
		audioplayeropus.max_polyphony = maximum_simultaneous_episodes
	else:
		audioplayeropus = null
		assert(false, "Audiostream player not found!")


func create_episode_playback() -> bool:
	audioplayeropus.play()  # Every talking episode gets its own playback.
	audio_stream_playback_opus = audioplayeropus.get_stream_playback()
	var result = audio_stream_playback_opus.initialize(opus_sample_rate, opus_channels,
			opusframesize, audio_buffer_length, stale_episode_timeout)
	if result != OK:
		push_error("Could not initialize Opus playback: %s" % error_string(result))
		audio_stream_playback_opus.stop()
		audio_stream_playback_opus = null
		return false
	var recovery_target_frames := roundi(maxf(0.0,
			audio_buffer_lag_time_target - audioserveroutputlatency) * opus_sample_rate)
	result = _configure_playout_recovery_target(recovery_target_frames)
	if result != OK:
		push_error("Could not configure Opus playout recovery: %s" % error_string(result))
		audio_stream_playback_opus.stop()
		audio_stream_playback_opus = null
		return false
	silence_recovery_baseline = 0
	speedup_recovery_baseline = 0
	set_sinewave_out(sinewaveoutmode)
	return true


func _configure_playout_recovery_target(target_frames: int) -> Error:
	playout_recovery_target_frames = maxi(0, target_frames)
	return audio_stream_playback_opus.configure_playout_recovery(
			playout_recovery_target_frames, maximum_playout_recovery_speed)

func setrecopusvalues(new_opus_sample_rate, new_opus_channels, new_opus_frame_size):
	opus_sample_rate = new_opus_sample_rate
	opus_channels = new_opus_channels
	opusframesize = new_opus_frame_size
	decoded_frame_max_values.resize(max(1,
			ceili(max(2.0, audio_buffer_length) * opus_sample_rate / opusframesize)))
	decoded_frame_max_values.fill(DISPLAY_EMPTY)
	if timing_meter:
		timing_meter.configure(opus_sample_rate, opusframesize)

func _set_diagnostic_trigger(trigger: String):
	if timing_meter:
		timing_meter.set_trigger(trigger)

func init_voip_speaker(p_timing_meter: TwoVoipTimingMeter = null):
	timing_meter = p_timing_meter
	if timing_meter:
		timing_meter.bind_speaker(self)

func queue_playout_delay(next_frame_time_usec: int) -> int:
	var frame_age := (Time.get_ticks_usec() - next_frame_time_usec \
			- source_clock_offset_estimate_usec) / 1000000.0
	var padding_frames := roundi(max(0.0,
			audio_buffer_lag_time_target - audioserveroutputlatency - frame_age) \
			* opus_sample_rate)
	padding_frames = min(padding_frames,
			max(0, audio_stream_playback_opus.available_space_frames() - opusframesize))
	if audio_stream_playback_opus.push_silence(padding_frames) != padding_frames:
		push_error("Could not queue Opus playout delay")
		return 0
	return padding_frames

func queue_initial_playout_delay(start_arrival_timeline: float) -> int:
	# No audio has been decoded when this is called. The packets are appended
	# afterwards, so subtracting their duration here would count them twice.
	var padding_frames := calculate_initial_playout_padding_frames(
			start_arrival_timeline)
	padding_frames = min(padding_frames,
			max(0, audio_stream_playback_opus.available_space_frames() - opusframesize))
	if audio_stream_playback_opus.push_silence(padding_frames) != padding_frames:
		push_error("Could not queue initial Opus playout delay")
		return 0
	return padding_frames

func calculate_initial_playout_padding_frames(
		start_arrival_timeline: float) -> int:
	return roundi(maxf(0.0,
			audio_buffer_lag_time_target - audioserveroutputlatency \
			- start_arrival_timeline) * opus_sample_rate)

func trim_initial_lead_to_target():
	var chunk_time: float = opusframesize / float(opus_sample_rate)
	var usable_lead_time: float = maxf(0.0, audio_buffer_lag_time_target \
			- audioserveroutputlatency \
			- TwoVoipPacket.ACQUISITION_TIME_ESTIMATE)
	# Keep at least one chunk of real zero padding between retained history and
	# the acquisition edge. Any older declared lead packets are intentionally
	# skipped, with the source counter and timestamp advanced by the same amount.
	var maximum_lead_frames: int = maxi(0,
			floori(usable_lead_time / chunk_time) - 1)
	var skip_frames: int = maxi(0,
			initial_playout_lead_frame_count - maximum_lead_frames)
	initial_playout_skipped_frame_count = skip_frames
	initial_wire_packets_to_skip = skip_frames
	initial_playout_lead_frame_count -= skip_frames
	source_next_frame_count += skip_frames
	source_next_frame_time_usec += roundi(skip_frames * chunk_time * 1000000.0)

func mark_initial_playout_padding_aligned():
	# The first real packet performs the one and only padding calculation.
	# Reaching the initial batch/lead boundary merely marks that controlled fill
	# complete; later arrivals must not add a second block of silence.
	initial_playout_padding_aligned = true

func get_effective_playout_lag_target() -> float:
	return audio_buffer_lag_time_target + playout_delay_extension_usec / 1000000.0

func observe_source_clock_reference(arrival_time_usec: int,
		source_time_usec: int, known_delay_usec: int,
		diagnose_reference_change := false) -> int:
	var candidate_upper_bound := arrival_time_usec - source_time_usec \
			- known_delay_usec
	source_clock_offset_observation_count += 1
	if not source_clock_offset_bound_valid:
		source_clock_offset_estimate_usec = candidate_upper_bound
		source_clock_offset_lower_bound_usec = candidate_upper_bound
		source_clock_offset_upper_bound_usec = candidate_upper_bound
		source_clock_offset_bound_valid = true
		source_clock_offset_revision_count += 1
		source_clock_revision_reason = "provisional one-way START reference"
	elif diagnose_reference_change and not source_clock_probe_valid:
		# A later episode is an observation of the established clock relation,
		# never permission to silently move it. Small residuals are tuning data;
		# large ones are evidence that needs an explicit explanation.
		source_clock_reference_deviation_usec = \
				candidate_upper_bound - source_clock_offset_estimate_usec
		source_clock_reference_max_deviation_usec = maxi(
				source_clock_reference_max_deviation_usec,
				absi(source_clock_reference_deviation_usec))
		if absi(source_clock_reference_deviation_usec) \
				>= SOURCE_CLOCK_REFERENCE_DEBUG_TOLERANCE_USEC:
			source_clock_reference_large_change_count += 1
			push_error("TwoVoIP clock reference changed by %+.3f ms; holding %.3f ms offset" % [
					source_clock_reference_deviation_usec / 1000.0,
					source_clock_offset_estimate_usec / 1000.0])
			_set_diagnostic_trigger("clock reference discontinuity %+.1f ms (held)" \
					% (source_clock_reference_deviation_usec / 1000.0))
		elif absi(source_clock_reference_deviation_usec) \
				> SOURCE_CLOCK_REFERENCE_TUNING_TOLERANCE_USEC:
			push_warning("TwoVoIP clock reference differs by %+.3f ms; holding %.3f ms offset" % [
					source_clock_reference_deviation_usec / 1000.0,
					source_clock_offset_estimate_usec / 1000.0])
	return arrival_time_usec - source_time_usec \
			- source_clock_offset_estimate_usec


func set_source_clock_estimate(estimate_usec: int, lower_bound_usec: int,
		upper_bound_usec: int, round_trip_usec: int, reason: String,
		unix_estimate_usec: int = 0, unix_estimate_valid := false):
	assert(lower_bound_usec <= estimate_usec)
	assert(estimate_usec <= upper_bound_usec)
	var previous_estimate_usec := source_clock_offset_estimate_usec
	var had_previous_estimate := source_clock_offset_bound_valid
	source_clock_offset_estimate_usec = estimate_usec
	source_clock_offset_lower_bound_usec = lower_bound_usec
	source_clock_offset_upper_bound_usec = upper_bound_usec
	source_clock_offset_uncertainty_usec = maxi(
			estimate_usec - lower_bound_usec,
			upper_bound_usec - estimate_usec)
	source_clock_probe_rtt_usec = round_trip_usec
	source_clock_probe_valid = true
	source_clock_unix_estimate_usec = unix_estimate_usec
	source_clock_unix_estimate_valid = unix_estimate_valid
	source_clock_estimate_minus_unix_usec = estimate_usec - unix_estimate_usec \
			if unix_estimate_valid else 0
	source_clock_offset_bound_valid = true
	source_clock_revision_reason = reason
	source_clock_last_revision_usec = previous_estimate_usec - estimate_usec \
			if had_previous_estimate else 0
	source_clock_offset_revision_count += 1
	_set_diagnostic_trigger("clock probe → offset %+.1f ± %.1f ms" % [
			estimate_usec / 1000.0,
			source_clock_offset_uncertainty_usec / 1000.0])

func observe_source_clock_timing(arrival_time_usec: int,
		source_time_usec: int) -> int:
	source_clock_offset_observation_count += 1
	var selected_timeline_usec := arrival_time_usec - source_time_usec \
			- source_clock_offset_estimate_usec
	source_clock_last_selected_timeline_usec = selected_timeline_usec
	if source_clock_unix_estimate_valid:
		source_clock_last_unix_timeline_usec = arrival_time_usec \
				- source_time_usec - source_clock_unix_estimate_usec
	# Earlier than the end of acquisition means the selected mapping claims the
	# packet arrived before its estimated send time. Preserve that contradiction.
	if selected_timeline_usec < roundi(
			TwoVoipPacket.ACQUISITION_TIME_ESTIMATE * 1000000.0):
		source_clock_pre_send_packet_count += 1
	return selected_timeline_usec

func _reset_playback_clock_anchor():
	playback_clock_anchor_ticks_usec = Time.get_ticks_usec()
	playback_clock_anchor_speaker_frame = \
			audio_stream_playback_opus.get_frame_number_actually_in_speaker() \
			if audio_stream_playback_opus else 0

func _reset_playback_underflow_baseline():
	playback_underflow_baseline = audio_stream_playback_opus.get_underflow_frames() \
			if audio_stream_playback_opus else 0
	silence_recovery_baseline = audio_stream_playback_opus.get_silence_recovery_frames() \
			if audio_stream_playback_opus else 0
	speedup_recovery_baseline = audio_stream_playback_opus.get_speedup_recovery_frames() \
			if audio_stream_playback_opus else 0


func _sync_playout_recovery_position():
	if audio_stream_playback_opus == null:
		return
	var previous_extension_usec: int = playout_delay_extension_usec
	var remaining_frames: int = maxi(0,
			audio_stream_playback_opus.get_playout_recovery_remaining_frames())
	playout_delay_extension_usec = roundi(
			remaining_frames * 1000000.0 / opus_sample_rate)
	if playout_timeline_base_offset_valid:
		playout_timeline_offset_usec = playout_timeline_base_offset_usec \
				+ playout_delay_extension_usec
	else:
		playout_timeline_offset_usec += \
				playout_delay_extension_usec - previous_extension_usec


func _account_playback_recovery():
	if audio_stream_playback_opus == null:
		return
	var silence_total: int = audio_stream_playback_opus.get_silence_recovery_frames()
	var speedup_total: int = audio_stream_playback_opus.get_speedup_recovery_frames()
	var silence_frames := maxi(0, silence_total - silence_recovery_baseline)
	var speedup_frames := maxi(0, speedup_total - speedup_recovery_baseline)
	silence_recovery_baseline = silence_total
	speedup_recovery_baseline = speedup_total
	var recovered_frames := silence_frames + speedup_frames
	# The audio thread owns recovery. Its remaining-frame counter is the single
	# source of truth for red's displacement from the fixed target; the two
	# cumulative counters below only explain how that debt was consumed.
	_sync_playout_recovery_position()
	if recovered_frames == 0:
		return
	if silence_frames > 0:
		_set_diagnostic_trigger("catch-up → crossed %.1f ms of zero PCM" %
				(silence_frames * 1000.0 / opus_sample_rate))
	else:
		_set_diagnostic_trigger("catch-up → %.2fx playback recovered %.1f ms" % [
				maximum_playout_recovery_speed,
				speedup_frames * 1000.0 / opus_sample_rate])

func _account_playback_underflow():
	if audio_stream_playback_opus == null:
		return
	_account_playback_recovery()
	var underflow_total: int = audio_stream_playback_opus.get_underflow_frames()
	var new_underflow_frames := maxi(0, underflow_total - playback_underflow_baseline)
	playback_underflow_baseline = underflow_total
	if new_underflow_frames == 0:
		return
	var mix_rate := AudioServer.get_mix_rate()
	if mix_rate <= 0.0:
		return
	var extension_usec := roundi(new_underflow_frames * 1000000.0 / mix_rate)
	var recovery_frames := roundi(new_underflow_frames * opus_sample_rate / mix_rate)
	var recovery_remaining: int = audio_stream_playback_opus.request_playout_recovery(
			recovery_frames)
	_sync_playout_recovery_position()
	_set_diagnostic_trigger("input starvation → recover %.0f ms (%.0f ms pending)" % [
			extension_usec / 1000.0,
			maxi(0, recovery_remaining) * 1000.0 / opus_sample_rate])

func _account_playback_clock_stall(stalled_usec: int):
	if stalled_usec <= 0 or audio_stream_playback_opus == null:
		return
	playback_clock_stall_count += 1
	playback_clock_stall_total_usec += stalled_usec
	playback_clock_last_stall_usec = stalled_usec
	var recovery_frames := roundi(stalled_usec * opus_sample_rate / 1000000.0)
	var recovery_remaining: int = audio_stream_playback_opus.request_playout_recovery(
			recovery_frames)
	_sync_playout_recovery_position()
	_set_diagnostic_trigger("local playback pause → recover %.0f ms (%.0f ms pending)" % [
			stalled_usec / 1000.0,
			maxi(0, recovery_remaining) * 1000.0 / opus_sample_rate])
	if timing_meter:
		timing_meter.record_local_playback_stall()

func _playback_clock_stall_usec() -> int:
	if audio_stream_playback_opus == null or playback_clock_anchor_ticks_usec == 0:
		return 0
	# With no decoded input available, a stationary source-frame position is
	# normal starvation, not proof that local playback paused. Start a fresh
	# comparison when input resumes.
	if audio_stream_playback_opus.queue_length_frames() == 0:
		_reset_playback_clock_anchor()
		return 0
	var elapsed_usec: int = Time.get_ticks_usec() - playback_clock_anchor_ticks_usec
	var elapsed_speaker_frames: int = \
			audio_stream_playback_opus.get_frame_number_actually_in_speaker() \
			- playback_clock_anchor_speaker_frame
	var speaker_elapsed_usec := roundi(
			elapsed_speaker_frames * 1000000.0 / opus_sample_rate)
	return maxi(0, elapsed_usec - speaker_elapsed_usec)

func restart_episode_playback(reason := "playback stopped") -> bool:
	if not inopusstream:
		return false
	if audio_stream_playback_opus and audio_stream_playback_opus.is_playing():
		audio_stream_playback_opus.stop()
	if not create_episode_playback():
		return false
	var next_frame_time_usec := source_next_frame_time_usec \
			+ int((opusframecount - source_next_frame_count) * opusframesize \
			* 1000000.0 / opus_sample_rate)
	var padding_frames := queue_playout_delay(next_frame_time_usec)
	if _configure_playout_recovery_target(padding_frames) != OK:
		push_error("Could not update Opus recovery target")
		return false
	playbackstartframenumber = tailframenumber - padding_frames
	playback_padding_end_frame = tailframenumber
	_set_playout_timeline_offset(next_frame_time_usec)
	playback_restart_count += 1
	_reset_playback_clock_anchor()
	_reset_playback_underflow_baseline()
	_set_diagnostic_trigger("local %s → replace playback" % reason)
	return true

func ensure_episode_playback(required_space_frames := 0) -> bool:
	if not replaying_transport:
		_account_playback_underflow()
	if audio_stream_playback_opus == null or not audio_stream_playback_opus.is_playing():
		return restart_episode_playback("starvation")
	if not replaying_transport:
		var stalled_usec := _playback_clock_stall_usec()
		if stalled_usec > PLAYBACK_CLOCK_STALL_TOLERANCE_USEC:
			_account_playback_clock_stall(stalled_usec)
	# Each packet gives us a fresh short comparison between monotonic time and
	# the independently advancing audio clock. This prevents harmless fractional
	# rate error from accumulating until it resembles a pause.
	_reset_playback_clock_anchor()
	if required_space_frames > audio_stream_playback_opus.available_space_frames():
		# A local pause can release more queued packets than this bounded playback
		# can hold. Replace the local backlog, but retain the wire episode, source
		# counters and reorder window.
		return restart_episode_playback("backlog overflow")
	return true

func start_playback_timeline(next_frame_count: int, next_frame_time_usec: int,
		start_arrival_timeline_usec: int, local_arrival_time_usec: int):
	var padding_frames := queue_initial_playout_delay(
			start_arrival_timeline_usec / 1000000.0)
	if _configure_playout_recovery_target(padding_frames) != OK:
		push_error("Could not update initial Opus recovery target")
	opusframecount = next_frame_count
	tailframenumber = opusframecount * opusframesize
	episodefirstframenumber = tailframenumber
	playbackstartframenumber = tailframenumber - padding_frames
	playback_padding_end_frame = tailframenumber
	source_next_frame_time_usec = next_frame_time_usec
	_set_playout_timeline_offset(
			next_frame_time_usec, local_arrival_time_usec, true)
	_reset_playback_clock_anchor()
	_reset_playback_underflow_baseline()

func start_initial_playback_from_packet(arrival_time_usec: int,
		source_time_usec: int, packet_frame_count: int) -> bool:
	if initial_playout_timeline_started:
		return true
	if (audio_stream_playback_opus == null \
			or not audio_stream_playback_opus.is_playing()) \
			and not create_episode_playback():
		return false
	initial_packet_arrival_timeline_usec = observe_source_clock_timing(
			arrival_time_usec, source_time_usec)
	# Playback is anchored at source_next_frame_count, which can precede the
	# first packet received when startup packets are reordered. Convert that
	# packet's measured age to the anchor frame exactly once.
	initial_start_arrival_timeline_usec = initial_packet_arrival_timeline_usec \
			+ roundi((packet_frame_count - source_next_frame_count) \
			* opusframesize * 1000000.0 / opus_sample_rate)
	initial_source_clock_offset_revision_count = \
			source_clock_offset_revision_count
	start_playback_timeline(
			source_next_frame_count,
			source_next_frame_time_usec,
			initial_start_arrival_timeline_usec,
			arrival_time_usec)
	initial_playout_timeline_started = true
	_set_diagnostic_trigger("first audio → establish playout timeline")
	return true

func push_silent_opus_frames(frame_count: int) -> bool:
	if frame_count <= 0:
		return true
	var silent_sample_frames: int = frame_count * opusframesize
	if not ensure_episode_playback(silent_sample_frames) or audio_stream_playback_opus.push_silence(silent_sample_frames) != silent_sample_frames:
		push_warning("Not enough playback buffer space for %d silent Opus frames" % frame_count)
		return false
	for frame in range(opusframecount, opusframecount + frame_count):
		decoded_frame_max_values[frame % decoded_frame_max_values.size()] = \
				DISPLAY_SOURCE_GAP
	opusframecount += frame_count
	tailframenumber += silent_sample_frames
	_set_diagnostic_trigger("MID → insert %d source-gap chunk%s" % [frame_count, "" if frame_count == 1 else "s"])
	return true

func report_opus_error(opus_err):
	if opus_err == -4:
		push_error("OPUS_INVALID_PACKET")
	elif opus_err == -1:
		push_error("OPUS_BAD_ARG")
	else:
		push_error("OPUS_ERR")

func push_opus_packet(packet: PackedByteArray, begin: int, decode_fec: bool):
	if not ensure_episode_playback(opusframesize):
		return -1
	var decoded_frames = audio_stream_playback_opus.push_opus_packet(packet, begin, 1 if decode_fec else 0)
	if decoded_frames < 0:
		report_opus_error(decoded_frames)
	else:
		assert (tailframenumber == opusframecount*opusframesize)
		var chunk_index = int(tailframenumber / opusframesize)
		decoded_frame_max_values[chunk_index % decoded_frame_max_values.size()] = \
				DISPLAY_FEC if decode_fec \
				else audio_stream_playback_opus.get_tail_max(opusframesize)
		outputsumsquares += audio_stream_playback_opus.get_tail_sum_squares(opusframesize)
		tailframenumber += decoded_frames
		if decode_fec:
			_set_diagnostic_trigger("missing packet → Opus FEC")
	return decoded_frames


func _shift_reorder_queue():
	outoforderchunkqueue.pop_front()
	outoforderchunkqueue.push_back(null)


func _push_missing_frame(recovery_packet) -> bool:
	missing_packet_count += 1
	if recovery_packet != null:
		if push_opus_packet(recovery_packet, lenchunkprefix, true) < 0:
			return false
		fec_recovery_count += 1
		return true
	if not ensure_episode_playback(opusframesize) \
			or audio_stream_playback_opus.push_silence(opusframesize) != opusframesize:
		return false
	assert(tailframenumber == opusframecount * opusframesize)
	decoded_frame_max_values[opusframecount \
			% decoded_frame_max_values.size()] = DISPLAY_LOSS
	tailframenumber += opusframesize
	loss_silence_count += 1
	_set_diagnostic_trigger("missing packet → silence")
	return true


func _consume_reorder_head(confirm_missing := false) -> bool:
	if outoforderchunkqueue[0] != null:
		if push_opus_packet(outoforderchunkqueue[0], lenchunkprefix, false) < 0:
			return false
		opusframequeuecount -= 1
	elif confirm_missing:
		# Opus in-band FEC in packet N can only reconstruct packet N-1. Never
		# reuse an arbitrary future packet for several older holes.
		var recovery_packet = outoforderchunkqueue[1] \
				if outoforderchunkqueue.size() > 1 else null
		if not _push_missing_frame(recovery_packet):
			return false
	else:
		return false
	_shift_reorder_queue()
	opusframecount += 1
	assert(opusframequeuecount >= 0)
	return true


func _flush_reorder_through(final_frame_count: int):
	while opusframecount < final_frame_count:
		if not _consume_reorder_head(true):
			break


func _hold_preheader_audio(packet: PackedByteArray,
		transport_debug_context: Dictionary):
	if preheader_audio_packets.size() >= PREHEADER_PACKET_LIMIT:
		preheader_audio_packets.pop_front()
		dropped_packet_count += 1
	preheader_audio_packets.append({
		"packet": packet.duplicate(),
		"context": transport_debug_context.duplicate(true),
	})
	_set_diagnostic_trigger("audio before START → hold")


func _replay_matching_preheader_audio():
	if preheader_audio_packets.is_empty():
		return
	var held_packets := preheader_audio_packets
	preheader_audio_packets = []
	for held in held_packets:
		var wire_packet: PackedByteArray = held.packet
		var decoded_packet := TwoVoipPacket.decode_audio_packet(
				wire_packet, audio_packets_base64)
		if lenchunkprefix >= TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE \
				and decoded_packet.size() >= TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE \
				and decoded_packet[0] & TwoVoipPacket.CHUNK_STREAM_PARITY_MASK \
						!= (opusstreamcount % 2) \
						* TwoVoipPacket.CHUNK_STREAM_PARITY_MASK:
			preheader_wrong_parity_discard_count += 1
			continue
		receive_audio_packet(wire_packet, held.context)

func get_frame_max(frame_number: int) -> float:
	if frame_number < episodefirstframenumber or opusframesize <= 0 \
			or decoded_frame_max_values.is_empty():
		return 0.0
	var chunk_index := int(frame_number / opusframesize)
	return maxf(0.0,
			decoded_frame_max_values[chunk_index % decoded_frame_max_values.size()])

func get_incoming_bitrate() -> int:
	return source_bitrate

func get_playout_lag_time() -> float:
	if audio_stream_playback_opus == null:
		return 0.0
	return audioserveroutputlatency \
			+ audio_stream_playback_opus.queue_length_frames() * 1.0 / opus_sample_rate

func _set_playout_timeline_offset(source_tail_time_usec: int,
		local_time_usec := 0, episode_start_reference := false):
	var now_usec := local_time_usec if local_time_usec != 0 else \
			Time.get_ticks_usec()
	var candidate_offset_usec := now_usec \
			+ roundi(get_playout_lag_time() * 1000000.0) - source_tail_time_usec
	if not playout_timeline_base_offset_valid and not episode_start_reference:
		# A MID or local restart can create playback before the first audio packet.
		# It may position that temporary playback, but cannot establish the durable
		# episode-to-episode relation.
		playout_timeline_offset_usec = candidate_offset_usec \
				+ playout_delay_extension_usec
		return
	if not playout_timeline_base_offset_valid:
		playout_timeline_base_offset_usec = candidate_offset_usec
		playout_timeline_base_offset_valid = true
	elif episode_start_reference:
		playout_timeline_candidate_deviation_usec = \
				candidate_offset_usec - playout_timeline_base_offset_usec
		playout_timeline_max_deviation_usec = maxi(
				playout_timeline_max_deviation_usec,
				absi(playout_timeline_candidate_deviation_usec))
		if absi(playout_timeline_candidate_deviation_usec) \
				>= SOURCE_CLOCK_REFERENCE_DEBUG_TOLERANCE_USEC:
			push_error("TwoVoIP playout offset candidate changed by %+.3f ms; holding %.3f ms base" % [
					playout_timeline_candidate_deviation_usec / 1000.0,
					playout_timeline_base_offset_usec / 1000.0])
			_set_diagnostic_trigger("playout offset discontinuity %+.1f ms (held)" \
					% (playout_timeline_candidate_deviation_usec / 1000.0))
		elif absi(playout_timeline_candidate_deviation_usec) \
				> SOURCE_CLOCK_REFERENCE_TUNING_TOLERANCE_USEC:
			push_warning("TwoVoIP playout offset candidate differs by %+.3f ms; holding %.3f ms base" % [
					playout_timeline_candidate_deviation_usec / 1000.0,
					playout_timeline_base_offset_usec / 1000.0])
	# Episode startup returns to the established baseline. Accounted starvation
	# and recovery alter only the active offset and extension, never this base.
	playout_timeline_offset_usec = playout_timeline_base_offset_usec \
			+ playout_delay_extension_usec

func get_playout_local_time_usec() -> int:
	return Time.get_ticks_usec()

func get_source_tail_time_usec() -> int:
	if source_next_frame_time_usec == 0 or opusframesize <= 0:
		return 0
	var source_anchor_frame: int = source_next_frame_count * opusframesize
	return source_next_frame_time_usec + roundi(
			(tailframenumber - source_anchor_frame) * 1000000.0 / opus_sample_rate)

func get_expected_playout_lag_usec() -> int:
	var source_tail_time_usec := get_source_tail_time_usec()
	if source_tail_time_usec == 0 or playout_timeline_offset_usec == 0:
		return 0
	var now_usec := get_playout_local_time_usec()
	return source_tail_time_usec + playout_timeline_offset_usec - now_usec

func get_timing_buffer_residual_usec() -> int:
	if audio_stream_playback_opus == null:
		return 0
	return roundi(get_playout_lag_time() * 1000000.0) \
			- get_expected_playout_lag_usec()

func external_end_stream():
	if inopusstream:
		print(":externally ending the stream at cutout")
		var footer := TwoVoipPacket.make_footer(opusstreamcount, opusframecount, 0.0, -1.0)
		receive_audio_packet(TwoVoipPacket.encode_control_packet(footer))

func _mid_timeline_residual_usec(next_frame_count: int, next_frame_time_usec: int) -> int:
	if source_next_frame_time_usec == 0:
		return 0
	var frame_usec := roundi(opusframesize * 1000000.0 / opus_sample_rate)
	var expected_time_usec := source_next_frame_time_usec \
			+ (next_frame_count - source_next_frame_count) * frame_usec
	return next_frame_time_usec - expected_time_usec

func _check_pending_mid_audio(arrival_time_usec: int, frame_count: int):
	if pending_mid_frame_count < 0 or frame_count < pending_mid_frame_count:
		return
	if frame_count == pending_mid_frame_count:
		last_mid_to_audio_usec = arrival_time_usec - pending_mid_arrival_usec
		var frame_usec := roundi(opusframesize * 1000000.0 / opus_sample_rate)
		if last_mid_to_audio_usec > maxi(50000, frame_usec * 2):
			delayed_mid_audio_count += 1
			_set_diagnostic_trigger("MID-to-audio delivery delay")
			push_warning("TwoVoIP MID preceded frame %d by %.1f ms on the reliable path" % [
					frame_count, last_mid_to_audio_usec / 1000.0])
	else:
		delayed_mid_audio_count += 1
		_set_diagnostic_trigger("MID target packet missing")
	pending_mid_frame_count = -1
	pending_mid_arrival_usec = 0

func receive_audio_control_packet(control_packet: Array,
		transport_debug_context: Dictionary = {}):
	if control_packet.is_empty():
		push_warning("Invalid TwoVoIP control packet")
		return
	var packet_type = control_packet[0]
	if packet_type == TwoVoipPacket.TYPE_START:
		if not TwoVoipPacket.header_is_valid(control_packet):
			push_warning("Unsupported or malformed TwoVoIP stream header")
			return
		if audio_stream_playback_opus:
			audio_stream_playback_opus.stop()
			audio_stream_playback_opus = null
		setrecopusvalues(
				int(control_packet[TwoVoipPacket.HeaderField.OPUS_SAMPLE_RATE]),
				int(control_packet[TwoVoipPacket.HeaderField.OPUS_CHANNELS]),
				int(control_packet[TwoVoipPacket.HeaderField.OPUS_FRAME_SIZE]))
		lenchunkprefix = int(control_packet[TwoVoipPacket.HeaderField.CHUNK_PREFIX_LENGTH])
		opusstreamcount = int(control_packet[TwoVoipPacket.HeaderField.OPUS_STREAM_COUNT])
		source_next_frame_count = int(control_packet[TwoVoipPacket.HeaderField.NEXT_FRAME_COUNT])
		source_next_frame_time_usec = int(control_packet[TwoVoipPacket.HeaderField.NEXT_FRAME_TIME_USEC])
		source_packet_first_frame_time_usec = 0
		source_bitrate = int(control_packet[TwoVoipPacket.HeaderField.OPUS_BITRATE])
		audio_packets_base64 = TwoVoipPacket.header_uses_base64(control_packet)
		initial_playout_declared_lead_frame_count = \
				TwoVoipPacket.header_lead_frame_count(control_packet)
		initial_playout_lead_frame_count = \
				initial_playout_declared_lead_frame_count
		initial_playout_lead_end_frame_count = source_next_frame_count \
				+ initial_playout_lead_frame_count
		initial_wire_packets_to_skip = 0
		initial_playout_skipped_frame_count = 0
		opusframecount = 0
		outputsumsquares = 0.0
		outputrms = 0.0
		tailframenumber = 0
		playbackstartframenumber = 0
		episodefirstframenumber = 0
		outoforderchunkqueue.clear()
		for i in range(Noutoforderqueue):
			outoforderchunkqueue.push_back(null)
		opusframequeuecount = 0
		assert(Npacketinitialbatching < Noutoforderqueue)
		runninglagtimeminimum = -1.0
		inopusstream = true
		playback_restart_count = 0
		playback_clock_stall_count = 0
		playback_clock_stall_total_usec = 0
		playback_clock_last_stall_usec = 0
		initial_playout_padding_aligned = false
		initial_playout_timeline_started = false
		initial_packet_arrival_timeline_usec = 0
		playout_delay_extension_usec = 0
		playout_timeline_offset_usec = playout_timeline_base_offset_usec \
				if playout_timeline_base_offset_valid else 0
		dropped_packet_count = 0
		duplicate_packet_count = 0
		preheader_wrong_parity_discard_count = 0
		missing_packet_count = 0
		fec_recovery_count = 0
		loss_silence_count = 0
		mid_time_error_count = 0
		delayed_mid_audio_count = 0
		pending_mid_frame_count = -1
		pending_mid_arrival_usec = 0
		last_mid_to_audio_usec = -1
		var start_arrival_usec := int(transport_debug_context.get(
				"arrival_time_usec",
				Time.get_ticks_usec()))
		# START announces the first sample timestamp before that audio packet has
		# completed acquisition. It is therefore the zero-delay clock reference;
		# the first real packet measures acquisition plus delivery from that point.
		observe_source_clock_reference(
				start_arrival_usec, source_next_frame_time_usec, 0,
				not source_clock_probe_valid)
		trim_initial_lead_to_target()
		opusframecount = source_next_frame_count
		tailframenumber = opusframecount * opusframesize
		episodefirstframenumber = tailframenumber
		if timing_meter:
			timing_meter.begin_episode()
		_set_diagnostic_trigger("START → await first audio")
		_replay_matching_preheader_audio()
	elif packet_type == TwoVoipPacket.TYPE_MID:
		if not TwoVoipPacket.mid_is_valid(control_packet):
			push_warning("Malformed TwoVoIP mid-stream update")
			return
		if not inopusstream or int(control_packet[TwoVoipPacket.MidField.OPUS_STREAM_COUNT]) != opusstreamcount:
			return
		if not ensure_episode_playback():
			return
		var mid_next_frame_count := int(control_packet[TwoVoipPacket.MidField.NEXT_FRAME_COUNT])
		var mid_next_frame_time_usec := int(control_packet[TwoVoipPacket.MidField.NEXT_FRAME_TIME_USEC])
		if mid_next_frame_count < opusframecount:
			_set_diagnostic_trigger("stale MID → ignore")
			return
		var mid_time_residual_usec := _mid_timeline_residual_usec(
				mid_next_frame_count, mid_next_frame_time_usec)
		if mid_time_residual_usec != 0:
			# A same-episode MID comes from data we control. Its counter remains
			# authoritative on a reliable path. Keep the established time grid;
			# a bad timestamp is a source protocol bug, not packet loss/FEC.
			mid_time_error_count += 1
			_set_diagnostic_trigger("MID time error → apply counter")
			push_error("TwoVoIP MID time error stream=%d frame=%d previous_frame=%d residual=%+d usec" % [
					opusstreamcount, mid_next_frame_count, source_next_frame_count,
					mid_time_residual_usec])
			mid_next_frame_time_usec -= mid_time_residual_usec
		source_next_frame_count = mid_next_frame_count
		source_next_frame_time_usec = mid_next_frame_time_usec
		source_bitrate = int(control_packet[TwoVoipPacket.MidField.OPUS_BITRATE])
		if source_next_frame_count > opusframecount:
			pending_mid_frame_count = source_next_frame_count
			pending_mid_arrival_usec = Time.get_ticks_usec()
		if source_next_frame_count > opusframecount:
			push_silent_opus_frames(source_next_frame_count - opusframecount)
	elif packet_type == TwoVoipPacket.TYPE_END:
		if not TwoVoipPacket.footer_is_valid(control_packet):
			push_warning("Malformed TwoVoIP stream footer")
			return
		if int(control_packet[TwoVoipPacket.FooterField.OPUS_STREAM_COUNT]) != opusstreamcount:
			return
		var final_frame_count := int(
				control_packet[TwoVoipPacket.FooterField.OPUS_FRAME_COUNT])
		if final_frame_count > opusframecount:
			_flush_reorder_through(final_frame_count)
		if audio_stream_playback_opus:
			audio_stream_playback_opus.finish_episode()
		var outputframecount = tailframenumber - episodefirstframenumber
		outputrms = sqrt(outputsumsquares/outputframecount) if outputframecount > 0 else 0.0
		control_packet[TwoVoipPacket.FooterField.RMS] = outputrms
		print("TwoVoIP speaker END stream=%d minimum_buffer=%.3f s target=%.3f s slip=%.3f s zero_recovery=%.3f s speed_recovery=%.3f s restarts=%d stale=%d duplicate=%d missing=%d fec=%d silence=%d" % [
				opusstreamcount, runninglagtimeminimum, get_effective_playout_lag_target(),
				playout_delay_extension_usec / 1000000.0,
				audio_stream_playback_opus.get_silence_recovery_frames() / float(opus_sample_rate)
						if audio_stream_playback_opus else 0.0,
				audio_stream_playback_opus.get_speedup_recovery_frames() / float(opus_sample_rate)
						if audio_stream_playback_opus else 0.0,
				playback_restart_count, dropped_packet_count, duplicate_packet_count,
				missing_packet_count, fec_recovery_count, loss_silence_count])
		inopusstream = false
		_set_diagnostic_trigger("END → drain episode")
		return control_packet
	elif packet_type == TwoVoipPacket.TYPE_HASH_REQUEST:
		if not TwoVoipPacket.hash_request_is_valid(control_packet):
			push_warning("Malformed decoded-audio hash request")
			return
		if int(control_packet[TwoVoipPacket.HashRequestField.OPUS_STREAM_COUNT]) != opusstreamcount:
			return
		var first_frame = int(control_packet[TwoVoipPacket.HashRequestField.FIRST_FRAME])
		var frame_count = int(control_packet[TwoVoipPacket.HashRequestField.FRAME_COUNT])
		var hash = -1
		if audio_stream_playback_opus and first_frame >= episodefirstframenumber:
			hash = audio_stream_playback_opus.get_frame_hash(
					first_frame - playbackstartframenumber, frame_count)
		var response = TwoVoipPacket.make_hash_response(
				opusstreamcount, first_frame, frame_count, hash)
		hash_response_ready.emit(TwoVoipPacket.encode_control_packet(response))
	else:
		push_warning("Unknown TwoVoIP control packet type: %s" % packet_type)

func receive_audio_packet(packet, transport_debug_context: Dictionary = {}):
	replaying_transport = bool(transport_debug_context.get("replay", false))
	if timing_meter and not transport_debug_context.is_empty():
		timing_meter.set_transport_context(transport_debug_context)
	if audiostreamopus == null:
		return
	if TwoVoipPacket.is_control_packet(packet):
		return receive_audio_control_packet(
				TwoVoipPacket.decode_control_packet(packet),
				transport_debug_context)
	if not inopusstream:
		_hold_preheader_audio(packet, transport_debug_context)
		return
	var wire_packet: PackedByteArray = packet
	packet = TwoVoipPacket.decode_audio_packet(wire_packet, audio_packets_base64)
	var arrival_time_usec := int(transport_debug_context.get(
			"arrival_time_usec",
			Time.get_ticks_usec()))
	if len(packet) <= lenchunkprefix:
		print("Bad audio packet too short")
		return
	if initial_wire_packets_to_skip > 0:
		initial_wire_packets_to_skip -= 1
		return
	if lenchunkprefix == -1:
		pass

	elif lenchunkprefix == 0:
		source_packet_first_frame_time_usec = source_next_frame_time_usec \
				+ int((opusframecount - source_next_frame_count) * opusframesize \
				* 1000000.0 / opus_sample_rate)
		var first_timeline_packet := not initial_playout_timeline_started
		if first_timeline_packet and not start_initial_playback_from_packet(
				arrival_time_usec, source_packet_first_frame_time_usec,
				opusframecount):
			return
		if not ensure_episode_playback(opusframesize):
			return
		var arrival_timeline_usec := initial_packet_arrival_timeline_usec \
				if first_timeline_packet else observe_source_clock_timing(
				arrival_time_usec, source_packet_first_frame_time_usec)
		if timing_meter:
			timing_meter.record_packet_arrival(
					arrival_time_usec, source_packet_first_frame_time_usec,
					arrival_timeline_usec)
		if opusframecount >= initial_playout_lead_end_frame_count:
			mark_initial_playout_padding_aligned()
		_check_pending_mid_audio(arrival_time_usec, opusframecount)
		if push_opus_packet(packet, lenchunkprefix, false) >= 0:
			opusframecount += 1
			if timing_meter:
				timing_meter.commit_packet_to_playout()

	else:
		assert (lenchunkprefix >= TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE)
		var unwrapped_frame_count := TwoVoipPacket.decode_sequence_chunk_prefix(packet, opusframecount, opusstreamcount)
		if unwrapped_frame_count < 0:
			if packet[0] & TwoVoipPacket.CHUNK_STREAM_PARITY_MASK \
					!= (opusstreamcount % 2) \
					* TwoVoipPacket.CHUNK_STREAM_PARITY_MASK:
				_hold_preheader_audio(wire_packet, transport_debug_context)
				return
			dropped_packet_count += 1
			_set_diagnostic_trigger("stale/wrong episode packet → drop")
			return
		source_packet_first_frame_time_usec = source_next_frame_time_usec \
				+ int((unwrapped_frame_count - source_next_frame_count) * opusframesize \
				* 1000000.0 / opus_sample_rate)
		var first_timeline_packet := not initial_playout_timeline_started
		if first_timeline_packet and not start_initial_playback_from_packet(
				arrival_time_usec, source_packet_first_frame_time_usec,
				unwrapped_frame_count):
			return
		if not ensure_episode_playback():
			return
		var arrival_timeline_usec := initial_packet_arrival_timeline_usec \
				if first_timeline_packet else observe_source_clock_timing(
				arrival_time_usec, source_packet_first_frame_time_usec)
		if timing_meter:
			timing_meter.record_packet_arrival(
					arrival_time_usec, source_packet_first_frame_time_usec,
					arrival_timeline_usec)
		_check_pending_mid_audio(arrival_time_usec, unwrapped_frame_count)
		var opusframecountR = unwrapped_frame_count - opusframecount
		while opusframecountR >= Noutoforderqueue:
			if outoforderchunkqueue[0] == null:
				push_error("TwoVoIP packet gap on reliable transport stream=%d expected=%d received=%d" % [
						opusstreamcount, opusframecount, unwrapped_frame_count])
			if not _consume_reorder_head(true):
				return
			opusframecountR -= 1

		if outoforderchunkqueue[opusframecountR] != null:
			duplicate_packet_count += 1
			_set_diagnostic_trigger("duplicate packet → ignore")
			return
		outoforderchunkqueue[opusframecountR] = packet
		opusframequeuecount += 1
		var initial_received_frame_count: int = opusframecount \
				- source_next_frame_count + opusframequeuecount
		if unwrapped_frame_count >= initial_playout_lead_end_frame_count \
				and outoforderchunkqueue[0] != null \
				and initial_received_frame_count >= Npacketinitialbatching:
			mark_initial_playout_padding_aligned()
		while outoforderchunkqueue[0] != null \
				and opusframecount - source_next_frame_count \
						+ opusframequeuecount >= Npacketinitialbatching:
			if not _consume_reorder_head():
				return
		if timing_meter and initial_playout_padding_aligned \
				and unwrapped_frame_count < opusframecount:
			timing_meter.commit_packet_to_playout()
var playingrecording = false
func _physics_process(_delta):
	if audio_stream_playback_opus == null:
		return
	if not replaying_transport:
		_account_playback_underflow()
	if not audio_stream_playback_opus.is_playing(): # could use the finished signal
		audio_stream_playback_opus = null
		return
	if playingrecording:
		return
	var queuelengthframes = audio_stream_playback_opus.queue_length_frames()
	var bufferlengthtime = audioserveroutputlatency + queuelengthframes*1.0/opus_sample_rate
	if runninglagtimeminimum < 0.0 or bufferlengthtime < runninglagtimeminimum:
		runninglagtimeminimum = bufferlengthtime


func replayrecording(_speedup, recordedheader, recordedopuspackets, recordedfooter):
	playingrecording = true
	receive_audio_packet(TwoVoipPacket.encode_control_packet(recordedheader))
	for x in recordedopuspackets:
		if recordedheader[TwoVoipPacket.HeaderField.OPUS_FRAME_SIZE] > audio_stream_playback_opus.available_space_frames():
			var tmm = audio_stream_playback_opus.queue_length_frames()*0.5/opus_sample_rate
			await get_tree().create_timer(tmm).timeout
		receive_audio_packet(x)
	receive_audio_packet(TwoVoipPacket.encode_control_packet(recordedfooter))
	playingrecording = false

var sinewaveoutmode = false
func set_sinewave_out(toggled_on):
	sinewaveoutmode = toggled_on
	if audio_stream_playback_opus:
		audio_stream_playback_opus.set_sinewave_frames(opus_sample_rate/440 if toggled_on else 0, 0.05)
