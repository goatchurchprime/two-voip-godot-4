extends Control

func _ready():
	# Wire up the optional controls and feedback from your UI
	$TwoVoipMic.init_voip_mic(true,
							  $MicOnButton,
							  $InputOptionButton,
							  $PTTButton,
							  $VoxButton,
							  $DenoiseButton,
							  $FeedbackDisplay.material)

	# Set up the opus compression library
	$TwoVoipMic.set_opus_values(48000, 20, 2, 12000, 5, true)

	# Set the threshold for voice activation
	$TwoVoipMic.set_vox_threshhold(0.02)

func _on_feedback_display_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		$TwoVoipMic.set_vox_threshhold(event.position.x/$FeedbackDisplay.size.x)

func _on_agc_button_toggled(toggled_on):
	$TwoVoipMic.opusencoder.set_automatic_gain(toggled_on)
	if not toggled_on:
		$TwoVoipMic.opusencoder.set_gain($HSliderAGC.value)

func _process(_delta):
	if $AGCButton.button_pressed:
		$HSliderAGC.value = $TwoVoipMic.opusencoder.get_gain()

func _on_h_slider_agc_value_changed(value):
	if not $AGCButton.button_pressed:
		$TwoVoipMic.opusencoder.set_gain($HSliderAGC.value)
