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
var opus_sample_rate = 48000
var opus_channels = 2
var runninglagtimeminimum = -1.0
var decoded_frame_max_values := PackedFloat32Array()
var playback_padding_end_frame = 0
var playback_restart_count = 0
var dropped_packet_count = 0
var diagnostic_trigger := "idle"
var offset_sample_count := 0
var offset_current_ms := 0.0
var offset_average_ms := 0.0
var offset_minimum_ms := 0.0
var offset_maximum_ms := 0.0
var offset_m2 := 0.0

const FRAME_KIND_AUDIO := "audio"
const FRAME_KIND_FEC := "fec"
const FRAME_KIND_SOURCE_GAP := "source gap"
const FRAME_KIND_RESERVE := "reserve"
const DISPLAY_EMPTY := -1.0
const DISPLAY_RESERVE := -2.0
const DISPLAY_SOURCE_GAP := -3.0
const DISPLAY_FEC := -4.0

var timing_meter: Control = null
var timing_output_cells: Array[ColorRect] = []
var timing_reorder_slots: Array[ColorRect] = []
var timing_trigger_flash := 0.0

const TIMING_AUDIO := Color(0.32, 0.68, 1.0, 1.0)
const TIMING_RESERVE := Color(0.72, 0.75, 0.8, 1.0)
const TIMING_SOURCE_GAP := Color(0.76, 0.4, 0.95, 1.0)
const TIMING_FEC := Color(1.0, 0.58, 0.18, 1.0)
const TIMING_EMPTY := Color(0.12, 0.14, 0.18, 1.0)

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
	set_sinewave_out(sinewaveoutmode)
	return true

func setrecopusvalues(new_opus_sample_rate, new_opus_channels, new_opus_frame_size):
	opus_sample_rate = new_opus_sample_rate
	opus_channels = new_opus_channels
	opusframesize = new_opus_frame_size
	decoded_frame_max_values.resize(max(1, ceili(max(2.0, audio_buffer_length)*opus_sample_rate/opusframesize)))
	decoded_frame_max_values.fill(DISPLAY_EMPTY)
	create_episode_playback()

func _set_diagnostic_trigger(trigger: String):
	diagnostic_trigger = trigger
	timing_trigger_flash = 1.0

func init_voip_speaker(p_timing_meter: Control = null):
	timing_meter = p_timing_meter
	timing_output_cells.clear()
	timing_reorder_slots.clear()
	if timing_meter == null:
		return
	var output_cells = timing_meter.get_node_or_null("Display/OutputClip/OutputCells")
	if output_cells:
		for child in output_cells.get_children():
			if child is ColorRect:
				timing_output_cells.append(child)
	var reorder_slots = timing_meter.get_node_or_null("Display/ReorderSlots")
	if reorder_slots:
		for child in reorder_slots.get_children():
			if child is ColorRect:
				timing_reorder_slots.append(child)
	_update_timing_meter(0.0)

func _reset_offset_statistics():
	offset_sample_count = 0
	offset_current_ms = 0.0
	offset_average_ms = 0.0
	offset_minimum_ms = 0.0
	offset_maximum_ms = 0.0
	offset_m2 = 0.0

func _record_packet_arrival(arrival_time_usec: int, capture_time_usec: int):
	var offset_ms := (arrival_time_usec - capture_time_usec) / 1000.0
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

func queue_playout_delay(next_frame_time_usec: int) -> int:
	var now_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	var frame_age := (now_usec - next_frame_time_usec) / 1000000.0
	var padding_frames := roundi(max(0.0,
			audio_buffer_lag_time_target - audioserveroutputlatency - frame_age) \
			* opus_sample_rate)
	padding_frames = min(padding_frames,
			max(0, audio_stream_playback_opus.available_space_frames() - opusframesize))
	if audio_stream_playback_opus.push_silence(padding_frames) != padding_frames:
		push_error("Could not queue Opus playout delay")
		return 0
	return padding_frames

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
	playbackstartframenumber = tailframenumber - padding_frames
	playback_padding_end_frame = tailframenumber
	playback_restart_count += 1
	_set_diagnostic_trigger("local %s → replace playback" % reason)
	return true

