extends Node

signal input_device_changed(new_input_device: String)
signal remote_audio_packet_received(multiplayer_id: int, packet: PackedByteArray)

const PARAM_OPUS_FRAME_SIZE := &"hp_ofs"
const PARAM_OPUS_SAMPLE_RATE := &"hp_osr"
const PARAM_OPUS_CHANNELS := &"hp_oc"
const PARAM_LEN_CHUNK_PREFIX := &"hp_lcp"
const PARAM_OPUS_STREAM_COUNT := &"hp_osc"
const PARAM_OPUS_FRAME_COUNT := &"hp_ofc"
const PARAM_TALKING_TIME_START := &"hp_tts"
const PARAM_TALKING_TIME_DURATION := &"hp_ttd"
const PARAM_TALKING_TIME_END := &"hp_tte"

const VOICE_CHAT_HEADER_CHANNEL: int = 1
const VOICE_CHAT_PACKET_CHANNEL: int = 2

var microphone: AutoVoipMicrophone
var enabled := false

var _last_input_device: String


func _ready() -> void:
	microphone = AutoVoipMicrophone.new(false)
	microphone.set_opus_values(48000, 20, 2, 12000, 5, true)
	microphone.activation_mode = AutoVoipMicrophone.Mode.PUSH_TO_TALK
	microphone.push_to_talk_action = &"push_to_talk"

	add_child(microphone)

	microphone.audio_packet_ready.connect(_received_audio_packet)
	microphone.audio_json_packet_ready.connect(_received_audio_json_packet)
	_last_input_device = AudioServer.input_device


func _process(_delta: float) -> void:
	if _last_input_device != AudioServer.input_device:
		input_device_changed.emit(AudioServer.input_device)
		_last_input_device = AudioServer.input_device


func to_ascii_buffer(header: Dictionary) -> PackedByteArray:
	return JSON.stringify(header).to_ascii_buffer()


func from_ascii_buffer(packet: PackedByteArray) -> Variant:
	return JSON.parse_string(packet.get_string_from_ascii())


func send_mid_header_to_new_peer(id: int) -> void:
	var mid_header = AutoVoip.microphone.request_audio_json_packet_mid_header()
	if mid_header:
		if AutoVoip.microphone.json_packets_as_binary:
			AutoVoip.received_audio_packet.rpc_id(id, AutoVoip.to_ascii_buffer(mid_header))
		else:
			AutoVoip.received_audio_json_packet.rpc_id(id, AutoVoip.to_ascii_buffer(mid_header))


@rpc("any_peer", "call_remote", "unreliable", VOICE_CHAT_PACKET_CHANNEL)
func received_audio_packet(packet: PackedByteArray) -> void:
	if not enabled:
		return
	remote_audio_packet_received.emit(multiplayer.get_remote_sender_id(), packet)


@rpc("any_peer", "call_remote", "reliable", VOICE_CHAT_HEADER_CHANNEL)
func received_audio_json_packet(packet: PackedByteArray) -> void:
	if not enabled:
		return
	remote_audio_packet_received.emit(multiplayer.get_remote_sender_id(), packet)


func _received_audio_packet(packet: PackedByteArray) -> void:
	if multiplayer.has_multiplayer_peer() and enabled:
		received_audio_packet.rpc(packet)


func _received_audio_json_packet(header: Dictionary) -> void:
	if multiplayer.has_multiplayer_peer() and enabled:
		received_audio_json_packet.rpc(to_ascii_buffer(header))
