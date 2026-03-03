extends Control

var audioeffectfftblock : AudioEffectFFTBlock

var audiosampleframetextureimage : Image
var audiosampleframetexture : ImageTexture
var windowarray : PackedFloat32Array
@onready var audiosampleframematerial = $FFTImage.material

var fftsize = 1024
var fftrows = 128

func _ready():
	audioeffectfftblock = AudioEffectFFTBlock.new()
	AudioServer.set_input_device_active(true)

	var audiosampleframedata = PackedVector2Array()
	audiosampleframedata.resize(fftsize*fftrows)
	for j in range(fftsize):
		audiosampleframedata.set(j, Vector2(-0.5,0.9) if (j%10)<5 else Vector2(0.6,0.1))

	audiosampleframetextureimage = Image.create_from_data(fftsize, fftrows, false, Image.FORMAT_RGF, audiosampleframedata.to_byte_array())
	audiosampleframetexture = ImageTexture.create_from_image(audiosampleframetextureimage)
	windowarray = PackedFloat32Array()
	windowarray.resize(fftsize)
	for i in range(fftsize):
		var lam = i*1.0/(fftsize - 1)
		windowarray[i] = 0.5*(1.0 - cos(2*PI*lam))
	audiosampleframematerial.set_shader_parameter("chunktexture", audiosampleframetexture)
	var advancestep = 1024
	audioeffectfftblock.set_images(audiosampleframetextureimage, audiosampleframetexture, windowarray, advancestep)
	prints("ffff ", fftsize, fftrows)

func _process(_delta):
	_process_record()

func _process_record():
	while true:
		var frames = AudioServer.get_input_frames(256)
		if len(frames):
			audioeffectfftblock.push_chunk(frames)
			audiosampleframematerial.set_shader_parameter("rowoffset", audioeffectfftblock.get_fftirow()*1.0/fftrows)

		else:
			break

func _on_h_slider_amp_value_changed(value):
	audiosampleframematerial.set_shader_parameter("fftgain", value/50.0)
