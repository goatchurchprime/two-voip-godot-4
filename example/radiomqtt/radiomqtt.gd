extends Control


@onready var speechbusidx = AudioServer.get_bus_index("SpeechBus")
@onready var SelfMember = $Members/Self

var audioeffectpitchshift : AudioEffectPitchShift = null
var audioeffectpitchshiftidx = 0
var opusencoder_forreprocessing : TwovoipOpusEncoder = TwovoipOpusEncoder.new()

var resampledchunkprefix = PackedByteArray([2,3])
var mqttpacketencodebase64 : bool = false

var recordedsamples = [ ]
var recordedopuspackets = [ ]
var recordedresampledpackets = null
const maxrecordedsamples = 10*50
var recordedopuspacketsMemSize = 0
var recordedchunkmax = 0.0
var recordedheader = { }
var recordedfooter = { }

var audiosampleframetextureimage : Image
var audiosampleframetexture : ImageTexture

var prevviseme = 0
var visemes = [ "sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS", "nn", "RR", "aa", "E", "ih", "oh", "ou", "LA" ]

var possibleusernames = ["Alice", "Beth", "Cath", "Dan", "Earl", "Fred", "George", "Harry", "Ivan", "John", "Kevin", "Larry", "Martin", "Oliver", "Peter", "Quentin", "Robert", "Samuel", "Thomas", "Ulrik", "Victor", "Wayne", "Xavier", "Youngs", "Zephir"]


func _ready():
	print("AudioServer.get_mix_rate()=", AudioServer.get_mix_rate())
	print("ProjectSettings.get_setting_with_override(\"audio/driver/mix_rate\")=", ProjectSettings.get_setting_with_override("audio/driver/mix_rate"))

	for h in [ $VBoxFrameLength/HBoxOpusFrame/FrameDuration, $VBoxFrameLength/HBoxAudioFrame/SampleRate, $VBoxFrameLength/HBoxOpusFrame/OptionChannels, $HBoxBigButtons/VBoxPTT/Denoise ]:
		h.connect("item_selected", func (_item_selected): updatesamplerates())
	for h in [ $VBoxFrameLength/HBoxOpusExtra/ComplexitySpinBox, $VBoxFrameLength/HBoxOpusExtra/BitRate, $HBoxBigButtons/VBoxVox/Leadtime, $HBoxBigButtons/VBoxVox/Hangtime ]:
		h.connect("value_changed", func (_value): updatesamplerates())
	for h in [ $VBoxFrameLength/HBoxOpusExtra/OptimizeForVoice, $HBoxMosquitto/base64, $VBoxFrameLength/HBoxOpusFrame/AutoGainControl ]:
		h.connect("toggled", func (_toggled_on): updatesamplerates())

	$TwoVoipMic.init_voip_mic(false, $HBoxMicTalk/MicWorking, $HBoxInputDevice/OptionInputDevice, $HBoxBigButtons/VBoxPTT/PTT, $HBoxBigButtons/VBoxVox/Vox, $HBoxMicTalk/VoxThreshold.material)
	$TwoVoipMic.set_vox_threshhold(0.017)

	for d in AudioServer.get_output_device_list():
		$HBoxOutputDevice/OptionOutputDevice.add_item(d)
	assert($HBoxOutputDevice/OptionOutputDevice.get_item_text($HBoxOutputDevice/OptionOutputDevice.selected) == "Default")
	$HBoxOutputDevice/OptionOutputDevice.connect("item_selected", _on_optionoutputdevice)

	if not AudioServer.has_method("get_input_frames"):
		$GodotVersionWarning.visible = true
		print($GodotVersionWarning.text)

	if $VBoxFrameLength/HBoxOpusFrame/FrameDuration.selected == -1:
		$VBoxFrameLength/HBoxOpusFrame/FrameDuration.select(3)
	if $VBoxFrameLength/HBoxOpusFrame/OptionChannels.selected == -1:
		$VBoxFrameLength/HBoxOpusFrame/OptionChannels.select(0)
	if $VBoxFrameLength/HBoxAudioFrame/SampleRate.selected == -1:
		$VBoxFrameLength/HBoxAudioFrame/SampleRate.select(4)

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
	
	$TwoVoipMic.connect("transmit_audio_json_packet", on_transmit_audio_json_packet)
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

var last_agc_gain := 1.0
var previous_ptt := false

