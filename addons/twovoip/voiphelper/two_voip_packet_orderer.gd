extends RefCounted

# One-to-one receive front end for TwoVoipSpeaker. This class knows packet
# ordering; the speaker remains responsible for episode, timing and playout
# decisions.

enum Kind { UNRESOLVED_AUDIO, START, MID, AUDIO, END }

class ReceivedPacket extends RefCounted:
	var kind: int = Kind.UNRESOLVED_AUDIO
	var control: Array = []
	var audio := PackedByteArray()
	var wire := PackedByteArray()
	var context: Dictionary = {}
	var arrival_time_usec := 0
	var stream_count := -1
	var parity := -1
	var sequence_7bit := -1
	var frame_count := -1
	var source_time_usec := 0
	var arrival_timeline_usec := 0
	var playout_arrival_time_usec := 0
	var timing_observed := false

const MAX_PENDING_PACKET_COUNT := TwoVoipPacket.CHUNK_SEQUENCE_MODULUS / 2

var _speaker_ref: WeakRef
var speaker:
	get:
		return _speaker_ref.get_ref() if _speaker_ref else null
	set(value):
		_speaker_ref = weakref(value) if value != null else null
var queue: Array[ReceivedPacket] = []


func _init(p_speaker: Node):
	speaker = p_speaker


func _priority(received: ReceivedPacket) -> int:
	if received.kind == Kind.MID:
		return 0
	if received.kind == Kind.AUDIO:
		return 1
	return 2


func _insert(received: ReceivedPacket):
	for queued in queue:
		if queued.kind == received.kind and queued.frame_count == received.frame_count \
				and queued.stream_count == received.stream_count:
			speaker.duplicate_packet_count += 1
			speaker._set_diagnostic_trigger("duplicate packet → ignore")
			return
	var insert_at := queue.size()
	for index in range(queue.size()):
		var queued := queue[index]
		if queued.kind == Kind.UNRESOLVED_AUDIO \
				or (speaker.inopusstream and received.stream_count == speaker.opusstreamcount \
					and queued.stream_count != speaker.opusstreamcount) \
				or (received.stream_count == queued.stream_count and (received.frame_count < queued.frame_count \
					or (received.frame_count == queued.frame_count and _priority(received) < _priority(queued)))):
			insert_at = index
			break
	queue.insert(insert_at, received)
	while queue.size() > MAX_PENDING_PACKET_COUNT:
		queue.pop_back()
		speaker.dropped_packet_count += 1


func _complete_sequence(sequence_7bit: int, reference_frame: int) -> int:
	var offset := (sequence_7bit - reference_frame % TwoVoipPacket.CHUNK_SEQUENCE_MODULUS \
			+ TwoVoipPacket.CHUNK_SEQUENCE_MODULUS) % TwoVoipPacket.CHUNK_SEQUENCE_MODULUS
	if offset >= TwoVoipPacket.CHUNK_SEQUENCE_MODULUS / 2:
		offset -= TwoVoipPacket.CHUNK_SEQUENCE_MODULUS
	return reference_frame + offset


func _resolve_audio(received: ReceivedPacket) -> bool:
	if received.audio.is_empty():
		received.audio = TwoVoipPacket.decode_audio_packet(received.wire, speaker.audio_packets_base64)
	if received.audio.size() <= speaker.lenchunkprefix:
		push_warning("Bad TwoVoIP audio packet: too short")
		return false
	if speaker.lenchunkprefix < TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE:
		received.kind = Kind.AUDIO
		received.stream_count = speaker.opusstreamcount
		received.parity = speaker.opusstreamcount % 2
		received.frame_count = speaker.opusframecount
		return true
	received.sequence_7bit = received.audio[0] & TwoVoipPacket.CHUNK_SEQUENCE_MASK
	received.parity = 1 if received.audio[0] & TwoVoipPacket.CHUNK_STREAM_PARITY_MASK else 0
	if received.parity != speaker.opusstreamcount % 2:
		return false
	received.kind = Kind.AUDIO
	received.stream_count = speaker.opusstreamcount
	received.frame_count = _complete_sequence(received.sequence_7bit, speaker.opusframecount)
	return true


