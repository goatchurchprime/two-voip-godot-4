class_name AutoVoipMicrophone
extends Node

signal metadata_packet_ready(metadata_packet: PackedByteArray)
signal opus_packet_ready(opus_packet: PackedByteArray)

signal transmitting_started
signal transmitting_stopped

enum Mode {
	PUSH_TO_TALK,
	VOICE_ACTIVATED_TRANSMISSION,
}

const ROOT_MEAN_SQUARE_MAX_MEASUREMENT := false

var opus_encoder := TwovoipOpusEncoder.new()
var chunk_prefix := PackedByteArray([0, 0])

var hang_time: float = 0.7
var vox_threshold: float = 0.07
var microphone_gain: float = 1.0

var is_currently_talking := false
var opus_frame_count: int = 0
var opus_stream_count: int = 0

var hang_frames: int = 25
var hang_frames_countup: int = 0

var talking_time_start: float = 0.0
var opus_chunk_size: int = 960
var audio_chunk_size: int = 882
var frame_time_seconds: float = 0.02
var opus_sample_rate: int = 48000
var opus_channels: int = 2

var audio_chunk = null # PackedVector2Array | null
var last_chunk_max: float = 0.0

var microphone_enabled := false:
	set(enabled):
		if microphone_enabled == enabled:
			return

		if enabled:
			var err: int = AudioServer.set_input_device_active(true)
			if err != OK:
				push_error("AutoVoipMicrophone: set_input_device_active error", err)
				return

			microphone_enabled = true
			set_process(true)
		else:
			AudioServer.set_input_device_active(false)
			microphone_enabled = false
			set_process(false)

var activation_mode := Mode.VOICE_ACTIVATED_TRANSMISSION:
	set(value):
		activation_mode = value
		if transmitting:
			transmitting = false

var denoise_enabled := false
var push_to_talk_action: StringName
var transmitting := false:
	set(transmit):
		if transmitting == transmit:
			return

		transmitting = transmit

		if transmitting:
			transmitting_started.emit()
		else:
			transmitting_stopped.emit()


func _init(
	p_microphone_enabled: bool = true,
	p_denoise_enabled: bool = true,
	p_activation_mode := Mode.VOICE_ACTIVATED_TRANSMISSION,
) -> void:
	microphone_enabled = p_microphone_enabled
	denoise_enabled = p_denoise_enabled
	activation_mode = p_activation_mode


func _ready() -> void:
	set_process(microphone_enabled)
	AutoVoip.input_device_changed.connect(_input_device_changed)


func _process(_delta: float) -> void:
	_process_talk_stream_ends(transmitting)
	while true:
		audio_chunk = AudioServer.get_input_frames(
			opus_encoder.calc_audio_chunk_size(opus_chunk_size)
		)
		if len(audio_chunk) == 0:
			break
		last_chunk_max = opus_encoder.process_pre_encoded_chunk(
			audio_chunk,
			opus_chunk_size,
			denoise_enabled,
			ROOT_MEAN_SQUARE_MAX_MEASUREMENT,
		)

		_process_vox(last_chunk_max)

		if is_currently_talking:
			_process_opus_chunk()
	audio_chunk = null


func _input(event: InputEvent) -> void:
	if activation_mode == Mode.PUSH_TO_TALK:
		assert(not push_to_talk_action.is_empty())
		if event.is_action_pressed(push_to_talk_action):
			transmitting = true
		elif event.is_action_released(push_to_talk_action):
			transmitting = false


func set_opus_values(
	p_opus_sample_rate: int,
	p_opus_frame_duration_ms: int,
	p_channels: int,
	p_opus_bitrate: int,
	p_opus_complexity: int,
	p_opus_optimize_for_voice: bool,
) -> void:
	_process_talk_stream_ends(false)
	assert(not is_currently_talking)

	opus_sample_rate = p_opus_sample_rate
	opus_channels = p_channels
	opus_encoder.create_sampler(
		int(AudioServer.get_input_mix_rate()),
		opus_sample_rate,
		opus_channels,
		denoise_enabled,
	)
	opus_encoder.create_opus_encoder(p_opus_bitrate, p_opus_complexity, p_opus_optimize_for_voice)
	opus_chunk_size = int(opus_sample_rate * p_opus_frame_duration_ms / 1000.0)
	audio_chunk_size = opus_encoder.calc_audio_chunk_size(opus_chunk_size)
	frame_time_seconds = p_opus_frame_duration_ms / 1000.0


func set_vox_threshold(p_vox_threshold: float) -> void:
	vox_threshold = p_vox_threshold


func set_gain(gain: float) -> void:
	microphone_gain = gain


