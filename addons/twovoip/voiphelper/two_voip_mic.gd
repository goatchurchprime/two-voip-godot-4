extends Node

var opusencoder : TwoVoipOpusEncoder
var chunkprefix := TwoVoipPacket.make_sequence_chunk_prefix()
var conditioner

var lead_time : float = 0.15
var hang_time : float  = 0.7
var input_gap_threshold : float = 0.1
var vox_threshhold = 0.07
var currentlytalking = false
var opusframecount = 0
var frame0usec = 0
var opusstreamcount = 0

var hangchunks = 25
var hangchunkscountup = 0
var chunkmaxpersist = 0.0

var audiosampleframetextureimage : Image
var audiosampleframetexture : ImageTexture
var audiosampleframematerial = null

signal transmit_audio_packet(opuspacket : PackedByteArray)
signal transmit_control_packet(packet: PackedByteArray, recipient: String)
signal clock_synchronization_finished(success: bool, missing_peers: Array[String])

const rootmeansquaremaxmeasurement = false
var encode_base64 = false

var agc_mode = 0

var talkingtimestart = 0
var talking_first_frame_time_usec: int = 0

const INPUT_TIMESTAMP_HISTORY_SECONDS := 1.0
# Experimental local history for measuring microphone interruptions.
var input_chunk_first_frame_times_usec := PackedInt64Array()
var conditioned_chunk_history: Array[PackedVector2Array] = []
var input_chunk_number := -1

var frametimesecs = 0.02
var opusframedurationms = 20
var input_mix_rate = 44100
var audio_chunk_size = 882
var opussamplerate = 48000
var opus_chunk_size = 960
var opuschannels = 2
var denoiser_mode = TwoVoipWebRTCConditioner.DENOISING_DISABLED
var agc_enabled = false
var conditioner_backend = -1
var echo_cancel_enabled = false

@export var check_unpack_hash_codes : bool = false
var chunks_per_hash = 50
var recent_hash_code = 0
var sentsumsquares = 0.0
var sent_audio_reference: AudioStreamPlaybackOpus = null
var application_resume_pending := false
var application_resume_count := 0

enum EchoCancelling {
	ECHO_CANCEL_DISABLED,
	ECHO_CANCEL_SPEEX,
	ECHO_CANCEL_WEBRTC
}
var echo_cancel_mode = EchoCancelling.ECHO_CANCEL_DISABLED

enum ConditionerBackend {
	RESAMPLE,
	WEBRTC,
	SPEEX,
}

func _notification(what: int):
	if what == NOTIFICATION_APPLICATION_RESUMED:
		# get_ticks_usec() is not a portable suspend clock. Force a fresh wire
		# episode before any captured post-resume frame can use the old mapping.
		application_resume_pending = true
		application_resume_count += 1

func consume_application_resume() -> bool:
	if not application_resume_pending:
		return false
	application_resume_pending = false
	if currentlytalking:
		processtalkstreamends(false)
	return true

