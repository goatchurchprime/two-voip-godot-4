extends Control

var audiostreamgeneratorplayback : AudioStreamGeneratorPlayback
var opuspacketsbuffer = [ ]
var audiopacketsbuffer = [ ]

const opussamplerate = 48000
var opusframesize = 480
const audiosamplerate = 44100
var audiosamplesize = 441

func _ready():
	$AudioStreamPlayer.play()
	audiostreamgeneratorplayback = $AudioStreamPlayer.get_stream_playback()
	$HandyOpusDecoder.createdecoder(opussamplerate, opusframesize, audiosamplerate, audiosamplesize); 
	print("createdecoder ", opussamplerate, " ", opusframesize, " ", audiosamplerate, " ", audiosamplesize)

func setname(lname):
	set_name(lname)
	$Label.text = name

func processheaderpacket(h):
	if opusframesize != h["opusframesize"] or audiosamplesize != h["audiosamplesize"]:
		opusframesize = h["opusframesize"]
		audiosamplesize = h["audiosamplesize"]
		if opusframesize != 0:
			$HandyOpusDecoder.createdecoder(opussamplerate, opusframesize, audiosamplerate, audiosamplesize); 
			print("createdecoder ", opussamplerate, " ", opusframesize, " ", audiosamplerate, " ", audiosamplesize)
		else:
			$HandyOpusDecoder.destroyallsamplers()

func receivemqttmessage(msg):
	if msg[0] == "{".to_ascii_buffer()[0]:
		var h = JSON.parse_string(msg.get_string_from_ascii())
		if h != null:
			print("audio json packet ", h)
			if h.has("opusframesize"):
				processheaderpacket(h)
	else:
		if opusframesize != 0:
			opuspacketsbuffer.push_back(msg)
		else:
			audiopacketsbuffer.push_back(msg)

func _process(_delta):
	$ColorRect.visible = (len(audiopacketsbuffer) > 0)
	while len(opuspacketsbuffer) != 0:
		var opuspacket = opuspacketsbuffer.pop_front()
		var samples = $HandyOpusDecoder.decodeopuspacket(opuspacket, 0)
		audiopacketsbuffer.push_back(samples)
	while len(audiopacketsbuffer) > 0 and audiostreamgeneratorplayback.get_frames_available() > len(audiopacketsbuffer[0]):
		var audiosamples = audiopacketsbuffer.pop_front()
		audiostreamgeneratorplayback.push_buffer(audiosamples)
	
