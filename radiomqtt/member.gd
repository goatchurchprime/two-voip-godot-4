extends Control

var audiostreamgeneratorplayback : AudioStreamGeneratorPlayback
var opuspacketsbuffer = [ ]
var audiopacketsbuffer = [ ]

var opussamplerate = 48000
var opusframesize = 480
var audiosamplerate = 44100
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
	print(h["audiosamplesize"],  "  ss  ", h["opusframesize"])
	#h["audiosamplesize"] = 400; h["audiosamplerate"] = 40000
	#print("setting audiosamplesize wrong on receive ", h)
	if opusframesize != h["opusframesize"] or audiosamplesize != h["audiosamplesize"]:
		opusframesize = h["opusframesize"]
		audiosamplesize = h["audiosamplesize"]
		opussamplerate = h["opussamplerate"]
		audiosamplerate = h["audiosamplerate"]
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

var D = 0
func _process(_delta):
	D += 1
	$ColorRect.visible = (len(audiopacketsbuffer) > 0)
	while len(opuspacketsbuffer) != 0:
		var opuspacket = opuspacketsbuffer.pop_front()
		var samples = $HandyOpusDecoder.decodeopuspacket(opuspacket, 0)
		audiopacketsbuffer.push_back(samples)
	while len(audiopacketsbuffer) > 0 and audiostreamgeneratorplayback.get_frames_available() > len(audiopacketsbuffer[0]):
		var audiosamples = audiopacketsbuffer.pop_front()
		#print(D, " ", len(audiosamples), " samples pushed into available ", audiostreamgeneratorplayback.get_frames_available(), "  ", audiostreamgeneratorplayback.get_skips())
		audiostreamgeneratorplayback.push_buffer(audiosamples)

