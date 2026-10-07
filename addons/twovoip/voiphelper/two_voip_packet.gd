class_name TwoVoipPacket
extends RefCounted


const WIRE_VERSION := 5
const ACQUISITION_TIME_ESTIMATE := 0.03

const TYPE_START := "start"
const TYPE_MID := "mid"
const TYPE_END := "end"
const TYPE_HASH_REQUEST := "hash?"
const TYPE_HASH_RESPONSE := "hash"
const TYPE_CLOCK_PING := "clock_ping"
const TYPE_CLOCK_PONG := "clock_pong"
const TYPE_CLOCK_ACK := "clock_ack"

const ENCODING_BINARY := "binary"
const ENCODING_BASE64 := "base64"

const ASCII_OPEN_BRACKET := 91
const ASCII_QUOTE := 34
const ASCII_CLOSE_BRACKET := 93

const CHUNK_SEQUENCE_PREFIX_SIZE := 1
# The receiver infers higher bits; an unnotified displacement must be less than 64 frames.
const CHUNK_SEQUENCE_MODULUS := 128
const CHUNK_SEQUENCE_MASK := 127
const CHUNK_STREAM_PARITY_MASK := 128
const CHUNK_FIRST_FRAME_TIME_OFFSET := CHUNK_SEQUENCE_PREFIX_SIZE
const CHUNK_FIRST_FRAME_TIME_SIZE := 8
const TIMESTAMPED_CHUNK_PREFIX_SIZE := CHUNK_SEQUENCE_PREFIX_SIZE + CHUNK_FIRST_FRAME_TIME_SIZE


enum HeaderField {
	TYPE,
	VERSION,
	OPUS_FRAME_SIZE,
	OPUS_SAMPLE_RATE,
	OPUS_CHANNELS,
	CHUNK_PREFIX_LENGTH,
	OPUS_STREAM_COUNT,
	NEXT_FRAME_COUNT,
	NEXT_FRAME_TIME_USEC,
	OPUS_BITRATE,
	AUDIO_ENCODING,
	LEAD_FRAME_COUNT,
	SIZE,
}


enum MidField {
	TYPE,
	OPUS_STREAM_COUNT,
	NEXT_FRAME_COUNT,
	NEXT_FRAME_TIME_USEC,
	OPUS_BITRATE,
	SIZE,
}


enum FooterField {
	TYPE,
	OPUS_STREAM_COUNT,
	OPUS_FRAME_COUNT,
	TALKING_TIME_DURATION,
	TALKING_TIME_END,
	RMS,
	SIZE,
}


enum HashRequestField {
	TYPE,
	VERSION,
	OPUS_STREAM_COUNT,
	FIRST_FRAME,
	FRAME_COUNT,
	SIZE,
}


enum HashResponseField {
	TYPE,
	VERSION,
	OPUS_STREAM_COUNT,
	FIRST_FRAME,
	FRAME_COUNT,
	HASH,
	SIZE,
}


enum ClockPingField {
	TYPE,
	VERSION,
	PROBE_ID,
	T1_USEC,
	CLOCK_DOMAIN_ID,
	SIZE,
}


enum ClockPongField {
	TYPE,
	VERSION,
	PROBE_ID,
	T1_USEC,
	T2_USEC,
	T3_USEC,
	CLOCK_DOMAIN_ID,
	SIZE,
}


enum ClockAckField {
	TYPE,
	VERSION,
	PROBE_ID,
	T1_USEC,
	T2_USEC,
	T3_USEC,
	T4_USEC,
	SIZE,
}