var echoframedelay = 0
func set_opus_values(p_opussamplerate, p_opusframedurationms, p_channels, p_opusbitrate, p_opuscomplexity, p_opusoptimizeforvoice, p_inband_perc, p_conditioner_backend, p_echo_cancel_enabled, p_denoiser_mode, p_agc_enabled):
	input_mix_rate = AudioServer.get_input_mix_rate()
	var bitrate_changed = opusencoder != null and opusencoder.get_bitrate() != p_opusbitrate
	var p_opus_chunk_size = int(p_opussamplerate*p_opusframedurationms/1000.0)
	var samplerates_changed = (opussamplerate != p_opussamplerate) or (opus_chunk_size != p_opus_chunk_size) or (opuschannels != p_channels)
	opussamplerate = p_opussamplerate
	opus_chunk_size = p_opus_chunk_size
	opusframedurationms = p_opusframedurationms
	opuschannels = p_channels
	denoiser_mode = p_denoiser_mode
	agc_enabled = p_agc_enabled
	if conditioner == null or conditioner_backend != p_conditioner_backend or samplerates_changed:
		conditioner_backend = p_conditioner_backend
		if conditioner_backend == ConditionerBackend.WEBRTC:
			conditioner = TwoVoipWebRTCConditioner.new()
			var conditioner_error = conditioner.initialize(p_opusframedurationms, input_mix_rate, p_opussamplerate)
			if conditioner_error == ERR_UNAVAILABLE:
				conditioner_backend == ConditionerBackend.RESAMPLE
		if conditioner_backend == ConditionerBackend.RESAMPLE:
			conditioner = TwoVoipConditioner.new()
			conditioner.initialize(p_opusframedurationms, input_mix_rate, p_opussamplerate)

	if conditioner is TwoVoipWebRTCConditioner:
		conditioner.set_echo_cancel_enabled(p_echo_cancel_enabled)
		conditioner.set_denoising_level(p_denoiser_mode)
		conditioner.set_agc_enabled(p_agc_enabled)
	echo_cancel_enabled = p_echo_cancel_enabled and conditioner is TwoVoipWebRTCConditioner
	
	if opusencoder == null or samplerates_changed:
		opusencoder = TwoVoipOpusEncoder.new()
		var history_size := ceili(INPUT_TIMESTAMP_HISTORY_SECONDS*1000.0/opusframedurationms) + 1
		input_chunk_first_frame_times_usec.resize(history_size)
		input_chunk_first_frame_times_usec.fill(0)
		conditioned_chunk_history.resize(history_size)
		input_chunk_number = -1
		var sampler_error = opusencoder.initialize(opussamplerate, opuschannels, opus_chunk_size)
		if sampler_error != OK:
			push_error("TwoVoIP sampler configuration failed: %s" % error_string(sampler_error))
			return false

	if echo_cancel_enabled:
		var n = AudioServer.get_bus_effect_count(0)
		if n == 0 or not is_instance_of(AudioServer.get_bus_effect(0, n-1), AudioEffectCapture):
			var aec = AudioEffectCapture.new()
			aec.buffer_length = 1.0
			AudioServer.add_bus_effect(0, aec)
			n = AudioServer.get_bus_effect_count(0)
		mastercapture = AudioServer.get_bus_effect(0, n - 1)

	opusencoder.set_bitrate(p_opusbitrate)
	opusencoder.set_complexity(p_opuscomplexity)
	opusencoder.set_signal_type(TwoVoipOpusEncoder.SIGNAL_VOICE if p_opusoptimizeforvoice else TwoVoipOpusEncoder.SIGNAL_MUSIC)
	opusencoder.set_inband_perc(p_inband_perc)
	if bitrate_changed and currentlytalking:
		transmit_audio_packet.emit(make_audio_packet_midstream_update())

	audio_chunk_size = conditioner.get_input_chunk_size()
	frametimesecs = p_opusframedurationms/1000.0
	if audiosampleframematerial:
		var audiosampleframedata = PackedVector2Array()
		audiosampleframedata.resize(opus_chunk_size)
		for j in range(opus_chunk_size):
			audiosampleframedata.set(j, Vector2(-0.5,0.9) if (j%10)<5 else Vector2(0.6,0.1))
		audiosampleframetextureimage = Image.create_from_data(opus_chunk_size, 1, false, Image.FORMAT_RGF, audiosampleframedata.to_byte_array())
		audiosampleframetexture = ImageTexture.create_from_image(audiosampleframetextureimage)
		audiosampleframematerial.set_shader_parameter("chunktexture", audiosampleframetexture)
	return true

var miconbutton: Button = null
var optioninputdevice: OptionButton = null
var pttbutton: Button = null
var voxbutton: Button = null
var mastercapture: AudioEffectCapture = null
var captureframeslip = 0

