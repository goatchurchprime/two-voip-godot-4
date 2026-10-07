class_name TwoVoipTimingMeter
extends Control

const FRAME_KIND_AUDIO := "audio"
const FRAME_KIND_FEC := "fec"
const FRAME_KIND_LOSS := "loss silence"
const FRAME_KIND_SOURCE_GAP := "source gap"
const FRAME_KIND_RESERVE := "reserve"

const TIMING_AUDIO := Color(0.32, 0.68, 1.0, 1.0)
const TIMING_RESERVE := Color(0.72, 0.75, 0.8, 1.0)
const TIMING_SOURCE_GAP := Color(0.76, 0.4, 0.95, 1.0)
const TIMING_FEC := Color(1.0, 0.58, 0.18, 1.0)
const TIMING_LOSS := Color(1.0, 0.22, 0.18, 1.0)
const TIMING_EMPTY := Color(0.0, 0.0, 0.0, 0.0)
const TIMING_UNKNOWN := Color(1.0, 0.1, 0.85, 1.0)
const TIMING_REORDER_EMPTY := Color(0.12, 0.14, 0.18, 1.0)
const TIMING_ACQUISITION := Color(0.2, 0.9, 0.42, 0.9)
const TIMING_AUDIBLE_DEADLINE := Color(1.0, 0.15, 0.15, 1.0)
const TIMING_TARGET := Color(1.0, 0.65, 0.68, 0.48)
const TIMING_ANOMALY_LOG_PATH := "user://two_voip_timing_anomalies.jsonl"

# These define one stable time coordinate system for the arrival graph, PCM
# cells, target marker, and (eventually) shader uniforms.
@export var acquisition_time_tolerance := 0.01
@export var timing_buffer_tolerance := 0.025
@export var display_span := 1.2
@export var display_before_source := 0.3
# Keep the console report compact. The detailed snapshot remains in the JSONL
# file, where it does not make the Godot debugger render several kilobytes for
# every detected condition.
@export var capture_timing_anomalies := true

var speaker: Node = null
var diagnostic_trigger := "idle"
var last_transport_debug_context: Dictionary = {}
var audible_level_brightness := 0.0

var output_cells: Array[ColorRect] = []
var reorder_slots: Array[ColorRect] = []
var arrival_sparks: Array[ColorRect] = []
var arrival_spark_density := PackedFloat32Array()
var arrival_spark_flash := PackedFloat32Array()
var arrival_spark_offscreen_left_count := 0
var arrival_spark_offscreen_right_count := 0

var offset_sample_count := 0
var offset_current_ms := 0.0
var offset_average_ms := 0.0
var offset_minimum_ms := 0.0
var offset_maximum_ms := 0.0
var offset_m2 := 0.0
var transport_current_ms := 0.0
var transport_maximum_ms := 0.0
var tail_alignment_sample_count := 0
var tail_alignment_current_ms := 0.0
var tail_alignment_average_ms := 0.0
var tail_alignment_minimum_ms := 0.0
var tail_alignment_maximum_ms := 0.0
var buffer_left_overflow_count := 0
var buffer_left_overflowing := false
var buffer_left_overflow_logged_ms := 0.0
var timing_buffer_mismatch_count := 0
var timing_buffer_mismatching := false
var audible_timeline_aligned := false
var initial_alignment_residual_ms := 0.0
var audible_timeline_offscreen_right := false
var audible_timeline_offscreen_right_count := 0


func _ready():
	_collect_scene_nodes()
	set_process(false)


func bind_speaker(p_speaker: Node):
	speaker = p_speaker
	_collect_scene_nodes()
	configure(speaker.opus_sample_rate, speaker.opusframesize)
	set_process(speaker != null)
	update_display(0.0)


func configure(sample_rate: int, frame_size: int):
	_rebuild_arrival_sparks(sample_rate, frame_size)


func begin_episode():
	_reset_offset_statistics()
	tail_alignment_sample_count = 0
	tail_alignment_current_ms = 0.0
	tail_alignment_average_ms = 0.0
	tail_alignment_minimum_ms = 0.0
	tail_alignment_maximum_ms = 0.0
	buffer_left_overflow_count = 0
	buffer_left_overflowing = false
	buffer_left_overflow_logged_ms = 0.0
	timing_buffer_mismatch_count = 0
	timing_buffer_mismatching = false
	audible_timeline_aligned = false
	initial_alignment_residual_ms = 0.0
	audible_timeline_offscreen_right = false
	audible_timeline_offscreen_right_count = 0
	arrival_spark_offscreen_left_count = 0
	arrival_spark_offscreen_right_count = 0