static func make_header(packet_type: String, opus_frame_size: int,
		opus_sample_rate: int, opus_channels: int, chunk_prefix_length: int,
		opus_stream_count: int, next_frame_count: int,
		next_frame_time_usec: int, opus_bitrate: int, encode_base64: bool,
		lead_frame_count: int = 0) -> Array:
	assert(packet_type == TYPE_START)
	var packet: Array = []
	packet.resize(HeaderField.SIZE)
	packet[HeaderField.TYPE] = packet_type
	packet[HeaderField.VERSION] = WIRE_VERSION
	packet[HeaderField.OPUS_FRAME_SIZE] = opus_frame_size
	packet[HeaderField.OPUS_SAMPLE_RATE] = opus_sample_rate
	packet[HeaderField.OPUS_CHANNELS] = opus_channels
	packet[HeaderField.CHUNK_PREFIX_LENGTH] = chunk_prefix_length
	packet[HeaderField.OPUS_STREAM_COUNT] = opus_stream_count
	packet[HeaderField.NEXT_FRAME_COUNT] = next_frame_count
	packet[HeaderField.NEXT_FRAME_TIME_USEC] = next_frame_time_usec
	packet[HeaderField.OPUS_BITRATE] = opus_bitrate
	packet[HeaderField.AUDIO_ENCODING] = ENCODING_BASE64 if encode_base64 else ENCODING_BINARY
	packet[HeaderField.LEAD_FRAME_COUNT] = lead_frame_count
	return packet


static func make_mid(opus_stream_count: int, next_frame_count: int,
		next_frame_time_usec: int, opus_bitrate: int) -> Array:
	var packet: Array = []
	packet.resize(MidField.SIZE)
	packet[MidField.TYPE] = TYPE_MID
	packet[MidField.OPUS_STREAM_COUNT] = opus_stream_count
	packet[MidField.NEXT_FRAME_COUNT] = next_frame_count
	packet[MidField.NEXT_FRAME_TIME_USEC] = next_frame_time_usec
	packet[MidField.OPUS_BITRATE] = opus_bitrate
	return packet


static func make_footer(opus_stream_count: int, opus_frame_count: int,
		talking_time_duration: float, talking_time_end: float, rms: float = 0.0) -> Array:
	var packet: Array = []
	packet.resize(FooterField.SIZE)
	packet[FooterField.TYPE] = TYPE_END
	packet[FooterField.OPUS_STREAM_COUNT] = opus_stream_count
	packet[FooterField.OPUS_FRAME_COUNT] = opus_frame_count
	packet[FooterField.TALKING_TIME_DURATION] = talking_time_duration
	packet[FooterField.TALKING_TIME_END] = talking_time_end
	packet[FooterField.RMS] = rms
	return packet


static func make_hash_request(opus_stream_count: int, first_frame: int,
		frame_count: int) -> Array:
	var packet: Array = []
	packet.resize(HashRequestField.SIZE)
	packet[HashRequestField.TYPE] = TYPE_HASH_REQUEST
	packet[HashRequestField.VERSION] = WIRE_VERSION
	packet[HashRequestField.OPUS_STREAM_COUNT] = opus_stream_count
	packet[HashRequestField.FIRST_FRAME] = first_frame
	packet[HashRequestField.FRAME_COUNT] = frame_count
	return packet


static func make_hash_response(opus_stream_count: int, first_frame: int, frame_count: int, hash: int) -> Array:
	var packet: Array = []
	packet.resize(HashResponseField.SIZE)
	packet[HashResponseField.TYPE] = TYPE_HASH_RESPONSE
	packet[HashResponseField.VERSION] = WIRE_VERSION
	packet[HashResponseField.OPUS_STREAM_COUNT] = opus_stream_count
	packet[HashResponseField.FIRST_FRAME] = first_frame
	packet[HashResponseField.FRAME_COUNT] = frame_count
	packet[HashResponseField.HASH] = hash
	return packet


static func make_clock_ping(probe_id: String, t1_usec: int,
		clock_domain_id: String) -> Array:
	return [TYPE_CLOCK_PING, WIRE_VERSION, probe_id, t1_usec, clock_domain_id]


static func make_clock_pong(probe_id: String, t1_usec: int,
		t2_usec: int, t3_usec: int, clock_domain_id: String) -> Array:
	return [TYPE_CLOCK_PONG, WIRE_VERSION, probe_id,
			t1_usec, t2_usec, t3_usec, clock_domain_id]


static func make_clock_ack(probe_id: String, t1_usec: int,
		t2_usec: int, t3_usec: int, t4_usec: int) -> Array:
	return [TYPE_CLOCK_ACK, WIRE_VERSION, probe_id,
			t1_usec, t2_usec, t3_usec, t4_usec]

