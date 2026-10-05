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
var playback_clock_anchor_ticks_usec = 0
var playback_clock_anchor_speaker_frame = 0
var playback_underflow_baseline = 0
var playout_delay_extension_usec = 0
var dropped_packet_count = 0
var duplicate_packet_count = 0
var rejected_mid_count = 0
var delayed_mid_audio_count = 0
var pending_mid_frame_count = -1
var pending_mid_arrival_usec = 0
var last_mid_to_audio_usec = -1
const PLAYBACK_CLOCK_STALL_TOLERANCE_USEC := 80000
const DISPLAY_EMPTY := -1.0
const DISPLAY_RESERVE := -2.0
const DISPLAY_SOURCE_GAP := -3.0
const DISPLAY_FEC := -4.0

var timing_meter: TwoVoipTimingMeter = null

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
	decoded_frame_max_values.resize(max(1,
			ceili(max(2.0, audio_buffer_length) * opus_sample_rate / opusframesize)))
	decoded_frame_max_values.fill(DISPLAY_EMPTY)
	if timing_meter:
		timing_meter.configure(opus_sample_rate, opusframesize)
	create_episode_playback()

func _set_diagnostic_trigger(trigger: String):
	if timing_meter:
		timing_meter.set_trigger(trigger)

func init_voip_speaker(p_timing_meter: TwoVoipTimingMeter = null):
	timing_meter = p_timing_meter
	if timing_meter:
		timing_meter.bind_speaker(self)

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

func get_effective_playout_lag_target() -> float:
	return audio_buffer_lag_time_target + playout_delay_extension_usec / 1000000.0

func _reset_playback_clock_anchor():
	playback_clock_anchor_ticks_usec = Time.get_ticks_usec()
	playback_clock_anchor_speaker_frame = \
			audio_stream_playback_opus.get_frame_number_actually_in_speaker() \
			if audio_stream_playback_opus else 0

func _reset_playback_underflow_baseline():
	playback_underflow_baseline = audio_stream_playback_opus.get_underflow_frames() \
			if audio_stream_playback_opus else 0

func _account_playback_underflow():
	if audio_stream_playback_opus == null:
		return
	var underflow_total: int = audio_stream_playback_opus.get_underflow_frames()
	var new_underflow_frames := maxi(0, underflow_total - playback_underflow_baseline)
	playback_underflow_baseline = underflow_total
	if new_underflow_frames == 0:
		return
	var mix_rate := AudioServer.get_mix_rate()
	if mix_rate <= 0.0:
		return
	var extension_usec := roundi(new_underflow_frames * 1000000.0 / mix_rate)
	playout_delay_extension_usec += extension_usec
	_set_diagnostic_trigger("input starvation → extend playout %.0f ms" %
			(extension_usec / 1000.0))

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
	playbackstartframenumber = tailframenumber - padding_frames
	playback_padding_end_frame = tailframenumber
	playback_restart_count += 1
	_reset_playback_clock_anchor()
	_reset_playback_underflow_baseline()
	_set_diagnostic_trigger("local %s → replace playback" % reason)
	return true

func ensure_episode_playback(required_space_frames := 0) -> bool:
	_account_playback_underflow()
	if audio_stream_playback_opus == null or not audio_stream_playback_opus.is_playing():
		return restart_episode_playback("starvation")
	var stalled_usec := _playback_clock_stall_usec()
	if stalled_usec > PLAYBACK_CLOCK_STALL_TOLERANCE_USEC:
		return restart_episode_playback("clock stalled %.0f ms" % (stalled_usec / 1000.0))
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
	_reset_playback_clock_anchor()
	_reset_playback_underflow_baseline()

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

func external_end_stream():
	if inopusstream:
		print(":externally ending the stream at cutout")
		var footer := TwoVoipPacket.make_footer(opusstreamcount, opusframecount, 0.0, -1.0)
		receive_audio_packet(TwoVoipPacket.encode_control_packet(footer))

func _mid_timeline_is_coherent(next_frame_count: int, next_frame_time_usec: int) -> bool:
	if source_next_frame_time_usec == 0 or next_frame_count < source_next_frame_count:
		return source_next_frame_time_usec == 0
	var frame_usec := roundi(opusframesize * 1000000.0 / opus_sample_rate)
	var expected_time_usec := source_next_frame_time_usec \
			+ (next_frame_count - source_next_frame_count) * frame_usec
	return absi(next_frame_time_usec - expected_time_usec) <= maxi(1, frame_usec / 2)

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
		playout_delay_extension_usec = 0
		dropped_packet_count = 0
		duplicate_packet_count = 0
		rejected_mid_count = 0
		delayed_mid_audio_count = 0
		pending_mid_frame_count = -1
		pending_mid_arrival_usec = 0
		last_mid_to_audio_usec = -1
		if timing_meter:
			timing_meter.begin_episode()
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
		var mid_next_frame_count := int(control_packet[TwoVoipPacket.MidField.NEXT_FRAME_COUNT])
		var mid_next_frame_time_usec := int(control_packet[TwoVoipPacket.MidField.NEXT_FRAME_TIME_USEC])
		if mid_next_frame_count < opusframecount:
			_set_diagnostic_trigger("stale MID → ignore")
			return
		if not _mid_timeline_is_coherent(mid_next_frame_count, mid_next_frame_time_usec):
			rejected_mid_count += 1
			_set_diagnostic_trigger("incoherent MID → reject")
			push_warning("TwoVoIP rejected MID frame %d: source timestamp does not continue frame %d timeline" % [
					mid_next_frame_count, source_next_frame_count])
			return
		source_next_frame_count = mid_next_frame_count
		source_next_frame_time_usec = mid_next_frame_time_usec
		source_bitrate = int(control_packet[TwoVoipPacket.MidField.OPUS_BITRATE])
		if source_next_frame_count > opusframecount:
			pending_mid_frame_count = source_next_frame_count
			pending_mid_arrival_usec = int(Time.get_unix_time_from_system() * 1000000.0)
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
		print("TwoVoIP speaker END stream=%d minimum_buffer=%.3f s target=%.3f s blank_extension=%.3f s restarts=%d drops=%d" % [
				opusstreamcount, runninglagtimeminimum, get_effective_playout_lag_target(),
				playout_delay_extension_usec / 1000000.0,
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

func receive_audio_packet(packet, transport_debug_context: Dictionary = {}):
	if timing_meter and not transport_debug_context.is_empty():
		timing_meter.set_transport_context(transport_debug_context)
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
		if timing_meter:
			timing_meter.record_packet_arrival(
					arrival_time_usec, source_packet_first_frame_time_usec)
		_check_pending_mid_audio(arrival_time_usec, opusframecount)
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
		if timing_meter:
			timing_meter.record_packet_arrival(
					arrival_time_usec, source_packet_first_frame_time_usec)
		_check_pending_mid_audio(arrival_time_usec, unwrapped_frame_count)
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

		if outoforderchunkqueue[opusframecountR] != null:
			duplicate_packet_count += 1
			_set_diagnostic_trigger("duplicate packet → ignore")
			return
		outoforderchunkqueue[opusframecountR] = packet
		opusframequeuecount += 1
		while outoforderchunkqueue[0] != null and opusframecount + opusframequeuecount >= Npacketinitialbatching:
			push_opus_packet(outoforderchunkqueue.pop_front(), lenchunkprefix, false)
			outoforderchunkqueue.push_back(null)
			opusframecount += 1
			opusframequeuecount -= 1
			assert (opusframequeuecount >= 0)
var playingrecording = false
func _physics_process(_delta):
	if audio_stream_playback_opus == null:
		return
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