func _preheader_limit() -> int:
	if speaker.cached_stream_header.is_empty():
		return MAX_PENDING_PACKET_COUNT
	var frame_size := int(speaker.cached_stream_header[TwoVoipPacket.HeaderField.OPUS_FRAME_SIZE])
	var sample_rate := int(speaker.cached_stream_header[TwoVoipPacket.HeaderField.OPUS_SAMPLE_RATE])
	if frame_size <= 0 or sample_rate <= 0:
		return MAX_PENDING_PACKET_COUNT
	return mini(1024, maxi(MAX_PENDING_PACKET_COUNT,
			ceili(speaker.audio_buffer_lag_time_target * sample_rate / frame_size) + 2))


func _prepare_cached_audio_run(stream_count: int) -> Dictionary:
	var packets: Array[ReceivedPacket] = []
	var decoded_audio: Array[PackedByteArray] = []
	var prepared := {
		"packets": packets,
		"audio": decoded_audio,
		"frames": PackedInt64Array(),
	}
	if speaker.cached_stream_header.is_empty():
		return prepared
	var encode_base64 := TwoVoipPacket.header_uses_base64(speaker.cached_stream_header)
	var prefix_length := int(speaker.cached_stream_header[TwoVoipPacket.HeaderField.CHUNK_PREFIX_LENGTH])
	var expected_parity := stream_count % 2
	var next_frame := -1
	for received in queue:
		if received.kind != Kind.UNRESOLVED_AUDIO:
			continue
		var decoded := TwoVoipPacket.decode_audio_packet(received.wire, encode_base64)
		if decoded.size() <= prefix_length or prefix_length < TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE:
			prepared.packets.clear()
			prepared.audio.clear()
			prepared.frames.clear()
			return prepared
		var parity := 1 if decoded[0] & TwoVoipPacket.CHUNK_STREAM_PARITY_MASK else 0
		if parity != expected_parity:
			continue
		var sequence := decoded[0] & TwoVoipPacket.CHUNK_SEQUENCE_MASK
		if next_frame < 0:
			next_frame = sequence
		elif sequence != next_frame % TwoVoipPacket.CHUNK_SEQUENCE_MODULUS:
			prepared.packets.clear()
			prepared.audio.clear()
			prepared.frames.clear()
			return prepared
		prepared.packets.append(received)
		prepared.audio.append(decoded)
		prepared.frames.append(next_frame)
		next_frame += 1
	return prepared


func _commit_cached_audio_run(prepared: Dictionary, stream_count: int) -> Array[ReceivedPacket]:
	var run: Array[ReceivedPacket] = prepared.packets
	for index in range(run.size()):
		var received := run[index]
		received.audio = prepared.audio[index]
		received.parity = stream_count % 2
		received.sequence_7bit = received.audio[0] & TwoVoipPacket.CHUNK_SEQUENCE_MASK
		received.stream_count = stream_count
		received.frame_count = int(prepared.frames[index])
	return run


func _header_configuration_matches(left: Array, right: Array) -> bool:
	for field in [
		TwoVoipPacket.HeaderField.OPUS_FRAME_SIZE,
		TwoVoipPacket.HeaderField.OPUS_SAMPLE_RATE,
		TwoVoipPacket.HeaderField.OPUS_CHANNELS,
		TwoVoipPacket.HeaderField.CHUNK_PREFIX_LENGTH,
		TwoVoipPacket.HeaderField.AUDIO_ENCODING,
	]:
		if left[field] != right[field]:
			return false
	return true


