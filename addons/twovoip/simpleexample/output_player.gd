extends Control

func _ready():
	$PlayerLabel.text = get_name()

var networkingnode = null
func RPC_incomingaudiopacket(packet):
	$TwoVoipSpeaker.tv_incomingaudiopacket(packet)

func _on_receiving_button_toggled(toggled_on):
	networkingnode.set_receiving(String(get_name()), toggled_on)
	if not toggled_on:
		$TwoVoipSpeaker.external_end_stream()
	
func findaudioplayer():
	return $AudioStreamPlayer

func _on_sine_output_button_toggled(toggled_on):
	$TwoVoipSpeaker.set_sinewave_out(toggled_on)

func _process(delta):
	if $TwoVoipSpeaker.audiostreamplaybackopus:
		var maxchunkvol = $TwoVoipSpeaker.audiostreamplaybackopus.get_chunk_max()
		$ColorRectLoudness.size.x = clamp(maxchunkvol*500, 1, 50)
		var queuetime = $TwoVoipSpeaker.audiostreamplaybackopus.queue_length_frames()/$AudioStreamPlayer.stream.opus_sample_rate/$AudioStreamPlayer.stream.buffer_length
		$ColorRectBuffer.size.x = clamp(queuetime*100, 1, 50)
