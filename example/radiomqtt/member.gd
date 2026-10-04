extends Control

var opuspacketsbuffer = [ ]
@onready var twovoipspeaker = $AudioStreamPlayer/TwoVoipSpeaker

func _ready():
	twovoipspeaker.init_voip_speaker($TimingMeter)

func setname(lname):
	set_name(lname)
	$Label.text = name
	
func receivemqttaudiometa(msg):
	twovoipspeaker.receive_audio_packet(msg)

func receivemqttaudio(msg):
	twovoipspeaker.receive_audio_packet(msg)

func _process(_delta):
	if twovoipspeaker.audio_stream_playback_opus and twovoipspeaker.audio_stream_playback_opus.is_playing():
		$AudioStreamPlayer.volume_db = $Node/Volume.value
		var speaker_frame = twovoipspeaker.audio_stream_playback_opus.get_frame_number_actually_in_speaker() + twovoipspeaker.playbackstartframenumber
		var chunkv1 = twovoipspeaker.get_frame_max(speaker_frame)
		$Node/ColorRectLoudness.size.x = lerp(min(chunkv1*5, 1.0)*size.x, $Node/ColorRectLoudness.size.x, 0.75)

func _on_audio_stream_player_finished():
	$Node/ColorRectLoudness.size.x = 0
