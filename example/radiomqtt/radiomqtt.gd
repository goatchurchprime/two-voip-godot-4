extends Control


@onready var microphoneidx = AudioServer.get_bus_index("MicrophoneBus")
@onready var speechbusidx = AudioServer.get_bus_index("SpeechBus")
@onready var SelfMember = $Members/Self

var audioeffectpitchshift : AudioEffectPitchShift = null
var audioeffectpitchshiftidx = 0
var audioeffectcapture : AudioEffectCapture = null
var audioopuschunkedeffect # : AudioEffectOpusChunked
var audioopuschunkedeffect_forreprocessing # : AudioEffectOpusChunked

@onready var audiostreamplaybackmicrophone = null # AudioStreamPlaybackMicrophone.new()

# values to use when AudioEffectOpusChunked cannot be instantiated
var frametimems : float = 20 
var opusbitrate : int = 0
var audiosamplerate : int = 44100
var audiosamplesize : int = 882
var audioresamplerate : int = 48000
var audioresamplesize : int = 960
var opussamplerate : int = 48000
var opusframesize : int = 960
var opuscomplexity : int = 5
var opusoptimizeforvoice : bool = true

var prefixbytes = PackedByteArray([23])
var mqttpacketencodebase64 : bool = false
var noopuscompression = false

