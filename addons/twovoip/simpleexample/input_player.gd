extends Control

@export var speech_mode := true
func _ready():
	# Wire up the optional controls and feedback from your UI
	$TwoVoipMic.init_voip_mic(false, $MicOnButton,
							  $InputOptionButton,
							  $PTTButton,
							  $VoxButton,
							  $FeedbackDisplay.material)

	# Set up the opus compression library
	var conditioner_backend = 1
	var echo_cancel_enabled = false
	var denoiser_mode = 0
	var agc_enabled = true
	if speech_mode:
		$StereoButton.button_pressed = false
		$AGCButton.button_pressed = true
		$DenoiseButton.button_pressed = true
		$TwoVoipMic.set_opus_values(48000, 20, 1, 12000, 5, true, -1, conditioner_backend, echo_cancel_enabled, denoiser_mode, agc_enabled)

	else:
		$StereoButton.button_pressed = true
		$AGCButton.button_pressed = false
		$DenoiseButton.button_pressed = false
		$TwoVoipMic.set_opus_values(48000, 20, 2, 12000, 5, true, -1, conditioner_backend, echo_cancel_enabled, denoiser_mode, false)

	# Set the threshold for voice activation
	$TwoVoipMic.set_vox_threshhold(0.02)

func _on_feedback_display_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		$TwoVoipMic.set_vox_threshhold(event.position.x/$FeedbackDisplay.size.x)


func _on_h_slider_man_gain_value_changed(value):
	$TwoVoipMic.set_gain(value)