static func encode_control_packet(packet: Array) -> PackedByteArray:
	return JSON.stringify(packet).to_ascii_buffer()

static func is_control_packet(packet: PackedByteArray) -> bool:
	return packet.size() >= 4 \
			and packet[0] == ASCII_OPEN_BRACKET \
			and packet[1] == ASCII_QUOTE \
			and packet[-1] == ASCII_CLOSE_BRACKET

static func decode_control_packet(packet: PackedByteArray) -> Array:
	if not is_control_packet(packet):
		return []
	var decoded = JSON.parse_string(packet.get_string_from_ascii())
	return decoded if decoded is Array else []


static func header_is_valid(packet: Array) -> bool:
	return packet.size() >= HeaderField.AUDIO_ENCODING + 1 \
			and packet.size() <= HeaderField.SIZE \
			and packet[HeaderField.TYPE] == TYPE_START \
			and packet[HeaderField.VERSION] == WIRE_VERSION \
			and packet[HeaderField.NEXT_FRAME_COUNT] >= 0 \
			and (packet[HeaderField.AUDIO_ENCODING] == ENCODING_BINARY \
					or packet[HeaderField.AUDIO_ENCODING] == ENCODING_BASE64)


static func mid_is_valid(packet: Array) -> bool:
	return packet.size() == MidField.SIZE \
			and packet[MidField.TYPE] == TYPE_MID \
			and packet[MidField.NEXT_FRAME_COUNT] >= 0 \
			and packet[MidField.OPUS_BITRATE] > 0


static func footer_is_valid(packet: Array) -> bool:
	return packet.size() == FooterField.SIZE and packet[FooterField.TYPE] == TYPE_END


static func hash_request_is_valid(packet: Array) -> bool:
	return packet.size() == HashRequestField.SIZE \
			and packet[HashRequestField.TYPE] == TYPE_HASH_REQUEST \
			and packet[HashRequestField.VERSION] == WIRE_VERSION \
			and packet[HashRequestField.FIRST_FRAME] >= 0 \
			and packet[HashRequestField.FRAME_COUNT] > 0


static func hash_response_is_valid(packet: Array) -> bool:
	return packet.size() == HashResponseField.SIZE \
			and packet[HashResponseField.TYPE] == TYPE_HASH_RESPONSE \
			and packet[HashResponseField.VERSION] == WIRE_VERSION \
			and packet[HashResponseField.FIRST_FRAME] >= 0 \
			and packet[HashResponseField.FRAME_COUNT] > 0


static func clock_ping_is_valid(packet: Array) -> bool:
	return packet.size() >= ClockPingField.CLOCK_DOMAIN_ID \
			and packet.size() <= ClockPingField.SIZE \
			and packet[ClockPingField.TYPE] == TYPE_CLOCK_PING \
			and packet[ClockPingField.VERSION] == WIRE_VERSION \
			and packet[ClockPingField.PROBE_ID] is String \
			and not packet[ClockPingField.PROBE_ID].is_empty() \
			and (packet.size() == ClockPingField.CLOCK_DOMAIN_ID \
					or packet[ClockPingField.CLOCK_DOMAIN_ID] is String)


static func clock_pong_is_valid(packet: Array) -> bool:
	return packet.size() >= ClockPongField.CLOCK_DOMAIN_ID \
			and packet.size() <= ClockPongField.SIZE \
			and packet[ClockPongField.TYPE] == TYPE_CLOCK_PONG \
			and packet[ClockPongField.VERSION] == WIRE_VERSION \
			and packet[ClockPongField.PROBE_ID] is String \
			and not packet[ClockPongField.PROBE_ID].is_empty() \
			and (packet.size() == ClockPongField.CLOCK_DOMAIN_ID \
					or packet[ClockPongField.CLOCK_DOMAIN_ID] is String)


static func clock_ping_domain_id(packet: Array) -> String:
	return str(packet[ClockPingField.CLOCK_DOMAIN_ID]) \
			if packet.size() > ClockPingField.CLOCK_DOMAIN_ID else ""


static func clock_pong_domain_id(packet: Array) -> String:
	return str(packet[ClockPongField.CLOCK_DOMAIN_ID]) \
			if packet.size() > ClockPongField.CLOCK_DOMAIN_ID else ""