var recordedsamples = [ ]
var recordedopuspackets = [ ]
var recordedresampledpackets = null
const maxrecordedsamples = 10*50
var recordedopuspacketsMemSize = 0
var recordedheader = { }

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
	var caninstantiate_audioeffectopuschunked = ClassDB.can_instantiate("AudioEffectOpusChunked")
	#caninstantiate_audioeffectopuschunked = false  # to disable it

	var caninstantiate_audiostreamplaybackmicrophone = ClassDB.can_instantiate("AudioStreamPlaybackMicrophone")
	#caninstantiate_audiostreamplaybackmicrophone = false  # to disable it

	$VBoxPlayback/HBoxStream/MixRate.value = AudioServer.get_mix_rate()

	if $VBoxFrameLength/HBoxOpusFrame/FrameDuration.selected == -1:
		$VBoxFrameLength/HBoxOpusFrame/FrameDuration.select(3)
	if $VBoxFrameLength/HBoxOpusBitRate/SampleRate.selected == -1:
		$VBoxFrameLength/HBoxOpusBitRate/SampleRate.select(4)

	if not caninstantiate_audioeffectopuschunked:
		$TwovoipWarning.visible = true
		$VBoxFrameLength/HBoxAudioFrame/ResampleRate.value = $VBoxFrameLength/HBoxAudioFrame/MicSampleRate.value
		$VBoxFrameLength/HBoxOpusBitRate/SampleRate.disabled = true
		
	if caninstantiate_audiostreamplaybackmicrophone:
		audiostreamplaybackmicrophone = ClassDB.instantiate("AudioStreamPlaybackMicrophone")
		$HBoxMicTalk/MicWorking.text = "*" + $HBoxMicTalk/MicWorking.text
		if caninstantiate_audioeffectopuschunked:
			audioopuschunkedeffect = ClassDB.instantiate("AudioEffectOpusChunked")
			audioopuschunkedeffect_forreprocessing = ClassDB.instantiate("AudioEffectOpusChunked")
		
	else:
		assert ($AudioStreamMicrophone.bus == "MicrophoneBus")
		var audioeffectonmic : AudioEffect = null
		for effect_idx in range(AudioServer.get_bus_effect_count(microphoneidx)):
			var laudioeffectonmic : AudioEffect = AudioServer.get_bus_effect(microphoneidx, effect_idx)
			if laudioeffectonmic.is_class("AudioEffectOpusChunked") or laudioeffectonmic.is_class("AudioEffectCapture"):
				audioeffectonmic = laudioeffectonmic
				break

		if audioeffectonmic == null:
			if caninstantiate_audioeffectopuschunked:
				audioeffectonmic = ClassDB.instantiate("AudioEffectOpusChunked")
				print("Adding AudioEffectOpusChunked to bus: ", $AudioStreamMicrophone.bus)
			else:
				audioeffectonmic = AudioEffectCapture.new()
				print("Adding AudioEffectCapture to bus: ", $AudioStreamMicrophone.bus)
			AudioServer.add_bus_effect(microphoneidx, audioeffectonmic)

		if audioeffectonmic.is_class("AudioEffectOpusChunked"):
			audioopuschunkedeffect = audioeffectonmic
			assert (caninstantiate_audioeffectopuschunked)
		elif audioeffectonmic.is_class("AudioEffectCapture"):
			audioeffectcapture = audioeffectonmic
			if caninstantiate_audioeffectopuschunked:
				audioopuschunkedeffect = ClassDB.instantiate("AudioEffectOpusChunked")
		if caninstantiate_audioeffectopuschunked:
			audioopuschunkedeffect_forreprocessing = ClassDB.instantiate("AudioEffectOpusChunked")

	if speechbusidx != -1:
		for effect_idx in range(AudioServer.get_bus_effect_count(speechbusidx)):
			var laudioeffectonspeechbus : AudioEffect = AudioServer.get_bus_effect(speechbusidx, effect_idx)
			if laudioeffectonspeechbus.is_class("AudioEffectPitchShift"):
				audioeffectpitchshift = laudioeffectonspeechbus
				audioeffectpitchshiftidx = effect_idx
				break

	$VBoxFrameLength/HBoxAudioFrame/MicSampleRate.value = AudioServer.get_mix_rate()
	$VBoxPlayback/HBoxStream/OutSampleRate.value = ProjectSettings.get_setting_with_override("audio/driver/mix_rate")
	updatesamplerates()
	for i in range(1, len(visemes)):
		var d = $HBoxVisemes/ColorRect.duplicate()
		d.get_node("Label").text = visemes[i]
		$HBoxVisemes.add_child(d)
		d.size.y = i*8
	$HBoxMosquitto/FriendlyName.text = possibleusernames.pick_random()

	SelfMember.audiobufferregulationtime = 3600.0

	if audiostreamplaybackmicrophone != null:
		audiostreamplaybackmicrophone.start_microphone()
		if $AudioStreamMicrophone.playing:
			$AudioStreamMicrophone.stop()


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
	frametimems = float($VBoxFrameLength/HBoxOpusFrame/FrameDuration.text)
	audiosamplerate = $VBoxFrameLength/HBoxAudioFrame/MicSampleRate.value
	audiosamplesize = int(audiosamplerate*frametimems/1000.0)
	audioresamplerate = $VBoxFrameLength/HBoxAudioFrame/ResampleRate.value
	audioresamplesize = int(audioresamplerate*frametimems/1000.0)
	opussamplerate = int($VBoxFrameLength/HBoxOpusBitRate/SampleRate.text)*1000
	opusframesize = int(opussamplerate*frametimems/1000.0)
	opuscomplexity = int($VBoxFrameLength/HBoxOpusExtra/ComplexitySpinBox.value)
	opusoptimizeforvoice = $VBoxFrameLength/HBoxOpusExtra/OptimizeForVoice.button_pressed

	print("aaa audiosamplesize ", audiosamplesize, "  audiosamplerate ", audiosamplerate)

	noopuscompression = false
	if opussamplerate == audioresamplerate:
		$VBoxFrameLength/HBoxOpusExtra/Compressed.disabled = false
		if not $VBoxFrameLength/HBoxOpusExtra/Compressed.button_pressed:
			noopuscompression = true
	else:
		$VBoxFrameLength/HBoxOpusExtra/Compressed.button_pressed = false
		$VBoxFrameLength/HBoxOpusExtra/Compressed.disabled = true
		noopuscompression = true
	opusbitrate = int($VBoxFrameLength/HBoxOpusBitRate/BitRate.value)
	
	if audioopuschunkedeffect != null:
		audioopuschunkedeffect.audiosamplerate = audiosamplerate
		audioopuschunkedeffect.audiosamplesize = audiosamplesize
		audioopuschunkedeffect.opussamplerate = audioresamplerate
		audioopuschunkedeffect.opusframesize = audioresamplesize
		audioopuschunkedeffect.opuscomplexity = opuscomplexity
		audioopuschunkedeffect.opusoptimizeforvoice = opusoptimizeforvoice
		audioopuschunkedeffect.opusbitrate = opusbitrate
		
		audioopuschunkedeffect_forreprocessing.audiosamplerate = audiosamplerate
		audioopuschunkedeffect_forreprocessing.audiosamplesize = audiosamplesize
		audioopuschunkedeffect_forreprocessing.opussamplerate = audioresamplerate
		audioopuschunkedeffect_forreprocessing.opusframesize = audioresamplesize
		audioopuschunkedeffect_forreprocessing.opuscomplexity = opuscomplexity
		audioopuschunkedeffect_forreprocessing.opusoptimizeforvoice = opusoptimizeforvoice
		audioopuschunkedeffect_forreprocessing.opusbitrate = opusbitrate
		
		$HBoxBigButtons/VBoxPTT/Denoise.disabled = not (audioopuschunkedeffect.denoiser_available() and audioresamplerate == 48000)
	else:
		$VBoxFrameLength/HBoxOpusExtra/Compressed.disabled = true
		$HBoxBigButtons/VBoxPTT/Denoise.disabled = true

	mqttpacketencodebase64 = $HBoxMosquitto/base64.button_pressed
	$VBoxFrameLength/HBoxAudioFrame/LabFrameLength.text = "%d samples" % audiosamplesize
	$VBoxFrameLength/HBoxAudioFrame/LabResampleFrameLength.text = "%d samples" % audioresamplesize
	recordedheader = { "opusframesize":audioresamplesize, 
					   "opussamplerate":audioresamplerate, 
					   "prefixbyteslength":len(prefixbytes), 
					   "noopuscompression":noopuscompression,
					   "mqttpacketencoding":"base64" if mqttpacketencodebase64 else "binary" }
	if len(recordedsamples) != 0 and len(recordedsamples[0]) != audiosamplesize:
		recordedsamples = rechunkrecordedchunks(recordedsamples, audiosamplesize)
	recordedopuspacketsMemSize = 0
	recordedopuspackets = null
	recordedresampledpackets = null
	if not noopuscompression:
		recordedopuspackets = [ ]
		audioopuschunkedeffect_forreprocessing.resetencoder(true)
		for s in recordedsamples:
			audioopuschunkedeffect_forreprocessing.push_chunk(s)
			assert (audioopuschunkedeffect_forreprocessing.chunk_available())
			audioopuschunkedeffect_forreprocessing.resampled_current_chunk()
			if $HBoxBigButtons/VBoxPTT/Denoise.button_pressed:
				audioopuschunkedeffect_forreprocessing.denoise_resampled_chunk()
			var opuspacket = audioopuschunkedeffect_forreprocessing.read_opus_packet(prefixbytes)
			audioopuschunkedeffect_forreprocessing.drop_chunk()
			recordedopuspackets.append(opuspacket)
			recordedopuspacketsMemSize += opuspacket.size() 
		$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = str(len(recordedopuspackets))
	elif audioopuschunkedeffect_forreprocessing != null:
		recordedresampledpackets = [ ]
		audioopuschunkedeffect_forreprocessing.resetencoder(true)
		var denoise = not $HBoxBigButtons/VBoxPTT/Denoise.disabled and $HBoxBigButtons/VBoxPTT/Denoise.button_pressed
		for s in recordedsamples:
			audioopuschunkedeffect_forreprocessing.push_chunk(s)
			assert (audioopuschunkedeffect_forreprocessing.chunk_available())
			audioopuschunkedeffect_forreprocessing.resampled_current_chunk()
			if $HBoxBigButtons/VBoxPTT/Denoise.button_pressed:
				audioopuschunkedeffect_forreprocessing.denoise_resampled_chunk()
			var resampledchunk = audioopuschunkedeffect_forreprocessing.read_chunk(true)
			recordedresampledpackets.append(resampledchunk)
			audioopuschunkedeffect_forreprocessing.drop_chunk()
	else:
		recordedresampledpackets = recordedsamples.duplicate()
		$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = "1"
		if len(recordedresampledpackets):
			recordedopuspacketsMemSize = len(recordedresampledpackets)*len(recordedresampledpackets[0])*4

	$VBoxPlayback/HBoxPlaycount/GridContainer/Totalbytes.text = str(recordedopuspacketsMemSize)
	var tm = len(recordedsamples)*frametimems*0.001
	$VBoxPlayback/HBoxPlaycount/GridContainer/Bytespersec.text = str(int(recordedopuspacketsMemSize/tm if tm else 0))
	setupaudioshader()
	