func _ready():
	set_process(false)
	if not TwoVoip.native_version_is_compatible():
		return
	$ClockSync.transmit_packet.connect(
			func(packet, recipient): transmit_control_packet.emit(packet, recipient))
	$ClockSync.synchronization_finished.connect(
			func(success, missing): clock_synchronization_finished.emit(success, missing))

func transport_connected(peer_id: String):
	$ClockSync.transport_connected(peer_id)

func transport_disconnected():
	$ClockSync.transport_disconnected()

func register_peer(peer_id: String, speaker: Node):
	$ClockSync.register_peer(peer_id, speaker)

func unregister_peer(peer_id: String):
	$ClockSync.unregister_peer(peer_id)

func receive_control_packet(peer_id: String, packet: PackedByteArray,
		arrival_time_usec: int = 0, replay := false) -> bool:
	return $ClockSync.receive_packet(peer_id, packet, arrival_time_usec, replay)


func get_peer_timing(peer_id: String) -> Dictionary:
	return $ClockSync.get_estimate(peer_id)

func _on_miconbutton(toggled_on):
	if toggled_on:
		if OS.get_name() == "Android" and not OS.request_permission("android.permission.RECORD_AUDIO"):
			print("Waiting for user response after requesting audio permissions")
			# Must enable Record Audio permission in on Android
			@warning_ignore("untyped_declaration")
			var x = await get_tree().on_request_permissions_result
			var permission: String = x[0]
			var granted: bool = x[1]
			assert(permission == "android.permission.RECORD_AUDIO")
			print("Android Audio permission granted ", granted)

		var err = AudioServer.set_input_device_active(true)
		if err != OK:
			print("Mic input err: ", err)
			miconbutton.set_pressed_no_signal(false)
	else:
		AudioServer.set_input_device_active(false)

func _on_optioninputdevice(index: int) -> void:
	var micwason = miconbutton.button_down
	if micwason:
		miconbutton.set_pressed(false)
	var input_device: String = optioninputdevice.get_item_text(index)
	print("Set input device: ", input_device)
	AudioServer.set_input_device(input_device)
	if micwason:
		miconbutton.set_pressed(true)

func _on_vox_toggled(toggled_on):
	pttbutton.toggle_mode = toggled_on
	pttbutton.set_pressed(false)

func init_voip_mic(p_encode_base64: bool,
				   p_miconbutton: Button, 
				   p_optioninputdevice: OptionButton, 
				   p_pttbutton: Button,
				   p_voxbutton: Button, 
				   p_audiosampleframematerial: Material):
	encode_base64 = p_encode_base64
	miconbutton = p_miconbutton
	if miconbutton == null:
		miconbutton = Button.new()
		miconbutton.toggle_mode = true
		miconbutton.button_pressed = true
	assert(miconbutton.toggle_mode, "MicOn must be a toggle button")
	miconbutton.connect("toggled", _on_miconbutton)
	_on_miconbutton(miconbutton.button_pressed)

	pttbutton = (p_pttbutton if p_pttbutton else Button.new())

	voxbutton = p_voxbutton
	if voxbutton == null:
		voxbutton = Button.new()
		voxbutton.toggle_mode = true
		voxbutton.button_pressed = true
	assert(voxbutton.toggle_mode, "Vox must be a toggle button")
	voxbutton.connect("toggled", _on_vox_toggled)
	_on_vox_toggled(voxbutton.button_pressed)

	audiosampleframematerial = p_audiosampleframematerial
	
	optioninputdevice = p_optioninputdevice if p_optioninputdevice else OptionButton.new()
	assert(optioninputdevice.item_count == 0)
	for d in AudioServer.get_input_device_list():
		optioninputdevice.add_item(d)
	assert(optioninputdevice.get_item_text(optioninputdevice.selected) == "Default")
	optioninputdevice.connect("item_selected", _on_optioninputdevice)

	set_process(true)

func set_encode_base64(p_encode_base64: bool):
	assert(not currentlytalking, "Audio encoding cannot change during a talk episode")
	encode_base64 = p_encode_base64