func _start_fabricated_episode(header: Array, run: Array[ReceivedPacket], reason: String):
	if not run.is_empty():
		var frame_usec := roundi(int(header[TwoVoipPacket.HeaderField.OPUS_FRAME_SIZE]) * 1000000.0 \
				/ int(header[TwoVoipPacket.HeaderField.OPUS_SAMPLE_RATE]))
		run[0].playout_arrival_time_usec = maxi(Time.get_ticks_usec(), run[-1].arrival_time_usec + frame_usec)
	speaker.cached_stream_header = header.duplicate(true)
	speaker.fabricated_start_active = true
	speaker.fabricated_start_draining = true
	speaker.fabricated_start_count += 1
	var received := ReceivedPacket.new()
	received.kind = Kind.START
	received.control = header
	received.stream_count = int(header[TwoVoipPacket.HeaderField.OPUS_STREAM_COUNT])
	received.frame_count = int(header[TwoVoipPacket.HeaderField.NEXT_FRAME_COUNT])
	received.context = {
		"arrival_time_usec": int(header[TwoVoipPacket.HeaderField.NEXT_FRAME_TIME_USEC]) \
				+ speaker.source_clock_offset_estimate_usec,
		"fabricated_start": true,
	}
	_start_episode(received)
	speaker.fabricated_start_draining = false
	speaker.mark_initial_playout_padding_aligned()
	if speaker.timing_meter and not run.is_empty():
		speaker.timing_meter.commit_packet_to_playout()
	speaker._set_diagnostic_trigger("START RECOVERY: %s" % reason)


func _try_fabricate_start_from_audio() -> bool:
	if speaker.inopusstream or speaker.cached_stream_header.is_empty():
		return false
	var stream_count := int(speaker.cached_stream_header[TwoVoipPacket.HeaderField.OPUS_STREAM_COUNT]) + 1
	var prepared := _prepare_cached_audio_run(stream_count)
	var frame_size := int(speaker.cached_stream_header[TwoVoipPacket.HeaderField.OPUS_FRAME_SIZE])
	var sample_rate := int(speaker.cached_stream_header[TwoVoipPacket.HeaderField.OPUS_SAMPLE_RATE])
	var required_packets := ceili(speaker.audio_buffer_lag_time_target * sample_rate / frame_size)
	if prepared.packets.size() < required_packets:
		return false
	var run := _commit_cached_audio_run(prepared, stream_count)
	var first := run[0]
	var first_time_usec: int = first.arrival_time_usec - speaker.source_clock_offset_estimate_usec \
			- roundi(TwoVoipPacket.ACQUISITION_TIME_ESTIMATE * 1000000.0)
	var header := TwoVoipPacket.make_header_from_config(speaker.cached_stream_header,
			stream_count, first.frame_count, first_time_usec,
			int(speaker.cached_stream_header[TwoVoipPacket.HeaderField.OPUS_BITRATE]))
	_start_fabricated_episode(header, run, "fabricated after %d coherent audio packets" % run.size())
	return true


func _try_fabricate_start_from_mid(mid_packet: ReceivedPacket) -> bool:
	if speaker.inopusstream or speaker.cached_stream_header.is_empty():
		return false
	var expected_stream := int(speaker.cached_stream_header[TwoVoipPacket.HeaderField.OPUS_STREAM_COUNT]) + 1
	if mid_packet.stream_count != expected_stream:
		return false
	var prepared := _prepare_cached_audio_run(expected_stream)
	var run := _commit_cached_audio_run(prepared, expected_stream)
	var first_frame := mid_packet.frame_count
	if not run.is_empty():
		first_frame = run[0].frame_count
	var frame_usec := roundi(int(speaker.cached_stream_header[TwoVoipPacket.HeaderField.OPUS_FRAME_SIZE]) \
			* 1000000.0 / int(speaker.cached_stream_header[TwoVoipPacket.HeaderField.OPUS_SAMPLE_RATE]))
	var mid_time_usec := int(mid_packet.control[TwoVoipPacket.MidField.NEXT_FRAME_TIME_USEC])
	var first_time_usec := mid_time_usec - (mid_packet.frame_count - first_frame) * frame_usec
	var header := TwoVoipPacket.make_header_from_config(speaker.cached_stream_header,
			expected_stream, first_frame, first_time_usec,
			int(mid_packet.control[TwoVoipPacket.MidField.OPUS_BITRATE]))
	_start_fabricated_episode(header, run, "fabricated from MID")
	return true


