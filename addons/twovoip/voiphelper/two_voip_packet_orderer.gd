extends Node

# One-to-one receive front end for TwoVoipSpeaker. This class knows packet
# ordering; the speaker remains responsible for episode, timing and playout
# decisions.

const Kind = TwoVoipPacket.ReceivedPacketKind
const ReceivedPacket = TwoVoipPacket.ReceivedPacket

const MAX_PENDING_PACKET_COUNT := TwoVoipPacket.CHUNK_SEQUENCE_MODULUS / 2

@export var enabled := true
var queue: Array[ReceivedPacket] = []
var start_pending := false
var diagnostic_trigger := ""
var active := false
var stream_count := 0
var frame_count := 0
var encode_base64 := false
var prefix_length := TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE
var cached_header: Array = []
var buffer_lag_target := 0.6
var clock_offset_usec := 0
var initial_wire_packets_to_skip := 0
var source_next_frame_count := 0
var fabricated_start_active := false
var dropped_count := 0
var duplicate_count := 0
var wrong_parity_count := 0


func update_receiver_state(is_active: bool, current_stream_count: int,
		current_frame_count: int, uses_base64: bool, chunk_prefix_length: int,
		stream_header: Array, lag_target: float, source_clock_offset_usec: int,
		lead_packets_to_skip: int, source_next_frame: int, fabricated_start: bool):
	active = is_active
	stream_count = current_stream_count
	frame_count = current_frame_count
	encode_base64 = uses_base64
	prefix_length = chunk_prefix_length
	cached_header = stream_header
	buffer_lag_target = lag_target
	clock_offset_usec = source_clock_offset_usec
	initial_wire_packets_to_skip = lead_packets_to_skip
	source_next_frame_count = source_next_frame
	fabricated_start_active = fabricated_start


func _priority(received: ReceivedPacket) -> int:
	if received.kind == Kind.START:
		return -1
	if received.kind == Kind.MID:
		return 0
	if received.kind == Kind.AUDIO:
		return 1
	return 2


func _insert(received: ReceivedPacket):
	for queued in queue:
		if queued.kind == received.kind and queued.frame_count == received.frame_count \
				and queued.stream_count == received.stream_count:
			duplicate_count += 1
			diagnostic_trigger = "duplicate packet → ignore"
			return
	var insert_at := queue.size()
	for index in range(queue.size()):
		var queued := queue[index]
		if queued.kind == Kind.UNRESOLVED_AUDIO \
				or (active and received.stream_count == stream_count \
					and queued.stream_count != stream_count) \
				or (received.stream_count == queued.stream_count and (received.frame_count < queued.frame_count \
					or (received.frame_count == queued.frame_count and _priority(received) < _priority(queued)))):
			insert_at = index
			break
	queue.insert(insert_at, received)
	while queue.size() > MAX_PENDING_PACKET_COUNT:
		queue.pop_back()
		dropped_count += 1


func _resolve_audio(received: ReceivedPacket) -> bool:
	if not received.resolve_audio(encode_base64, prefix_length, stream_count, frame_count):
		if received.audio.size() <= prefix_length:
			push_warning("Bad TwoVoIP audio packet: too short")
		return false
	return true


func _preheader_limit() -> int:
	if cached_header.is_empty():
		return MAX_PENDING_PACKET_COUNT
	var frame_size := int(cached_header[TwoVoipPacket.HeaderField.OPUS_FRAME_SIZE])
	var sample_rate := int(cached_header[TwoVoipPacket.HeaderField.OPUS_SAMPLE_RATE])
	if frame_size <= 0 or sample_rate <= 0:
		return MAX_PENDING_PACKET_COUNT
	return mini(1024, maxi(MAX_PENDING_PACKET_COUNT,
			ceili(buffer_lag_target * sample_rate / frame_size) + 2))


