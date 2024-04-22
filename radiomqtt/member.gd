extends Control

var audiostreamgeneratorplayback : AudioStreamGeneratorPlayback
var audiopacketsbuffer = [ ]
var isOpus = true

func _ready():
	$AudioStreamPlayer.play()
	audiostreamgeneratorplayback = $AudioStreamPlayer.get_stream_playback()
	$HandyOpusDecoder.createdecoder(48000, 480, 44100, 441); 

func setname(lname):
	set_name(lname)
	$Label.text = name

var DdropfourthpacketsFEC = false
func _process(_delta):
	$ColorRect.visible = (len(audiopacketsbuffer) > 0)
	while len(audiopacketsbuffer) > 0 and audiostreamgeneratorplayback.get_frames_available() > 441:
		var packet = audiopacketsbuffer.pop_front()
		var fec = 0
		if DdropfourthpacketsFEC and (len(audiopacketsbuffer) % 4) == 1:
			packet = audiopacketsbuffer[0]
			fec = 1
		var frames = $HandyOpusDecoder.decodeopuspacket(packet, fec) if isOpus else packet
		audiostreamgeneratorplayback.push_buffer(frames)
	
