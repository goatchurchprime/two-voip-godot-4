extends Control

# AudioStreamPlayer can either be AudioStreamOpusChunked or AudioStreamGeneratorPlayback
var audiostreamopuschunked : AudioStreamOpusChunked
var audiostreamgeneratorplayback : AudioStreamGeneratorPlayback
var opuspacketsbuffer = [ ]
var audiopacketsbuffer = [ ]

func _ready():
	var audiostream = $AudioStreamPlayer.stream
	assert (audiostream.resource_local_to_scene)
	$AudioStreamPlayer.play()
	if audiostream.is_class("AudioStreamOpusChunked"):
		audiostreamopuschunked = audiostream
		#var audiostreamopyschunkedplayback = $AudioStreamPlayer.get_stream_playback()
		#audiostreamopyschunkedplayback.begin_resample()
	elif audiostream.is_class("AudioStreamGenerator"):
		audiostreamopuschunked = AudioStreamOpusChunked.new()
		audiostreamgeneratorplayback = $AudioStreamPlayer.get_stream_playback()
	else:
		printerr("Incorrect AudioStream type ", audiostream)

func setname(lname):
	set_name(lname)
	$Label.text = name

func processheaderpacket(h):
	print(h["audiosamplesize"],  "  ss  ", h["opusframesize"])
	#h["audiosamplesize"] = 400; h["audiosamplerate"] = 40000
	#print("setting audiosamplesize wrong on receive ", h)
	if audiostreamopuschunked.opusframesize != h["opusframesize"] or \
	   audiostreamopuschunked.audiosamplesize != h["audiosamplesize"]:
		audiostreamopuschunked.opusframesize = h["opusframesize"]
		audiostreamopuschunked.audiosamplesize = h["audiosamplesize"]
		audiostreamopuschunked.opussamplerate = h["opussamplerate"]
		audiostreamopuschunked.audiosamplerate = h["audiosamplerate"]
		if audiostreamopuschunked.opusframesize != 0:
			print("createdecoder ", audiostreamopuschunked.opussamplerate, " ", audiostreamopuschunked.opusframesize, " ", audiostreamopuschunked.audiosamplerate, " ", audiostreamopuschunked.audiosamplesize)
			#$AudioStreamPlayer.play()

func receivemqttmessage(msg):
	if msg[0] == "{".to_ascii_buffer()[0]:
		var h = JSON.parse_string(msg.get_string_from_ascii())
		if h != null:
			print("audio json packet ", h)
			if h.has("opusframesize"):
				processheaderpacket(h)
	else:
		if audiostreamopuschunked.opusframesize != 0:
			opuspacketsbuffer.push_back(msg)
		else:
			audiopacketsbuffer.push_back(msg)


func _process(_delta):
	$Node/ColorRect2.visible = (len(audiopacketsbuffer) + len(opuspacketsbuffer) > 0)
	if audiostreamgeneratorplayback == null:
		while audiostreamopuschunked.chunk_space_available():
			if len(audiopacketsbuffer) != 0:
				audiostreamopuschunked.push_audio_chunk(audiopacketsbuffer.pop_front())
			elif len(opuspacketsbuffer) != 0:
				audiostreamopuschunked.push_opus_packet(opuspacketsbuffer.pop_front(), 0, 0)
			else:
				break
		$Node/ColorRect.size.x = audiostreamopuschunked.queue_length_frames()/(50.0*881)*100

	else:
		while audiostreamgeneratorplayback.get_frames_available() > audiostreamopuschunked.audiosamplesize:
			if len(audiopacketsbuffer) != 0:
				audiostreamgeneratorplayback.push_buffer(audiopacketsbuffer.pop_front())
			elif len(opuspacketsbuffer) != 0:
				var audiochunk = audiostreamopuschunked.opus_packet_to_chunk(opuspacketsbuffer.pop_front(), 0, 0)
				audiostreamgeneratorplayback.push_buffer(audiochunk)
			else:
				break