func set_trigger(trigger: String):
	diagnostic_trigger = trigger


func set_transport_context(context: Dictionary):
	last_transport_debug_context = context.duplicate(true)


func record_local_playback_stall():
	if speaker == null or speaker.playingrecording:
		return
	var playback = speaker.audio_stream_playback_opus
	if playback == null:
		return
	var ring_queue_frames: int = playback.queue_length_frames()
	_capture_anomaly("local playback clock stalled",
			speaker.get_playout_lag_time() * 1000.0,
			ring_queue_frames, speaker.tailframenumber - ring_queue_frames)


func record_packet_arrival(arrival_time_usec: int, sample_time_usec: int,
		arrival_timeline_usec: int):
	var offset_ms := (arrival_time_usec - sample_time_usec) / 1000.0
	offset_current_ms = offset_ms
	offset_sample_count += 1
	if offset_sample_count == 1:
		offset_average_ms = offset_ms
		offset_minimum_ms = offset_ms
		offset_maximum_ms = offset_ms
	else:
		var previous_average := offset_average_ms
		offset_average_ms += (offset_ms - offset_average_ms) / offset_sample_count
		offset_m2 += (offset_ms - previous_average) * (offset_ms - offset_average_ms)
		offset_minimum_ms = minf(offset_minimum_ms, offset_ms)
		offset_maximum_ms = maxf(offset_maximum_ms, offset_ms)
	# Do not clamp an implied negative transport time to the acquisition edge.
	# Cyan is deliberately allowed left of the source origin to expose a bad
	# timeline; yellow must show the same evidence instead of hiding it in green.
	transport_current_ms = arrival_timeline_usec / 1000.0 \
			- TwoVoipPacket.ACQUISITION_TIME_ESTIMATE * 1000.0
	transport_maximum_ms = maxf(transport_maximum_ms, transport_current_ms)
	_record_arrival_spark(TwoVoipPacket.ACQUISITION_TIME_ESTIMATE * 1000.0 \
			+ transport_current_ms)


func get_current_arrival_timeline_seconds() -> float:
	return TwoVoipPacket.ACQUISITION_TIME_ESTIMATE \
			+ transport_current_ms / 1000.0


func commit_packet_to_playout():
	if speaker == null or speaker.audio_stream_playback_opus == null:
		return
	# Yellow is when the complete packet becomes available. The left edge of the
	# reversed PCM strip is that same packet's tail boundary, so these compare
	# directly without a one-chunk correction.
	var displayed_audible_timeline_ms := _get_audible_timeline_ms()
	var queue_ms: float = speaker.get_playout_lag_time() * 1000.0
	var arrival_ms := TwoVoipPacket.ACQUISITION_TIME_ESTIMATE * 1000.0 \
			+ transport_current_ms
	var measured_audible_timeline_ms := queue_ms + arrival_ms
	var tail_timeline_ms := displayed_audible_timeline_ms - queue_ms
	tail_alignment_current_ms = tail_timeline_ms - arrival_ms
	tail_alignment_sample_count += 1
	if tail_alignment_sample_count == 1:
		tail_alignment_average_ms = tail_alignment_current_ms
		tail_alignment_minimum_ms = tail_alignment_current_ms
		tail_alignment_maximum_ms = tail_alignment_current_ms
	else:
		tail_alignment_average_ms += (tail_alignment_current_ms \
				- tail_alignment_average_ms) / tail_alignment_sample_count
		tail_alignment_minimum_ms = minf(
				tail_alignment_minimum_ms, tail_alignment_current_ms)
		tail_alignment_maximum_ms = maxf(
				tail_alignment_maximum_ms, tail_alignment_current_ms)
	if audible_timeline_aligned:
		return
	initial_alignment_residual_ms = measured_audible_timeline_ms \
			- displayed_audible_timeline_ms
	audible_timeline_aligned = true
	var clean_episode_start: bool = speaker.mid_time_error_count == 0 \
			and speaker.dropped_packet_count == 0 \
			and speaker.duplicate_packet_count == 0 \
			and speaker.playback_restart_count == 0 \
			and speaker.playback_clock_stall_count == 0 \
			and speaker.playout_delay_extension_usec == 0 \
			and speaker.source_clock_offset_revision_count \
					== speaker.initial_source_clock_offset_revision_count \
			and speaker.source_next_frame_count == 0
	if clean_episode_start and not speaker.playingrecording \
			and absf(initial_alignment_residual_ms) \
			> acquisition_time_tolerance * 1000.0:
		var ring_queue_frames: int = \
				speaker.audio_stream_playback_opus.queue_length_frames()
		_capture_anomaly("initial playout padding mismatch", queue_ms,
				ring_queue_frames, speaker.tailframenumber - ring_queue_frames)
		set_trigger("initial padding mismatch (%+.1f ms)" \
				% initial_alignment_residual_ms)