func _prepare_cached_audio_run(stream_count: int) -> Dictionary:
	var packets: Array[ReceivedPacket] = []
	var decoded_audio: Array[PackedByteArray] = []
	var prepared := {
		"packets": packets,
		"audio": decoded_audio,
		"frames": PackedInt64Array(),
	}
	if cached_header.is_empty():
		return prepared
	var cached_encode_base64 := TwoVoipPacket.header_uses_base64(cached_header)
	var cached_prefix_length := int(cached_header[TwoVoipPacket.HeaderField.CHUNK_PREFIX_LENGTH])
	var expected_parity := stream_count % 2
	var next_frame := -1
	for received in queue:
		if received.kind != Kind.UNRESOLVED_AUDIO:
			continue
		var decoded := TwoVoipPacket.decode_audio_packet(received.wire, cached_encode_base64)
		if decoded.size() <= cached_prefix_length \
				or cached_prefix_length < TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE:
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
	cached_header = header
	var received := ReceivedPacket.new()
	received.kind = Kind.START
	received.is_control = true
	received.control = header
	received.stream_count = int(header[TwoVoipPacket.HeaderField.OPUS_STREAM_COUNT])
	received.frame_count = int(header[TwoVoipPacket.HeaderField.NEXT_FRAME_COUNT])
	received.arrival_time_usec = int(header[TwoVoipPacket.HeaderField.NEXT_FRAME_TIME_USEC]) \
			+ clock_offset_usec
	received.fabricated_start = true
	received.fabricated_start_reason = reason
	received.fabricated_run_has_audio = not run.is_empty()
	queue.push_front(received)


func _try_fabricate_start_from_audio() -> bool:
	if active or cached_header.is_empty():
		return false
	var next_stream_count := int(cached_header[TwoVoipPacket.HeaderField.OPUS_STREAM_COUNT]) + 1
	var prepared := _prepare_cached_audio_run(next_stream_count)
	var frame_size := int(cached_header[TwoVoipPacket.HeaderField.OPUS_FRAME_SIZE])
	var sample_rate := int(cached_header[TwoVoipPacket.HeaderField.OPUS_SAMPLE_RATE])
	var required_packets := ceili(buffer_lag_target * sample_rate / frame_size)
	if prepared.packets.size() < required_packets:
		return false
	var run := _commit_cached_audio_run(prepared, next_stream_count)
	var first := run[0]
	var first_time_usec: int = first.arrival_time_usec - clock_offset_usec \
			- roundi(TwoVoipPacket.ACQUISITION_TIME_ESTIMATE * 1000000.0)
	var header := TwoVoipPacket.make_header_from_config(cached_header,
			next_stream_count, first.frame_count, first_time_usec,
			int(cached_header[TwoVoipPacket.HeaderField.OPUS_BITRATE]))
	_start_fabricated_episode(header, run, "fabricated after %d coherent audio packets" % run.size())
	return true


func _try_fabricate_start_from_mid(mid_packet: ReceivedPacket) -> bool:
	if active or cached_header.is_empty():
		return false
	var expected_stream := int(cached_header[TwoVoipPacket.HeaderField.OPUS_STREAM_COUNT]) + 1
	if mid_packet.stream_count != expected_stream:
		return false
	var prepared := _prepare_cached_audio_run(expected_stream)
	var run := _commit_cached_audio_run(prepared, expected_stream)
	var first_frame := mid_packet.frame_count
	if not run.is_empty():
		first_frame = run[0].frame_count
	var frame_usec := roundi(int(cached_header[TwoVoipPacket.HeaderField.OPUS_FRAME_SIZE]) \
			* 1000000.0 / int(cached_header[TwoVoipPacket.HeaderField.OPUS_SAMPLE_RATE]))
	var mid_time_usec := int(mid_packet.control[TwoVoipPacket.MidField.NEXT_FRAME_TIME_USEC])
	var first_time_usec := mid_time_usec - (mid_packet.frame_count - first_frame) * frame_usec
	var header := TwoVoipPacket.make_header_from_config(cached_header,
			expected_stream, first_frame, first_time_usec,
			int(mid_packet.control[TwoVoipPacket.MidField.OPUS_BITRATE]))
	_start_fabricated_episode(header, run, "fabricated from MID")
	return true


