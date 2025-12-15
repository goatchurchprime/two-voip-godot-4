extends Control


@onready var speechbusidx = AudioServer.get_bus_index("SpeechBus")
@onready var SelfMember = $Members/Self

var audioeffectpitchshift : AudioEffectPitchShift = null
var audioeffectpitchshiftidx = 0
var audioopuschunkedeffect_forreprocessing # : AudioEffectOpusChunked

var resampledchunkprefix = PackedByteArray([2,3])
var mqttpacketencodebase64 : bool = false

var recordedsamples = [ ]
var recordedopuspackets = [ ]
var recordedresampledpackets = null
const maxrecordedsamples = 10*50
var recordedopuspacketsMemSize = 0
var recordedheader = { }
var recordedfooter = { }

var audiosampleframetextureimage : Image
var audiosampleframetexture : ImageTexture
var audioresampledframetextureimage : Image
var audioresampledframetexture : ImageTexture

var prevviseme = 0
var visemes = [ "sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS", "nn", "RR", "aa", "E", "ih", "oh", "ou", "LA" ]

var possibleusernames = ["Alice", "Beth", "Cath", "Dan", "Earl", "Fred", "George", "Harry", "Ivan", "John", "Kevin", "Larry", "Martin", "Oliver", "Peter", "Quentin", "Robert", "Samuel", "Thomas", "Ulrik", "Victor", "Wayne", "Xavier", "Youngs", "Zephir"]

func _ready():
	print("AudioServer.get_mix_rate()=", AudioServer.get_mix_rate())
	print("ProjectSettings.get_setting_with_override(\"audio/driver/mix_rate\")=", ProjectSettings.get_setting_with_override("audio/driver/mix_rate"))

	for h in [ $VBoxFrameLength/HBoxOpusFrame/FrameDuration, $VBoxFrameLength/HBoxOpusBitRate/SampleRate ]:
		h.connect("item_selected", func (_item_selected): updatesamplerates())
	for h in [ $VBoxFrameLength/HBoxOpusExtra/ComplexitySpinBox, $VBoxFrameLength/HBoxOpusBitRate/BitRate, $HBoxBigButtons/VBoxVox/Leadtime, $HBoxBigButtons/VBoxVox/Hangtime ]:
		h.connect("value_changed", func (_value): updatesamplerates())
	for h in [ $VBoxFrameLength/HBoxOpusExtra/OptimizeForVoice, $HBoxBigButtons/VBoxPTT/Denoise ]:
		h.connect("toggled", func (_toggled_on): updatesamplerates())

	$TwoVoipMic.initvoipmic($HBoxMicTalk/MicWorking, $HBoxInputDevice/OptionInputDevice, $HBoxBigButtons/VBoxPTT/PTT, $HBoxBigButtons/VBoxVox/Vox, $HBoxBigButtons/VBoxPTT/Denoise, $HBoxMicTalk/VoxThreshold.material)

	#for d in AudioServer.get_output_device_list():
	#	%OptionOutput.add_item(d)
	#assert(%OptionOutput.get_item_text(%OptionOutput.selected) == "Default")

	if not AudioServer.has_method("get_input_frames"):
		$GodotVersionWarning.visible = true
		print($GodotVersionWarning.text)
	audioopuschunkedeffect_forreprocessing = ClassDB.instantiate("AudioEffectOpusChunked")

	#$VBoxPlayback/HBoxStream/MixRate.value = AudioServer.get_mix_rate()
	$VBoxPlayback/HBoxStream/MixRate.value = ProjectSettings.get_setting_with_override("audio/driver/mix_rate")

	if $VBoxFrameLength/HBoxOpusFrame/FrameDuration.selected == -1:
		$VBoxFrameLength/HBoxOpusFrame/FrameDuration.select(3)
	if $VBoxFrameLength/HBoxOpusBitRate/SampleRate.selected == -1:
		$VBoxFrameLength/HBoxOpusBitRate/SampleRate.select(4)

	if speechbusidx != -1:
		for effect_idx in range(AudioServer.get_bus_effect_count(speechbusidx)):
			var laudioeffectonspeechbus : AudioEffect = AudioServer.get_bus_effect(speechbusidx, effect_idx)
			if laudioeffectonspeechbus.is_class("AudioEffectPitchShift"):
				audioeffectpitchshift = laudioeffectonspeechbus
				audioeffectpitchshiftidx = effect_idx
				break

	$VBoxPlayback/HBoxStream/OutSampleRate.value = ProjectSettings.get_setting_with_override("audio/driver/mix_rate")
	updatesamplerates()
	for i in range(1, len(visemes)):
		var d = $HBoxVisemes/ColorRect.duplicate()
		d.get_node("Label").text = visemes[i]
		$HBoxVisemes.add_child(d)
		d.size.y = i*8
	$HBoxMosquitto/FriendlyName.text = possibleusernames.pick_random()

	await get_tree().create_timer(0.1).timeout
	$HBoxMicTalk/MicWorking.set_pressed(true)
	
	$TwoVoipMic.connect("transmitaudiojsonpacket", on_transmitaudiojsonpacket)
	$TwoVoipMic.connect("transmitaudiopacket", on_transmitaudiopacket)

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
			