func updatesamplerates():
	$TwoVoipMic.processtalkstreamends(false)
	$VBoxFrameLength/HBoxAudioFrame/MicSampleRate.value = AudioServer.get_input_mix_rate()
	var frametimems = float($VBoxFrameLength/HBoxOpusFrame/FrameDuration.text)
	var opussamplerate = int($VBoxFrameLength/HBoxAudioFrame/SampleRate.text)*1000
	var denoiser_mode = $HBoxBigButtons/VBoxPTT/Denoise.selected
	var agc_mode = TwovoipOpusEncoder.AGC_APPLIED if $VBoxFrameLength/HBoxOpusFrame/AutoGainControl.button_pressed else TwovoipOpusEncoder.AGC_DISABLED

	$TwoVoipMic.set_opus_values(opussamplerate, frametimems, 
			int($VBoxFrameLength/HBoxOpusFrame/OptionChannels.text),
			int($VBoxFrameLength/HBoxOpusExtra/BitRate.value), 
			int($VBoxFrameLength/HBoxOpusExtra/ComplexitySpinBox.value),
			$VBoxFrameLength/HBoxOpusExtra/OptimizeForVoice.button_pressed,
			denoiser_mode, agc_mode)

	$HBoxBigButtons/VBoxPTT/Denoise.disabled = not (opussamplerate == 48000)
	$TwoVoipMic.lead_time = $HBoxBigButtons/VBoxVox/Leadtime.value
	$TwoVoipMic.hang_time = $HBoxBigButtons/VBoxVox/Hangtime.value
	reprocessoriginalchunks()

func reprocessoriginalchunks():
	var opussamplerate = int($VBoxFrameLength/HBoxAudioFrame/SampleRate.text)*1000
	var opuschannels = int($VBoxFrameLength/HBoxOpusFrame/OptionChannels.text)
	var denoiser = $HBoxBigButtons/VBoxPTT/Denoise.selected
	opusencoder_forreprocessing.create_sampler(AudioServer.get_input_mix_rate(), opussamplerate, opuschannels, denoiser, TwovoipOpusEncoder.AGC_DISABLED, $TwoVoipMic.opus_chunk_size)
	opusencoder_forreprocessing.set_gain($VBoxFrameLength/HBoxOpusFrame/GainManualSpinBox.value * last_agc_gain)
	opusencoder_forreprocessing.create_opus_encoder(int($VBoxFrameLength/HBoxOpusExtra/BitRate.value), int($VBoxFrameLength/HBoxOpusExtra/ComplexitySpinBox.value), $VBoxFrameLength/HBoxOpusExtra/OptimizeForVoice.button_pressed)
	opusencoder_forreprocessing.reset_opus_encoder()
	recordedheader["opusframesize"] = $TwoVoipMic.opus_chunk_size
	recordedheader["opussamplerate"] = opussamplerate
	recordedheader["opuschannels"] = opuschannels

	mqttpacketencodebase64 = $HBoxMosquitto/base64.button_pressed
	$VBoxFrameLength/HBoxAudioFrame/LabFrameLength.text = "%d frames" % $TwoVoipMic.audio_chunk_size

	var frametimems = float($VBoxFrameLength/HBoxOpusFrame/FrameDuration.text)
	var audioresamplerate = int($VBoxFrameLength/HBoxAudioFrame/SampleRate.text)*1000
	var audioresamplesize = int(audioresamplerate*frametimems/1000.0)
	$VBoxFrameLength/HBoxAudioFrame/LabResampleFrameLength.text = "%d frames" % audioresamplesize

	if len(recordedsamples) != 0 and len(recordedsamples[0]) != $TwoVoipMic.audio_chunk_size:
		recordedsamples = rechunkrecordedchunks(recordedsamples, $TwoVoipMic.audio_chunk_size)
	recordedopuspacketsMemSize = 0
	recordedchunkmax = 0.0
	recordedopuspackets = null
	recordedresampledpackets = null

	recordedopuspackets = [ ]
	#opusencoder_forreprocessing.resetencoder(true)
	var resampledopusframecount = 0
	for s in recordedsamples:
		if opusencoder_forreprocessing.process_chunk(s) < 0:
			break
		var chunkmax = opusencoder_forreprocessing.get_peak()
		recordedchunkmax = max(recordedchunkmax, chunkmax)
		resampledchunkprefix.set(0, (resampledopusframecount%256))  # 32768 frames is 10 minutes
		resampledchunkprefix.set(1, (int(resampledopusframecount/256)&127) + (recordedheader["opusstreamcount"]%2)*128)
		var opuspacket : PackedByteArray = opusencoder_forreprocessing.encode_chunk(resampledchunkprefix)
		recordedopuspackets.append(opuspacket)
		resampledopusframecount += 1
		recordedopuspacketsMemSize += opuspacket.size() 
	recordedfooter["opusframecount"] = resampledopusframecount
	$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = str(len(recordedopuspackets))
	$VBoxPlayback/HBoxPlaycount/GridContainer/Totalbytes.text = str(recordedopuspacketsMemSize)
	var tm = len(recordedsamples)*frametimems*0.001
	$VBoxPlayback/HBoxPlaycount/GridContainer/TimeSecs.text = str(tm)
	$VBoxPlayback/HBoxPlaycount/GridContainer/Bytespersec.text = str(int(recordedopuspacketsMemSize/tm if tm else 0))
	$VBoxPlayback/HBoxStream/ChunkMax.text = str(recordedchunkmax)