func _hold(received: ReceivedPacket):
	received.kind = Kind.UNRESOLVED_AUDIO
	if queue.size() >= _preheader_limit():
		queue.pop_front()
		dropped_count += 1
	queue.append(received)
	diagnostic_trigger = "audio before START → hold"
	_try_fabricate_start_from_audio()


func _resolve_held_packets():
	var held_packets := queue
	queue = []
	for held in held_packets:
		if held.kind == Kind.UNRESOLVED_AUDIO:
			if held.stream_count == stream_count and held.frame_count >= 0 \
					and not held.audio.is_empty():
				held.kind = Kind.AUDIO
			else:
				if not _resolve_audio(held):
					wrong_parity_count += 1
					continue
		elif held.stream_count != stream_count:
			wrong_parity_count += 1
			continue
		_insert(held)


func _is_initial_lead(received: ReceivedPacket) -> bool:
	return received.kind == Kind.AUDIO and initial_wire_packets_to_skip > 0 \
			and received.frame_count < source_next_frame_count


func in_order_or_push(received: ReceivedPacket) -> bool:
	if received.is_control:
		return _receive_control(received)
	if not active:
		_hold(received)
		return false
	if not _resolve_audio(received):
		_hold(received)
		return false
	if received.frame_count < frame_count and not _is_initial_lead(received):
		dropped_count += 1
		diagnostic_trigger = "stale packet → drop"
		return false
	if queue.is_empty() and (received.frame_count == frame_count \
			or _is_initial_lead(received)):
		return true
	_insert(received)
	return false


func _receive_control(received: ReceivedPacket):
	if received.kind not in [Kind.START, Kind.MID, Kind.END]:
		return true
	if received.kind == Kind.START:
		if fabricated_start_active and active and received.stream_count == stream_count:
			if not _header_configuration_matches(cached_header, received.control):
				push_error("TwoVoIP late START contradicts fabricated episode configuration")
				return false
			cached_header = received.control
			received.fabricated_start_confirmation = true
			diagnostic_trigger = "START RECOVERY: confirmed by late START"
			return true
		cached_header = received.control
		start_pending = true
		return true
	if received.kind == Kind.MID and not active:
		_try_fabricate_start_from_mid(received)
	if not active or received.stream_count != stream_count:
		_insert(received)
		return false
	if queue.is_empty() and received.frame_count == frame_count:
		return true
	_insert(received)
	return false


func has_next_packet_order(force_gap := false) -> bool:
	if start_pending and active:
		start_pending = false
		_resolve_held_packets()
	if queue.is_empty():
		return false
	while active and not queue.is_empty():
		var received := queue[0]
		if received.kind == Kind.START:
			return true
		if received.kind == Kind.UNRESOLVED_AUDIO \
				or received.stream_count != stream_count:
			return false
		if received.frame_count < frame_count and not _is_initial_lead(received):
			queue.pop_front()
			dropped_count += 1
			diagnostic_trigger = "stale packet → drop"
			continue
		return force_gap or received.frame_count == frame_count \
				or _is_initial_lead(received)
	return not queue.is_empty() and queue[0].kind == Kind.START


func next_packet_order() -> ReceivedPacket:
	assert(has_next_packet_order(true))
	var received: ReceivedPacket = queue.pop_front()
	if received.kind == Kind.START:
		start_pending = true
	return received


func clear():
	queue.clear()
	start_pending = false
	diagnostic_trigger = ""


func take_diagnostic_trigger() -> String:
	var trigger := diagnostic_trigger
	diagnostic_trigger = ""
	return trigger


func take_counts() -> PackedInt32Array:
	var counts := PackedInt32Array([dropped_count, duplicate_count, wrong_parity_count])
	dropped_count = 0
	duplicate_count = 0
	wrong_parity_count = 0
	return counts


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
		if received.kind == Kind.AUDIO and received.frame_count == frame_count + offset:
			return true
	return false
