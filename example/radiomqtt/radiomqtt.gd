extends Control


@onready var microphoneidx = AudioServer.get_bus_index("MicrophoneBus")
@onready var speechbusidx = AudioServer.get_bus_index("SpeechBus")
@onready var SelfMember = $Members/Self

var audioeffectpitchshift : AudioEffectPitchShift = null
var audioeffectpitchshiftidx = 0
var audioeffectcapture : AudioEffectCapture = null
var audioopuschunkedeffect # : AudioEffectOpusChunked

# values to use when AudioEffectOpusChunked cannot be instantiated
var frametimems : float = 20 
var opusbitrate : int = 0
var opusframesize : int = 20
var audiosamplerate : int = 44100
var opussamplerate : int = 48000
var audiosamplesize : int = 882
var prefixbyteslength : int = 0
var mqttpacketencodebase64 : bool = false

var recordedsamples = [ ]
var recordedopuspackets = [ ]
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
	if $VBoxFrameLength/HBoxOpusFrame/FrameDuration.selected == -1:
		$VBoxFrameLength/HBoxOpusFrame/FrameDuration.select(3)
	if $VBoxFrameLength/HBoxAudioFrame/ResampleState.selected == -1:
		$VBoxFrameLength/HBoxAudioFrame/ResampleState.select(1)
	if $VBoxFrameLength/HBoxBitRate/BitRate.selected == -1:
		$VBoxFrameLength/HBoxBitRate/BitRate.select(2)
	if $VBoxFrameLength/HBoxBitRate/BitRate.selected == -1:
		$VBoxFrameLength/HBoxBitRate/BitRate.select(2)
	if not ClassDB.can_instantiate("AudioEffectOpusChunked"):
		$VBoxFrameLength/HBoxAudioFrame/ResampleState.select(0)
		$VBoxFrameLength/HBoxAudioFrame/ResampleState.disabled = true
		$TwovoipWarning.visible = true
		
	assert ($AudioStreamMicrophone.bus == "MicrophoneBus")
	var audioeffectonmic : AudioEffect = null
	for effect_idx in range(AudioServer.get_bus_effect_count(microphoneidx)):
		var laudioeffectonmic : AudioEffect = AudioServer.get_bus_effect(microphoneidx, effect_idx)
		if laudioeffectonmic.is_class("AudioEffectOpusChunked") or laudioeffectonmic.is_class("AudioEffectCapture"):
			audioeffectonmic = laudioeffectonmic
			break
	if audioeffectonmic == null:
		if ClassDB.can_instantiate("AudioEffectOpusChunked"):
			audioeffectonmic = ClassDB.instantiate("AudioEffectOpusChunked")
			print("Adding AudioEffectOpusChunked to bus: ", $AudioStreamMicrophone.bus)
		else:
			audioeffectonmic = AudioEffectCapture.new()
			print("Adding AudioEffectCapture to bus: ", $AudioStreamMicrophone.bus)
		AudioServer.add_bus_effect(microphoneidx, audioeffectonmic)
	if audioeffectonmic.is_class("AudioEffectOpusChunked"):
		audioopuschunkedeffect = audioeffectonmic
	elif audioeffectonmic.is_class("AudioEffectCapture"):
		audioeffectcapture = audioeffectonmic
		if ClassDB.can_instantiate("AudioEffectOpusChunked"):
			audioopuschunkedeffect = ClassDB.instantiate("AudioEffectOpusChunked")

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

	SelfMember.audiobufferregulationtime = 3600.0

