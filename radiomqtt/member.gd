extends Control

var audiostreamgeneratorplayback : AudioStreamGeneratorPlayback
var audiostreamopuschunked : AudioStream
var opuspacketsbuffer = [ ]
var audiopacketsbuffer = [ ]

var opussamplerate = 48000
var opusframesize = 480
var audiosamplerate = 44100
var audiosamplesize = 441

func _ready():
	$AudioStreamPlayer.play()
	$AudioStreamPlayer2.play()
	audiostreamgeneratorplayback = $AudioStreamPlayer.get_stream_playback()
	$HandyOpusDecoder.createdecoder(opussamplerate, opusframesize, audiosamplerate, audiosamplesize); 
	audiostreamopuschunked = $AudioStreamPlayer2.stream
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
		audiostreamopuschunked.opusframesize = h["opusframesize"]
		audiostreamopuschunked.audiosamplesize = h["audiosamplesize"]
		audiostreamopuschunked.opussamplerate = h["opussamplerate"]
		audiostreamopuschunked.audiosamplerate = h["audiosamplerate"]
		if opusframesize != 0:
			$HandyOpusDecoder.createdecoder(opussamplerate, opusframesize, audiosamplerate, audiosamplesize); 
			print("createdecoder ", opussamplerate, " ", opusframesize, " ", audiosamplerate, " ", audiosamplesize)
			#$AudioStreamPlayer.play()
			$AudioStreamPlayer2.play()
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
	while audiostreamopuschunked.chunk_space_available():
		if len(audiopacketsbuffer) != 0:
			audiostreamopuschunked.push_audio_chunk(audiopacketsbuffer.pop_front())
		elif len(opuspacketsbuffer) != 0:
			audiostreamopuschunked.push_opus_packet(opuspacketsbuffer.pop_front(), 0, 0)
		else:
			break

var D = 0
func D_process(_delta):
	D += 1
	$ColorRect.visible = (len(audiopacketsbuffer) > 0)
	#print("audiostreamgeneratorplayback", audiostreamgeneratorplayback.get_buffer_length())
	while len(audiopacketsbuffer) > 0 and audiostreamgeneratorplayback.get_frames_available() > len(audiopacketsbuffer[0]):
		var audiosamples = audiopacketsbuffer.pop_front()
		#print(D, " ", len(audiosamples), " samples pushed into available ", audiostreamgeneratorplayback.get_frames_available(), "  ", audiostreamgeneratorplayback.get_skips())
		audiostreamgeneratorplayback.push_buffer(audiosamples)
	while len(opuspacketsbuffer) > 0 and audiostreamgeneratorplayback.get_frames_available() > audiosamplesize:
		var opuspacket = opuspacketsbuffer.pop_front()
		$HandyOpusDecoder.decodeopuspacketSP(opuspacket, 0, audiostreamgeneratorplayback)

