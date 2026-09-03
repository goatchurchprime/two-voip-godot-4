extends Node

signal input_device_changed(new_input_device: String)
signal remote_opus_packet_received(remote_sender_id: int, packet: PackedByteArray)
signal remote_metadata_packet_received(remote_sender_id: int, packet: PackedByteArray)

## Magic byte to identify header packet
const HEADER_SIGNATURE := 0x1A
const HEADER_BYTE_LENGTH := 57

# Byte offsets for header
const HEADER_PARAM_TALKING_TIME_START := 1
const HEADER_PARAM_OPUS_CHUNK_SIZE := 1 + 8 * 1
const HEADER_PARAM_OPUS_SAMPLE_RATE := 1 + 8 * 2
const HEADER_PARAM_OPUS_CHANNELS := 1 + 8 * 3
const HEADER_PARAM_LEN_CHUNK_PREFIX := 1 + 8 * 4
const HEADER_PARAM_OPUS_STREAM_COUNT := 1 + 8 * 5
const HEADER_PARAM_OPUS_FRAME_COUNT := 1 + 8 * 6

## Magic byte to identify footer packet
const FOOTER_SIGNATURE := 0x1B
const FOOTER_BYTE_LENGTH := 33

# Byte offsets for footer
const FOOTER_PARAM_TALKING_TIME_END := 1
const FOOTER_PARAM_TALKING_TIME_DURATION := 1 + 8 * 1
const FOOTER_PARAM_OPUS_STREAM_COUNT := 1 + 8 * 2
const FOOTER_PARAM_OPUS_FRAME_COUNT := 1 + 8 * 3

var microphone: AutoVoipMicrophone
var enabled := false

var _last_input_device: String


func _enter_tree() -> void:
	_configure_rpc()


func _ready() -> void:
	_last_input_device = AudioServer.input_device

	microphone = AutoVoipMicrophone.new()
	microphone.set_opus_values(48000, 20, 2, 12000, 5, true)
	microphone.activation_mode = AutoVoipMicrophone.Mode.PUSH_TO_TALK
	microphone.push_to_talk_action = &"push_to_talk"

	add_child(microphone)

	microphone.opus_packet_ready.connect(_received_opus_packet)
	microphone.metadata_packet_ready.connect(_received_metadata_packet)


func _process(_delta: float) -> void:
	if _last_input_device != AudioServer.input_device:
		input_device_changed.emit(AudioServer.input_device)
		_last_input_device = AudioServer.input_device


func send_mid_header_to_new_peer(id: int) -> void:
	var mid_header = microphone.request_metadata_packet_mid_header()
	if mid_header:
		received_metadata_packet.rpc_id(id, mid_header)


func received_opus_packet(packet: PackedByteArray) -> void:
	if not enabled:
		return
	remote_opus_packet_received.emit(multiplayer.get_remote_sender_id(), packet)


func received_metadata_packet(packet: PackedByteArray) -> void:
	if not enabled:
		return
	remote_metadata_packet_received.emit(multiplayer.get_remote_sender_id(), packet)


func _configure_rpc() -> void:
	rpc_config(
		"received_metadata_packet",
		{
			"rpc_mode": MultiplayerAPI.RPCMode.RPC_MODE_ANY_PEER,
			"transfer_mode": MultiplayerPeer.TransferMode.TRANSFER_MODE_RELIABLE,
			"call_local": false,
			"channel": ProjectSettings.get_setting("audio/auto_voip/metadata_rpc_channel"),
		},
	)
	rpc_config(
		"received_opus_packet",
		{
			"rpc_mode": MultiplayerAPI.RPCMode.RPC_MODE_ANY_PEER,
			"transfer_mode": MultiplayerPeer.TransferMode.TRANSFER_MODE_UNRELIABLE,
			"call_local": false,
			"channel": ProjectSettings.get_setting("audio/auto_voip/opus_rpc_channel"),
		},
	)


func _received_opus_packet(packet: PackedByteArray) -> void:
	if multiplayer.has_multiplayer_peer() and enabled:
		received_opus_packet.rpc(packet)


func _received_metadata_packet(packet: PackedByteArray) -> void:
	if multiplayer.has_multiplayer_peer() and enabled:
		received_metadata_packet.rpc(packet)
