extends Control


@onready var microphoneidx = AudioServer.get_bus_index("MicrophoneBus")
var audiocaptureeffect : AudioEffectCapture
var audiospectrumeffect : AudioEffectSpectrumAnalyzer
var audiospectrumeffectinstance : AudioEffectSpectrumAnalyzerInstance
var audiostreamgeneratorplayback : AudioStreamGeneratorPlayback

func _ready():
	assert ($AudioStreamMicrophone.bus == "MicrophoneBus")
	audiocaptureeffect = AudioServer.get_bus_effect(microphoneidx, 0)
	audiospectrumeffect = AudioServer.get_bus_effect(microphoneidx, 1)
	audiospectrumeffectinstance = AudioServer.get_bus_effect_instance(microphoneidx, 1)
	$AudioStreamGenerator.play()
	audiostreamgeneratorplayback = $AudioStreamGenerator.get_stream_playback()

var recordedpackets = [ ]
var recordedpacketsMemSize = 0
var recordedpacketsI = 0

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
			if $OpusPackets.button_pressed:
				recordedpackets.append($HandyOpusNode.encode_opus_packet(samples))
				$MQTTnetwork.transportaudiopacket(recordedpackets[-1])
			else:
				recordedpackets.append(samples)
			recordedpacketsMemSize += len(recordedpackets[-1])

	if $Play.button_pressed:
		while recordedpacketsI < len(recordedpackets) and audiostreamgeneratorplayback.get_frames_available() > 441:
			var packet = recordedpackets[recordedpacketsI]
			recordedpacketsI += 1
			if $OpusPackets.button_pressed:
				audiostreamgeneratorplayback.push_buffer($HandyOpusNode.decode_opus_packet(packet))
			else:
				audiostreamgeneratorplayback.push_buffer(packet)
		if recordedpacketsI == len(recordedpackets):
			$Play.button_pressed = false
			

func _on_ptt_button_down():
	recordedpackets = [ ]
	recordedpacketsMemSize = 0

func _on_ptt_button_up():
	print("recordedpacketsMemSize ", recordedpacketsMemSize)
	var k = "frames: %d  mem: %d  time: %.01f" % [len(recordedpackets), recordedpacketsMemSize, len(recordedpackets)*0.01]
	$FrameCount.text = k
	
# use this to change the encoding of the packet list
func _on_opus_packets_toggled(toggled_on):
	var rs = [ ]
	recordedpacketsMemSize = 0
	if toggled_on:
		for samples in recordedpackets:
			rs.append($HandyOpusNode.encode_opus_packet(samples))
			recordedpacketsMemSize += len(rs[-1])
		print("Encoded to opus to size ", recordedpacketsMemSize)
	else:
		for packet in recordedpackets:
			rs.append($HandyOpusNode.decode_opus_packet(packet))
			recordedpacketsMemSize += len(rs[-1])
		print("Decoded from opus to size ", recordedpacketsMemSize)
	recordedpackets = rs
	

func _on_play_toggled(toggled_on):
	if toggled_on:
		$OpusPackets.disabled = true
		$PTT.disabled = true
		recordedpacketsI = 0
	else:
		$OpusPackets.disabled = false
		$PTT.disabled = false

