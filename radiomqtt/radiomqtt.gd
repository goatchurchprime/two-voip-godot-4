extends Control


@onready var speechbusidx = AudioServer.get_bus_index("SpeechBus")
@onready var SelfMember = $ScrollMembers/Members/Self

var audioeffectpitchshift : AudioEffectPitchShift = null
var audioeffectpitchshiftidx = 0

var resampledchunkprefix := TwoVoipPacket.make_sequence_chunk_prefix()
var audio_packets_base64 : bool = false

var recordedsamples = [ ]
var conditionedsamples = [ ]
var conditionedsamples_mixrate = 1
var recordedopuspackets = [ ]
var recordedresampledpackets = null
const maxrecordedsamples = 10*50
var recordedopuspacketsMemSize = 0
var recordedchunkmax = 0.0
var recordedheader: Array = []
var recordedfooter: Array = []

var audiosampleframetextureimage : Image
var audiosampleframetexture : ImageTexture

var prevviseme = 0
var visemes = [ "sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS", "nn", "RR", "aa", "E", "ih", "oh", "ou", "LA" ]

var possibleusernames = ["Alice", "Beth", "Cath", "Dan", "Earl", "Fred", "George", "Harry", "Ivan", "John", "Kevin", "Larry", "Martin", "Oliver", "Peter", "Quentin", "Robert", "Samuel", "Thomas", "Ulrik", "Victor", "Wayne", "Xavier", "Youngs", "Zephir"]


func _ready():
	print("AudioServer.get_mix_rate()=", AudioServer.get_mix_rate())
	print("ProjectSettings.get_setting_with_override(\"audio/driver/mix_rate\")=", ProjectSettings.get_setting_with_override("audio/driver/mix_rate"))

	for h in [ $VBoxFrameLength/HBoxOpusFrame/FrameDuration, $VBoxFrameLength/HBoxOpusFrame/SampleRate, $VBoxConditioning/HBoxConditioner/OptionChannels, $HBoxBigButtons/VBoxPTT/Denoise, $VBoxConditioning/HBoxConditioner/ConditionerOption, $VBoxConditioning/HBoxAudioFrame/WebRTCdenoiser ]:
		h.connect("item_selected", func (_item_selected): updatesamplerates())
	for h in [ $VBoxFrameLength/HBoxOpusExtra/ComplexitySpinBox, $VBoxFrameLength/HBoxOpusExtra/FecSpinBox, $VBoxFrameLength/HBoxOpusExtra/BitRate, $HBoxBigButtons/VBoxVox/Leadtime, $HBoxBigButtons/VBoxVox/Hangtime ]:
		h.connect("value_changed", func (_value): updatesamplerates())
	for h in [ $VBoxFrameLength/HBoxOpusExtra/OptimizeForVoice, $HBoxMosquitto/base64, $VBoxConditioning/HBoxAudioFrame/EchocancelEnabled, $VBoxConditioning/HBoxAudioFrame/AGCEnabled ]:
		h.connect("toggled", func (_toggled_on): updatesamplerates())

	audio_packets_base64 = $HBoxMosquitto/base64.button_pressed
	$TwoVoipMic.init_voip_mic(audio_packets_base64, $HBoxMicTalk/MicWorking, $HBoxInputDevice/OptionInputDevice, $HBoxBigButtons/VBoxPTT/PTT, $HBoxBigButtons/VBoxVox/Vox, $HBoxMicTalk/VoxThreshold.material)
	$TwoVoipMic.set_vox_threshhold(0.017)

	for d in AudioServer.get_output_device_list():
		$HBoxOutputDevice/OptionOutputDevice.add_item(d)
	assert($HBoxOutputDevice/OptionOutputDevice.get_item_text($HBoxOutputDevice/OptionOutputDevice.selected) == "Default")
	$HBoxOutputDevice/OptionOutputDevice.connect("item_selected", _on_optionoutputdevice)

	if not AudioServer.has_method("get_input_frames"):
		$GodotVersionWarning.visible = true
		print($GodotVersionWarning.text)

	if $VBoxFrameLength/HBoxOpusFrame/FrameDuration.selected == -1:
		$VBoxFrameLength/HBoxOpusFrame/FrameDuration.select(1)
	if $VBoxConditioning/HBoxConditioner/OptionChannels.selected == -1:
		$VBoxConditioning/HBoxConditioner/OptionChannels.select(1)
	if $VBoxFrameLength/HBoxOpusFrame/SampleRate.selected == -1:
		$VBoxFrameLength/HBoxOpusFrame/SampleRate.select(4)

	if speechbusidx != -1:
		for effect_idx in range(AudioServer.get_bus_effect_count(speechbusidx)):
			var laudioeffectonspeechbus : AudioEffect = AudioServer.get_bus_effect(speechbusidx, effect_idx)
			if laudioeffectonspeechbus.is_class("AudioEffectPitchShift"):
				audioeffectpitchshift = laudioeffectonspeechbus
				audioeffectpitchshiftidx = effect_idx
				break

	updatesamplerates()
	for i in range(1, len(visemes)):
		var d = $HBoxVisemes/ColorRect.duplicate()
		d.get_node("Label").text = visemes[i]
		$HBoxVisemes.add_child(d)
		d.size.y = i*8
	$HBoxMosquitto/FriendlyName.text = possibleusernames.pick_random()

	await get_tree().create_timer(0.1).timeout
	$HBoxMicTalk/MicWorking.set_pressed(true)

	$TwoVoipMic.connect("transmit_audio_packet", on_transmit_audio_packet)

	# handle lower resolution screens
	var window_size = get_node("/root").size
	var screen_size = DisplayServer.screen_get_size()
	if window_size.y > screen_size.y - 100:
		var rat = screen_size.y*0.9/window_size.y
		get_node("/root").set_size(window_size*rat)
		var window_position = DisplayServer.window_get_position()
		if window_position.y == 0:
			window_position.y = 30
			DisplayServer.window_set_position(window_position)