func resamplerecordedsamples(orgsamples, newsamplesize):
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
	opusbitrate = int($VBoxFrameLength/HBoxBitRate/BitRate.text)
	if audioopuschunkedeffect != null:
		audiosamplerate = audioopuschunkedeffect.audiosamplerate
		opussamplerate = audioopuschunkedeffect.opussamplerate
		audioopuschunkedeffect.opusbitrate = opusbitrate
		opusframesize = int(opussamplerate*frametimems/1000.0)
		audioopuschunkedeffect.opusframesize = opusframesize
		$HBoxBigButtons/VBoxPTT/Denoise.disabled = not audioopuschunkedeffect.denoiser_available()
	else:
		opusframesize = int(opussamplerate*frametimems/1000.0)
	
	var i = $VBoxFrameLength/HBoxAudioFrame/ResampleState.get_selected_id()
	if i == 0:  # uncompressed
		recordedopuspackets = [ ]
		audiosamplesize = int(audiosamplerate*frametimems/1000)
		opusframesize = 0
		if audioopuschunkedeffect != null:
			audioopuschunkedeffect.opusframesize = int(opussamplerate*frametimems/1000.0)
	elif i == 1: # Speexresample
		audiosamplesize = int(audiosamplerate*frametimems/1000)
	else:  # 441.1k as 48k fakery
		audiosamplesize = opusframesize
	if audioopuschunkedeffect != null:
		audioopuschunkedeffect.audiosamplesize = audiosamplesize

	mqttpacketencodebase64 = $HBoxMosquitto/base64.button_pressed
	$VBoxFrameLength/HBoxOpusFrame/LabFrameLength.text = "%d samples at 48KHz" % opusframesize
	$VBoxFrameLength/HBoxAudioFrame/LabFrameLength.text = "%d samples at 44.1KHz" % audiosamplesize
	recordedheader = { "opusframesize":opusframesize, "audiosamplesize":audiosamplesize, 
					   "opussamplerate":opussamplerate, "audiosamplerate":audiosamplerate, 
					   "prefixbyteslength":prefixbyteslength, 
					   "mqttpacketencoding":"base64" if mqttpacketencodebase64 else "binary" }
	if len(recordedsamples) != 0 and len(recordedsamples[0]) != audiosamplesize:
		recordedsamples = resamplerecordedsamples(recordedsamples, audiosamplesize)
	var prefixbytes = PackedByteArray()
	recordedopuspacketsMemSize = 0
	if opusframesize != 0:
		recordedopuspackets = [ ]
		for s in recordedsamples:
			var opuspacket = audioopuschunkedeffect.chunk_to_opus_packet(prefixbytes, s, $HBoxBigButtons/VBoxPTT/Denoise.button_pressed)
			recordedopuspackets.append(opuspacket)
			recordedopuspacketsMemSize += opuspacket.size() 
		$HBoxPlaycount/GridContainer/FrameCount.text = str(len(recordedopuspackets))
	else:
		if len(recordedsamples):
			recordedopuspacketsMemSize = len(recordedsamples)*len(recordedsamples[0])*4
		$HBoxPlaycount/GridContainer/FrameCount.text = "1"
	$HBoxPlaycount/GridContainer/Totalbytes.text = str(recordedopuspacketsMemSize)
	var tm = len(recordedsamples)*frametimems*0.001
	$HBoxPlaycount/GridContainer/Bytespersec.text = str(int(recordedopuspacketsMemSize/tm if tm else 0))
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
	if audioopuschunkedeffect.opusframesize != 0:
		var audioresampledframedata_blank = PackedVector2Array()
		audioresampledframedata_blank.resize(audioopuschunkedeffect.opusframesize)
		audioresampledframetextureimage = Image.create_from_data(audioopuschunkedeffect.opusframesize, 1, false, Image.FORMAT_RGF, audioresampledframedata_blank.to_byte_array())
		audioresampledframetexture = ImageTexture.create_from_image(audioresampledframetextureimage)
		assert (audioresampledframetexture != null)
		$HBoxMicTalk/HSliderVox/ColorRectBackground.material.set_shader_parameter("voice_resampled", audioresampledframetexture)
		$HBoxMicTalk/HSliderVox/ColorRectBackground.material.set_shader_parameter("drawresampled", true)
	else:
		$HBoxMicTalk/HSliderVox/ColorRectBackground.material.set_shader_parameter("drawresampled", false)

	
func audiosamplestoshader(audiosamples, resampled):
	if resampled:
		assert (len(audiosamples)== audioopuschunkedeffect.opusframesize)
		audioresampledframetextureimage.set_data(audioopuschunkedeffect.opusframesize, 1, false, Image.FORMAT_RGF, audiosamples.to_byte_array())
		audioresampledframetexture.update(audioresampledframetextureimage)
	else:
		assert (len(audiosamples)== audiosamplesize)
		audiosampleframetextureimage.set_data(audiosamplesize, 1, false, Image.FORMAT_RGF, audiosamples.to_byte_array())
		audiosampleframetexture.update(audiosampleframetextureimage)

var currentlytalking = false
var talkingstarttime = 0
func starttalking():
	currentlytalking = true
	recordedsamples = [ ]
	recordedopuspackets = [ ]
	$HBoxPlaycount/GridContainer/FrameCount.text = str(0)
	$HBoxPlaycount/GridContainer/TimeSecs.text = str(0)
	recordedopuspacketsMemSize = 0
	$HBoxPlaycount/GridContainer/Totalbytes.text = str(0)
	$HBoxPlaycount/GridContainer/Bytespersec.text = str(0)
	
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
		#if opusframesize != 0:
		audioopuschunkedeffect.flush_opus_encoder(false)

func _on_mic_working_toggled(toggled_on):
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

