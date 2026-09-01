class_name AutoVoipSpeaker
extends Node

const ASCII_OPEN_BRACE: int = 123 # "{".to_ascii_buffer()[0]
const ASCII_CLOSE_BRACE: int = 125 # "}".to_ascii_buffer()[0]
const N_OUT_OF_ORDER_QUEUE: int = 4
const N_PACKET_INITIAL_BATCHING: int = 2

@export var audio_buffer_lag_time_target: float = 0.6
@export var audio_buffer_lag_time_target_tolerance: float = 0.35
@export var audio_player_opus: Node = null # AudioStreamPlayer | AudioStreamPlayer2D | AudioStreamPlayer3D

var audio_stream_opus: AudioStreamOpus = null
var audio_stream_playback_opus: AudioStreamPlaybackOpus = null

var audio_server_output_latency: float = AudioServer.get_output_latency()
var len_chunk_prefix: int = -1
var opus_stream_count: int = 0
var in_opus_stream := false
var opus_frame_count: int = 0
var opus_frame_size: int = 960
var out_of_order_chunk_queue: Array[Variant] = []
var opus_frame_queue_count: int = 0

var playback_paused_on_mark := false

var playing_recording := false
var pause_reached := false


func _ready() -> void:
	assert(
			audio_player_opus is AudioStreamPlayer or audio_player_opus is AudioStreamPlayer2D
					or audio_player_opus is AudioStreamPlayer3D
	)

	audio_stream_opus = AudioStreamOpus.new()
	audio_player_opus.set_stream(audio_stream_opus)


func _physics_process(_delta: float) -> void:
	if audio_stream_playback_opus == null:
		return

	if playing_recording:
		return

	var queue_length_frames: int = audio_stream_playback_opus.queue_length_frames()
	if not pause_reached and queue_length_frames == 0:
		pause_reached = true

	var buffer_length_time: float = audio_server_output_latency + queue_length_frames * 1.0 / audio_stream_opus.opus_sample_rate


func unpause_when_buffer_ready() -> void:
	assert(playback_paused_on_mark)
	if audio_stream_playback_opus == null:
		return
	var buffer_length_time: float = audio_server_output_latency + audio_stream_playback_opus.queue_length_frames() * 1.0 / audio_stream_opus.opus_sample_rate
	if buffer_length_time > audio_buffer_lag_time_target:
		audio_stream_playback_opus.mark_end_opus_stream(true)
		playback_paused_on_mark = false


func external_end_stream() -> void:
	if in_opus_stream:
		receive_audio_packet(AutoVoip.to_ascii_buffer({ AutoVoip.PARAM_TALKING_TIME_END: -1 }))


func receive_audio_packet(packet: PackedByteArray) -> void:
	if audio_stream_opus == null:
		return
	if len(packet) <= 3:
		if OS.has_feature(&"debug"):
			push_error("Bad packet, too short")
		return

	# JSON header or footer
	if packet[0] == ASCII_OPEN_BRACE and packet[-1] == ASCII_CLOSE_BRACE:
		var dictionary = AutoVoip.from_ascii_buffer(packet)
		if dictionary == null or dictionary is not Dictionary:
			return

		# Process header
		if dictionary.has(AutoVoip.PARAM_TALKING_TIME_START):
			_process_header(dictionary)
			return

		# Process footer
		if dictionary.has(AutoVoip.PARAM_TALKING_TIME_END):
			_process_footer(dictionary)
			return
		return

	if len_chunk_prefix == -1:
		return

	if len_chunk_prefix == 0:
		audio_stream_opus.push_opus_packet(packet, len_chunk_prefix, 0)
		opus_frame_count += 1
		if playback_paused_on_mark:
			unpause_when_buffer_ready()
		return

	if packet[1] & 128 == (opus_stream_count % 2) * 128:
		assert(len_chunk_prefix == 2)
		var opus_frame_count_i: int = packet[0] + (packet[1] & 127) * 256
		var opus_frame_count_r: int = opus_frame_count_i - opus_frame_count
		if opus_frame_count_r < 0:
			if opus_frame_count_r < -30000:
				opus_frame_count = opus_frame_count_i
				opus_frame_count_r = 0

		if opus_frame_count_r >= 0 and not out_of_order_chunk_queue.is_empty():
			while opus_frame_count_r >= N_OUT_OF_ORDER_QUEUE:
				if out_of_order_chunk_queue[0] != null:
					audio_stream_playback_opus.push_opus_packet(
							out_of_order_chunk_queue[0],
							len_chunk_prefix,
							0,
							)
					opus_frame_queue_count -= 1
				else:
					var next_valid_packet_for_fec: PackedByteArray = packet
					for i in range(1, N_OUT_OF_ORDER_QUEUE):
						if out_of_order_chunk_queue[i] != null:
							next_valid_packet_for_fec = out_of_order_chunk_queue[i]
							break
					audio_stream_playback_opus.push_opus_packet(
							next_valid_packet_for_fec,
							len_chunk_prefix,
							1,
							)
				out_of_order_chunk_queue.pop_front()
				out_of_order_chunk_queue.push_back(null)
				opus_frame_count_r -= 1
				opus_frame_count += 1
				assert(opus_frame_queue_count >= 0)

			out_of_order_chunk_queue[opus_frame_count_r] = packet
			opus_frame_queue_count += 1
			while (
					out_of_order_chunk_queue[0] != null
					and opus_frame_count + opus_frame_queue_count >= N_PACKET_INITIAL_BATCHING
			):
				if opus_frame_size > audio_stream_playback_opus.available_space_frames():
					break
				audio_stream_playback_opus.push_opus_packet(
						out_of_order_chunk_queue.pop_front(),
						len_chunk_prefix,
						0,
						)
				out_of_order_chunk_queue.push_back(null)
				opus_frame_count += 1
				opus_frame_queue_count -= 1
				assert(opus_frame_queue_count >= 0)

		if playback_paused_on_mark:
			unpause_when_buffer_ready()
		return