func _process(delta: float):
	update_display(delta)


func _collect_scene_nodes():
	output_cells.clear()
	reorder_slots.clear()
	arrival_sparks.clear()
	var cells = get_node_or_null("Display/OutputClip/OutputCells")
	if cells:
		for child in cells.get_children():
			if child is ColorRect:
				output_cells.append(child)
	var slots = get_node_or_null("Display/ReorderSlots")
	if slots:
		for index in range(speaker.Noutoforderqueue if speaker else 4):
			var slot: ColorRect = slots.get_node_or_null("Slot%d" % index)
			if slot:
				reorder_slots.append(slot)


func _rebuild_arrival_sparks(sample_rate: int, frame_size: int):
	arrival_sparks.clear()
	var sparks = get_node_or_null("Display/Arrival/ArrivalSparks")
	if sparks == null:
		return
	var template: ColorRect = sparks.get_node_or_null("SparkTemplate")
	if template == null:
		return
	for child in sparks.get_children():
		if child != template:
			sparks.remove_child(child)
			child.queue_free()
	var bin_count := max(1, ceili((display_before_source + display_span) \
			* sample_rate / frame_size))
	for index in range(bin_count):
		var spark: ColorRect = template.duplicate()
		spark.name = "Spark%02d" % index
		spark.visible = true
		sparks.add_child(spark)
		arrival_sparks.append(spark)
	arrival_spark_density.resize(bin_count)
	arrival_spark_flash.resize(bin_count)
	arrival_spark_density.fill(0.0)
	arrival_spark_flash.fill(0.0)


func _reset_offset_statistics():
	offset_sample_count = 0
	offset_current_ms = 0.0
	offset_average_ms = 0.0
	offset_minimum_ms = 0.0
	offset_maximum_ms = 0.0
	offset_m2 = 0.0
	transport_current_ms = 0.0
	transport_maximum_ms = 0.0
	arrival_spark_density.fill(0.0)
	arrival_spark_flash.fill(0.0)


func _record_arrival_spark(timeline_ms: float):
	if arrival_sparks.is_empty():
		return
	var before_source_ms := display_before_source * 1000.0
	var display_ms := maxf(1.0, (display_before_source + display_span) * 1000.0)
	var bin := floori((before_source_ms + timeline_ms) / display_ms \
			* arrival_sparks.size())
	if bin < 0:
		arrival_spark_offscreen_left_count += 1
		return
	if bin >= arrival_sparks.size():
		arrival_spark_offscreen_right_count += 1
		return
	arrival_spark_density[bin] = minf(1.0, arrival_spark_density[bin] + 0.16)
	arrival_spark_flash[bin] = 1.0


func _get_frame_kind(frame_number: int) -> String:
	if frame_number >= speaker.playbackstartframenumber \
			and frame_number < speaker.playback_padding_end_frame:
		# Deliberately inserted timeline silence has the same meaning as silence
		# inserted by a MID counter advance, so both are shown as purple packing.
		return FRAME_KIND_SOURCE_GAP
	if frame_number < speaker.episodefirstframenumber \
			or frame_number >= speaker.tailframenumber \
			or speaker.opusframesize <= 0 \
			or speaker.decoded_frame_max_values.is_empty():
		return ""
	var chunk_index := int(frame_number / speaker.opusframesize)
	var display_value: float = speaker.decoded_frame_max_values[
			chunk_index % speaker.decoded_frame_max_values.size()]
	if display_value == speaker.DISPLAY_SOURCE_GAP:
		return FRAME_KIND_SOURCE_GAP
	if display_value == speaker.DISPLAY_FEC:
		return FRAME_KIND_FEC
	if display_value == speaker.DISPLAY_LOSS:
		return FRAME_KIND_LOSS
	if display_value == speaker.DISPLAY_RESERVE:
		return FRAME_KIND_RESERVE
	return FRAME_KIND_AUDIO if display_value >= 0.0 else ""


