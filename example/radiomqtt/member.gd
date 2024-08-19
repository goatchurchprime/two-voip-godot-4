extends Control

# AudioStreamPlayer can either be AudioStreamOpusChunked or AudioStreamGeneratorPlayback
var audiostreamopuschunked # : AudioStreamOpusChunked
var audiostreamgeneratorplayback : AudioStreamGeneratorPlayback
var opuspacketsbuffer = [ ]
var audiopacketsbuffer = [ ]

var opusframesize : int = 0 # 960
var audiosamplesize : int = 0 # 882
var opussamplerate : int = 48000
var audiosamplerate : int = 44100
var prefixbyteslength : int = 0
var mqttpacketencodebase64 : bool = false

var chunkcount : int = 0
var audiobuffersize : int = 50*882

var audiosampleframetextureimage : Image
var audiosampleframetexture : ImageTexture

var audioserveroutputlatency = 0.015
var audiobufferregulationtime = 0.7
var audiobufferregulationpitch = 1.4

func _ready():
	var audiostream = $AudioStreamPlayer.stream
	if audiostream == null:
		if ClassDB.can_instantiate("AudioStreamOpusChunked"):
			print("Instantiating AudioStreamOpusChunked")
			audiostream = ClassDB.instantiate("AudioStreamOpusChunked")
		else:
			print("Instantiating AudioStreamGenerator")
			audiostream = AudioStreamGenerator.new()
		$AudioStreamPlayer.stream = audiostream
	else:
		assert (audiostream.resource_local_to_scene)

	$AudioStreamPlayer.play()
	if audiostream.is_class("AudioStreamOpusChunked"):
		audiostreamopuschunked = audiostream
		#var audiostreamopyschunkedplayback = $AudioStreamPlayer.get_stream_playback()
		#audiostreamopyschunkedplayback.begin_resample()
	elif audiostream.is_class("AudioStreamGenerator"):
		if ClassDB.can_instantiate("AudioStreamOpusChunked"):
			audiostreamopuschunked = ClassDB.instantiate("AudioStreamOpusChunked").new()
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
	prefixbyteslength = h["prefixbyteslength"]
	mqttpacketencodebase64 = (h.get("mqttpacketencoding") == "base64")
	chunkcount = 0
	if opusframesize != h["opusframesize"] or audiosamplesize != h["audiosamplesize"]:
		opusframesize = h["opusframesize"]
		audiosamplesize = h["audiosamplesize"]
		opussamplerate = h["opussamplerate"]
		audiosamplerate = h["audiosamplerate"]

		if audiostreamopuschunked != null:
			audiostreamopuschunked.opusframesize = opusframesize
			audiostreamopuschunked.audiosamplesize = audiosamplesize
			audiostreamopuschunked.opussamplerate = opussamplerate
			audiostreamopuschunked.audiosamplerate = audiosamplerate
			audiobuffersize = audiostreamopuschunked.audiosamplesize*audiostreamopuschunked.audiosamplechunks
			
			if opusframesize != 0:
				print("createdecoder ", opussamplerate, " ", opusframesize, " ", audiosamplerate, " ", audiosamplesize)
			#$AudioStreamPlayer.play()
		setupaudioshader()

	if opusframesize != 0 and audiostreamopuschunked == null:
		print("Compressed opus stream received that we cannot decompress")
	audioserveroutputlatency = AudioServer.get_output_latency()
	print("audioserveroutputlatency ", audioserveroutputlatency)

func setupaudioshader():
	var audiosampleframedata : PackedVector2Array
	audiosampleframedata.resize(audiosamplesize)
	audiosampleframetextureimage = Image.create_from_data(audiosamplesize, 1, false, Image.FORMAT_RGF, audiosampleframedata.to_byte_array())
	audiosampleframetexture = ImageTexture.create_from_image(audiosampleframetextureimage)
	assert (audiosampleframetexture != null)
	$Node/ColorRectBackground.material.set_shader_parameter("voice", audiosampleframetexture)
	$Node/ColorRectBackground.visible = false
	
func audiosamplestoshader(audiosamples):
	assert (len(audiosamples)== audiosamplesize)
	audiosampleframetextureimage.set_data(audiosamplesize, 1, false, Image.FORMAT_RGF, audiosamples.to_byte_array())
	audiosampleframetexture.update(audiosampleframetextureimage)

func receivemqttmessage(msg):
	if msg[0] == "{".to_ascii_buffer()[0]:
		var h = JSON.parse_string(msg.get_string_from_ascii())
		if h != null:
			print("audio json packet ", h)
			if h.has("opusframesize"):
				processheaderpacket(h)
	else:
		if mqttpacketencodebase64:
			msg = Marshalls.base64_to_raw(msg.get_string_from_ascii())
		if opusframesize != 0:
			opuspacketsbuffer.push_back(msg)
		else:
			audiopacketsbuffer.push_back(bytes_to_var(msg))


var timedelaytohide = 0.1
func _process(delta):
	$Node/ColorRect2.visible = (len(audiopacketsbuffer) + len(opuspacketsbuffer) > 0)
	if audiostreamgeneratorplayback == null:
		assert (audiostreamopuschunked != null)
		var chunkv1 = 0.0
		while audiostreamopuschunked.chunk_space_available():
			if len(audiopacketsbuffer) != 0:
				audiostreamopuschunked.push_audio_chunk(audiopacketsbuffer.pop_front())
			elif len(opuspacketsbuffer) != 0:
				const fec = 0
				audiostreamopuschunked.push_opus_packet(opuspacketsbuffer.pop_front(), prefixbyteslength, fec)
			else:
				break
			chunkcount += 1
			chunkv1 = audiostreamopuschunked.last_chunk_max()
		$Node/ColorRectBufferQueue.size.x = min(1.0, audiostreamopuschunked.queue_length_frames()*1.0/audiobuffersize)*size.x
		if chunkv1 != 0.0:
			var audiosamples = audiostreamopuschunked.read_last_chunk()
			audiosamplestoshader(audiosamples)
			$Node/ColorRectLoudness.size.x = $Node.size.x*chunkv1
			$Node/ColorRectBackground.visible = true
			timedelaytohide = 0.1
			
		var bufferlengthtime = audioserveroutputlatency + audiostreamopuschunked.queue_length_frames()*1.0/audiosamplerate
		if bufferlengthtime < audiobufferregulationtime:
			$AudioStreamPlayer.pitch_scale = 1.0
		else:
			var w = inverse_lerp(audiobufferregulationtime, audioserveroutputlatency + audiobuffersize/audiosamplerate, bufferlengthtime)
			$AudioStreamPlayer.pitch_scale = lerp(1.0, audiobufferregulationpitch, w)
	
	else:
		while audiostreamgeneratorplayback.get_frames_available() > audiosamplesize:
			if len(audiopacketsbuffer) != 0:
				audiostreamgeneratorplayback.push_buffer(audiopacketsbuffer.pop_front())
			elif len(opuspacketsbuffer) != 0:
				const fec = 0
				var audiochunk = audiostreamopuschunked.opus_packet_to_chunk(opuspacketsbuffer.pop_front(), prefixbyteslength, fec)
				audiostreamgeneratorplayback.push_buffer(audiochunk)
			else:
				break

	$AudioStreamPlayer.volume_db = $Node/Volume.value
	
	if timedelaytohide > 0.0:
		timedelaytohide -= delta
		if timedelaytohide <= 0.0:
			$Node/ColorRectBackground.visible = false
			$Node/ColorRectLoudness.size.x = 0