func _on_optionoutputdevice(index: int) -> void:
	var output_device: String = $HBoxOutputDevice/OptionOutputDevice.get_item_text(index)
	print("Set input device: ", output_device)
	AudioServer.set_input_device(output_device)

func rechunkrecordedchunks(orgsamples, newsamplesize):
	assert (newsamplesize > 0)
	var res = [ ]
	var currentsample = PackedVector2Array()
	while len(orgsamples) != 0:
		var s = orgsamples.pop_front()
		if len(currentsample) + len(s) >= newsamplesize:
			res.append(currentsample + s.slice(0, newsamplesize - len(currentsample)))
			currentsample = s.slice(newsamplesize - len(currentsample))
		else:
			currentsample.append_array(s)
		while len(currentsample) >= newsamplesize:
			res.append(currentsample.slice(0, newsamplesize))
			currentsample = currentsample.slice(newsamplesize)
	return res

var previous_ptt := false

func updatesamplerates():
	$TwoVoipMic.processtalkstreamends(false)
	audio_packets_base64 = $HBoxMosquitto/base64.button_pressed
	$TwoVoipMic.set_encode_base64(audio_packets_base64)
	$VBoxConditioning/HBoxConditioner/MicSampleRate.value = AudioServer.get_input_mix_rate()
	var conditioner_backend = $VBoxConditioning/HBoxConditioner/ConditionerOption.selected
	var frametimems = float($VBoxFrameLength/HBoxOpusFrame/FrameDuration.text)
	var opussamplerate = int($VBoxFrameLength/HBoxOpusFrame/SampleRate.text)*1000
	var denoiser_mode = $VBoxConditioning/HBoxAudioFrame/WebRTCdenoiser.selected
	var agc_enabled = $VBoxConditioning/HBoxAudioFrame/AGCEnabled.button_pressed
	var echo_cancel_enabled = $VBoxConditioning/HBoxAudioFrame/EchocancelEnabled.button_pressed
	var channels = int($VBoxConditioning/HBoxConditioner/OptionChannels.text)

	$TwoVoipMic.set_opus_values(opussamplerate, frametimems, channels,
			int($VBoxFrameLength/HBoxOpusExtra/BitRate.value), 
			int($VBoxFrameLength/HBoxOpusExtra/ComplexitySpinBox.value),
			$VBoxFrameLength/HBoxOpusExtra/OptimizeForVoice.button_pressed,
			int($VBoxFrameLength/HBoxOpusExtra/FecSpinBox.value),
			conditioner_backend, echo_cancel_enabled, denoiser_mode, agc_enabled)
	$TwoVoipMic.set_gain($VBoxConditioning/HBoxEchoCancel/GainManualSpinBox.value)
	$VBoxConditioning/HBoxAudioFrame/EchocancelEnabled.disabled = not (conditioner_backend == $TwoVoipMic.ConditionerBackend.WEBRTC)

	$TwoVoipMic.lead_time = $HBoxBigButtons/VBoxVox/Leadtime.value
	$TwoVoipMic.hang_time = $HBoxBigButtons/VBoxVox/Hangtime.value
	reprocessoriginalchunks()