func recordoriginalchunks(audiosamples, chunkmax, opuspacket):
	recordedsamples.append(audiosamples)
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
	if len(recordedsamples) < maxrecordedsamples:
		recordoriginalchunks($TwoVoipMic.audio_chunk, $TwoVoipMic.last_chunkmax, opuspacket)
	$MQTTnetwork.transportaudiopacket(opuspacket, mqttpacketencodebase64, max(0, $HBoxLogging/TransmissionNoise.selected))

func on_transmit_audio_json_packet(audiostreampacketheader):
	print(audiostreampacketheader)

	if audiostreampacketheader.has("talkingtimestart"):
		recordedsamples = [ ]
		recordedopuspackets = [ ]
		recordedresampledpackets = [ ]

		$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = str(0)
		$VBoxPlayback/HBoxPlaycount/GridContainer/TimeSecs.text = str(0)
		recordedopuspacketsMemSize = 0
		recordedchunkmax = 0.0
		$VBoxPlayback/HBoxPlaycount/GridContainer/Totalbytes.text = str(0)
		$VBoxPlayback/HBoxPlaycount/GridContainer/Bytespersec.text = str(0)
	
		print("start talking")
		audiostreampacketheader["mqttpacketencoding"] = "base64" if mqttpacketencodebase64 else "binary"
		recordedheader = audiostreampacketheader
		recordedfooter = { }
		$MQTTnetwork.transportaudiopacketjson(audiostreampacketheader)
	
	else:
		recordedfooter = audiostreampacketheader
		assert(audiostreampacketheader.has("talkingtimeend"))
		print("recordedpacketsMemSize ", recordedopuspacketsMemSize)
		$MQTTnetwork.transportaudiopacketjson(audiostreampacketheader)
		print("Talked for ", audiostreampacketheader["talkingtimeduration"], " seconds")

func _on_vox_threshold_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		$TwoVoipMic.set_vox_threshhold(event.position.x/$HBoxMicTalk/VoxThreshold.size.x)

func _on_play_pressed():
	if false and audioeffectpitchshift != null:
		var speedup = $VBoxPlayback/HBoxStream/StreamSpeedup.value
		AudioServer.set_bus_effect_enabled(speechbusidx, audioeffectpitchshiftidx, (speedup != 1.0))
		SelfMember.get_node("AudioStreamPlayer").pitch_scale = speedup
		audioeffectpitchshift.pitch_scale = 1.0/speedup

	recordedheader.erase("opusframecount")
	SelfMember.twovoipspeaker.replayrecording($VBoxPlayback/HBoxStream/StreamSpeedup.value, recordedheader, recordedopuspackets, recordedfooter)

var saveplaybackfile = "user://savedplayback.dat"
func _on_sav_options_item_selected(index):
	pass # Replace with function body.
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
	if previous_ptt and not ptt:
		last_agc_gain = $TwoVoipMic.get_agc_gain()
	previous_ptt = ptt
	if $TwoVoipMic.agc_mode == TwovoipOpusEncoder.AGC_APPLIED:
		$VBoxFrameLength/HBoxOpusFrame/GainSpinBox.set_value_no_signal($TwoVoipMic.get_agc_gain())

func _on_gain_manual_spin_box_value_changed(value):
	$TwoVoipMic.set_gain(value)
	reprocessoriginalchunks()
