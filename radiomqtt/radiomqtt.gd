extends Control


@onready var microphoneidx = AudioServer.get_bus_index("MicrophoneBus")

var audioeffectcapture : AudioEffectCapture = null
var audioopuschunkedeffect : AudioEffectOpusChunked

var recordedsamples = [ ]
var recordedopuspackets = [ ]
var recordedopuspacketsMemSize = 0
var recordedheader = { }

var prevviseme = 0
var visemes = [ "sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS", "nn", "RR", "aa", "E", "ih", "oh", "ou", "LA" ]

func _ready():
	assert ($AudioStreamMicrophone.bus == "MicrophoneBus")
	var audioeffectonmic : AudioEffect = AudioServer.get_bus_effect(microphoneidx, 0)
	if audioeffectonmic.is_class("AudioEffectOpusChunked"):
		audioopuschunkedeffect = audioeffectonmic
	elif audioeffectonmic.is_class("AudioEffectCapture"):
		audioeffectcapture = audioeffectonmic
		audioopuschunkedeffect = AudioEffectOpusChunked.new()
	updatesamplerates()
	for i in range(1, len(visemes)):
		var d = $HBoxVisemes/ColorRect.duplicate()
		d.get_node("Label").text = visemes[i]
		$HBoxVisemes.add_child(d)
		d.size.y = i*8
		print("dd ", d.size)

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
	var prefixbytes = PackedByteArray()
	if audioopuschunkedeffect.opusframesize != 0:
		recordedopuspackets = [ ]
		recordedopuspacketsMemSize = 0
		for s in recordedsamples:
			var opuspacket = audioopuschunkedeffect.chunk_to_opus_packet(prefixbytes, s, 0)
			recordedopuspackets.append(opuspacket)
			recordedopuspacketsMemSize += recordedopuspackets[-1].size() 
	var tm = len(recordedsamples)*audioopuschunkedeffect.audiosamplesize*1.0/audioopuschunkedeffect.audiosamplerate
	var k = "Smem: %d  time: %.01f  byte/s:%d" % [recordedopuspacketsMemSize, tm, int(recordedopuspacketsMemSize/tm)]
	if recordedopuspacketsMemSize != 0:
		$HBoxPlaycount/VBoxContainer/FrameCount.text = k


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
	var talking = $HBoxMicTalk/PTT.button_pressed
	if talking and not currentlytalking:
		starttalking()
	elif not talking and currentlytalking:
		endtalking()

	var prefixbytes = PackedByteArray()
	if audioeffectcapture == null:
		while audioopuschunkedeffect.chunk_available():
			var audiosamples = audioopuschunkedeffect.read_chunk()
			var chunkv1 = audioopuschunkedeffect.chunk_max()
			var chunkv2 = audioopuschunkedeffect.chunk_rms()
			var viseme = audioopuschunkedeffect.chunk_to_lipsync()
			if viseme != prevviseme:
				print(" viseme ", visemes[viseme], " ", chunkv2)
				prevviseme = viseme
			if viseme != -1:
				var vv = audioopuschunkedeffect.read_visemes();
				for i in range($HBoxVisemes.get_child_count()):
					$HBoxVisemes.get_child(i).size.y = int(50*vv[i])
				#print(" vvv ", vv[-2], "  ", vv[-1])
				
			$HBoxMicTalk.loudnessvalues(chunkv1, chunkv2)
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
	else:
		while audioeffectcapture.get_frames_available() > audioopuschunkedeffect.audiosamplesize:
			var audiosamples = audioeffectcapture.get_buffer(audioopuschunkedeffect.audiosamplesize)
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
				if audioopuschunkedeffect.opusframesize != 0:
					var opuspacket = audioopuschunkedeffect.chunk_to_opus_packet(prefixbytes, audiosamples, 0);
					recordedopuspackets.append(opuspacket)
					$MQTTnetwork.transportaudiopacket(opuspacket)
					recordedopuspacketsMemSize += opuspacket.size()
				else:
					$MQTTnetwork.transportaudiopacket(audiosamples)
			else:
				audioopuschunkedeffect.drop_chunk()
		
func endtalking():
	currentlytalking = false
	print("recordedpacketsMemSize ", recordedopuspacketsMemSize)
	var tm = len(recordedsamples)*audioopuschunkedeffect.audiosamplesize*1.0/audioopuschunkedeffect.audiosamplerate
	print(len(recordedsamples), " audioopuschunkedeffect.audiosamplesize ", audioopuschunkedeffect.audiosamplesize, "  ", audioopuschunkedeffect.audiosamplerate)
	var k = "mem: %d  time: %.01f  byte/s:%d" % [recordedopuspacketsMemSize, tm, int(recordedopuspacketsMemSize/tm)]
	$HBoxPlaycount/VBoxContainer/FrameCount.text = k
	$MQTTnetwork.transportaudiopacket(JSON.stringify({"framecount":len(recordedsamples)}).to_ascii_buffer())
	print("Talked for ", (Time.get_ticks_msec() - talkingstarttime)*0.001, " seconds")

func _on_play_pressed():
	if recordedopuspackets:
		$HBoxPlaycount/Self.processheaderpacket(recordedheader.duplicate())
		$HBoxPlaycount/Self.opuspacketsbuffer = recordedopuspackets.duplicate()
	else:
		var lrecordedsamples = [ ]
		lrecordedsamples = recordedsamples.duplicate()
		$HBoxPlaycount/Self.processheaderpacket(recordedheader.duplicate())
		$HBoxPlaycount/Self.audiopacketsbuffer = lrecordedsamples

func _on_frame_duration_item_selected(_index):
	updatesamplerates()

func _on_resample_state_item_selected(_index):
	updatesamplerates()

func _on_option_button_item_selected(_index):
	updatesamplerates()
