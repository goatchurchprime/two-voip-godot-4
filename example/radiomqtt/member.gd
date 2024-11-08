extends Control

# AudioStreamPlayer can either be AudioStreamOpusChunked or AudioStreamGeneratorPlayback
var audiostreamopuschunked # : AudioStreamOpusChunked
var audiostreamgeneratorplayback : AudioStreamGeneratorPlayback
var opuspacketsbuffer = [ ]
var resampledpacketsbuffer = null
var audiopacketsbuffer = [ ]

var opusframesize : int = 0 # 960
var audiosamplesize : int = 0 # 882
var opussamplerate : int = 48000
var audiosamplerate : int = 44100
var mix_rate : int = 44100
var prefixbyteslength : int = 0
var mqttpacketencodebase64 : bool = false

var chunkcount : int = 0
var audiobuffersize : int = 50*882

var audiosampleframetextureimage : Image
var audiosampleframetexture : ImageTexture

var audioserveroutputlatency = 0.015
var audiobufferregulationtime = 0.7
var audiobufferregulationpitch = 1.4

var playbackstarttime = -1.0

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
		assert (audiostream.resource_local_to_scene, "AudioStreamGenerator must be local_to_scene")

	$AudioStreamPlayer.play()
	if audiostream.is_class("AudioStreamOpusChunked"):
		audiostreamopuschunked = audiostream
		#var audiostreamopyschunkedplayback = $AudioStreamPlayer.get_stream_playback()
		#audiostreamopyschunkedplayback.begin_resample()
	elif audiostream.is_class("AudioStreamGenerator"):
		if ClassDB.can_instantiate("AudioStreamOpusChunked"):
			audiostreamopuschunked = ClassDB.instantiate("AudioStreamOpusChunked")
		audiostreamgeneratorplayback = $AudioStreamPlayer.get_stream_playback()
	else:
		printerr("Incorrect AudioStream type ", audiostream)

func setname(lname):
	set_name(lname)
	$Label.text = name

func processheaderpacket(h):
	var radiomqtt = get_node("../..")
	audiosamplerate = radiomqtt.get_node("VBoxPlayback/HBoxStream/OutSampleRate").value
	mix_rate = radiomqtt.get_node("VBoxPlayback/HBoxStream/MixRate").value
	prefixbyteslength = h["prefixbyteslength"]
	mqttpacketencodebase64 = (h.get("mqttpacketencoding") == "base64")
	chunkcount = 0
	if opusframesize != h["opusframesize"] or opussamplerate != h["opussamplerate"] or \
			((audiostreamopuschunked != null) and (audiostreamopuschunked.audiosamplesize != audiosamplesize or audiostreamopuschunked.audiosamplerate != audiosamplerate or \
			audiostreamopuschunked.mix_rate != mix_rate)):
		opusframesize = h["opusframesize"]
		opussamplerate = h["opussamplerate"]
		var frametimems = opusframesize*1000.0/opussamplerate
		audiosamplesize = int(audiosamplerate*frametimems/1000.0)
		resampledpacketsbuffer = null
		if audiostreamopuschunked != null:
			audiostreamopuschunked.opusframesize = opusframesize
			audiostreamopuschunked.opussamplerate = opussamplerate
			audiostreamopuschunked.audiosamplesize = audiosamplesize
			audiostreamopuschunked.audiosamplerate = audiosamplerate
			audiostreamopuschunked.mix_rate = mix_rate
			audiobuffersize = audiostreamopuschunked.audiosamplesize*audiostreamopuschunked.audiosamplechunks
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
	assert (audiosamplesize != 0)
	audiosampleframetextureimage = Image.create_from_data(audiosamplesize, 1, false, Image.FORMAT_RGF, audiosampleframedata.to_byte_array())
	audiosampleframetexture = ImageTexture.create_from_image(audiosampleframetextureimage)
	assert (audiosampleframetexture != null)
	$Node/ColorRectBackground.material.set_shader_parameter("voice", audiosampleframetexture)
	$Node/ColorRectBackground.visible = false
	
func audiosamplestoshader(audiosamples):
	assert (len(audiosamples)== audiosamplesize)
	audiosampleframetextureimage.set_data(audiosamplesize, 1, false, Image.FORMAT_RGF, audiosamples.to_byte_array())
	audiosampleframetexture.update(audiosampleframetextureimage)

func receivemqttaudiometa(msg):
	assert (msg[0] == "{".to_ascii_buffer()[0])
	var h = JSON.parse_string(msg.get_string_from_ascii())
	if h != null:
		print("audio json packet ", h)
		if h.has("opusframesize"):
			processheaderpacket(h)
			
func receivemqttaudio(msg):
	if mqttpacketencodebase64:
		msg = Marshalls.base64_to_raw(msg.get_string_from_ascii())
	if opusframesize != 0:
		opuspacketsbuffer.push_back(msg)
	else:
		var a = bytes_to_var(msg)
		assert (a != null)
		if a != null:
			audiopacketsbuffer.push_back(a)


var timedelaytohide = 0.1
func _process(delta):
	$Node/ColorRect2.visible = (len(audiopacketsbuffer) + len(opuspacketsbuffer) > 0)
	if audiostreamgeneratorplayback == null:
		assert (audiostreamopuschunked != null)
		var chunkv1 = 0.0
		while audiostreamopuschunked.chunk_space_available():
			if resampledpacketsbuffer != null and len(resampledpacketsbuffer) != 0:
				#audiostreamopuschunked.push_audio_chunk(resampledpacketsbuffer.pop_front())
				var audiochunk = audiostreamopuschunked.resample_chunk(resampledpacketsbuffer.pop_front())
				audiostreamopuschunked.push_audio_chunk(audiochunk)
			elif len(audiopacketsbuffer) != 0:
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
			
		if playbackstarttime != -1.0 and audiostreamopuschunked.queue_length_frames() == 0:
			var playbackduration = Time.get_ticks_msec() - playbackstarttime + audioserveroutputlatency
			playbackstarttime = -1.0
			print("--- Playback time: ", playbackduration/1000.0)

		var bufferlengthtime = audioserveroutputlatency + audiostreamopuschunked.queue_length_frames()*1.0/audiosamplerate
		if audiobufferregulationtime == 3600:
			pass
		elif bufferlengthtime < audiobufferregulationtime:
			$AudioStreamPlayer.pitch_scale = 1.0
		else:
			var w = inverse_lerp(audiobufferregulationtime, audioserveroutputlatency + audiobuffersize/audiosamplerate, bufferlengthtime)
			$AudioStreamPlayer.pitch_scale = lerp(1.0, audiobufferregulationpitch, w)
#show some view of the speedup rate on here

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
