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
	twovoipspeaker.receive_audio_packet(msg)

func receivemqttaudio(msg):
	twovoipspeaker.receive_audio_packet(msg)


var timedelaytohide = 0.1
var prevopusframecount = -1
func _process(delta):
	if twovoipspeaker.audio_stream_playback_opus:
		$Node/ColorRectBufferQueue.size.x = min(1.0, twovoipspeaker.audio_stream_playback_opus.queue_length_frames()/twovoipspeaker.opus_sample_rate/twovoipspeaker.audio_buffer_length)*size.x
		$AudioStreamPlayer.volume_db = $Node/Volume.value
		var chunkv1 = twovoipspeaker.audio_stream_playback_opus.get_chunk_max()
		if chunkv1 != 0.0:
			chunkv1 = min(chunkv1*10, 1.0)
			$Node/ColorRectLoudness.size.x = chunkv1*size.x
			timedelaytohide = 0.1
		prevopusframecount = twovoipspeaker.opusframecount

		if $AudioStreamPlayer.pitch_scale == 1.0:
			$Node/ColorRectBufferQueue.color = colournormal
		else:
			$Node/ColorRectBufferQueue.color = colourslow if $AudioStreamPlayer.pitch_scale < 1.0 else colourfast

	if timedelaytohide > 0.0:
		timedelaytohide -= delta
		if timedelaytohide <= 0.0:
			$Node/ColorRectLoudness.size.x = 0