func processtalkstreamends(talking: bool):
	if talking and not currentlytalking:
		if input_chunk_number < 0:
			return
		var available_chunks_back = min(input_chunk_number, input_chunk_first_frame_times_usec.size() - 1)
		var leadchunks = min(int(lead_time/frametimesecs), available_chunks_back)
		talkingtimestart = Time.get_ticks_msec()*0.001 - leadchunks*frametimesecs
		talking_first_frame_time_usec = get_input_chunk_first_frame_time_usec(leadchunks)
		hangchunks = int(hang_time/frametimesecs)
		var audiostreampacketheader := TwoVoipPacket.make_header(
				TwoVoipPacket.TYPE_START, opus_chunk_size, opussamplerate,
				opuschannels, len(chunkprefix), opusstreamcount, 0,
				talking_first_frame_time_usec, opusencoder.get_bitrate(), encode_base64,
				leadchunks)
		transmit_audio_packet.emit(TwoVoipPacket.encode_control_packet(audiostreampacketheader))
		
		sentsumsquares = 0.0
		sent_audio_reference = null
		if check_unpack_hash_codes:
			sent_audio_reference = AudioStreamPlaybackOpus.new()
			sent_audio_reference.initialize(opussamplerate, opuschannels, opus_chunk_size)

		opusencoder.reset()
		opusframecount = 0
		frame0usec = talking_first_frame_time_usec
		currentlytalking = true
		audio_chunk = null

		for i in range(leadchunks + 1):
			processopuschunk(leadchunks - i)

	elif not talking and currentlytalking:
		currentlytalking = false
		var talkingtimeend = Time.get_ticks_msec()*0.001
		var talkingtimeduration = talkingtimeend - talkingtimestart
		var sentrms = sqrt(sentsumsquares/(opusframecount*opus_chunk_size)) if opusframecount > 0 else 0.0
		var audiopacketstreamfooter := TwoVoipPacket.make_footer(
				opusstreamcount, opusframecount, talkingtimeduration, talkingtimeend, sentrms)
		var chunk_time: float = talkingtimeduration / opusframecount if opusframecount > 0 else 0.0
		print("TwoVoIP mic END stream=%d frames=%d duration=%.3f s chunk=%.4f s" % [
				opusstreamcount, opusframecount, talkingtimeduration, chunk_time])
		transmit_audio_packet.emit(TwoVoipPacket.encode_control_packet(audiopacketstreamfooter))
		opusstreamcount += 1
		sent_audio_reference = null

func get_next_frame_time_usec() -> int:
	return frame0usec + opusframecount * opusframedurationms * 1000

func make_audio_packet_midstream_update() -> PackedByteArray:
	var audiostreampacketmid := TwoVoipPacket.make_mid(
			opusstreamcount, opusframecount, get_next_frame_time_usec(),
			opusencoder.get_bitrate())
	return TwoVoipPacket.encode_control_packet(audiostreampacketmid)

func notify_audio_input_gap(missing_frame_count: int, next_frame_time_usec: int):
	assert(currentlytalking)
	assert(missing_frame_count > 0)
	opusframecount += missing_frame_count
	var mid := TwoVoipPacket.make_mid(opusstreamcount, opusframecount, next_frame_time_usec, opusencoder.get_bitrate())
	transmit_audio_packet.emit(TwoVoipPacket.encode_control_packet(mid))

func request_audio_packet_midstream() -> Array[PackedByteArray]:
	if not currentlytalking:
		return []
	var audiostreampacketheader := TwoVoipPacket.make_header(
			TwoVoipPacket.TYPE_START, opus_chunk_size, opussamplerate,
			opuschannels, len(chunkprefix), opusstreamcount, opusframecount,
			get_next_frame_time_usec(), opusencoder.get_bitrate(), encode_base64)
	return [TwoVoipPacket.encode_control_packet(audiostreampacketheader)]