func updatesamplerates():
	var audiosamplerate = AudioServer.get_input_mix_rate()
	$VBoxFrameLength/HBoxAudioFrame/MicSampleRate.value = audiosamplerate
	var frametimems = float($VBoxFrameLength/HBoxOpusFrame/FrameDuration.text)
	var audioresamplerate = int($VBoxFrameLength/HBoxOpusBitRate/SampleRate.text)*1000
	var audioresamplesize = int(audioresamplerate*frametimems/1000.0)
	$VBoxFrameLength/HBoxAudioFrame/ResampleRate.value = audioresamplerate
	var opussamplerate = int($VBoxFrameLength/HBoxOpusBitRate/SampleRate.text)*1000
	$TwoVoipMic.setopusvalues(audiosamplerate,
			opussamplerate, frametimems, 
			int($VBoxFrameLength/HBoxOpusBitRate/BitRate.value), 
			int($VBoxFrameLength/HBoxOpusExtra/ComplexitySpinBox.value), 
			$VBoxFrameLength/HBoxOpusExtra/OptimizeForVoice.button_pressed)
	$HBoxBigButtons/VBoxPTT/Denoise.disabled = not ($TwoVoipMic.audioopuschunkedeffect.denoiser_available() and audioresamplerate == 48000)
	$TwoVoipMic.leadtime = $HBoxBigButtons/VBoxVox/Leadtime.value
	$TwoVoipMic.hangtime = $HBoxBigButtons/VBoxVox/Hangtime.value
	reprocessoriginalchunks()

func reprocessoriginalchunks():
	var aoce = $TwoVoipMic.audioopuschunkedeffect
	audioopuschunkedeffect_forreprocessing.audiosamplerate = aoce.audiosamplerate
	audioopuschunkedeffect_forreprocessing.audiosamplesize = aoce.audiosamplesize
	audioopuschunkedeffect_forreprocessing.opussamplerate = aoce.opussamplerate
	audioopuschunkedeffect_forreprocessing.opusframesize = aoce.opusframesize
	audioopuschunkedeffect_forreprocessing.opuscomplexity = aoce.opuscomplexity
	audioopuschunkedeffect_forreprocessing.opusoptimizeforvoice = aoce.opusoptimizeforvoice
	audioopuschunkedeffect_forreprocessing.opusbitrate = aoce.opusbitrate

	recordedheader["opusframesize"] = audioopuschunkedeffect_forreprocessing.opusframesize
	recordedheader["opussamplerate"] = audioopuschunkedeffect_forreprocessing.opussamplerate

	mqttpacketencodebase64 = $HBoxMosquitto/base64.button_pressed
	$VBoxFrameLength/HBoxAudioFrame/LabFrameLength.text = "%d samples" % aoce.audiosamplesize

	var frametimems = float($VBoxFrameLength/HBoxOpusFrame/FrameDuration.text)
	var audioresamplerate = int($VBoxFrameLength/HBoxOpusBitRate/SampleRate.text)*1000
	var audioresamplesize = int(audioresamplerate*frametimems/1000.0)
	$VBoxFrameLength/HBoxAudioFrame/LabResampleFrameLength.text = "%d samples" % audioresamplesize

	if len(recordedsamples) != 0 and len(recordedsamples[0]) != aoce.audiosamplesize:
		recordedsamples = rechunkrecordedchunks(recordedsamples, aoce.audiosamplesize)
	recordedopuspacketsMemSize = 0
	recordedopuspackets = null
	recordedresampledpackets = null

	recordedopuspackets = [ ]
	audioopuschunkedeffect_forreprocessing.resetencoder(true)
	var resampledopusframecount = 0
	for s in recordedsamples:
		audioopuschunkedeffect_forreprocessing.push_chunk(s)
		assert (audioopuschunkedeffect_forreprocessing.chunk_available())
		audioopuschunkedeffect_forreprocessing.resampled_current_chunk()
		if $HBoxBigButtons/VBoxPTT/Denoise.button_pressed:
			audioopuschunkedeffect_forreprocessing.denoise_resampled_chunk()
		resampledchunkprefix.set(0, (resampledopusframecount%256))  # 32768 frames is 10 minutes
		resampledchunkprefix.set(1, (int(resampledopusframecount/256)&127) + (recordedheader["opusstreamcount"]%2)*128)
		var opuspacket = audioopuschunkedeffect_forreprocessing.read_opus_packet(resampledchunkprefix)
		audioopuschunkedeffect_forreprocessing.drop_chunk()
		recordedopuspackets.append(opuspacket)
		resampledopusframecount += 1
		recordedopuspacketsMemSize += opuspacket.size() 
	recordedfooter["opusframecount"] = resampledopusframecount
	$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = str(len(recordedopuspackets))
	$VBoxPlayback/HBoxPlaycount/GridContainer/Totalbytes.text = str(recordedopuspacketsMemSize)
	var tm = len(recordedsamples)*frametimems*0.001
	$VBoxPlayback/HBoxPlaycount/GridContainer/TimeSecs.text = str(tm)
	$VBoxPlayback/HBoxPlaycount/GridContainer/Bytespersec.text = str(int(recordedopuspacketsMemSize/tm if tm else 0))