func _hold(received: ReceivedPacket):
	received.kind = Kind.UNRESOLVED_AUDIO
	if queue.size() >= _preheader_limit():
		queue.pop_front()
		speaker.dropped_packet_count += 1
	queue.append(received)
	speaker._set_diagnostic_trigger("audio before START → hold")
	_try_fabricate_start_from_audio()


func _hold_unresolved(packet: PackedByteArray, context: Dictionary):
	var received := ReceivedPacket.new()
	received.wire = packet
	received.context = context.duplicate(true)
	received.arrival_time_usec = int(context.get("arrival_time_usec", Time.get_ticks_usec()))
	_hold(received)


func _start_episode(start_packet: ReceivedPacket):
	var held_packets := queue
	queue = []
	speaker._receive_audio_control_packet_in_order(start_packet.control, start_packet.context)
	if not speaker.inopusstream:
		return
	for held in held_packets:
		if held.kind == Kind.UNRESOLVED_AUDIO:
			if held.stream_count == speaker.opusstreamcount and held.frame_count >= 0 \
					and not held.audio.is_empty():
				held.kind = Kind.AUDIO
			else:
				if not _resolve_audio(held):
					speaker.preheader_wrong_parity_discard_count += 1
					continue
			if speaker._discard_initial_lead_packet(held):
				continue
			if not speaker._observe_audio_arrival(held):
				continue
		elif held.stream_count != speaker.opusstreamcount:
			speaker.preheader_wrong_parity_discard_count += 1
			continue
		_insert(held)
	drain()


func _force_gap_before(received: ReceivedPacket) -> bool:
	if received.kind == Kind.MID:
		return true
	while speaker.opusframecount < received.frame_count:
		var recovery_packet = received.audio if received.kind == Kind.AUDIO \
				and speaker.opusframecount == received.frame_count - 1 else null
		if not speaker._push_missing_frame(recovery_packet):
			return false
		speaker.opusframecount += 1
	return true


func drain(force_gap := false):
	while speaker.inopusstream and not queue.is_empty():
		var received := queue[0]
		if received.kind == Kind.UNRESOLVED_AUDIO:
			return
		if received.stream_count != speaker.opusstreamcount:
			return
		if received.frame_count < speaker.opusframecount:
			queue.pop_front()
			speaker.dropped_packet_count += 1
			speaker._set_diagnostic_trigger("stale packet → drop")
			continue
		if received.frame_count > speaker.opusframecount:
			if not force_gap or not _force_gap_before(received):
				return
		queue.pop_front()
		if received.kind == Kind.AUDIO:
			speaker._receive_audio_packet_in_order(received)
		elif received.kind == Kind.MID or received.kind == Kind.END:
			speaker._receive_audio_control_packet_in_order(received.control, received.context)


func receive(packet, context: Dictionary = {}):
	if TwoVoipPacket.is_control_packet(packet):
		return _receive_control(packet, context)
	if not speaker.inopusstream:
		_hold_unresolved(packet, context)
		return
	var received := ReceivedPacket.new()
	received.wire = packet
	received.context = context.duplicate(true)
	received.arrival_time_usec = int(context.get("arrival_time_usec", Time.get_ticks_usec()))
	if not _resolve_audio(received):
		_hold(received)
		return
	if speaker._discard_initial_lead_packet(received):
		return
	if received.frame_count < speaker.opusframecount:
		speaker.dropped_packet_count += 1
		speaker._set_diagnostic_trigger("stale packet → drop")
		return
	if not speaker._observe_audio_arrival(received):
		return
	speaker.last_episode_packet_arrival_usec = Time.get_ticks_usec()
	_insert(received)
	drain()