func set_vox_threshhold(p_vox_threshhold):
	vox_threshhold = p_vox_threshhold
	if audiosampleframematerial:
		audiosampleframematerial.set_shader_parameter("voxthreshhold", vox_threshhold)

func set_gain(gain):
	conditioner.set_gain(gain)

func get_gain():
	return conditioner.get_gain()

func processvox(chunkmax, speechnoiseprobability, resampled_chunk):
	if audiosampleframematerial:
		audiosampleframematerial.set_shader_parameter("speechnoiseprobability", speechnoiseprobability)
		audiosampleframematerial.set_shader_parameter("chunkmax", chunkmax)

	if chunkmax >= vox_threshhold:
		if voxbutton.button_pressed and not pttbutton.button_pressed:
			pttbutton.button_pressed = true
		hangchunkscountup = 0
		if chunkmax > chunkmaxpersist:
			chunkmaxpersist = chunkmax
			if audiosampleframematerial:
				audiosampleframematerial.set_shader_parameter("chunkmaxpersist", chunkmaxpersist)
	else:
		if hangchunkscountup == hangchunks:
			if voxbutton.button_pressed:
				pttbutton.button_pressed = false
			chunkmaxpersist = 0.0
			if audiosampleframematerial:
				audiosampleframematerial.set_shader_parameter("chunkmaxpersist", chunkmaxpersist)
		hangchunkscountup += 1

	if audiosampleframematerial:
		if pttbutton.button_pressed:
			audiosampleframematerial.set_shader_parameter("chunktexenabled", true)
			assert (len(resampled_chunk) == opus_chunk_size)
			audiosampleframetextureimage.set_data(opus_chunk_size, 1, false, Image.FORMAT_RGF, resampled_chunk.to_byte_array())
			audiosampleframetexture.update(audiosampleframetextureimage)
		else:
			audiosampleframematerial.set_shader_parameter("chunktexenabled", false)

func get_input_chunk_first_frame_time_usec(chunks_back: int) -> int:
	if chunks_back < 0 or chunks_back > min(input_chunk_number, input_chunk_first_frame_times_usec.size() - 1):
		return 0
	return input_chunk_first_frame_times_usec[(input_chunk_number - chunks_back) % input_chunk_first_frame_times_usec.size()]

func get_conditioned_chunk(chunks_back: int) -> PackedVector2Array:
	if chunks_back < 0 or chunks_back > min(input_chunk_number, conditioned_chunk_history.size() - 1):
		return PackedVector2Array()
	return conditioned_chunk_history[(input_chunk_number - chunks_back) % conditioned_chunk_history.size()]

func store_conditioned_chunk(chunk: PackedVector2Array, first_frame_time_usec: int) -> void:
	input_chunk_number += 1
	var history_index := input_chunk_number % conditioned_chunk_history.size()
	conditioned_chunk_history[history_index] = chunk
	input_chunk_first_frame_times_usec[history_index] = first_frame_time_usec

func chunk_sum_squares(chunk: PackedVector2Array) -> float:
	var sum_squares := 0.0
	for frame in chunk:
		sum_squares += frame.length_squared()
	return sum_squares / opuschannels

func plan_audio_input_gap(frameCusec: int) -> Dictionary:
	if not currentlytalking:
		return {}
	if frameCusec == 0 or frame0usec == 0:
		push_error("Cannot detect an audio input gap without valid frame times")
		return {}
	var frame_duration_usec: int = opusframedurationms * 1000
	var frameCusec_predicted: int = frame0usec + opusframecount * frame_duration_usec
	var gap_usec: int = frameCusec - frameCusec_predicted
	if gap_usec >= input_gap_threshold*1000000.0:
		var missing_frame_count := ceili(float(gap_usec) / frame_duration_usec)
		if missing_frame_count <= 0:
			return {}
		var next_frame_time_usec: int = frameCusec_predicted + missing_frame_count * frame_duration_usec
		var discard_input_frames: int = ceili(maxi(0, next_frame_time_usec - frameCusec) * input_mix_rate / 1000000.0)
		return {
			"gap_usec": gap_usec,
			"missing_frame_count": missing_frame_count,
			"next_frame_time_usec": next_frame_time_usec,
			"discard_input_frames": discard_input_frames,
			"end_episode": gap_usec > hang_time * 1000000.0,
		}
	elif gap_usec <= -input_gap_threshold*1000000.0:
		push_error("impossible big negative gap in the audio stream timing %f" % (gap_usec/1000000.0))
	return {}

