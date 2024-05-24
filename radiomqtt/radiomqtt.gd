extends Control


@onready var microphoneidx = AudioServer.get_bus_index("MicrophoneBus")

var audioopuschunkedeffect : AudioEffectOpusChunked
var audiospectrumeffect : AudioEffectSpectrumAnalyzer
var audiospectrumeffectinstance : AudioEffectSpectrumAnalyzerInstance

var recordedsamples = [ ]
var recordedopuspackets = [ ]
var recordedopuspacketsMemSize = 0
var recordedheader = { }

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
	var frametimems = float($VBoxFrameLength/HBoxOpusFrame/FrameDuration.text)
	audioopuschunkedeffect.opusbitrate = int($VBoxFrameLength/HBoxBitRate/BitRate.text)
	audioopuschunkedeffect.opusframesize = int(audioopuschunkedeffect.opussamplerate*frametimems/1000)
	var i = $VBoxFrameLength/HBoxAudioFrame/ResampleState.get_selected_id()
	if i == 0:  # uncompressed
		audioopuschunkedeffect.audiosamplesize = int(audioopuschunkedeffect.audiosamplerate*frametimems/1000)
		recordedopuspackets = [ ]
		audioopuschunkedeffect.opusframesize = 0
	elif i == 1: # Speexresample
		audioopuschunkedeffect.audiosamplesize = int(audioopuschunkedeffect.audiosamplerate*frametimems/1000)
	else:  # 441.1k as 48k fakery
		audioopuschunkedeffect.audiosamplesize = audioopuschunkedeffect.opusframesize
		
	$VBoxFrameLength/HBoxOpusFrame/LabFrameLength.text = "%d samples" % audioopuschunkedeffect.opusframesize
	$VBoxFrameLength/HBoxAudioFrame/LabFrameLength.text = "%d samples" % audioopuschunkedeffect.audiosamplesize
	recordedheader = { "opusframesize":audioopuschunkedeffect.opusframesize, "audiosamplesize":audioopuschunkedeffect.audiosamplesize, "opussamplerate":audioopuschunkedeffect.opussamplerate, "audiosamplerate":audioopuschunkedeffect.audiosamplerate }
	if len(recordedsamples) != 0 and len(recordedsamples[0]) != audioopuschunkedeffect.audiosamplesize:
		recordedsamples = resamplerecordedsamples(recordedsamples, audioopuschunkedeffect.audiosamplesize)
	var prefixbytes = PackedByteArray([0])
	if audioopuschunkedeffect.opusframesize != 0:
		recordedopuspackets = [ ]
		recordedopuspacketsMemSize = 0
		prefixbytes.set(0,99)
		for s in recordedsamples:
			var opuspacket = audioopuschunkedeffect.chunk_to_opus_packet(prefixbytes, s, 0)
			print(opuspacket[0])
			recordedopuspackets.append(opuspacket.slice(1))
			recordedopuspacketsMemSize += recordedopuspackets[-1].size() 
	var tm = len(recordedsamples)*audioopuschunkedeffect.audiosamplesize*1.0/audioopuschunkedeffect.audiosamplerate
	var k = "Smem: %d  time: %.01f  byte/s:%d" % [recordedopuspacketsMemSize, tm, int(recordedopuspacketsMemSize/tm)]
	if recordedopuspacketsMemSize != 0:
		$FrameCount.text = k

func _ready():
	assert ($AudioStreamMicrophone.bus == "MicrophoneBus")
	audioopuschunkedeffect = AudioServer.get_bus_effect(microphoneidx, 0)
	audiospectrumeffect = AudioServer.get_bus_effect(microphoneidx, 1)
	audiospectrumeffectinstance = AudioServer.get_bus_effect_instance(microphoneidx, 1)
	updatesamplerates()

var currentlytalking = false
var talkingstarttime = 0
func starttalking():
	currentlytalking = true
	recordedsamples = [ ]
	recordedopuspackets = [ ]
	recordedopuspacketsMemSize = 0
	print("start talking")
	$MQTTnetwork.transportaudiopacket(JSON.stringify(recordedheader).to_ascii_buffer())
	talkingstarttime = Time.get_ticks_msec()

