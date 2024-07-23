extends Control


@onready var microphoneidx = AudioServer.get_bus_index("MicrophoneBus")
@onready var SelfMember = $Members/Self

var audioeffectcapture : AudioEffectCapture = null
var audioopuschunkedeffect # : AudioEffectOpusChunked

# values to use when AudioEffectOpusChunked cannot be instantiated
var frametimems : float 
var opusbitrate : int
var opusframesize : int = 0
var audiosamplerate : int = 44100
var opussamplerate : int = 48000
var audiosamplesize : int

var recordedsamples = [ ]
var recordedopuspackets = [ ]
var recordedopuspacketsMemSize = 0
var recordedheader = { }

var audiosampleframedata : PackedByteArray
var audiosampleframedata2 : PackedVector2Array
var audiosampleframetextureimage : Image
var audiosampleframetexture : ImageTexture
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

	updatesamplerates()
	for i in range(1, len(visemes)):
		var d = $HBoxVisemes/ColorRect.duplicate()
		d.get_node("Label").text = visemes[i]
		$HBoxVisemes.add_child(d)
		d.size.y = i*8
	$HBoxMosquitto/FriendlyName.text = possibleusernames.pick_random()

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
		audioopuschunkedeffect.opusbitrate = opusbitrate
		audioopuschunkedeffect.opusframesize = opusframesize
		audiosamplerate = audioopuschunkedeffect.audiosamplerate
		opussamplerate = audioopuschunkedeffect.opussamplerate
	opusframesize = int(opussamplerate*frametimems/1000.0)
	
	var i = $VBoxFrameLength/HBoxAudioFrame/ResampleState.get_selected_id()
	if i == 0:  # uncompressed
		recordedopuspackets = [ ]
		audiosamplesize = int(audiosamplerate*frametimems/1000)
		opusframesize = 0
		if audioopuschunkedeffect != null:
			audioopuschunkedeffect.opusframesize = 0
	elif i == 1: # Speexresample
		audiosamplesize = int(audiosamplerate*frametimems/1000)
	else:  # 441.1k as 48k fakery
		audiosamplesize = opusframesize
	if audioopuschunkedeffect != null:
		audioopuschunkedeffect.audiosamplesize = audiosamplesize
				
	$VBoxFrameLength/HBoxOpusFrame/LabFrameLength.text = "%d samples at 48KHz" % opusframesize
	$VBoxFrameLength/HBoxAudioFrame/LabFrameLength.text = "%d samples at 44.1KHz" % audiosamplesize
	recordedheader = { "opusframesize":opusframesize, "audiosamplesize":audiosamplesize, "opussamplerate":opussamplerate, "audiosamplerate":audiosamplerate }
	if len(recordedsamples) != 0 and len(recordedsamples[0]) != audiosamplesize:
		recordedsamples = resamplerecordedsamples(recordedsamples, audiosamplesize)
	var prefixbytes = PackedByteArray()
	recordedopuspacketsMemSize = 0
	if opusframesize != 0:
		recordedopuspackets = [ ]
		for s in recordedsamples:
			var opuspacket = audioopuschunkedeffect.chunk_to_opus_packet(prefixbytes, s, 0)
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
	audiosampleframedata = PackedByteArray()
	audiosampleframedata.resize(audiosamplesize)
	for j in range(audiosamplesize):
		audiosampleframedata.set(j, (j*10)%256)

	audiosampleframedata2 = PackedVector2Array()
	audiosampleframedata2.resize(audiosamplesize)
	for j in range(audiosamplesize):
		audiosampleframedata2.set(j, Vector2(-0.5,0.9) if (j%10)<5 else Vector2(0.6,0.1))

	audiosampleframetextureimage = Image.create_from_data(audiosamplesize, 1, false, Image.FORMAT_RGF, audiosampleframedata2.to_byte_array())
	audiosampleframetexture = ImageTexture.create_from_image(audiosampleframetextureimage)
	assert (audiosampleframetexture != null)
	$HBoxMicTalk/HSliderVox/ColorRectBackground.material.set_shader_parameter("voice", audiosampleframetexture)
	