func setupaudioshader():
	var audiosampleframedata_blank = PackedVector2Array()
	audiosampleframedata_blank.resize(audiosamplesize)
	for j in range(audiosamplesize):
		audiosampleframedata_blank.set(j, Vector2(-0.5,0.9) if (j%10)<5 else Vector2(0.6,0.1))
	audiosampleframetextureimage = Image.create_from_data(audiosamplesize, 1, false, Image.FORMAT_RGF, audiosampleframedata_blank.to_byte_array())
	audiosampleframetexture = ImageTexture.create_from_image(audiosampleframetextureimage)
	assert (audiosampleframetexture != null)
	$HBoxMicTalk/HSliderVox/ColorRectBackground.material.set_shader_parameter("voice", audiosampleframetexture)
	if opusframesize != 0:
		var audioresampledframedata_blank = PackedVector2Array()
		audioresampledframedata_blank.resize(opusframesize)
		audioresampledframetextureimage = Image.create_from_data(opusframesize, 1, false, Image.FORMAT_RGF, audioresampledframedata_blank.to_byte_array())
		audioresampledframetexture = ImageTexture.create_from_image(audioresampledframetextureimage)
		assert (audioresampledframetexture != null)
		$HBoxMicTalk/HSliderVox/ColorRectBackground.material.set_shader_parameter("voice_resampled", audioresampledframetexture)
		$HBoxMicTalk/HSliderVox/ColorRectBackground.material.set_shader_parameter("drawresampled", true)
	else:
		$HBoxMicTalk/HSliderVox/ColorRectBackground.material.set_shader_parameter("drawresampled", false)