func reprocessoriginalchunks():
	var opussamplerate = int($VBoxFrameLength/HBoxOpusFrame/SampleRate.text)*1000
	var opuschannels = int($VBoxConditioning/HBoxConditioner/OptionChannels.text)

	var conditioner_forreprocessing := TwoVoipConditioner.new()
	conditioner_forreprocessing.initialize($TwoVoipMic.opusframedurationms, conditionedsamples_mixrate, opussamplerate)

	var opusencoder_forreprocessing := TwoVoipOpusEncoder.new()
	opusencoder_forreprocessing.initialize(opussamplerate, opuschannels, $TwoVoipMic.opus_chunk_size)
	#opusencoder_forreprocessing.set_gain($VBoxFrameLength/HBoxOpusFrame/GainManualSpinBox.value )

	opusencoder_forreprocessing.set_bitrate(int($VBoxFrameLength/HBoxOpusExtra/BitRate.value))
	opusencoder_forreprocessing.set_complexity(int($VBoxFrameLength/HBoxOpusExtra/ComplexitySpinBox.value))
	opusencoder_forreprocessing.set_inband_perc(int($VBoxFrameLength/HBoxOpusExtra/FecSpinBox.value))
	opusencoder_forreprocessing.set_signal_type(TwoVoipOpusEncoder.SIGNAL_VOICE if $VBoxFrameLength/HBoxOpusExtra/OptimizeForVoice.button_pressed else TwoVoipOpusEncoder.SIGNAL_MUSIC)

	var recorded_stream_count := 0
	var recorded_first_frame_time_usec := 0
	if TwoVoipPacket.header_is_valid(recordedheader):
		recorded_stream_count = int(recordedheader[TwoVoipPacket.HeaderField.OPUS_STREAM_COUNT])
		recorded_first_frame_time_usec = int(recordedheader[TwoVoipPacket.HeaderField.NEXT_FRAME_TIME_USEC])
	recordedheader = TwoVoipPacket.make_header(
			TwoVoipPacket.TYPE_START, $TwoVoipMic.opus_chunk_size,
			opussamplerate, opuschannels, resampledchunkprefix.size(),
			recorded_stream_count, 0, recorded_first_frame_time_usec,
			opusencoder_forreprocessing.get_bitrate(), audio_packets_base64)
	if not TwoVoipPacket.footer_is_valid(recordedfooter):
		recordedfooter = TwoVoipPacket.make_footer(int(recordedheader[TwoVoipPacket.HeaderField.OPUS_STREAM_COUNT]), 0, 0.0, 0.0)

	var frametimems = float($VBoxFrameLength/HBoxOpusFrame/FrameDuration.text)
	var audioresamplerate = int($VBoxFrameLength/HBoxOpusFrame/SampleRate.text)*1000
	var audioresamplesize = int(audioresamplerate*frametimems/1000.0)
	$VBoxFrameLength/HBoxOpusFrame/LabResampleFrameLength.text = "%d frames" % audioresamplesize

	if len(conditionedsamples) != 0 and len(conditionedsamples[0]) != conditioner_forreprocessing.get_input_chunk_size():
		conditionedsamples = rechunkrecordedchunks(conditionedsamples, conditioner_forreprocessing.get_input_chunk_size())
	recordedopuspacketsMemSize = 0
	recordedchunkmax = 0.0
	recordedopuspackets = null
	recordedresampledpackets = null

	recordedopuspackets = [ ]
	#opusencoder_forreprocessing.resetencoder(true)
	var resampledopusframecount = 0
	for i in range(len(conditionedsamples)):
		var s = conditionedsamples[i]
		s = conditioner_forreprocessing.condition(s, PackedVector2Array())
		TwoVoipPacket.set_sequence_chunk_prefix(resampledchunkprefix, resampledopusframecount, int(recordedheader[TwoVoipPacket.HeaderField.OPUS_STREAM_COUNT]))
		var opuspacket : PackedByteArray = opusencoder_forreprocessing.encode_chunk(s, resampledchunkprefix)
		opuspacket = TwoVoipPacket.encode_audio_packet(opuspacket, audio_packets_base64)
		recordedopuspackets.append(opuspacket)
		resampledopusframecount += 1
		recordedopuspacketsMemSize += opuspacket.size() 
	recordedfooter[TwoVoipPacket.FooterField.OPUS_FRAME_COUNT] = resampledopusframecount
	$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = str(len(recordedopuspackets))
	$VBoxPlayback/HBoxPlaycount/GridContainer/Totalbytes.text = str(recordedopuspacketsMemSize)
	var tm = len(conditionedsamples)*frametimems*0.001
	$VBoxPlayback/HBoxPlaycount/GridContainer/TimeSecs.text = str(tm)
	$VBoxPlayback/HBoxPlaycount/GridContainer/Bytespersec.text = str(int(recordedopuspacketsMemSize/tm if tm else 0))
	$VBoxPlayback/HBoxStream/ChunkMax.text = str(recordedchunkmax)