func ensure_episode_playback(required_space_frames := 0) -> bool:
	if audio_stream_playback_opus == null or not audio_stream_playback_opus.is_playing():
		return restart_episode_playback("starvation")
	if required_space_frames > audio_stream_playback_opus.available_space_frames():
		# A local pause can release more queued packets than this bounded playback
		# can hold. Replace the local backlog, but retain the wire episode, source
		# counters and reorder window.
		return restart_episode_playback("backlog overflow")
	return true

func start_playback_timeline(next_frame_count: int, next_frame_time_usec: int):
	var padding_frames := queue_playout_delay(next_frame_time_usec)
	opusframecount = next_frame_count
	tailframenumber = opusframecount * opusframesize
	episodefirstframenumber = tailframenumber
	playbackstartframenumber = tailframenumber - padding_frames
	playback_padding_end_frame = tailframenumber
	source_next_frame_time_usec = next_frame_time_usec

func push_silent_opus_frames(frame_count: int) -> bool:
	if frame_count <= 0:
		return true
	var silent_sample_frames: int = frame_count * opusframesize
	if not ensure_episode_playback(silent_sample_frames) or audio_stream_playback_opus.push_silence(silent_sample_frames) != silent_sample_frames:
		push_warning("Not enough playback buffer space for %d silent Opus frames" % frame_count)
		return false
	for frame in range(opusframecount, opusframecount + frame_count):
		decoded_frame_max_values[frame % decoded_frame_max_values.size()] = DISPLAY_SOURCE_GAP
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
		decoded_frame_max_values[chunk_index % decoded_frame_max_values.size()] = DISPLAY_FEC if decode_fec \
				else audio_stream_playback_opus.get_tail_max(opusframesize)
		outputsumsquares += audio_stream_playback_opus.get_tail_sum_squares(opusframesize)
		tailframenumber += decoded_frames
		if decode_fec:
			_set_diagnostic_trigger("missing packet → Opus FEC")
	return decoded_frames

func get_frame_max(frame_number: int) -> float:
	if frame_number < episodefirstframenumber or opusframesize <= 0 \
			or decoded_frame_max_values.is_empty():
		return 0.0
	var chunk_index = int(frame_number / opusframesize)
	return maxf(0.0, decoded_frame_max_values[chunk_index % decoded_frame_max_values.size()])

func _get_frame_kind(frame_number: int) -> String:
	if frame_number >= playbackstartframenumber and frame_number < playback_padding_end_frame:
		return FRAME_KIND_RESERVE
	if frame_number < episodefirstframenumber or frame_number >= tailframenumber \
			or opusframesize <= 0 or decoded_frame_max_values.is_empty():
		return ""
	var chunk_index := int(frame_number / opusframesize)
	var display_value := decoded_frame_max_values[chunk_index % decoded_frame_max_values.size()]
	if display_value == DISPLAY_SOURCE_GAP:
		return FRAME_KIND_SOURCE_GAP
	if display_value == DISPLAY_FEC:
		return FRAME_KIND_FEC
	if display_value == DISPLAY_RESERVE:
		return FRAME_KIND_RESERVE
	return FRAME_KIND_AUDIO if display_value >= 0.0 else ""

func get_incoming_bitrate() -> int:
	return source_bitrate

func get_playout_lag_time() -> float:
	if audio_stream_playback_opus == null:
		return 0.0
	return audioserveroutputlatency \
			+ audio_stream_playback_opus.queue_length_frames() * 1.0 / opus_sample_rate

func _timing_frame_colour(kind: String) -> Color:
	match kind:
		FRAME_KIND_AUDIO:
			return TIMING_AUDIO
		FRAME_KIND_RESERVE:
			return TIMING_RESERVE
		FRAME_KIND_SOURCE_GAP:
			return TIMING_SOURCE_GAP
		FRAME_KIND_FEC:
			return TIMING_FEC
	return TIMING_EMPTY