func audiosamplestoshader(audiosamples, resampled):
	if resampled:
		assert (len(audiosamples) == audioopuschunkedeffect.opusframesize)
		audioresampledframetextureimage.set_data(audioopuschunkedeffect.opusframesize, 1, false, Image.FORMAT_RGF, audiosamples.to_byte_array())
		audioresampledframetexture.update(audioresampledframetextureimage)
	else:
		assert (len(audiosamples) == audiosamplesize)
		audiosampleframetextureimage.set_data(audiosamplesize, 1, false, Image.FORMAT_RGF, audiosamples.to_byte_array())
		audiosampleframetexture.update(audiosampleframetextureimage)

var currentlytalking = false
var talkingstarttime = 0
func starttalking():
	currentlytalking = true
	recordedsamples = [ ]
	if not noopuscompression:
		recordedopuspackets = [ ]
		recordedresampledpackets = null
	else:
		recordedopuspackets = null
		if audioopuschunkedeffect != null:
			recordedresampledpackets = [ ]
		else:
			recordedresampledpackets = null

	$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = str(0)
	$VBoxPlayback/HBoxPlaycount/GridContainer/TimeSecs.text = str(0)
	recordedopuspacketsMemSize = 0
	$VBoxPlayback/HBoxPlaycount/GridContainer/Totalbytes.text = str(0)
	$VBoxPlayback/HBoxPlaycount/GridContainer/Bytespersec.text = str(0)
	
	print("start talking")
	$MQTTnetwork.transportaudiopacketjson(recordedheader)
	talkingstarttime = Time.get_ticks_msec()
	
	if audioopuschunkedeffect != null:
		var leadtimems = $HBoxBigButtons/VBoxVox/Leadtime.value*1000 - frametimems
		var Dundroppedchunks = 0
		while leadtimems > 0 and audioopuschunkedeffect.undrop_chunk():
			leadtimems -= frametimems
			Dundroppedchunks += 1
		print("Undropped ", Dundroppedchunks, " chunks")
		if opusframesize != 0 and $VBoxFrameLength/HBoxOpusExtra/Compressed.button_pressed:
			audioopuschunkedeffect.resetencoder(false)

func _on_mic_working_toggled(toggled_on):
	if audiostreamplaybackmicrophone != null:
		print("_on_mic_working_toggled audiostreamplaybackmicrophone ", audiostreamplaybackmicrophone.is_microphone_playing(), " to ", toggled_on)
		if toggled_on:
			audiostreamplaybackmicrophone.start_microphone()
			print("  is_playing=", audiostreamplaybackmicrophone.is_microphone_playing())
		else:
			audiostreamplaybackmicrophone.stop_microphone()

	else:
		print("_on_mic_working_toggled ", $AudioStreamMicrophone.playing, " to ", toggled_on)
		if toggled_on:
			if not $AudioStreamMicrophone.playing:
				$AudioStreamMicrophone.play()
		else:
			if $AudioStreamMicrophone.playing:
				$AudioStreamMicrophone.stop()

