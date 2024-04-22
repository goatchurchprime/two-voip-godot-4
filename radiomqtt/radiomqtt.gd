extends Control


@onready var microphoneidx = AudioServer.get_bus_index("MicrophoneBus")
var audiocaptureeffect : AudioEffectCapture
var audiospectrumeffect : AudioEffectSpectrumAnalyzer
var audiospectrumeffectinstance : AudioEffectSpectrumAnalyzerInstance

var recordedsamples = [ ]
var recordedopuspackets = [ ]
var recordedopuspacketsMemSize = 0

func _ready():
	assert ($AudioStreamMicrophone.bus == "MicrophoneBus")
	audiocaptureeffect = AudioServer.get_bus_effect(microphoneidx, 0)
	audiospectrumeffect = AudioServer.get_bus_effect(microphoneidx, 1)
	audiospectrumeffectinstance = AudioServer.get_bus_effect_instance(microphoneidx, 1)
	$AudioStreamMicrophone/HandyOpusEncoder.createencoder(44100, 441, 48000, 480); 

func _on_ptt_button_down():
	recordedsamples = [ ]
	recordedopuspackets = [ ]
	recordedopuspacketsMemSize = 0

func _process(_delta):
	var s0 = audiospectrumeffectinstance.get_magnitude_for_frequency_range(20, 500)
	$LowFreq.size.x = s0.x*1000 + 2
	var s1 = audiospectrumeffectinstance.get_magnitude_for_frequency_range(500, 2000)
	$MidFreq.size.x = s1.x*1000 + 2
	var s2 = audiospectrumeffectinstance.get_magnitude_for_frequency_range(2000, 20000)
	$HighFreq.size.x = s2.x*10000 + 2

	while audiocaptureeffect.get_frames_available() >= 441:
		var samples = audiocaptureeffect.get_buffer(441)
		if $PTT.button_pressed:
			recordedsamples.append(samples)
			if $OpusPackets.button_pressed:
				var opuspacket = $AudioStreamMicrophone/HandyOpusEncoder.encodeopuspacket(samples)
				recordedopuspackets.append(opuspacket)
				$MQTTnetwork.transportaudiopacket(opuspacket)
				recordedopuspacketsMemSize += len(opuspacket)


func _on_ptt_button_up():
	print("recordedpacketsMemSize ", recordedopuspacketsMemSize)
	var k = "frames: %d  mem: %d  time: %.01f" % [len(recordedsamples), recordedopuspacketsMemSize, len(recordedsamples)*0.01]
	$FrameCount.text = k
	
# use this to change the encoding of the packet list
func _on_opus_packets_toggled(toggled_on):
	if toggled_on:
		recordedopuspackets = [ ]
		recordedopuspacketsMemSize = 0
		for samples in recordedsamples:
			var opuspacket = $AudioStreamMicrophone/HandyOpusEncoder.encodeopuspacket(samples)
			recordedopuspackets.append(opuspacket)
			recordedopuspacketsMemSize += len(opuspacket)
		print("Encoded to opus to size ", recordedopuspacketsMemSize)
	else:
		recordedsamples = [ ]
		for opuspacket in recordedopuspackets:
			recordedsamples.append($MQTTnetwork/Members/Self/HandyOpusDecoder.decodeopuspacket(opuspacket, 0))
	

func _on_play_pressed():
	if recordedopuspackets:
		$MQTTnetwork/Members/Self.audiopacketsbuffer = recordedopuspackets.duplicate()
		$MQTTnetwork/Members/Self.isOpus = true 
	else:
		$MQTTnetwork/Members/Self.audiopacketsbuffer = recordedsamples.duplicate()
		$MQTTnetwork/Members/Self.isOpus = false 