func _frame_colour(kind: String) -> Color:
	match kind:
		FRAME_KIND_AUDIO:
			return TIMING_AUDIO
		FRAME_KIND_RESERVE:
			return TIMING_RESERVE
		FRAME_KIND_SOURCE_GAP:
			return TIMING_SOURCE_GAP
		FRAME_KIND_FEC:
			return TIMING_FEC
		FRAME_KIND_LOSS:
			return TIMING_LOSS
	return TIMING_EMPTY


func _layout_reference_markers():
	if speaker == null:
		return
	var display_duration_ms := maxf(1.0,
			(display_before_source + display_span) * 1000.0)
	var before_source_ms := display_before_source * 1000.0
	var arrival: Control = get_node_or_null("Display/Arrival")
	if arrival:
		var arrival_scale := arrival.size.x / display_duration_ms
		var source_position := before_source_ms * arrival_scale
		var source_event: ColorRect = arrival.get_node("SourceEvent")
		source_event.visible = true
		source_event.position.x = source_position
		var acquisition: ColorRect = arrival.get_node("Acquisition")
		acquisition.visible = true
		acquisition.position.x = source_position
		acquisition.size.x = minf(arrival.size.x,
				TwoVoipPacket.ACQUISITION_TIME_ESTIMATE * 1000.0 * arrival_scale)
		acquisition.color = TIMING_ACQUISITION
	var output_clip: Control = get_node_or_null("Display/OutputClip")
	if output_clip:
		var output_scale := output_clip.size.x / display_duration_ms
		var audible_target_x := (before_source_ms \
				+ _get_audible_timeline_ms()) * output_scale
		var audible_deadline: ColorRect = output_clip.get_node("AudibleDeadline")
		audible_deadline.visible = true
		audible_deadline.position.x = audible_target_x - audible_deadline.size.x
		audible_deadline.color = TIMING_AUDIBLE_DEADLINE
		var target_deadline: ColorRect = output_clip.get_node("TargetDeadline")
		target_deadline.visible = true
		target_deadline.position.x = (before_source_ms \
				+ _get_target_timeline_ms()) * output_scale \
				- target_deadline.size.x / 2.0
		target_deadline.color = TIMING_TARGET