func _update_timing_meter(delta: float):
	if timing_meter == null:
		return
	timing_trigger_flash = maxf(0.0, timing_trigger_flash - delta * 1.5)
	var playback = audio_stream_playback_opus
	if playback == null or not playback.is_playing() \
			or (audioplayeropus and not audioplayeropus.playing):
		_clear_timing_meter()
		return
	var audible_frame: int = playbackstartframenumber
	audible_frame += playback.get_frame_number_actually_in_speaker()
	var frame_size := maxi(1, opusframesize)
	var first_frame := floori(float(audible_frame) / frame_size) * frame_size
	var phase := float(audible_frame - first_frame) / frame_size
	var output_cells_node = timing_meter.get_node_or_null("Display/OutputClip/OutputCells")
	var cell_width := 0.0
	if output_cells_node and not timing_output_cells.is_empty():
		cell_width = timing_output_cells[0].custom_minimum_size.x + 1.0
		output_cells_node.position.x = 0.0
	for index in range(timing_output_cells.size()):
		var frame_number := first_frame + index * frame_size
		var kind := _get_frame_kind(frame_number)
		var colour := _timing_frame_colour(kind)
		if kind == FRAME_KIND_AUDIO:
			colour = colour.lerp(Color.WHITE,
					clampf(get_frame_max(frame_number) * 2.0, 0.0, 0.65))
		timing_output_cells[index].color = colour
	var audible_head: ColorRect = timing_meter.get_node_or_null("Display/OutputClip/AudibleHead")
	if audible_head:
		audible_head.size.x = (1.0 - phase) * cell_width
	var target_highlight: ColorRect = timing_meter.get_node_or_null("Display/OutputClip/TargetBufferHighlight")
	if target_highlight:
		var packet_time: float = frame_size * 1.0 / opus_sample_rate
		target_highlight.size.x = minf(target_highlight.get_parent().size.x,
				audio_buffer_lag_time_target / packet_time * cell_width)
	for index in range(timing_reorder_slots.size()):
		var occupied := index < outoforderchunkqueue.size() \
				and outoforderchunkqueue[index] != null
		timing_reorder_slots[index].color = TIMING_AUDIO if occupied else TIMING_EMPTY

	var variation_current_ms := maxf(0.0, offset_current_ms - offset_minimum_ms)
	var variation_average_ms := maxf(0.0, offset_average_ms - offset_minimum_ms)
	var variation_maximum_ms := maxf(0.0, offset_maximum_ms - offset_minimum_ms)
	var standard_deviation := sqrt(offset_m2 / maxi(1, offset_sample_count - 1))
	var target_ms: float = audio_buffer_lag_time_target * 1000.0
	var queue_ms: float = get_playout_lag_time() * 1000.0
	var lag_text: Label = timing_meter.get_node_or_null("LagText")
	if lag_text:
		lag_text.text = "offset %.1f ms   bounds %.1f–%.1f   samples %d   bitrate %.1f kb/s\nvariation %.1f/%.1f ms   avg %.1f   σ %.1f   playout %.0f/%.0f ms" % [
				offset_current_ms, offset_minimum_ms, offset_maximum_ms,
				offset_sample_count, source_bitrate / 1000.0,
				variation_current_ms, variation_maximum_ms, variation_average_ms,
				standard_deviation, queue_ms, target_ms]
	var arrival = timing_meter.get_node_or_null("Display/Arrival")
	if arrival:
		arrival.get_node("Average").visible = true
		arrival.get_node("Current").visible = true
		arrival.get_node("Target").visible = true
		var scale_max: float = maxf(100.0, maxf(target_ms * 1.2, variation_maximum_ms * 1.1))
		var scale: float = arrival.size.x / scale_max
		arrival.get_node("Range").size.x = maxf(1.0, variation_maximum_ms * scale)
		arrival.get_node("Average").position.x = variation_average_ms * scale - 1.0
		arrival.get_node("Current").position.x = minf(variation_current_ms, scale_max) * scale - 1.5
		arrival.get_node("Target").position.x = minf(target_ms, scale_max) * scale - 1.0
		var is_outlier: bool = offset_sample_count > 10 \
				and abs(offset_current_ms - offset_average_ms) > maxf(20.0, standard_deviation * 3.0)
		arrival.get_node("Current").color = Color.RED if is_outlier else Color.YELLOW
	var trigger_background: ColorRect = timing_meter.get_node_or_null("Display/TriggerBackground")
	if trigger_background:
		trigger_background.color = Color(1.0, 0.72, 0.28,
				0.25 + timing_trigger_flash * 0.45)
	var trigger_label: Label = timing_meter.get_node_or_null("Display/TriggerLabel")
	if trigger_label:
		trigger_label.text = "TRIGGER  %s   | restart %d  drop %d  queued %d" % [
				diagnostic_trigger, playback_restart_count, dropped_packet_count,
				opusframequeuecount]