func apply_audio_input_gap(gap_plan: Dictionary):
	if gap_plan.is_empty():
		return
	var missing_frame_count: int = gap_plan.missing_frame_count
	var next_frame_time_usec: int = gap_plan.next_frame_time_usec
	if gap_plan.end_episode:
		print("TwoVoIP mic input gap %.3f ms exceeded %.3f ms hang: end episode" % [
				gap_plan.gap_usec / 1000.0, hang_time * 1000.0])
		processtalkstreamends(false)
		if voxbutton != null and voxbutton.button_pressed:
			pttbutton.button_pressed = false
			hangchunkscountup = hangchunks + 1
		return
	print("TwoVoIP mic input gap %.3f ms: insert %d chunks, discard %d input frames" % [
			gap_plan.gap_usec / 1000.0, missing_frame_count,
			gap_plan.discard_input_frames])
	var stored_silent_chunks = min(missing_frame_count, conditioned_chunk_history.size())
	var silent_chunk := PackedVector2Array()
	silent_chunk.resize(opus_chunk_size)
	for chunk in range(stored_silent_chunks):
		store_conditioned_chunk(silent_chunk, next_frame_time_usec \
				- (stored_silent_chunks - chunk) * opusframedurationms * 1000)
	notify_audio_input_gap(missing_frame_count, next_frame_time_usec)

func detect_audio_input_gap(frameCusec: int):
	# Kept as a direct diagnostic/test entry point. Live capture plans first so
	# it can discard the fractional prefix before retaining more microphone data.
	apply_audio_input_gap(plan_audio_input_gap(frameCusec))

func processopuschunk(chunks_back):
	assert(currentlytalking)
	if len(chunkprefix) >= TwoVoipPacket.CHUNK_SEQUENCE_PREFIX_SIZE:
		TwoVoipPacket.set_sequence_chunk_prefix(chunkprefix, opusframecount, opusstreamcount)
	else:
		assert (len(chunkprefix) == 0)
	var conditioned_chunk := get_conditioned_chunk(chunks_back)
	assert(conditioned_chunk.size() == opus_chunk_size)
	audio_chunk = conditioned_chunk
	var opuspacket : PackedByteArray = opusencoder.encode_chunk(conditioned_chunk, chunkprefix)
	assert(not opuspacket.is_empty())
	transmit_audio_packet.emit(TwoVoipPacket.encode_audio_packet(opuspacket, encode_base64))
	opusframecount += 1
	if sent_audio_reference:
		if sent_audio_reference.push_opus_packet(opuspacket, len(chunkprefix), 0) > 0:
			sentsumsquares += sent_audio_reference.get_tail_sum_squares(opus_chunk_size)
		if (opusframecount % chunks_per_hash) == 0 and check_unpack_hash_codes:
			recent_hash_code = sent_audio_reference.get_frame_hash((opusframecount - chunks_per_hash)*opus_chunk_size, chunks_per_hash*opus_chunk_size)
			var hashrequest = TwoVoipPacket.make_hash_request(opusstreamcount, (opusframecount - chunks_per_hash)*opus_chunk_size, chunks_per_hash*opus_chunk_size)
			transmit_audio_packet.emit(TwoVoipPacket.encode_control_packet(hashrequest))
	else:
		sentsumsquares += chunk_sum_squares(conditioned_chunk)

