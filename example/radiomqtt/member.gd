extends Control

var opuspacketsbuffer = [ ]
@onready var twovoipspeaker = $AudioStreamPlayer/TwoVoipSpeaker
@onready var colournormal = $Node/ColorRectBufferQueue.color
var colourfast = Color.GREEN
var colourslow = Color.ORANGE
var colourpause = Color.GRAY

func setname(lname):
	set_name(lname)
	$Label.text = name
	
func receivemqttaudiometa(msg):
	assert (msg[0] == "{".to_ascii_buffer()[0])
	twovoipspeaker.tv_incomingaudiopacket(msg)

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
				chunkv1 = min(chunkv1*10, 1.0)
				$Node/ColorRectLoudness.size.x = chunkv1*size.x
				timedelaytohide = 0.1
			prevopusframecount = twovoipspeaker.opusframecount

		if $AudioStreamPlayer.stream_paused:
			$Node/ColorRectBufferQueue.color = colourpause
		elif $AudioStreamPlayer.pitch_scale == 1.0:
			$Node/ColorRectBufferQueue.color = colournormal
		else:
			$Node/ColorRectBufferQueue.color = colourslow if $AudioStreamPlayer.pitch_scale < 1.0 else colourfast

	if timedelaytohide > 0.0:
		timedelaytohide -= delta
		if timedelaytohide <= 0.0:
			$Node/ColorRectLoudness.size.x = 0