static func clock_ack_is_valid(packet: Array) -> bool:
	return packet.size() == ClockAckField.SIZE \
			and packet[ClockAckField.TYPE] == TYPE_CLOCK_ACK \
			and packet[ClockAckField.VERSION] == WIRE_VERSION \
			and packet[ClockAckField.PROBE_ID] is String \
			and not packet[ClockAckField.PROBE_ID].is_empty()


static func header_uses_base64(packet: Array) -> bool:
	return packet[HeaderField.AUDIO_ENCODING] == ENCODING_BASE64


static func header_lead_frame_count(packet: Array) -> int:
	return maxi(0, int(packet[HeaderField.LEAD_FRAME_COUNT])) \
			if packet.size() > HeaderField.LEAD_FRAME_COUNT else 0


static func make_timestamped_chunk_prefix() -> PackedByteArray:
	var prefix := PackedByteArray()
	prefix.resize(TIMESTAMPED_CHUNK_PREFIX_SIZE)
	return prefix


static func make_sequence_chunk_prefix() -> PackedByteArray:
	var prefix := PackedByteArray()
	prefix.resize(CHUNK_SEQUENCE_PREFIX_SIZE)
	return prefix

static func set_sequence_chunk_prefix(prefix: PackedByteArray, frame_count: int, stream_count: int) -> void:
	assert(prefix.size() >= CHUNK_SEQUENCE_PREFIX_SIZE)
	prefix[0] = frame_count % CHUNK_SEQUENCE_MODULUS + (stream_count % 2)*CHUNK_STREAM_PARITY_MASK

static func decode_sequence_chunk_prefix(packet: PackedByteArray, minimum_frame_count: int, stream_count: int) -> int:
	if packet.size() < CHUNK_SEQUENCE_PREFIX_SIZE or packet[0]&CHUNK_STREAM_PARITY_MASK != (stream_count % 2)*CHUNK_STREAM_PARITY_MASK:
		return -1
	var frame_count_offset: int = ((packet[0]&CHUNK_SEQUENCE_MASK) - (minimum_frame_count % CHUNK_SEQUENCE_MODULUS) + CHUNK_SEQUENCE_MODULUS) % CHUNK_SEQUENCE_MODULUS
	if frame_count_offset >= CHUNK_SEQUENCE_MODULUS/2:
		return -1
	return minimum_frame_count + frame_count_offset


static func set_chunk_first_frame_time_usec(prefix: PackedByteArray, time_usec: int) -> void:
	assert(prefix.size() >= TIMESTAMPED_CHUNK_PREFIX_SIZE)
	prefix.encode_u64(CHUNK_FIRST_FRAME_TIME_OFFSET, time_usec)


static func get_chunk_first_frame_time_usec(packet: PackedByteArray) -> int:
	if packet.size() < TIMESTAMPED_CHUNK_PREFIX_SIZE:
		return 0
	return packet.decode_u64(CHUNK_FIRST_FRAME_TIME_OFFSET)


static func has_escaped_control_prefix(packet: PackedByteArray) -> bool:
	return packet.size() >= 2 \
			and packet[0] == ASCII_OPEN_BRACKET \
			and packet[1] == ASCII_QUOTE


static func encode_audio_packet(opus_packet: PackedByteArray, encode_base64: bool) -> PackedByteArray:
	if encode_base64:
		return Marshalls.raw_to_base64(opus_packet).to_ascii_buffer()
	var packet := opus_packet.duplicate()
	# Never let raw audio look like a JSON string array. The zero is transport
	# escaping only and is removed before libopus sees the packet.
	if has_escaped_control_prefix(packet):
		packet.append(0)
	return packet


static func decode_audio_packet(wire_packet: PackedByteArray, encoded_base64: bool) -> PackedByteArray:
	if encoded_base64:
		return Marshalls.base64_to_raw(wire_packet.get_string_from_ascii())
	var packet := wire_packet.duplicate()
	if has_escaped_control_prefix(packet):
		if packet[-1] != 0:
			return PackedByteArray()
		packet.resize(packet.size() - 1)
	return packet