func anomaly_snapshot(reason: String, queue_ms: float,
		ring_queue_frames: int, ring_read_frame: int) -> Dictionary:
	var audible_timeline_ms := _get_audible_timeline_ms()
	var pcm_tail_boundary_ms: float = audible_timeline_ms - queue_ms
	var committed_packet_time_ms: float = pcm_tail_boundary_ms
	return {
		"reason": reason,
		"unix_time_usec": int(Time.get_unix_time_from_system() * 1000000.0),
		"stream": speaker.opusstreamcount,
		"speaker": str(get_parent().name) if get_parent() else str(get_path()),
		"in_stream": speaker.inopusstream,
		"queue_ms": queue_ms,
		"target_ms": _get_target_timeline_ms(),
		"effective_playout_lag_ms": \
				speaker.get_effective_playout_lag_target() * 1000.0,
		"audible_timeline_ms": audible_timeline_ms,
		"initial_alignment_residual_ms": initial_alignment_residual_ms,
		"source_clock_offset_estimate_ms": \
				speaker.source_clock_offset_estimate_usec / 1000.0,
		"source_clock_offset_lower_bound_ms": \
				speaker.source_clock_offset_lower_bound_usec / 1000.0,
		"source_clock_offset_upper_bound_ms": \
				speaker.source_clock_offset_upper_bound_usec / 1000.0,
		"source_clock_offset_uncertainty_ms": \
				speaker.source_clock_offset_uncertainty_usec / 1000.0,
		"source_clock_probe_rtt_ms": speaker.source_clock_probe_rtt_usec / 1000.0,
		"source_clock_unix_estimate_valid": speaker.source_clock_unix_estimate_valid,
		"source_clock_unix_estimate_ms": \
				speaker.source_clock_unix_estimate_usec / 1000.0,
		"source_clock_estimate_minus_unix_ms": \
				speaker.source_clock_estimate_minus_unix_usec / 1000.0,
		"source_clock_last_selected_timeline_ms": \
				speaker.source_clock_last_selected_timeline_usec / 1000.0,
		"source_clock_last_unix_timeline_ms": \
				speaker.source_clock_last_unix_timeline_usec / 1000.0,
		"source_clock_pre_send_packet_count": \
				speaker.source_clock_pre_send_packet_count,
		"source_clock_revision_reason": speaker.source_clock_revision_reason,
		"source_clock_offset_observations": \
				speaker.source_clock_offset_observation_count,
		"source_clock_offset_revisions": \
				speaker.source_clock_offset_revision_count,
		"source_clock_last_revision_ms": \
				speaker.source_clock_last_revision_usec / 1000.0,
		"source_clock_reference_deviation_ms": \
				speaker.source_clock_reference_deviation_usec / 1000.0,
		"source_clock_reference_max_deviation_ms": \
				speaker.source_clock_reference_max_deviation_usec / 1000.0,
		"source_clock_reference_large_changes": \
				speaker.source_clock_reference_large_change_count,
		"yellow_timeline_ms": TwoVoipPacket.ACQUISITION_TIME_ESTIMATE * 1000.0 \
				+ transport_current_ms,
		"cyan_tail_timeline_ms": pcm_tail_boundary_ms,
		"tail_alignment_current_ms": tail_alignment_current_ms,
		"tail_alignment_average_ms": tail_alignment_average_ms,
		"tail_alignment_minimum_ms": tail_alignment_minimum_ms,
		"tail_alignment_maximum_ms": tail_alignment_maximum_ms,
		"tail_alignment_sample_count": tail_alignment_sample_count,
		"initial_declared_lead_frames": speaker.initial_playout_declared_lead_frame_count,
		"initial_retained_lead_frames": speaker.initial_playout_lead_frame_count,
		"initial_skipped_lead_frames": speaker.initial_playout_skipped_frame_count,
		"initial_start_arrival_timeline_ms": \
				speaker.initial_start_arrival_timeline_usec / 1000.0,
		"initial_padding_frames": speaker.playback_padding_end_frame \
				- speaker.playbackstartframenumber,
		"initial_padding_ms": (speaker.playback_padding_end_frame \
				- speaker.playbackstartframenumber) * 1000.0 \
				/ speaker.opus_sample_rate,
		"playout_extension_ms": speaker.playout_delay_extension_usec / 1000.0,
		"playout_recovery_target_ms": speaker.playout_recovery_target_frames \
				* 1000.0 / speaker.opus_sample_rate,
		"recovery_pending_ms": speaker.audio_stream_playback_opus.get_playout_recovery_remaining_frames()
				* 1000.0 / speaker.opus_sample_rate
				if speaker.audio_stream_playback_opus else 0.0,
		"silence_recovery_ms": speaker.audio_stream_playback_opus.get_silence_recovery_frames()
				* 1000.0 / speaker.opus_sample_rate
				if speaker.audio_stream_playback_opus else 0.0,
		"speedup_recovery_ms": speaker.audio_stream_playback_opus.get_speedup_recovery_frames()
				* 1000.0 / speaker.opus_sample_rate
				if speaker.audio_stream_playback_opus else 0.0,
		"playout_timeline_offset_ms": speaker.playout_timeline_offset_usec / 1000.0,
		"playout_timeline_base_offset_ms": \
				speaker.playout_timeline_base_offset_usec / 1000.0,
		"playout_timeline_candidate_deviation_ms": \
				speaker.playout_timeline_candidate_deviation_usec / 1000.0,
		"playout_timeline_max_deviation_ms": \
				speaker.playout_timeline_max_deviation_usec / 1000.0,
		"source_tail_time_usec": speaker.get_source_tail_time_usec(),
		"expected_queue_ms": speaker.get_expected_playout_lag_usec() / 1000.0,
		"usec_buffer_residual_ms": speaker.get_timing_buffer_residual_usec() / 1000.0,
		"origin_overrun_ms": maxf(0.0, -committed_packet_time_ms),
		"arrival_sparks_offscreen_left": arrival_spark_offscreen_left_count,
		"arrival_sparks_offscreen_right": arrival_spark_offscreen_right_count,
		"audible_timeline_offscreen_right": audible_timeline_offscreen_right,
		"audible_timeline_offscreen_right_count": \
				audible_timeline_offscreen_right_count,
		"pcm_tail_boundary_ms": pcm_tail_boundary_ms,
		"committed_packet_time_ms": committed_packet_time_ms,
		"buffer_left_time_ms": committed_packet_time_ms,
		"acquisition_width_ms": TwoVoipPacket.ACQUISITION_TIME_ESTIMATE * 1000.0,
		"acquisition_tolerance_ms": acquisition_time_tolerance * 1000.0,
		"output_latency_ms": speaker.audioserveroutputlatency * 1000.0,
		"queue_frames": ring_queue_frames,
		"available_frames": speaker.audio_stream_playback_opus.available_space_frames()
				if speaker.audio_stream_playback_opus else -1,
		"tail_frame": speaker.tailframenumber,
		"ring_read_frame": ring_read_frame,
		"playback_start_frame": speaker.playbackstartframenumber,
		"episode_first_frame": speaker.episodefirstframenumber,
		"opus_frame_count": speaker.opusframecount,
		"source_next_frame_count": speaker.source_next_frame_count,
		"source_next_frame_time_usec": speaker.source_next_frame_time_usec,
		"source_packet_first_frame_time_usec": speaker.source_packet_first_frame_time_usec,
		"restart_count": speaker.playback_restart_count,
		"playback_clock_stall_count": speaker.playback_clock_stall_count,
		"playback_clock_stall_total_ms": speaker.playback_clock_stall_total_usec / 1000.0,
		"playback_clock_last_stall_ms": speaker.playback_clock_last_stall_usec / 1000.0,
		"drop_count": speaker.dropped_packet_count,
		"duplicate_count": speaker.duplicate_packet_count,
		"missing_packet_count": speaker.missing_packet_count,
		"fec_recovery_count": speaker.fec_recovery_count,
		"loss_silence_count": speaker.loss_silence_count,
		"preheader_held_count": speaker.preheader_audio_packets.size(),
		"preheader_wrong_parity_discards": \
				speaker.preheader_wrong_parity_discard_count,
		"mid_time_error_count": speaker.mid_time_error_count,
		"delayed_mid_audio_count": speaker.delayed_mid_audio_count,
		"player_playing": bool(speaker.audioplayeropus and speaker.audioplayeropus.playing),
		"playback_playing": bool(speaker.audio_stream_playback_opus
				and speaker.audio_stream_playback_opus.is_playing()),
		"previous_trigger": diagnostic_trigger,
		"transport_context": last_transport_debug_context.duplicate(true),
	}