func recordoriginalchunks(audiosamples, opuspacket):
	recordedsamples.append(audiosamples)
	recordedopuspackets.append(opuspacket)
	$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = str(len(recordedopuspackets))
	recordedopuspacketsMemSize += opuspacket.size()
	$VBoxPlayback/HBoxPlaycount/GridContainer/Totalbytes.text = str(recordedopuspacketsMemSize)
	var tm = len(recordedopuspackets)*$TwoVoipMic.audioopuschunkedeffect.audiosamplesize*1.0/$TwoVoipMic.audioopuschunkedeffect.audiosamplerate
	$VBoxPlayback/HBoxPlaycount/GridContainer/TimeSecs.text = str(tm)
	$VBoxPlayback/HBoxPlaycount/GridContainer/Bytespersec.text = str(int(recordedopuspacketsMemSize/tm))

func on_transmitaudiopacket(opuspacket, opusframecount):
	if len(recordedsamples) < maxrecordedsamples:
		recordoriginalchunks($TwoVoipMic.audioopuschunkedeffect.read_chunk(false), opuspacket)
	$MQTTnetwork.transportaudiopacket(opuspacket, opusframecount, mqttpacketencodebase64)

func on_transmitaudiojsonpacket(audiostreampacketheader):
	print(audiostreampacketheader)

	if audiostreampacketheader.has("talkingtimestart"):
		recordedsamples = [ ]
		recordedopuspackets = [ ]
		recordedresampledpackets = [ ]

		$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = str(0)
		$VBoxPlayback/HBoxPlaycount/GridContainer/TimeSecs.text = str(0)
		recordedopuspacketsMemSize = 0
		$VBoxPlayback/HBoxPlaycount/GridContainer/Totalbytes.text = str(0)
		$VBoxPlayback/HBoxPlaycount/GridContainer/Bytespersec.text = str(0)
	
		print("start talking")
		audiostreampacketheader["mqttpacketencoding"] = "base64" if mqttpacketencodebase64 else "binary"
		recordedheader = audiostreampacketheader
		recordedfooter = { }
		$MQTTnetwork.transportaudiopacketjson(audiostreampacketheader)
	
	else:
		recordedfooter = audiostreampacketheader
		print("recordedpacketsMemSize ", recordedopuspacketsMemSize)
		$MQTTnetwork.transportaudiopacketjson({"framecount":audiostreampacketheader["opusframecount"]})
		print("Talked for ", audiostreampacketheader["talkingtimeduration"], " seconds")

func _on_vox_threshold_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		$TwoVoipMic.set_voxthreshhold(event.position.x/$HBoxMicTalk/VoxThreshold.size.x)

func _on_play_pressed():
	if audioeffectpitchshift != null:
		var speedup = $VBoxPlayback/HBoxStream/StreamSpeedup.value
		AudioServer.set_bus_effect_enabled(speechbusidx, audioeffectpitchshiftidx, (speedup != 1.0))
		SelfMember.get_node("AudioStreamPlayer").pitch_scale = speedup
		audioeffectpitchshift.pitch_scale = 1.0/speedup

	SelfMember.twovoipspeaker.tv_incomingaudiopacket(JSON.stringify(recordedheader).to_ascii_buffer())
	for x in recordedopuspackets:
		if not SelfMember.twovoipspeaker.audiostreamopuschunked.chunk_space_available():
			var tmm = SelfMember.twovoipspeaker.audiostreamopuschunked.queue_length_frames()*0.5/SelfMember.twovoipspeaker.audiostreamopuschunked.audiosamplerate
			await get_tree().create_timer(tmm).timeout
		SelfMember.twovoipspeaker.tv_incomingaudiopacket(x)
	SelfMember.twovoipspeaker.tv_incomingaudiopacket(JSON.stringify(recordedfooter).to_ascii_buffer())

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