func request_metadata_packet_mid_header() -> Variant:
	if not is_currently_talking:
		return null

	var header := PackedByteArray()

	header.resize(AutoVoip.HEADER_BYTE_LENGTH)

	header.encode_s8(0, AutoVoip.HEADER_SIGNATURE)
	header.encode_double(AutoVoip.HEADER_PARAM_TALKING_TIME_START, talking_time_start)
	header.encode_u64(AutoVoip.HEADER_PARAM_OPUS_CHUNK_SIZE, opus_chunk_size)
	header.encode_u64(AutoVoip.HEADER_PARAM_OPUS_SAMPLE_RATE, opus_sample_rate)
	header.encode_u64(AutoVoip.HEADER_PARAM_OPUS_CHANNELS, opus_channels)
	header.encode_u64(AutoVoip.HEADER_PARAM_LEN_CHUNK_PREFIX, len(chunk_prefix))
	header.encode_u64(AutoVoip.HEADER_PARAM_OPUS_STREAM_COUNT, opus_stream_count)
	header.encode_u64(AutoVoip.HEADER_PARAM_OPUS_FRAME_COUNT, opus_frame_count - 1)

	return header


func _input_device_changed(_new_input_device: String) -> void:
	if microphone_enabled:
		microphone_enabled = false
		microphone_enabled = true


func _process_talk_stream_ends(is_talking: bool) -> void:
	if is_talking and not is_currently_talking:
		talking_time_start = Time.get_ticks_msec() * 0.001
		hang_frames = int(hang_time / frame_time_seconds)

		var header := PackedByteArray()

		header.resize(AutoVoip.HEADER_BYTE_LENGTH)

		header.encode_s8(0, AutoVoip.HEADER_SIGNATURE)
		header.encode_double(AutoVoip.HEADER_PARAM_TALKING_TIME_START, talking_time_start)
		header.encode_u64(AutoVoip.HEADER_PARAM_OPUS_CHUNK_SIZE, opus_chunk_size)
		header.encode_u64(AutoVoip.HEADER_PARAM_OPUS_SAMPLE_RATE, opus_sample_rate)
		header.encode_u64(AutoVoip.HEADER_PARAM_OPUS_CHANNELS, opus_channels)
		header.encode_u64(AutoVoip.HEADER_PARAM_LEN_CHUNK_PREFIX, len(chunk_prefix))
		header.encode_u64(AutoVoip.HEADER_PARAM_OPUS_STREAM_COUNT, opus_stream_count)
		header.encode_u64(AutoVoip.HEADER_PARAM_OPUS_FRAME_COUNT, 0)

		opus_encoder.reset_opus_encoder()

		metadata_packet_ready.emit(header)

		opus_frame_count = 0
		is_currently_talking = true

	elif not is_talking and is_currently_talking:
		is_currently_talking = false
		var talking_time_end: float = Time.get_ticks_msec() * 0.001
		var talking_time_duration: float = talking_time_end - talking_time_start

		var footer := PackedByteArray()

		footer.resize(AutoVoip.FOOTER_BYTE_LENGTH)

		footer.encode_s8(0, AutoVoip.FOOTER_SIGNATURE)
		footer.encode_double(AutoVoip.FOOTER_PARAM_TALKING_TIME_END, talking_time_end)
		footer.encode_double(AutoVoip.FOOTER_PARAM_TALKING_TIME_DURATION, talking_time_duration)
		footer.encode_u64(AutoVoip.FOOTER_PARAM_OPUS_STREAM_COUNT, opus_stream_count)
		footer.encode_u64(AutoVoip.FOOTER_PARAM_OPUS_FRAME_COUNT, opus_frame_count)

		metadata_packet_ready.emit(footer)
		opus_stream_count += 1


func _process_vox(chunk_max: float):
	if chunk_max >= vox_threshold:
		if activation_mode == Mode.VOICE_ACTIVATED_TRANSMISSION and not transmitting:
			transmitting = true
		hang_frames_countup = 0
	else:
		if hang_frames_countup >= hang_frames:
			if activation_mode == Mode.VOICE_ACTIVATED_TRANSMISSION:
				transmitting = false
		hang_frames_countup += 1


func _process_opus_chunk():
	assert(is_currently_talking)
	if len(chunk_prefix) == 2:
		chunk_prefix.set(0, (opus_frame_count % 256)) # 32768 frames is 10 minutes
		@warning_ignore("integer_division")
		chunk_prefix.set(1, (int(opus_frame_count / 256) & 127) + (opus_stream_count % 2) * 128)
	else:
		assert(len(chunk_prefix) == 0)
	var opus_packet: PackedByteArray = opus_encoder.encode_chunk(chunk_prefix, microphone_gain)
	opus_packet_ready.emit(opus_packet)
	opus_frame_count += 1