func recordoriginalchunks(audiosamples, audiochunk, chunkmax, opuspacket):
	if audiosamples != null:
		recordedsamples.append(audiosamples)
	assert(audiochunk != null)
	conditionedsamples.append(audiochunk)
	recordedopuspackets.append(opuspacket)
	$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = str(len(recordedopuspackets))
	recordedopuspacketsMemSize += opuspacket.size()
	$VBoxPlayback/HBoxPlaycount/GridContainer/Totalbytes.text = str(recordedopuspacketsMemSize)
	var tm = len(recordedopuspackets)*$TwoVoipMic.audio_chunk_size*1.0/AudioServer.get_input_mix_rate()
	$VBoxPlayback/HBoxPlaycount/GridContainer/TimeSecs.text = str(tm)
	$VBoxPlayback/HBoxPlaycount/GridContainer/Bytespersec.text = str(int(recordedopuspacketsMemSize/tm))
	recordedchunkmax = max(recordedchunkmax, chunkmax)
	$VBoxPlayback/HBoxStream/ChunkMax.text = str(recordedchunkmax)

func on_transmit_audio_packet(opuspacket : PackedByteArray):
	if TwoVoipPacket.is_control_packet(opuspacket):
		intercept_transmit_audio_control_packet(TwoVoipPacket.decode_control_packet(opuspacket))
	elif len(recordedsamples) < maxrecordedsamples:
		recordoriginalchunks($TwoVoipMic.raw_audio_chunk, $TwoVoipMic.audio_chunk, $TwoVoipMic.last_chunkmax, opuspacket)
	$MQTTnetwork.transportaudiopacket(opuspacket, max(0, $HBoxLogging/TransmissionNoise.selected))

func hash_key(stream_count: int, first_frame: int, frame_count: int) -> String:
	return "%d:%d:%d" % [stream_count, first_frame, frame_count]