func _process(_delta):
	var s0 = audiospectrumeffectinstance.get_magnitude_for_frequency_range(20, 500)
	$LowFreq.size.x = s0.x*1000 + 2
	var s1 = audiospectrumeffectinstance.get_magnitude_for_frequency_range(500, 2000)
	$MidFreq.size.x = s1.x*1000 + 2
	var s2 = audiospectrumeffectinstance.get_magnitude_for_frequency_range(2000, 20000)
	$HighFreq.size.x = s2.x*10000 + 2
	
	var talking = $PTT.button_pressed or ($VoxDetector/EnableVox.button_pressed and $VoxDetector/ColorRectThreshold.visible)
	if talking and not currentlytalking:
		starttalking()
	elif not talking and currentlytalking:
		endtalking()

	var prefixbytes = PackedByteArray()
	while audioopuschunkedeffect.chunk_available():
		var audiosamples = audioopuschunkedeffect.read_chunk()
		var a = audioopuschunkedeffect.chunk_max()
		$NoiseGraph.addwindow(a)
		$VoxDetector.addwindow(a)
		if currentlytalking:
			recordedsamples.append(audiosamples)
			if audioopuschunkedeffect.opusframesize != 0:
				var opuspacket = audioopuschunkedeffect.pop_opus_packet(prefixbytes)
				recordedopuspackets.append(opuspacket)
				$MQTTnetwork.transportaudiopacket(opuspacket)
				recordedopuspacketsMemSize += opuspacket.size()
			else:
				audioopuschunkedeffect.drop_chunk()
				$MQTTnetwork.transportaudiopacket(audiosamples)
		else:
			audioopuschunkedeffect.drop_chunk()
	
func endtalking():
	currentlytalking = false
	print("recordedpacketsMemSize ", recordedopuspacketsMemSize)
	var tm = len(recordedsamples)*audioopuschunkedeffect.audiosamplesize*1.0/audioopuschunkedeffect.audiosamplerate
	print(len(recordedsamples), " audioopuschunkedeffect.audiosamplesize ", audioopuschunkedeffect.audiosamplesize, "  ", audioopuschunkedeffect.audiosamplerate)
	var k = "mem: %d  time: %.01f  byte/s:%d" % [recordedopuspacketsMemSize, tm, int(recordedopuspacketsMemSize/tm)]
	$FrameCount.text = k
	$MQTTnetwork.transportaudiopacket(JSON.stringify({"framecount":len(recordedsamples)}).to_ascii_buffer())
	print("Talked for ", (Time.get_ticks_msec() - talkingstarttime)*0.001, " seconds")

#var D = 0
#func _input(event):
#	if event is InputEventKey:
#		D += 1
#		print(D, " ", event.pressed, " ", event.keycode)

func _on_play_pressed():
	if recordedopuspackets:
		$MQTTnetwork/Members/Self.processheaderpacket(recordedheader.duplicate())
		$MQTTnetwork/Members/Self.opuspacketsbuffer = recordedopuspackets.duplicate()
	else:
		var lrecordedsamples = [ ]
		if false:  # inline resample uncompressed case
			var Dresampler = HandyOpusNode.new()
			#Dresampler.createdecoder(48000, 0, 44100, 441); 
			Dresampler.createdecoder(44100, 0, 20000, 200); 
			print("Using local Dresampler")
			for audiosample in recordedsamples:
				lrecordedsamples.append(Dresampler.resampledecodedopuspacket(audiosample))
			Dresampler.destroyallsamplers()
		else:
			lrecordedsamples = recordedsamples.duplicate()
		$MQTTnetwork/Members/Self.audiopacketsbuffer = lrecordedsamples

func _on_frame_duration_item_selected(index):
	updatesamplerates()

func _on_resample_state_item_selected(index):
	updatesamplerates()

func _on_option_button_item_selected(index):
	updatesamplerates()