func _clear_timing_meter():
	for cell in timing_output_cells:
		cell.color = TIMING_EMPTY
	for slot in timing_reorder_slots:
		slot.color = TIMING_EMPTY
	var audible_head = timing_meter.get_node_or_null("Display/OutputClip/AudibleHead")
	if audible_head:
		audible_head.size.x = 0.0
	var target_highlight = timing_meter.get_node_or_null("Display/OutputClip/TargetBufferHighlight")
	if target_highlight:
		target_highlight.size.x = 0.0
	var arrival = timing_meter.get_node_or_null("Display/Arrival")
	if arrival:
		arrival.get_node("Range").size.x = 0.0
		arrival.get_node("Average").visible = false
		arrival.get_node("Current").visible = false
		arrival.get_node("Target").visible = false
	var lag_text = timing_meter.get_node_or_null("LagText")
	if lag_text:
		lag_text.text = ""
	var trigger_background = timing_meter.get_node_or_null("Display/TriggerBackground")
	if trigger_background:
		trigger_background.color = Color.TRANSPARENT
	var trigger_label = timing_meter.get_node_or_null("Display/TriggerLabel")
	if trigger_label:
		trigger_label.text = ""

func external_end_stream():
	if inopusstream:
		print(":externally ending the stream at cutout")
		var footer := TwoVoipPacket.make_footer(opusstreamcount, opusframecount, 0.0, -1.0)
		receive_audio_packet(TwoVoipPacket.encode_control_packet(footer))

func receive_audio_control_packet(control_packet: Array):
	if control_packet.is_empty():
		push_warning("Invalid TwoVoIP control packet")
		return
	var packet_type = control_packet[0]
	if packet_type == TwoVoipPacket.TYPE_START:
		if not TwoVoipPacket.header_is_valid(control_packet):
			push_warning("Unsupported or malformed TwoVoIP stream header")
			return
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
		dropped_packet_count = 0
		_reset_offset_statistics()
		start_playback_timeline(
				source_next_frame_count,
				source_next_frame_time_usec)
		_set_diagnostic_trigger("START → establish playout timeline")
	elif packet_type == TwoVoipPacket.TYPE_MID:
		if not TwoVoipPacket.mid_is_valid(control_packet):
			push_warning("Malformed TwoVoIP mid-stream update")
			return
		if not inopusstream or int(control_packet[TwoVoipPacket.MidField.OPUS_STREAM_COUNT]) != opusstreamcount:
			return
		if not ensure_episode_playback():
			return
		source_next_frame_count = int(control_packet[TwoVoipPacket.MidField.NEXT_FRAME_COUNT])
		source_next_frame_time_usec = int(control_packet[TwoVoipPacket.MidField.NEXT_FRAME_TIME_USEC])
		source_bitrate = int(control_packet[TwoVoipPacket.MidField.OPUS_BITRATE])
		if source_next_frame_count > opusframecount:
			push_silent_opus_frames(source_next_frame_count - opusframecount)
	elif packet_type == TwoVoipPacket.TYPE_END:
		if not TwoVoipPacket.footer_is_valid(control_packet):
			push_warning("Malformed TwoVoIP stream footer")
			return
		if int(control_packet[TwoVoipPacket.FooterField.OPUS_STREAM_COUNT]) != opusstreamcount:
			return
		if audio_stream_playback_opus:
			audio_stream_playback_opus.finish_episode()
		var outputframecount = tailframenumber - episodefirstframenumber
		outputrms = sqrt(outputsumsquares/outputframecount) if outputframecount > 0 else 0.0
		control_packet[TwoVoipPacket.FooterField.RMS] = outputrms
		print("TwoVoIP speaker END stream=%d minimum_buffer=%.3f s target=%.3f s restarts=%d drops=%d" % [
				opusstreamcount, runninglagtimeminimum, audio_buffer_lag_time_target,
				playback_restart_count, dropped_packet_count])
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

