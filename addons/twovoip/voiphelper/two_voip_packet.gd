class_name TwoVoipPacket
extends RefCounted


const WIRE_VERSION := 2

const TYPE_START := "start"
const TYPE_MID := "mid"
const TYPE_END := "end"
const TYPE_HASH_REQUEST := "hash?"
const TYPE_HASH_RESPONSE := "hash"

const ENCODING_BINARY := "binary"
const ENCODING_BASE64 := "base64"

const ASCII_OPEN_BRACKET := 91
const ASCII_QUOTE := 34
const ASCII_CLOSE_BRACKET := 93

const CHUNK_SEQUENCE_PREFIX_SIZE := 2
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
	OPUS_FRAME_COUNT,
	FIRST_FRAME_TIME_USEC,
	AUDIO_ENCODING,
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


static func make_header(packet_type: String, opus_frame_size: int,
		opus_sample_rate: int, opus_channels: int, chunk_prefix_length: int,
		opus_stream_count: int, opus_frame_count: int,
		first_frame_time_usec: int, encode_base64: bool) -> Array:
	assert(packet_type == TYPE_START or packet_type == TYPE_MID)
	var packet: Array = []
	packet.resize(HeaderField.SIZE)
	packet[HeaderField.TYPE] = packet_type
	packet[HeaderField.VERSION] = WIRE_VERSION
	packet[HeaderField.OPUS_FRAME_SIZE] = opus_frame_size
	packet[HeaderField.OPUS_SAMPLE_RATE] = opus_sample_rate
	packet[HeaderField.OPUS_CHANNELS] = opus_channels
	packet[HeaderField.CHUNK_PREFIX_LENGTH] = chunk_prefix_length
	packet[HeaderField.OPUS_STREAM_COUNT] = opus_stream_count
	packet[HeaderField.OPUS_FRAME_COUNT] = opus_frame_count
	packet[HeaderField.FIRST_FRAME_TIME_USEC] = first_frame_time_usec
	packet[HeaderField.AUDIO_ENCODING] = ENCODING_BASE64 if encode_base64 else ENCODING_BINARY
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
	return packet.size() == HeaderField.SIZE \
			and (packet[HeaderField.TYPE] == TYPE_START or packet[HeaderField.TYPE] == TYPE_MID) \
			and packet[HeaderField.VERSION] == WIRE_VERSION \
			and (packet[HeaderField.AUDIO_ENCODING] == ENCODING_BINARY \
					or packet[HeaderField.AUDIO_ENCODING] == ENCODING_BASE64)


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


static func header_uses_base64(packet: Array) -> bool:
	return packet[HeaderField.AUDIO_ENCODING] == ENCODING_BASE64


static func make_timestamped_chunk_prefix() -> PackedByteArray:
	var prefix := PackedByteArray()
	prefix.resize(TIMESTAMPED_CHUNK_PREFIX_SIZE)
	return prefix


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