func intercept_transmit_audio_control_packet(control_packet: Array):
	print(control_packet)
	if control_packet.is_empty():
		return

	if control_packet[0] == TwoVoipPacket.TYPE_START:
		assert(TwoVoipPacket.header_is_valid(control_packet))
		recordedsamples = [ ]
		conditionedsamples = [ ]
		conditionedsamples_mixrate = $TwoVoipMic.opussamplerate
		recordedopuspackets = [ ]
		recordedresampledpackets = [ ]

		$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = str(0)
		$VBoxPlayback/HBoxPlaycount/GridContainer/TimeSecs.text = str(0)
		recordedopuspacketsMemSize = 0
		recordedchunkmax = 0.0
		$VBoxPlayback/HBoxPlaycount/GridContainer/Totalbytes.text = str(0)
		$VBoxPlayback/HBoxPlaycount/GridContainer/Bytespersec.text = str(0)
		recordedheader = control_packet.duplicate()
		recordedfooter = [ ]
	
	elif control_packet[0] == TwoVoipPacket.TYPE_END:
		assert(TwoVoipPacket.footer_is_valid(control_packet))
		recordedfooter = control_packet.duplicate()

func _on_vox_threshold_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		$TwoVoipMic.set_vox_threshhold(event.position.x/$HBoxMicTalk/VoxThreshold.size.x)

func _on_play_pressed():
	$VBoxConditioning/HBoxEchoCancel/VoiceEcho.button_pressed = false
	if false and audioeffectpitchshift != null:
		var speedup = $VBoxPlayback/HBoxStream/StreamSpeedup.value
		AudioServer.set_bus_effect_enabled(speechbusidx, audioeffectpitchshiftidx, (speedup != 1.0))
		SelfMember.get_node("AudioStreamPlayer").pitch_scale = speedup
		audioeffectpitchshift.pitch_scale = 1.0/speedup

	if TwoVoipPacket.header_is_valid(recordedheader) and TwoVoipPacket.footer_is_valid(recordedfooter):
		SelfMember.twovoipspeaker.replayrecording($VBoxPlayback/HBoxStream/StreamSpeedup.value, recordedheader, recordedopuspackets, recordedfooter, $VBoxPlayback/HBoxStream/PacketDropOption.selected)


var saveplaybackfile = "user://savedplayback.dat"
func _on_sav_options_item_selected(index):
	if index == 1:
		var f = FileAccess.open(saveplaybackfile, FileAccess.WRITE)
		prints("Saving to file:", f.get_path_absolute())
		f.store_var({"audiosamplerate":$TwoVoipMic.audioopuschunkedeffect.audiosamplerate,
					 "recordedsamples":recordedsamples})
		f.close()
	elif index == 2:
		var f = FileAccess.open(saveplaybackfile, FileAccess.READ)
		prints("Loading from file:", f.get_path_absolute())
		var dat = f.get_var()
		if $TwoVoipMic.audioopuschunkedeffect.audiosamplerate != dat["audiosamplerate"]:
			prints(" sample rates disagree!!", dat["audiosamplerate"], $TwoVoipMic.audioopuschunkedeffect.audiosamplerate)
		recordedsamples = dat["recordedsamples"]
		f.close()
	$VBoxPlayback/HBoxPlaycount/VBoxExpt/SavOptions.select(0)

func _process(delta):
	var ptt = $HBoxBigButtons/VBoxPTT/PTT.button_pressed
	previous_ptt = ptt

func _on_gain_manual_spin_box_value_changed(value):
	$TwoVoipMic.set_gain(value)
	reprocessoriginalchunks()

func _on_hash_check_button_toggled(toggled_on):
	$TwoVoipMic.check_unpack_hash_codes = toggled_on

func _on_pause_check_toggled(toggled_on):
	get_tree().paused = toggled_on
	if toggled_on:
		await get_tree().create_timer(0.4).timeout
		$HBoxNetManage/PauseCheck.button_pressed = false

func _on_stall_in_1_toggled(toggled_on):
	$MQTTnetwork/MQTT.set_process(not toggled_on)
	if $MQTTnetwork/MQTTSimulatedBroker._server:
		$MQTTnetwork/MQTTSimulatedBroker.set_process(not toggled_on)
	if toggled_on:
		await get_tree().create_timer(0.3).timeout
		$HBoxNetManage/StallIn1.button_pressed = false

func _on_stall_in_5_toggled(toggled_on):
	$MQTTnetwork/MQTT.set_process(not toggled_on)
	if toggled_on:
		await get_tree().create_timer(5.0).timeout
		$HBoxNetManage/StallIn5.button_pressed = false


