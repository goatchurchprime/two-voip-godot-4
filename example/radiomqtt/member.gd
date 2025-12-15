extends Control

var opuspacketsbuffer = [ ]
@onready var twovoipspeaker = $AudioStreamPlayer/TwoVoipSpeaker

var audiosampleframetextureimage : Image
var audiosampleframetexture : ImageTexture

func _ready():
	twovoipspeaker.connect("sigvoicespeedrate", on_sigvoicespeedrate)
	twovoipspeaker.connect("sigvoicestartstream", on_sigvoicestartstream)

func on_sigvoicespeedrate(audiobufferpitchscale):
	print("aaa ", audiobufferpitchscale)

func setname(lname):
	set_name(lname)
	$Label.text = name

func setupaudioshader(width):
	if audiosampleframetextureimage == null or audiosampleframetextureimage.get_size().x != width:
		var audiosampleframedata : PackedVector2Array
		audiosampleframedata.resize(width)
		audiosampleframetextureimage = Image.create_from_data(width, 1, false, Image.FORMAT_RGF, audiosampleframedata.to_byte_array())
		audiosampleframetexture = ImageTexture.create_from_image(audiosampleframetextureimage)
		assert (audiosampleframetexture != null)
		$Node/ColorRectBackground.material.set_shader_parameter("voice", audiosampleframetexture)
		$Node/ColorRectBackground.visible = false
	
func audiosamplestoshader(audiosamples):
	assert (len(audiosamples)== $AudioStreamPlayer/TwoVoipSpeaker.audiostreamopuschunked.audiosamplesize)
	audiosampleframetextureimage.set_data($AudioStreamPlayer/TwoVoipSpeaker.audiostreamopuschunked.audiosamplesize, 1, false, Image.FORMAT_RGF, audiosamples.to_byte_array())
	audiosampleframetexture.update(audiosampleframetextureimage)

func receivemqttaudiometa(msg):
	assert (msg[0] == "{".to_ascii_buffer()[0])
	twovoipspeaker.tv_incomingaudiopacket(msg)

func on_sigvoicestartstream():
	$AudioStreamPlayer.play()
	setupaudioshader($AudioStreamPlayer/TwoVoipSpeaker.audiostreamopuschunked.audiosamplesize)
			
func receivemqttaudio(msg):
	if twovoipspeaker.asbase64:
		msg = Marshalls.base64_to_raw(msg.get_string_from_ascii())
	twovoipspeaker.tv_incomingaudiopacket(msg)

var timedelaytohide = 0.1
var prevopusframecount = -1
func _process(delta):
	$Node/ColorRectBufferQueue.size.x = min(1.0, $AudioStreamPlayer/TwoVoipSpeaker.audiostreamopuschunked.queue_length_frames()*1.0/$AudioStreamPlayer/TwoVoipSpeaker.audiobuffersize)*size.x
	$AudioStreamPlayer.volume_db = $Node/Volume.value
	if $AudioStreamPlayer/TwoVoipSpeaker.opusframecount != prevopusframecount:
		var chunkv1 = $AudioStreamPlayer/TwoVoipSpeaker.audiostreamopuschunked.last_chunk_max()
		if chunkv1 != 0.0:
			var audiosamples = $AudioStreamPlayer/TwoVoipSpeaker.audiostreamopuschunked.read_last_chunk()
			audiosamplestoshader(audiosamples)
			$Node/ColorRectLoudness.size.x = $Node.size.x*chunkv1
			$Node/ColorRectBackground.visible = true
			timedelaytohide = 0.1
		prevopusframecount = $AudioStreamPlayer/TwoVoipSpeaker.opusframecount
	
	if timedelaytohide > 0.0:
		timedelaytohide -= delta
		if timedelaytohide <= 0.0:
			$Node/ColorRectBackground.visible = false
			$Node/ColorRectLoudness.size.x = 0
