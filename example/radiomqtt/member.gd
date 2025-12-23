extends Control

var opuspacketsbuffer = [ ]
@onready var twovoipspeaker = $AudioStreamPlayer/TwoVoipSpeaker
@onready var colournormal = $Node/ColorRectBufferQueue.color
var colourfast = Color.GREEN
var colourslow = Color.ORANGE
var colourpause = Color.GRAY

func _ready():
	twovoipspeaker.connect("sigvoicespeedrate", on_sigvoicespeedrate)
	twovoipspeaker.connect("sigvoicestartstream", on_sigvoicestartstream)

func on_sigvoicespeedrate(audiobufferpitchscale):
	print("aaa ", audiobufferpitchscale)
	if audiobufferpitchscale == 1.0:
		$Node/ColorRectBufferQueue.color = colournormal
	elif audiobufferpitchscale == 0.0:
		$Node/ColorRectBufferQueue.color = colourpause
	else:
		$Node/ColorRectBufferQueue.color = colourslow if audiobufferpitchscale < 1.0 else colourfast

	if audiobufferpitchscale == 0.0:
		$AudioStreamPlayer.stream_paused = true
	else:
		$AudioStreamPlayer.stream_paused = false
		$AudioStreamPlayer.pitch_scale = audiobufferpitchscale

func setname(lname):
	set_name(lname)
	$Label.text = name
	
func receivemqttaudiometa(msg):
	assert (msg[0] == "{".to_ascii_buffer()[0])
	twovoipspeaker.tv_incomingaudiopacket(msg)

func on_sigvoicestartstream():
	if not $AudioStreamPlayer.playing:
		$AudioStreamPlayer.play()  # calling play() always instantiates a new playback object
		twovoipspeaker.audiostreamplaybackopus = $AudioStreamPlayer.get_stream_playback()

func receivemqttaudio(msg):
	if twovoipspeaker.asbase64:
		msg = Marshalls.base64_to_raw(msg.get_string_from_ascii())
	twovoipspeaker.tv_incomingaudiopacket(msg)

var timedelaytohide = 0.1
var prevopusframecount = -1
func _process(delta):
	if twovoipspeaker.audiostreamplaybackopus:
		$Node/ColorRectBufferQueue.size.x = min(1.0, twovoipspeaker.audiostreamplaybackopus.queue_length_frames()/$AudioStreamPlayer.stream.opus_sample_rate/$AudioStreamPlayer.stream.buffer_length)*size.x
		$AudioStreamPlayer.volume_db = $Node/Volume.value
		if twovoipspeaker.opusframecount != prevopusframecount:
			var chunkv1 = twovoipspeaker.audiostreamplaybackopus.get_last_chunk_max()
			if chunkv1 != 0.0:
				$Node/ColorRectLoudness.size.x = chunkv1*size.x
				timedelaytohide = 0.1
			prevopusframecount = twovoipspeaker.opusframecount
	
	if timedelaytohide > 0.0:
		timedelaytohide -= delta
		if timedelaytohide <= 0.0:
			$Node/ColorRectLoudness.size.x = 0