func receive_audio_hash_response(receiver_name: String, response: Array):
	#var stream_count = int(response[TwoVoipPacket.HashResponseField.OPUS_STREAM_COUNT])
	#var first_frame = int(response[TwoVoipPacket.HashResponseField.FIRST_FRAME])
	#var frame_count = int(response[TwoVoipPacket.HashResponseField.FRAME_COUNT])
	var received_hash = int(response[TwoVoipPacket.HashResponseField.HASH])
	if received_hash != recent_hash_code:
		print("Audio hash response from %s bad" % [receiver_name])
		get_node("../HBoxNetManage/HashErrors").value += 1
	recent_hash_code = 0

var raw_audio_chunk = null
var captured_audio_chunk = null
var audio_chunk = null
var last_chunkmax = 0.0
var speechnoiseprobability = 0.0
var chirpbuffer = null

var predicted_first_frame_time = 0.0
func _process(_delta):
	var resumed_this_process := consume_application_resume()
	# Spend one process pass rebuilding capture history after resume. This keeps
	# pre-suspend lead-time audio out of the new episode.
	processtalkstreamends(pttbutton.button_pressed and not resumed_this_process)

	while true:
		var input_frames_available := AudioServer.get_input_frames_available()
		var first_frame_time_usec := Time.get_ticks_usec() - roundi(input_frames_available * 1000000.0 / input_mix_rate)

		var gap_plan := plan_audio_input_gap(first_frame_time_usec)
		if not gap_plan.is_empty():
			print("**** gap plan")
			var discard_input_frames: int = 0 if gap_plan.end_episode else gap_plan.discard_input_frames
			if input_frames_available < discard_input_frames:
				break
			if discard_input_frames > 0:
				var discarded_audio := AudioServer.get_input_frames(discard_input_frames)
				if len(discarded_audio) != discard_input_frames:
					push_error("Could not discard the planned audio input alignment prefix")
					break
				first_frame_time_usec = gap_plan.next_frame_time_usec
			apply_audio_input_gap(gap_plan)
			input_frames_available -= discard_input_frames

		var required_input_frames: int = audio_chunk_size
		if input_frames_available < required_input_frames:
			break

		if predicted_first_frame_time == 0.0 or abs(predicted_first_frame_time - first_frame_time_usec) > input_gap_threshold*1000000.0:
			print("clear mastercaptyre ", first_frame_time_usec - predicted_first_frame_time)
			predicted_first_frame_time = first_frame_time_usec
			if mastercapture:
				mastercapture.clear_buffer()
				captureframeslip = 0

		raw_audio_chunk = AudioServer.get_input_frames(required_input_frames)
		if len(raw_audio_chunk) == 0:
			break
		predicted_first_frame_time += roundi(required_input_frames/input_mix_rate*1000000.0)

		audio_chunk = raw_audio_chunk
		captured_audio_chunk = PackedVector2Array()
		if echo_cancel_enabled and mastercapture:
			captured_audio_chunk = mastercapture.get_buffer(min(mastercapture.get_frames_available(), required_input_frames))
			if required_input_frames != captured_audio_chunk.size():
				captureframeslip += required_input_frames - captured_audio_chunk.size()
				print("captureframeslip ", captureframeslip)

		audio_chunk = conditioner.condition(raw_audio_chunk, captured_audio_chunk)

		if chirpbuffer != null and len(chirpbuffer) < 200:
			chirpbuffer.append(raw_audio_chunk)
			chirpbuffer.append(captured_audio_chunk)

		if audio_chunk.size() != opus_chunk_size:
			break
		store_conditioned_chunk(audio_chunk, first_frame_time_usec)
		speechnoiseprobability = 0.0
		if rootmeansquaremaxmeasurement:
			last_chunkmax = conditioner.get_rms()
		else:
			last_chunkmax = conditioner.get_peak()
		processvox(last_chunkmax, speechnoiseprobability, audio_chunk)
		if currentlytalking:
			processopuschunk(0)
	raw_audio_chunk = null
	captured_audio_chunk = null
	audio_chunk = null
