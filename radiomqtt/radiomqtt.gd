extends Control


@onready var microphoneidx = AudioServer.get_bus_index("MicrophoneBus")
var audiocaptureeffect : AudioEffectCapture
var audiospectrumeffect : AudioEffectSpectrumAnalyzer
var audiospectrumeffectinstance : AudioEffectSpectrumAnalyzerInstance



var recordedsamples = [ ]
var recordedopuspackets = [ ]
var recordedopuspacketsMemSize = 0
var recordedheader = { }

const opussamplerate = 48000
var opusframesize = 480
const audiosamplerate = 44100
var audiosamplesize = 441

func resamplerecordedsamples(orgsamples, newsamplesize):
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
			res.append(currentsample + s.slice(0, newsamplesize))
			currentsample = s.slice(newsamplesize)
	return res
			
func updatesamplerates():
	var frametimems = float($VBoxFrameLength/HBoxOpusFrame/FrameDuration.text)
	opusframesize = int(opussamplerate*frametimems/1000)
	var i = $VBoxFrameLength/HBoxAudioFrame/ResampleState.get_selected_id()
	if i == 0:  # uncompressed
		audiosamplesize = opusframesize
		opusframesize = 0
	elif i == 1: # Speexresample
		audiosamplesize = int(audiosamplerate*frametimems/1000)
	else:  # 441.1k as 48k fakery
		audiosamplesize = opusframesize
		
	$VBoxFrameLength/HBoxOpusFrame/LabFrameLength.text = "%d samples" % opusframesize
	$VBoxFrameLength/HBoxAudioFrame/LabFrameLength.text = "%d samples" % audiosamplesize
	if opusframesize != 0:
		$AudioStreamMicrophone/HandyOpusEncoder.createencoder(audiosamplerate, audiosamplesize, opussamplerate, opusframesize); 
	else:
		$AudioStreamMicrophone/HandyOpusEncoder.destroyallsamplers()
	recordedheader = { "opusframesize":opusframesize, "audiosamplesize":audiosamplesize }
	if len(recordedsamples) != 0 and len(recordedsamples[0]) != audiosamplesize:
		recordedsamples = resamplerecordedsamples(recordedsamples, audiosamplesize)
	if opusframesize != 0:
		recordedopuspackets = [ ]
		for s in recordedsamples:
			recordedopuspackets.append($AudioStreamMicrophone/HandyOpusEncoder.encodeopuspacket(s))
	

func _ready():
	assert ($AudioStreamMicrophone.bus == "MicrophoneBus")
	audiocaptureeffect = AudioServer.get_bus_effect(microphoneidx, 0)
	audiospectrumeffect = AudioServer.get_bus_effect(microphoneidx, 1)
	audiospectrumeffectinstance = AudioServer.get_bus_effect_instance(microphoneidx, 1)
	updatesamplerates()

func _on_ptt_button_down():
	recordedsamples = [ ]
	recordedopuspackets = [ ]
	recordedopuspacketsMemSize = 0
	$MQTTnetwork.transportaudiopacket(JSON.stringify(recordedheader))

func _process(_delta):
	var s0 = audiospectrumeffectinstance.get_magnitude_for_frequency_range(20, 500)
	$LowFreq.size.x = s0.x*1000 + 2
	var s1 = audiospectrumeffectinstance.get_magnitude_for_frequency_range(500, 2000)
	$MidFreq.size.x = s1.x*1000 + 2
	var s2 = audiospectrumeffectinstance.get_magnitude_for_frequency_range(2000, 20000)
	$HighFreq.size.x = s2.x*10000 + 2

	while audiocaptureeffect.get_frames_available() >= audiosamplesize:
		var audiosamples = audiocaptureeffect.get_buffer(audiosamplesize)
		if $PTT.button_pressed:
			recordedsamples.append(audiosamples)
			if opusframesize != 0:
				var opuspacket = $AudioStreamMicrophone/HandyOpusEncoder.encodeopuspacket(audiosamples)
				recordedopuspackets.append(opuspacket)
				$MQTTnetwork.transportaudiopacket(opuspacket)
				recordedopuspacketsMemSize += len(opuspacket)
			else:
				$MQTTnetwork.transportaudiopacket(audiosamples)
					

func _on_ptt_button_up():
	print("recordedpacketsMemSize ", recordedopuspacketsMemSize)
	var k = "frames: %d  mem: %d  time: %.01f" % [len(recordedsamples), recordedopuspacketsMemSize, len(recordedsamples)*audiosamplesize/audiosamplerate]
	$FrameCount.text = k
	$MQTTnetwork.transportaudiopacket(JSON.stringify({"framecount":len(recordedsamples)}))
	
	

func _on_play_pressed():
	if recordedopuspackets:
		$MQTTnetwork/Members/Self.processheaderpacket(recordedheader)
		$MQTTnetwork/Members/Self.opuspacketsbuffer = recordedopuspackets.duplicate()
	else:
		$MQTTnetwork/Members/Self.audiopacketsbuffer = recordedsamples.duplicate()

func _on_frame_duration_item_selected(index):
	updatesamplerates()

func _on_resample_state_item_selected(index):
	updatesamplerates()