func _input(event):
	if event is InputEventKey and event.is_pressed():
		if event.keycode == KEY_P:
			print("turn off processing")
			set_process(false)
			await get_tree().create_timer(2.0).timeout
			set_process(true)
			print("turn on processing")
		if event.keycode == KEY_I or event.keycode == KEY_O:
			$AudioStreamMicrophone.volume_db += (1 if event.keycode == KEY_I else -1)
			print($AudioStreamMicrophone.volume_db)

		if event.keycode == KEY_D:
			audioopuschunkedeffect.Drunmicthing()


var timems0formicstreamestimate = 0
var framesformicstreamestimate = 0
const micframecheckratems = 4000
func _process(_delta):
	var talking = $HBoxBigButtons/VBoxPTT/PTT.button_pressed
	if talking:
		$VBoxPlayback/HBoxPlaycount/GridContainer/TimeSecs.text = "%.1f" % ((Time.get_ticks_msec() - talkingstarttime)*0.001)
	if talking and not currentlytalking:
		if not $AudioStreamMicrophone.playing and audiostreamplaybackmicrophone == null:
			$AudioStreamMicrophone.play()
		starttalking()
	elif not talking and currentlytalking:
		endtalking()

	if audiostreamplaybackmicrophone != null:
		$HBoxMicTalk/MicWorking.set_pressed_no_signal(audiostreamplaybackmicrophone.is_microphone_playing())
	else:
		$HBoxMicTalk/MicWorking.set_pressed_no_signal($AudioStreamMicrophone.playing)

	if audioopuschunkedeffect != null:
		var framesinprocessformicstreamestimate = 0
		assert (audioopuschunkedeffect != null)
		if audiostreamplaybackmicrophone != null and audiostreamplaybackmicrophone.is_microphone_playing():
			var microphonesamples = audiostreamplaybackmicrophone.get_microphone_buffer(audiosamplesize)
			if len(microphonesamples) != 0:
				audioopuschunkedeffect.push_chunk(microphonesamples)

		elif audioeffectcapture != null:
			var captureframesavailable = audioeffectcapture.get_frames_available()
			if captureframesavailable > 0:
				var captureframes = audioeffectcapture.get_buffer(captureframesavailable)
				audioopuschunkedeffect.push_chunk(captureframes)
		else:
			pass  # the input is arriving from the process value
		
		while audioopuschunkedeffect.chunk_available():
			var audiosamples = audioopuschunkedeffect.read_chunk(false)
			framesinprocessformicstreamestimate += len(audiosamples)
			audiosamplestoshader(audiosamples, false)
			audioopuschunkedeffect.resampled_current_chunk()
			var chunkv1 = audioopuschunkedeffect.chunk_max(false, false)
			var chunkv2 = audioopuschunkedeffect.chunk_max(true, false)
			var speechnoiseprobability = -1.0
			if $HBoxBigButtons/VBoxPTT/Denoise.button_pressed:
				if opusframesize != 0 or audioopuschunkedeffect.opusframesize != 0:
					speechnoiseprobability = audioopuschunkedeffect.denoise_resampled_chunk()
					audiosamplestoshader(audioopuschunkedeffect.read_chunk(true), true)
					$HBoxMicTalk/HSliderVox/ColorRectBackground.material.set_shader_parameter("drawresampled", true)
			else:
				$HBoxMicTalk/HSliderVox/ColorRectBackground.material.set_shader_parameter("drawresampled", false)

			var viseme = audioopuschunkedeffect.chunk_to_lipsync(false)
			if viseme != prevviseme:
				print(" viseme ", visemes[viseme], " ", chunkv2)
				prevviseme = viseme
			if viseme != -1:
				var vv = audioopuschunkedeffect.read_visemes();
				for i in range($HBoxVisemes.get_child_count()):
					$HBoxVisemes.get_child(i).size.y = int(50*vv[i])
				#print(" vvv ", vv[-2], "  ", vv[-1])
				$HBoxVisemes.visible = true
			else:
				$HBoxVisemes.visible = false
				
			$HBoxMicTalk.loudnessvalues(chunkv1, chunkv2, frametimems, speechnoiseprobability)
			if currentlytalking:
				if len(recordedsamples) < maxrecordedsamples:
					recordedsamples.append(audiosamples)
				if noopuscompression:
					recordedresampledpackets.append(audioopuschunkedeffect.read_chunk(true))
				elif opusframesize != 0:
					var opuspacket = audioopuschunkedeffect.read_opus_packet(prefixbytes)
					$MQTTnetwork.transportaudiopacket(opuspacket, mqttpacketencodebase64)
					if len(recordedopuspackets) < maxrecordedsamples:
						recordedopuspackets.append(opuspacket)
						$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = str(len(recordedopuspackets))
						recordedopuspacketsMemSize += opuspacket.size()
						$VBoxPlayback/HBoxPlaycount/GridContainer/Totalbytes.text = str(recordedopuspacketsMemSize)
						var tm = len(recordedopuspackets)*audioopuschunkedeffect.audiosamplesize*1.0/audioopuschunkedeffect.audiosamplerate
						$VBoxPlayback/HBoxPlaycount/GridContainer/Bytespersec.text = str(int(recordedopuspacketsMemSize/tm))
				else:
					$MQTTnetwork.transportaudiopacket(var_to_bytes(audiosamples), mqttpacketencodebase64)
			audioopuschunkedeffect.drop_chunk()

		var timemsformicstreamestimate = Time.get_ticks_msec()
		framesformicstreamestimate += framesinprocessformicstreamestimate
		#if framesinprocessformicstreamestimate != 0:
		#	print("ff ", timemsformicstreamestimate, framesformicstreamestimate)
		var dtimems = timemsformicstreamestimate - timems0formicstreamestimate
		if dtimems > micframecheckratems or timems0formicstreamestimate == 0:
			if timems0formicstreamestimate != 0:
				var micfreq = framesformicstreamestimate*1000.0/micframecheckratems
				print("calculated mic frequency ", micfreq)
			timems0formicstreamestimate = timemsformicstreamestimate
			framesformicstreamestimate = 0

	elif audioeffectcapture != null:
		while audioeffectcapture.get_frames_available() > audiosamplesize:
			var audiosamples = audioeffectcapture.get_buffer(audiosamplesize)
			audiosamplestoshader(audiosamples, false)
			var chunkv1 = 0.0
			var schunkv2 = 0.0
			for i in range(len(audiosamples)):
				var v = audiosamples[i]
				var vm = max(abs(v.x), abs(v.y))
				if vm > chunkv1:
					chunkv1 = vm
				schunkv2 = v.x*v.x + v.y*v.y
			var chunkv2 = sqrt(schunkv2/(len(audiosamples)*2))
			$HBoxMicTalk.loudnessvalues(chunkv1, chunkv2, frametimems, -1.0)
			if currentlytalking:
				recordedsamples.append(audiosamples)
				var framecount = len(recordedsamples)
				var rawpacket = var_to_bytes(audiosamples)
				recordedopuspacketsMemSize += rawpacket.size()
				$MQTTnetwork.transportaudiopacket(rawpacket, mqttpacketencodebase64)
				$VBoxPlayback/HBoxPlaycount/GridContainer/FrameCount.text = str(framecount)
				$VBoxPlayback/HBoxPlaycount/GridContainer/Totalbytes.text = str(recordedopuspacketsMemSize)
				var tm = framecount*audiosamplesize*1.0/audiosamplerate
				$VBoxPlayback/HBoxPlaycount/GridContainer/Bytespersec.text = str(int(recordedopuspacketsMemSize/tm))
		