func _receive_control(packet, context: Dictionary):
	var control_packet := TwoVoipPacket.decode_control_packet(packet)
	if control_packet.is_empty():
		return speaker._receive_audio_control_packet_in_order(control_packet, context)
	var packet_type = control_packet[0]
	if packet_type not in [TwoVoipPacket.TYPE_START, TwoVoipPacket.TYPE_MID, TwoVoipPacket.TYPE_END]:
		return speaker._receive_audio_control_packet_in_order(control_packet, context)
	var received := ReceivedPacket.new()
	received.control = control_packet
	received.context = context.duplicate(true)
	received.arrival_time_usec = int(context.get("arrival_time_usec", Time.get_ticks_usec()))
	if packet_type == TwoVoipPacket.TYPE_START:
		if not TwoVoipPacket.header_is_valid(control_packet):
			return speaker._receive_audio_control_packet_in_order(control_packet, context)
		received.kind = Kind.START
		received.stream_count = int(control_packet[TwoVoipPacket.HeaderField.OPUS_STREAM_COUNT])
		received.frame_count = int(control_packet[TwoVoipPacket.HeaderField.NEXT_FRAME_COUNT])
		if speaker.fabricated_start_active and speaker.inopusstream \
				and received.stream_count == speaker.opusstreamcount:
			if not _header_configuration_matches(speaker.cached_stream_header, control_packet):
				push_error("TwoVoIP late START contradicts fabricated episode configuration")
				return
			speaker.cached_stream_header = control_packet.duplicate(true)
			speaker.fabricated_start_active = false
			speaker.fabricated_start_confirmation_count += 1
			speaker._set_diagnostic_trigger("START RECOVERY: confirmed by late START")
			return
		speaker.cached_stream_header = control_packet.duplicate(true)
		speaker.fabricated_start_active = false
		return _start_episode(received)
	if packet_type == TwoVoipPacket.TYPE_MID:
		if not TwoVoipPacket.mid_is_valid(control_packet):
			return speaker._receive_audio_control_packet_in_order(control_packet, context)
		received.kind = Kind.MID
		received.stream_count = int(control_packet[TwoVoipPacket.MidField.OPUS_STREAM_COUNT])
		received.frame_count = int(control_packet[TwoVoipPacket.MidField.NEXT_FRAME_COUNT])
	else:
		if not TwoVoipPacket.footer_is_valid(control_packet):
			return speaker._receive_audio_control_packet_in_order(control_packet, context)
		received.kind = Kind.END
		received.stream_count = int(control_packet[TwoVoipPacket.FooterField.OPUS_STREAM_COUNT])
		received.frame_count = int(control_packet[TwoVoipPacket.FooterField.OPUS_FRAME_COUNT])
	if packet_type == TwoVoipPacket.TYPE_MID and not speaker.inopusstream:
		_try_fabricate_start_from_mid(received)
	if not speaker.inopusstream or received.stream_count != speaker.opusstreamcount:
		_insert(received)
		return
	speaker.last_episode_packet_arrival_usec = Time.get_ticks_usec()
	_insert(received)
	drain()
	return control_packet if packet_type == TwoVoipPacket.TYPE_END and not speaker.inopusstream else null


func clear():
	queue.clear()


func has_pending() -> bool:
	return not queue.is_empty()


func pending_count() -> int:
	return queue.size()


func preheader_count() -> int:
	var count := 0
	for received in queue:
		if received.kind == Kind.UNRESOLVED_AUDIO:
			count += 1
	return count


func reorder_slot_occupied(offset: int) -> bool:
	for received in queue:
		if received.kind == Kind.AUDIO and received.frame_count == speaker.opusframecount + offset:
			return true
	return false