func receive_audio_packet(packet):
	if audiostreamopus == null:
		return
	if TwoVoipPacket.is_control_packet(packet):
		return receive_audio_control_packet(TwoVoipPacket.decode_control_packet(packet))
	if not inopusstream:
		print("Audio packet received before a stream header")
		return
	packet = TwoVoipPacket.decode_audio_packet(packet, audio_packets_base64)
	var arrival_time_usec := int(Time.get_unix_time_from_system() * 1000000.0)
	if len(packet) <= lenchunkprefix:
		print("Bad audio packet too short")
		return
	if lenchunkprefix == -1:
		pass

	elif lenchunkprefix == 0:
		if not ensure_episode_playback(opusframesize):
			return
		source_packet_first_frame_time_usec = source_next_frame_time_usec \
				+ int((opusframecount - source_next_frame_count) * opusframesize \
				* 1000000.0 / opus_sample_rate)
		_record_packet_arrival(arrival_time_usec, source_packet_first_frame_time_usec)
		push_opus_packet(packet, lenchunkprefix, false)
		opusframecount += 1

	else:
		if not ensure_episode_playback():
			return
		assert (lenchunkprefix >= TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE)
		var unwrapped_frame_count := TwoVoipPacket.decode_sequence_chunk_prefix(packet, opusframecount, opusstreamcount)
		if unwrapped_frame_count < 0:
			dropped_packet_count += 1
			_set_diagnostic_trigger("stale/wrong episode packet → drop")
			return
		source_packet_first_frame_time_usec = source_next_frame_time_usec \
				+ int((unwrapped_frame_count - source_next_frame_count) * opusframesize \
				* 1000000.0 / opus_sample_rate)
		_record_packet_arrival(arrival_time_usec, source_packet_first_frame_time_usec)
		var opusframecountR = unwrapped_frame_count - opusframecount
		while opusframecountR >= Noutoforderqueue:
			print("shifting outoforderqueue ", unwrapped_frame_count, " ", ("null" if outoforderchunkqueue[0] == null else len(outoforderchunkqueue[0])))
			if outoforderchunkqueue[0] != null:
				push_opus_packet(outoforderchunkqueue[0], lenchunkprefix, false)
				opusframequeuecount -= 1
			else:
				var nextvalidpacketforfec = packet
				for i in range(1, Noutoforderqueue):
					if outoforderchunkqueue[i] != null:
						nextvalidpacketforfec = outoforderchunkqueue[i]
						break
				push_opus_packet(nextvalidpacketforfec, lenchunkprefix, true)
			outoforderchunkqueue.pop_front()
			outoforderchunkqueue.push_back(null)
			opusframecountR -= 1
			opusframecount += 1
			assert (opusframequeuecount >= 0)

		outoforderchunkqueue[opusframecountR] = packet
		opusframequeuecount += 1
		while outoforderchunkqueue[0] != null and opusframecount + opusframequeuecount >= Npacketinitialbatching:
			push_opus_packet(outoforderchunkqueue.pop_front(), lenchunkprefix, false)
			outoforderchunkqueue.push_back(null)
			opusframecount += 1
			opusframequeuecount -= 1
			assert (opusframequeuecount >= 0)
var playingrecording = false
func _physics_process(delta):
	_update_timing_meter(delta)
	if audio_stream_playback_opus == null:
		return
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