func endtalking():
	currentlytalking = false
	print("recordedpacketsMemSize ", recordedopuspacketsMemSize)
	$MQTTnetwork.transportaudiopacketjson({"framecount":len(recordedsamples)})
	print("Talked for ", (Time.get_ticks_msec() - talkingstarttime)*0.001, " seconds")



func duplicatewithslippage(audiopackets, lframeslip):
	var frameslip = abs(lframeslip)
	var bleftside = (lframeslip >= 0)
	var slippedaudiopackets = [ ]
	for i in range(1, len(audiopackets)):
		var prevpacket = audiopackets[i-1]
		var packet = audiopackets[i]
		var dpacket = packet.duplicate()
		var n = len(packet)
		if bleftside:
			for j in range(n):
				if j < frameslip:
					dpacket[j].x = prevpacket[n - frameslip + j].x
				else:
					dpacket[j].x = packet[j - frameslip].x
		else:
			for j in range(n):
				if j < frameslip:
					dpacket[j].y = prevpacket[n - frameslip + j].y
				else:
					dpacket[j].y = packet[j - frameslip].y
		slippedaudiopackets.push_back(dpacket)
	return slippedaudiopackets
		

func _on_play_pressed():
	if audioeffectpitchshift != null:
		var speedup = $VBoxPlayback/HBoxStream/StreamSpeedup.value
		AudioServer.set_bus_effect_enabled(speechbusidx, audioeffectpitchshiftidx, (speedup != 1.0))
		SelfMember.get_node("AudioStreamPlayer").pitch_scale = speedup
		audioeffectpitchshift.pitch_scale = 1.0/speedup

	var h = recordedheader.duplicate()
	if recordedopuspackets:
		SelfMember.processheaderpacket(h)
		SelfMember.resampledpacketsbuffer = null
		SelfMember.opuspacketsbuffer = recordedopuspackets.duplicate()
	elif recordedresampledpackets != null:
		SelfMember.processheaderpacket(h)
		var stereoframeslip = $VBoxPlayback/HBoxStream/StereoFrameSlip.value
		if stereoframeslip == 0:
			SelfMember.resampledpacketsbuffer = recordedresampledpackets.duplicate()
		else:
			SelfMember.resampledpacketsbuffer = duplicatewithslippage(recordedresampledpackets, stereoframeslip)

	elif recordedsamples and SelfMember.audiostreamgeneratorplayback != null:
		SelfMember.audiosamplesize = audiosamplesize
		SelfMember.audiopacketsbuffer = recordedsamples.duplicate()

	SelfMember.playbackstarttime = Time.get_ticks_msec()


