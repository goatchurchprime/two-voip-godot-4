extends HBoxContainer

const outlinewidth = 4
var samplesrunon = 17
var samplescountdown = 1
var voxthreshold = 1.0
var voiceprobthreshold = 0.5
var visthreshold = 1.0

@onready var PTT = get_node("../HBoxBigButtons/VBoxPTT/PTT")
@onready var Denoise = get_node("../HBoxBigButtons/VBoxPTT/Denoise")
@onready var Vox = get_node("../HBoxBigButtons/VBoxVox/Vox")
@onready var Sil = get_node("../HBoxBigButtons/VBoxVox/Silence")
@onready var Hangtime = get_node("../HBoxBigButtons/VBoxVox/Hangtime")


func _on_h_slider_vox_value_changed(value):
	if Denoise.button_pressed:
		voiceprobthreshold = value/$HSliderVox.max_value
	else:
		voxthreshold = value/$HSliderVox.max_value
	
func _ready():
	await get_tree().process_frame 
	$HSliderVox/ColorRectBackground.size = $HSliderVox.size
	$HSliderVox/ColorRectLoudness.size = Vector2($HSliderVox.size.x, $HSliderVox.size.y/2)
	$HSliderVox/ColorRectLoudness.position = Vector2(0, $HSliderVox.size.y/4)
	$HSliderVox/ColorRectLoudnessRMS.size = Vector2($HSliderVox.size.x, $HSliderVox.size.y/4)
	$HSliderVox/ColorRectLoudnessRMS.position = Vector2(0, $HSliderVox.size.y*3/8)
	$HSliderVox/ColorRectThreshold.size = Vector2(outlinewidth, $HSliderVox.size.y)
	$HSliderVox/ColorRectThreshold.position = Vector2(0,0)
	$HSliderVox/ColorRectThreshold.size = Vector2(outlinewidth, $HSliderVox.size.y)
	$HSliderVox/ColorRectDenoiseVoiceProb.position = Vector2($HSliderVox.size.x/4, $HSliderVox.size.y*7/8)
	$HSliderVox/ColorRectDenoiseVoiceProb.size = Vector2($HSliderVox.size.x*2/3, $HSliderVox.size.y/8)
	$HSliderVox/ColorRectDenoiseVoiceProb.visible = false
	$HSliderVox/ColorRectMicZero.position = Vector2($HSliderVox.size.x/2 - $HSliderVox/ColorRectMicZero.size.x/2, $HSliderVox.size.y*7/8) + Vector2(0, 3)
	_on_h_slider_vox_value_changed($HSliderVox.value)
	
func loudnessvalues(chunkv1, chunkv2, frametimems, speechprobability):
	$HSliderVox/ColorRectLoudness.size.x = $HSliderVox.size.x*chunkv1
	$HSliderVox/ColorRectLoudnessRMS.size.x = $HSliderVox.size.x*chunkv2
	if speechprobability > 0.0:
		$HSliderVox/ColorRectDenoiseVoiceProb.size.x = $HSliderVox.size.x*speechprobability
		$HSliderVox/ColorRectDenoiseVoiceProb.position.x = $HSliderVox.size.x/2*(1-speechprobability)
		$HSliderVox/ColorRectDenoiseVoiceProb.visible = true
	else:
		$HSliderVox/ColorRectDenoiseVoiceProb.visible = false
	$HSliderVox/ColorRectMicZero.visible = (chunkv1 == 0.0)

	if Sil.button_pressed:
		if Vox.pressed:
			PTT.set_pressed(false)
		if Denoise.button_pressed:
			if speechprobability >= voiceprobthreshold:
				$HSliderVox.value = speechprobability*$HSliderVox.max_value
		else:
			if chunkv1 >= voxthreshold:
				$HSliderVox.value = chunkv1*$HSliderVox.max_value

	elif Denoise.button_pressed and speechprobability > voiceprobthreshold:
		if Vox.button_pressed:
			PTT.set_pressed(true)
		samplescountdown = int(Hangtime.value*1000.0/frametimems)

	elif (not Denoise.button_pressed) and chunkv1 >= voxthreshold:
		if not $HSliderVox/ColorRectThreshold.visible:
			visthreshold = chunkv1
			$HSliderVox/ColorRectThreshold.visible = true
			if Vox.button_pressed:
				PTT.set_pressed(true)
		else:
			visthreshold = max(visthreshold, chunkv1)
		$HSliderVox/ColorRectThreshold.position.x = $HSliderVox.size.x*visthreshold - outlinewidth/2.0
		samplescountdown = int(Hangtime.value*1000.0/frametimems)

	elif samplescountdown > 0:
		samplescountdown -= 1
		if samplescountdown == 0:
			$HSliderVox/ColorRectThreshold.visible = false
			if Vox.pressed:
				PTT.set_pressed(false)
		

func _on_silence_button_down():
	$HSliderVox.value = 0
