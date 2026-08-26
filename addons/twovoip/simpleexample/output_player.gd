extends Control

func _ready():
	$PlayerLabel.text = get_name()

func RPC_incomingaudiopacket(packet):
	$TwoVoipSpeaker.receive_audio_packet(packet)

func _on_receiving_button_toggled(toggled_on):
	get_node("../..").set_receiving(String(get_name()), toggled_on)
	if not toggled_on:
		$TwoVoipSpeaker.external_end_stream()
	
func findaudioplayer():
	return $AudioStreamPlayer

func _on_sine_output_button_toggled(toggled_on):
	$TwoVoipSpeaker.set_sinewave_out(toggled_on)

func _process(delta):
	if $TwoVoipSpeaker.audio_stream_playback_opus:
		var maxchunkvol = $TwoVoipSpeaker.audio_stream_playback_opus.get_chunk_max()
		$ColorRectLoudness.size.x = clamp(maxchunkvol*500, 1, 50)
		var queuetime = $TwoVoipSpeaker.audio_stream_playback_opus.queue_length_frames()/$AudioStreamPlayer.stream.opus_sample_rate/$AudioStreamPlayer.stream.buffer_length
		$ColorRectBuffer.size.x = clamp(queuetime*100, 1, 50)