func audiosamplestoshader(audiosamples):
	assert (len(audiosamples)== audiosamplesize)
	for j in range(audiosamplesize):
		var v = audiosamples[j]
		audiosampleframedata.set(j, int((v.x + 1.0)/2.0*255))
	audiosampleframetextureimage.set_data(audiosamplesize, 1, false, Image.FORMAT_RGF, audiosamples.to_byte_array())
	audiosampleframetexture.update(audiosampleframetextureimage)

	#$HBoxMicTalk/HSliderVox/ColorRectBackground.material.set_shader_parameter("voice", audiosampleframetexture)

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
	$MQTTnetwork.transportaudiopacket(JSON.stringify(recordedheader).to_ascii_buffer())
	talkingstarttime = Time.get_ticks_msec()


func _on_mic_working_toggled(toggled_on):
	print("_on_mic_working_toggled ", $AudioStreamMicrophone.playing, " to ", toggled_on)
	if toggled_on:
		if not $AudioStreamMicrophone.playing:
			$AudioStreamMicrophone.play()
	else:
		if $AudioStreamMicrophone.playing:
			$AudioStreamMicrophone.stop()

func _process(_delta):
	var talking = $HBoxBigButtons/PTT.button_pressed
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
		while audioopuschunkedeffect.chunk_available():
			var audiosamples = audioopuschunkedeffect.read_chunk()
			audiosamplestoshader(audiosamples)
			var chunkv1 = audioopuschunkedeffect.chunk_max()
			var chunkv2 = audioopuschunkedeffect.chunk_rms()
			var viseme = -1 # audioopuschunkedeffect.chunk_to_lipsync()
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
				
			$HBoxMicTalk.loudnessvalues(chunkv1, chunkv2)
			if currentlytalking:
				recordedsamples.append(audiosamples)
				if audioopuschunkedeffect.opusframesize != 0:
					var opuspacket = audioopuschunkedeffect.pop_opus_packet(prefixbytes)
					recordedopuspackets.append(opuspacket)
					$MQTTnetwork.transportaudiopacket(opuspacket)
					$HBoxPlaycount/GridContainer/FrameCount.text = str(len(recordedopuspackets))
					recordedopuspacketsMemSize += opuspacket.size()
					$HBoxPlaycount/GridContainer/Totalbytes.text = str(recordedopuspacketsMemSize)
					var tm = len(recordedopuspackets)*audioopuschunkedeffect.audiosamplesize*1.0/audioopuschunkedeffect.audiosamplerate
					$HBoxPlaycount/GridContainer/Bytespersec.text = str(int(recordedopuspacketsMemSize/tm))
				else:
					audioopuschunkedeffect.drop_chunk()
					$MQTTnetwork.transportaudiopacket(var_to_bytes(audiosamples))
			else:
				audioopuschunkedeffect.drop_chunk()
	else:
		while audioeffectcapture.get_frames_available() > audiosamplesize:
			var audiosamples = audioeffectcapture.get_buffer(audiosamplesize)
			audiosamplestoshader(audiosamples)
			var chunkv1 = 0.0
			var schunkv2 = 0.0
			for i in range(len(audiosamples)):
				var v = audiosamples[i]
				var vm = max(abs(v.x), abs(v.y))
				if vm > chunkv1:
					chunkv1 = vm
				schunkv2 = v.x*v.x + v.y*v.y
			var chunkv2 = sqrt(schunkv2/(len(audiosamples)*2))
			$HBoxMicTalk.loudnessvalues(chunkv1, chunkv2)
			if currentlytalking:
				recordedsamples.append(audiosamples)
				var framecount = len(recordedsamples)
				if opusframesize != 0:
					var opuspacket = audioopuschunkedeffect.chunk_to_opus_packet(prefixbytes, audiosamples, 0);
					recordedopuspackets.append(opuspacket)
					framecount = len(recordedopuspackets)
					$MQTTnetwork.transportaudiopacket(opuspacket)
					recordedopuspacketsMemSize += opuspacket.size()
				else:
					var rawpacket = var_to_bytes(audiosamples)
					recordedopuspacketsMemSize += rawpacket.size()
					$MQTTnetwork.transportaudiopacket(rawpacket)
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
	$MQTTnetwork.transportaudiopacket(JSON.stringify({"framecount":len(recordedsamples)}).to_ascii_buffer())
	print("Talked for ", (Time.get_ticks_msec() - talkingstarttime)*0.001, " seconds")

func _on_play_pressed():
	if recordedopuspackets:
		SelfMember.processheaderpacket(recordedheader.duplicate())
		SelfMember.opuspacketsbuffer = recordedopuspackets.duplicate()
	else:
		var lrecordedsamples = [ ]
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