func _capture_anomaly(reason: String, queue_ms: float,
		ring_queue_frames: int, ring_read_frame: int):
	print("TwoVoIP timing anomaly: %s stream=%d queue=%.1f ms after %s" % [
			reason, speaker.opusstreamcount, queue_ms, diagnostic_trigger])
	if not capture_timing_anomalies:
		return
	var snapshot := anomaly_snapshot(reason, queue_ms, ring_queue_frames, ring_read_frame)
	var snapshot_json := JSON.stringify(snapshot)
	var file := FileAccess.open(TIMING_ANOMALY_LOG_PATH, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
	else:
		file = FileAccess.open(TIMING_ANOMALY_LOG_PATH, FileAccess.WRITE)
	if file:
		file.store_line(snapshot_json)
	else:
		push_warning("Could not write TwoVoIP timing anomaly log: %s" \
				% TIMING_ANOMALY_LOG_PATH)


func update_display(delta: float):
	if speaker == null:
		return
	var playback = speaker.audio_stream_playback_opus
	if playback == null or not playback.is_playing() \
			or (speaker.audioplayeropus and not speaker.audioplayeropus.playing):
		_clear_display()
		return
	_layout_reference_markers()
	var audible_frame: int = speaker.playbackstartframenumber \
			+ playback.get_frame_number_actually_in_speaker()
	var frame_size := maxi(1, speaker.opusframesize)
	var audible_chunk_frame := floori(float(audible_frame) / frame_size) * frame_size
	var phase := float(audible_frame - audible_chunk_frame) / frame_size
	var output_cells_node = get_node_or_null("Display/OutputClip/OutputCells")
	var cell_width := 0.0
	var audible_timeline_ms: float = _get_audible_timeline_ms()
	var before_source_ms: float = display_before_source * 1000.0
	var audible_target_x := 0.0
	var queue_ms: float = speaker.get_playout_lag_time() * 1000.0
	var ring_queue_frames: int = playback.queue_length_frames()
	var ring_read_frame: int = speaker.tailframenumber - ring_queue_frames
	if output_cells_node and not output_cells.is_empty():
		var time_scale: float = output_cells_node.get_parent().size.x \
				/ maxf(1.0, (display_before_source + display_span) * 1000.0)
		cell_width = frame_size * 1000.0 / speaker.opus_sample_rate * time_scale
		var separation: float = output_cells_node.get_theme_constant("separation")
		var component_width := maxf(1.0, cell_width - separation)
		for cell in output_cells:
			cell.custom_minimum_size.x = component_width
		audible_target_x = (before_source_ms + audible_timeline_ms) * time_scale
		output_cells_node.position.x = audible_target_x - output_cells.size() * cell_width
		var is_offscreen_right: bool = audible_target_x \
				> output_cells_node.get_parent().size.x
		if is_offscreen_right and not audible_timeline_offscreen_right:
			audible_timeline_offscreen_right_count += 1
		audible_timeline_offscreen_right = is_offscreen_right
	_update_sparks(delta)
	for index in range(output_cells.size()):
		var frame_number := audible_chunk_frame \
				+ (output_cells.size() - 1 - index) * frame_size
		var kind := _get_frame_kind(frame_number)
		var frame_is_buffered: bool = frame_number >= audible_chunk_frame \
				and frame_number < speaker.tailframenumber
		var colour := _frame_colour(kind) if frame_is_buffered else TIMING_EMPTY
		if frame_is_buffered and kind.is_empty():
			# Missing metadata for a supposedly buffered frame is evidence, not
			# reserve PCM. Keep it conspicuous instead of making the strip look valid.
			colour = TIMING_UNKNOWN
		if kind == FRAME_KIND_AUDIO:
			colour = colour.lerp(Color.WHITE,
					clampf(speaker.get_frame_max(frame_number) * 2.0, 0.0, 0.65))
		output_cells[index].color = colour
	var audible_head: ColorRect = get_node_or_null("Display/OutputClip/AudibleHead")
	if audible_head:
		audible_head.size.x = (1.0 - phase) * cell_width
		audible_head.position.x = audible_target_x - audible_head.size.x
	var audible_deadline: ColorRect = get_node_or_null("Display/OutputClip/AudibleDeadline")
	if audible_deadline:
		audible_deadline.visible = true
		audible_deadline.position.x = audible_target_x - audible_deadline.size.x
	var audible_level: ColorRect = get_node_or_null("Display/AudibleLevel")
	if audible_level:
		audible_level.visible = true
		audible_level.position.x = output_cells_node.get_parent().position.x \
				+ audible_target_x + 2.0
		var target_brightness := clampf(speaker.get_frame_max(audible_frame) * 12.0,
				0.0, 1.0)
		audible_level_brightness = lerpf(
				target_brightness, audible_level_brightness, 0.75)
		audible_level.color = Color(0.18, 0.35, 0.55, 0.75).lerp(
				Color(0.92, 0.96, 1.0, 1.0), audible_level_brightness)
	for index in range(reorder_slots.size()):
		var occupied: bool = index < speaker.outoforderchunkqueue.size() \
				and speaker.outoforderchunkqueue[index] != null
		reorder_slots[index].color = TIMING_AUDIO if occupied else TIMING_REORDER_EMPTY
	_update_overflow(queue_ms, audible_timeline_ms,
			ring_queue_frames, ring_read_frame)
	_update_usec_consistency(queue_ms, ring_queue_frames, ring_read_frame)


func _get_audible_timeline_ms() -> float:
	if speaker.playout_timeline_base_offset_valid \
			and speaker.source_clock_offset_bound_valid:
		# The playout offset contains both the inter-computer clock relation and
		# the source-to-audible journey. Subtracting the current clock estimate
		# leaves the measured red timeline. A clock-bound revision therefore moves
		# red and yellow together while the independently drawn target stays fixed.
		return (speaker.playout_timeline_offset_usec \
				- speaker.source_clock_offset_estimate_usec) / 1000.0
	return _get_target_timeline_ms()


func _get_target_timeline_ms() -> float:
	return speaker.audio_buffer_lag_time_target * 1000.0


func _update_sparks(delta: float):
	var sparks_node = get_node_or_null("Display/Arrival/ArrivalSparks")
	if sparks_node == null or arrival_sparks.is_empty():
		return
	var spark_width: float = sparks_node.size.x / arrival_sparks.size()
	for index in range(arrival_sparks.size()):
		arrival_spark_density[index] = move_toward(
				arrival_spark_density[index], 0.0, delta * 0.06)
		arrival_spark_flash[index] = move_toward(
				arrival_spark_flash[index], 0.0, delta * 3.0)
		var spark := arrival_sparks[index]
		spark.custom_minimum_size.x = spark_width
		var brightness: float = arrival_spark_flash[index]
		var alpha: float = minf(0.9,
				arrival_spark_density[index] * 0.65 + brightness * 0.55)
		spark.color = Color(1.0, 0.72 + brightness * 0.25,
				0.08 + brightness * 0.5, alpha)


func _update_overflow(queue_ms: float, audible_timeline_ms: float,
		ring_queue_frames: int, ring_read_frame: int):
	# The reversed strip's left edge and the yellow arrival both describe the
	# boundary at which the complete newest packet is available.
	var buffer_left_time_ms: float = audible_timeline_ms - queue_ms
	var acquisition_end_time_ms := \
			TwoVoipPacket.ACQUISITION_TIME_ESTIMATE * 1000.0
	# The PCM tail cannot exist at the receiver during the green acquisition
	# interval. Entry into it means the red audible reference, green duration,
	# or their shared clock mapping is wrong; it is not a permissible overrun.
	var entered_acquisition_interval: bool = buffer_left_time_ms \
			< acquisition_end_time_ms
	var crossed_source_start: bool = buffer_left_time_ms < 0.0
	var overflowing_left: bool = speaker.inopusstream and not speaker.playingrecording \
			and entered_acquisition_interval
	if overflowing_left:
		if not buffer_left_overflowing:
			buffer_left_overflow_count += 1
			buffer_left_overflow_logged_ms = queue_ms
			var reason := "buffer crossed source-time origin" \
					if crossed_source_start else "buffer entered acquisition interval"
			_capture_anomaly(reason, queue_ms,
					ring_queue_frames, ring_read_frame)
			set_trigger("%s (left %.1f ms)" % [reason, buffer_left_time_ms])
		elif queue_ms >= buffer_left_overflow_logged_ms + 100.0:
			buffer_left_overflow_logged_ms = queue_ms
			_capture_anomaly("source-origin overrun grew", queue_ms,
					ring_queue_frames, ring_read_frame)
	elif buffer_left_overflowing:
		buffer_left_overflow_logged_ms = 0.0
	buffer_left_overflowing = overflowing_left


func _update_usec_consistency(queue_ms: float,
		ring_queue_frames: int, ring_read_frame: int):
	if not speaker.inopusstream or speaker.playingrecording:
		timing_buffer_mismatching = false
		return
	var residual_ms: float = speaker.get_timing_buffer_residual_usec() / 1000.0
	var mismatching := absf(residual_ms) > timing_buffer_tolerance * 1000.0
	if mismatching and not timing_buffer_mismatching:
		timing_buffer_mismatch_count += 1
		var reason := "PCM buffer longer than source usec timeline" \
				if residual_ms > 0.0 else "PCM buffer shorter than source usec timeline"
		_capture_anomaly(reason, queue_ms, ring_queue_frames, ring_read_frame)
		set_trigger("%s (%+.1f ms)" % [reason, residual_ms])
	timing_buffer_mismatching = mismatching


func _clear_display():
	for cell in output_cells:
		cell.color = TIMING_EMPTY
	for slot in reorder_slots:
		slot.color = TIMING_REORDER_EMPTY
	arrival_spark_density.fill(0.0)
	arrival_spark_flash.fill(0.0)
	for spark in arrival_sparks:
		spark.color = Color.TRANSPARENT
	var audible_head = get_node_or_null("Display/OutputClip/AudibleHead")
	if audible_head:
		audible_head.size.x = 0.0
	audible_level_brightness = 0.0
	var audible_level: ColorRect = get_node_or_null("Display/AudibleLevel")
	if audible_level:
		audible_level.color = Color(0.18, 0.35, 0.55, 0.75)
		audible_level.visible = false
	_layout_reference_markers()
