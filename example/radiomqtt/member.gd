extends Control

var opuspacketsbuffer = [ ]
@onready var twovoipspeaker = $AudioStreamPlayer/TwoVoipSpeaker

func _ready():
	twovoipspeaker.init_voip_speaker($TimingMeter)

func setname(lname):
	set_name(lname)
	$Label.text = name
	
func receivemqttaudiometa(msg, transport_debug_context: Dictionary = {}):
	twovoipspeaker.receive_audio_packet(msg, transport_debug_context)

func receivemqttaudio(msg, transport_debug_context: Dictionary = {}):
	twovoipspeaker.receive_audio_packet(msg, transport_debug_context)

func _process(_delta):
	if twovoipspeaker.audio_stream_playback_opus and twovoipspeaker.audio_stream_playback_opus.is_playing():
		$AudioStreamPlayer.volume_db = $Node/Volume.value