func _process(_delta):
	var talking = $HBoxBigButtons/VBoxPTT/PTT.button_pressed
	if talking:
		$HBoxPlaycount/GridContainer/TimeSecs.text = "%.1f" % ((Time.get_ticks_msec() - talkingstarttime)*0.001)
	if talking and not currentlytalking:
		if not $AudioStreamMicrophone.playing:
			$AudioStreamMicrophone.play()
		starttalking()
	elif not talking and currentlytalking:
		endtalking()
	$HBoxMicTalk/MicWorking.button_pressed = $AudioStreamMicrophone.playing

	var prefixbytes = PackedByteArray()
	if audioeffectcapture == null:
		assert (audioopuschunkedeffect != null)
		while audioopuschunkedeffect.chunk_available():
			var audiosamples = audioopuschunkedeffect.read_chunk(false)
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
				if opusframesize != 0:
					var opuspacket = audioopuschunkedeffect.read_opus_packet(prefixbytes)
					if len(recordedopuspackets) < maxrecordedsamples:
						recordedopuspackets.append(opuspacket)
					$MQTTnetwork.transportaudiopacket(opuspacket, mqttpacketencodebase64)
					$HBoxPlaycount/GridContainer/FrameCount.text = str(len(recordedopuspackets))
					recordedopuspacketsMemSize += opuspacket.size()
					$HBoxPlaycount/GridContainer/Totalbytes.text = str(recordedopuspacketsMemSize)
					var tm = len(recordedopuspackets)*audioopuschunkedeffect.audiosamplesize*1.0/audioopuschunkedeffect.audiosamplerate
					$HBoxPlaycount/GridContainer/Bytespersec.text = str(int(recordedopuspacketsMemSize/tm))
				else:
					$MQTTnetwork.transportaudiopacket(var_to_bytes(audiosamples), mqttpacketencodebase64)
			audioopuschunkedeffect.drop_chunk()

	else:
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
				if opusframesize != 0:
					var opuspacket = audioopuschunkedeffect.chunk_to_opus_packet(prefixbytes, audiosamples, $HBoxBigButtons/VBoxPTT/Denoise.button_pressed)
					recordedopuspackets.append(opuspacket)
					framecount = len(recordedopuspackets)
					$MQTTnetwork.transportaudiopacket(opuspacket, mqttpacketencodebase64)
					recordedopuspacketsMemSize += opuspacket.size()
				else:
					var rawpacket = var_to_bytes(audiosamples)
					recordedopuspacketsMemSize += rawpacket.size()
					$MQTTnetwork.transportaudiopacket(rawpacket, mqttpacketencodebase64)
				$HBoxPlaycount/GridContainer/FrameCount.text = str(framecount)
				$HBoxPlaycount/GridContainer/Totalbytes.text = str(recordedopuspacketsMemSize)
				var tm = framecount*audiosamplesize*1.0/audiosamplerate
				$HBoxPlaycount/GridContainer/Bytespersec.text = str(int(recordedopuspacketsMemSize/tm))

			else:
				if audioopuschunkedeffect != null:
					audioopuschunkedeffect.drop_chunk()
		
func endtalking():
	currentlytalking = false
	print("recordedpacketsMemSize ", recordedopuspacketsMemSize)
	$MQTTnetwork.transportaudiopacketjson({"framecount":len(recordedsamples)})
	print("Talked for ", (Time.get_ticks_msec() - talkingstarttime)*0.001, " seconds")

func _on_play_pressed():
	if audioeffectpitchshift != null:
		var speedup = $HBoxPlaycount/StreamSpeedup.value
		AudioServer.set_bus_effect_enabled(speechbusidx, audioeffectpitchshiftidx, (speedup != 1.0))
		SelfMember.get_node("AudioStreamPlayer").pitch_scale = speedup
		audioeffectpitchshift.pitch_scale = 1.0/speedup


	if recordedopuspackets:
		SelfMember.processheaderpacket(recordedheader.duplicate())
		SelfMember.opuspacketsbuffer = recordedopuspackets.duplicate()
	else:
		var lrecordedsamples = [ ]
		if $HBoxBigButtons/VBoxPTT/Denoise.button_pressed and audioopuschunkedeffect.opusframesize != 0:
			for s in recordedsamples:
				lrecordedsamples.append(audioopuschunkedeffect.chunk_resample_denoise(s, true))
		else:
			lrecordedsamples = recordedsamples.duplicate()
		SelfMember.processheaderpacket(recordedheader.duplicate())
		SelfMember.audiopacketsbuffer = lrecordedsamples




func _on_frame_duration_item_selected(_index):
	updatesamplerates()

func _on_resample_state_item_selected(_index):
	updatesamplerates()

func _on_audio_stream_microphone_finished():
	print("_on_audio_stream_microphone_finished")

func _on_option_button_item_selected(_index):
	updatesamplerates()

func _on_denoise_toggled(toggled_on):
	$HBoxMicTalk/HSliderVox.value = ($HBoxMicTalk.voiceprobthreshold if toggled_on else $HBoxMicTalk.voxthreshold)*$HBoxMicTalk/HSliderVox.max_value
	updatesamplerates()

func _on_base_64_toggled(toggled_on):
	updatesamplerates()