func _on_bad_order_toggled(toggled_on):
	$MQTTnetwork/AudioPacketFilter.set_random_delay(
			toggled_on, _selected_fault_packet_kind())
	if toggled_on:
		await get_tree().create_timer(1.0).timeout
		$HBoxNetManage/BadOrder.button_pressed = false

func _on_drop_packets_pressed():
	var packet_kind := _selected_fault_packet_kind()
	var count := int($HBoxNetManage/FaultRunLength.value) \
			if packet_kind == "audio" else 1
	$MQTTnetwork/AudioPacketFilter.drop_next(packet_kind, count)


func _selected_fault_packet_kind() -> String:
	return $HBoxNetManage/FaultPacketKind.get_item_text(
			$HBoxNetManage/FaultPacketKind.selected).to_lower()

func _on_voice_echo_toggled(toggled_on):
	$VBoxConditioning/HBoxEchoCancel/AudioStreamVoiceEcho.playing = toggled_on

var chirpdata = null
var leafvals = [ -1, -1 ]
var echoframedelay = 0
var conditioner_delay_frames = 0
func findchirp(leafoffset, chirpdata, chirpbuffer, twovoipmic):
	var best_score := -1.0
	var best_frame := -1
	var frame = 0
	var chunk = leafoffset
	var chunkframe = 0
	while true:
		var score:= 0.0
		var lchunk = chunk
		var lchunkframe = chunkframe
		for j in range(len(chirpdata)):
			var s = chirpbuffer[lchunk][lchunkframe]
			score += chirpdata[j].x*(s.x + s.y)
			lchunkframe += 1
			if lchunkframe >= len(chirpbuffer[lchunk]):
				lchunk += 2
				if lchunk >= len(chirpbuffer):
					lchunk = -1
					break
				lchunkframe = 0
		if lchunk == -1:
			break
		if absf(score) > best_score:
			best_score = absf(score)
			best_frame = frame
		frame += 1
		chunkframe += 1
		if chunkframe >= len(chirpbuffer[chunk]):
			chunk += 2
			if chunk >= len(chirpbuffer):
				break
			chunkframe = 0
	print(leafoffset, "  frame ", best_frame, " score: ", best_score)
	leafvals[leafoffset] = best_frame
	if leafvals[1-leafoffset] != -1:
		echoframedelay = leafvals[0] - leafvals[1]
		twovoipmic.echoframedelay = leafvals[0] - leafvals[1]
		prints(" -- echoframedelay ", echoframedelay, " echoest ", conditioner_delay_frames)
	return best_frame


func _on_chirp_button_pressed():
	$VBoxConditioning/HBoxEchoCancel/AudioStreamChirp.play()
	$TwoVoipMic.chirpbuffer = [ ]
	await get_tree().create_timer(0.5).timeout
	var chirpbuffer = $TwoVoipMic.chirpbuffer
	var lcaptureframeslip = $TwoVoipMic.captureframeslip
	$TwoVoipMic.chirpbuffer = null
	print("chirpbuffer ", len(chirpbuffer))
	if chirpdata == null:
		var d :PackedByteArray = $VBoxConditioning/HBoxEchoCancel/AudioStreamChirp.stream.get_data()
		chirpdata = PackedVector2Array()
		chirpdata.resize(len(d)/4)
		for i in range(len(chirpdata)):
			chirpdata[i] = Vector2(d.decode_s16(i*4)/32768.0, d.decode_s16(i*4+2)/32768.0)
	leafvals = [ -1, -1 ]
	if $TwoVoipMic.conditioner.has_method("get_stream_delay_ms"):
		conditioner_delay_frames = roundi($TwoVoipMic.conditioner.get_stream_delay_ms()/1000.0*AudioServer.get_input_mix_rate())
	WorkerThreadPool.add_group_task(findchirp.bind(chirpdata, chirpbuffer, $TwoVoipMic), 2)
	#WorkerThreadPool.add_group_task(findchirp.bind(chirpdata, chirpbuffer), 1))
	