func set_rec_opus_values(opus_sample_rate: int, opus_channels: int) -> void:
	if (
			not audio_player_opus.playing or audio_stream_opus.opus_sample_rate != opus_sample_rate
			or audio_stream_opus.opus_channels != opus_channels
	):
		audio_stream_opus.opus_sample_rate = opus_sample_rate
		audio_stream_opus.opus_channels = opus_channels
		audio_player_opus.play() # creates a new playback
		audio_stream_playback_opus = audio_player_opus.get_stream_playback()
		# begins in a paused state
		# audio_stream_playback_opus.mark_end_opus_stream(false)
		playback_paused_on_mark = true
		pause_reached = false


func _process_header(header: Dictionary) -> void:
	# Ensure header is properly formatted, even if not all values are needed
	if (
			not header.has(AutoVoip.PARAM_TALKING_TIME_START)
			or header.get(AutoVoip.PARAM_TALKING_TIME_START) is not float
	):
		return

	if (
			not header.has(AutoVoip.PARAM_OPUS_FRAME_SIZE)
			or header.get(AutoVoip.PARAM_OPUS_FRAME_SIZE) is not float
	):
		return
	if (
			not header.has(AutoVoip.PARAM_OPUS_SAMPLE_RATE)
			or header.get(AutoVoip.PARAM_OPUS_SAMPLE_RATE) is not float
	):
		return
	if (
			not header.has(AutoVoip.PARAM_OPUS_CHANNELS)
			or header.get(AutoVoip.PARAM_OPUS_CHANNELS) is not float
	):
		return
	if (
			not header.has(AutoVoip.PARAM_LEN_CHUNK_PREFIX)
			or header.get(AutoVoip.PARAM_LEN_CHUNK_PREFIX) is not float
	):
		return
	if (
			not header.has(AutoVoip.PARAM_OPUS_STREAM_COUNT)
			or header.get(AutoVoip.PARAM_OPUS_STREAM_COUNT) is not float
	):
		return
	if (
			not header.has(AutoVoip.PARAM_OPUS_FRAME_COUNT)
			or header.get(AutoVoip.PARAM_OPUS_FRAME_COUNT) is not float
	):
		return

	set_rec_opus_values(
			header[AutoVoip.PARAM_OPUS_SAMPLE_RATE],
			header.get(AutoVoip.PARAM_OPUS_CHANNELS, 2),
			)

	in_opus_stream = true

	len_chunk_prefix = int(header[AutoVoip.PARAM_LEN_CHUNK_PREFIX])
	opus_stream_count = int(header[AutoVoip.PARAM_OPUS_STREAM_COUNT])
	opus_frame_size = int(header[AutoVoip.PARAM_OPUS_FRAME_SIZE])

	opus_frame_count = 0
	if header.get(AutoVoip.PARAM_OPUS_FRAME_COUNT, 0) > 0:
		opus_frame_count = int(header[AutoVoip.PARAM_OPUS_FRAME_COUNT]) + 1

	out_of_order_chunk_queue.clear()
	out_of_order_chunk_queue.resize(AutoVoipSpeaker.N_OUT_OF_ORDER_QUEUE)
	opus_frame_queue_count = 0


func _process_footer(footer: Dictionary) -> void:
	# Ensure footer is properly formatted, even if not all values are needed
	if (
			not footer.has(AutoVoip.PARAM_TALKING_TIME_END)
			or footer.get(AutoVoip.PARAM_TALKING_TIME_END) is not float
	):
		return

	if (
			not footer.has(AutoVoip.PARAM_OPUS_STREAM_COUNT)
			or footer.get(AutoVoip.PARAM_OPUS_STREAM_COUNT) is not float
	):
		return
	if (
			not footer.has(AutoVoip.PARAM_OPUS_FRAME_COUNT)
			or footer.get(AutoVoip.PARAM_OPUS_FRAME_COUNT) is not float
	):
		return
	if (
			not footer.has(AutoVoip.PARAM_TALKING_TIME_DURATION)
			or footer.get(AutoVoip.PARAM_TALKING_TIME_DURATION) is not float
	):
		return

	in_opus_stream = false

	if audio_stream_playback_opus == null:
		return

	if playback_paused_on_mark and audio_stream_playback_opus.queue_length_frames() == 0:
		audio_stream_playback_opus.mark_end_opus_stream(true)

	audio_stream_playback_opus.mark_end_opus_stream(false)
	playback_paused_on_mark = true
	pause_reached = false