var saveplaybackfile = "user://savedplayback.dat"
func _on_sav_options_item_selected(index):
	pass # Replace with function body.
	if index == 1:
		var f = FileAccess.open(saveplaybackfile, FileAccess.WRITE)
		prints("Saving to file:", f.get_path_absolute())
		f.store_var({"audiosamplerate":audiosamplerate,
					 "recordedsamples":recordedsamples})
		f.close()
	elif index == 2:
		var f = FileAccess.open(saveplaybackfile, FileAccess.READ)
		prints("Loading from file:", f.get_path_absolute())
		var dat = f.get_var()
		if audiosamplerate != dat["audiosamplerate"]:
			prints(" sample rates disagree!!", dat["audiosamplerate"], audiosamplerate)
		recordedsamples = dat["recordedsamples"]
		f.close()
	$VBoxPlayback/HBoxPlaycount/VBoxExpt/SavOptions.select(0)


func _on_frame_duration_item_selected(_index):
	updatesamplerates()

func _on_sample_rate_item_selected(index):
	$VBoxFrameLength/HBoxAudioFrame/ResampleRate.value = int($VBoxFrameLength/HBoxOpusBitRate/SampleRate.text)*1000
	$VBoxFrameLength/HBoxOpusExtra/Compressed.button_pressed = true
	updatesamplerates()

func _on_resample_state_item_selected(_index):
	updatesamplerates()

func _on_audio_stream_microphone_finished():
	print(" ** _on_audio_stream_microphone_finished")

func _on_option_button_item_selected(_index):
	updatesamplerates()

func _on_denoise_toggled(toggled_on):
	$HBoxMicTalk/HSliderVox.value = ($HBoxMicTalk.voiceprobthreshold if toggled_on else $HBoxMicTalk.voxthreshold)*$HBoxMicTalk/HSliderVox.max_value
	updatesamplerates()

func _on_base_64_toggled(toggled_on):
	updatesamplerates()

func _on_compressed_toggled(toggled_on):
	updatesamplerates()

func _on_resample_rate_value_changed(value):
	updatesamplerates()

func _on_sample_rate_value_changed(value):
	updatesamplerates()


func _on_spin_box_value_changed(value):
	$AudioStreamMicrophone.pitch_scale = value

func _on_volume_db_spin_box_value_changed(value):
	$AudioStreamMicrophone.volume_db = value

func _on_complexity_spin_box_value_changed(value):
	updatesamplerates()

func _on_audio_optimized_check_button_toggled(toggled_on):
	updatesamplerates()
	$VBoxFrameLength/HBoxOpusExtra/OptimizeForVoice/AudioStreamPlayerTestNoise.play()

func _on_bit_rate_value_changed(value):
	updatesamplerates()
