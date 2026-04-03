extends Node

var opusencoder : TwovoipOpusEncoder = TwovoipOpusEncoder.new()
var chunkprefix : PackedByteArray = PackedByteArray([0,0]) 

var leadtime : float = 0.15
var hangtime : float  = 0.7
var voxthreshhold = 0.07
var microphone_gain = 1.0

var currentlytalking = false
var opusframecount = 0
var opusstreamcount = 0

var hangframes = 25
var hangframescountup = 0
var chunkmaxpersist = 0.0

var audiosampleframetextureimage : Image
var audiosampleframetexture : ImageTexture
var audiosampleframematerial = null

signal transmitaudiopacket(opuspacket : PackedByteArray, opusframecount : int)
signal transmitaudiojsonpacket(audiostreampacketheader : Dictionary)

const rootmeansquaremaxmeasurement = false

var microphoneaudiosamplescountSeconds = 0.0
var microphoneaudiosamplescount = 0
var microphoneaudiosamplescountSecondsSampleWindow = 10.0

var talkingtimestart = 0
var opus_chunk_size = 960
var audio_chunk_size = 882
var frametimesecs = 0.02
var opussamplerate = 48000
var opuschannels = 2
func setopusvalues(p_opussamplerate, opusframedurationms, p_channels, opusbitrate, opuscomplexity, opusoptimizeforvoice):
	opussamplerate = p_opussamplerate
	opuschannels = p_channels
	opusencoder.create_sampler(AudioServer.get_input_mix_rate(), opussamplerate, opuschannels, denoisebutton.button_pressed)
	opusencoder.create_opus_encoder(opusbitrate, opuscomplexity, opusoptimizeforvoice)
	# optimize for voice

	assert (not currentlytalking)
	opus_chunk_size = int(opussamplerate*opusframedurationms/1000.0)
	audio_chunk_size = opusencoder.calc_audio_chunk_size(opus_chunk_size)
	frametimesecs = opusframedurationms/1000.0

	if audiosampleframematerial:
		var audiosampleframedata = PackedVector2Array()
		audiosampleframedata.resize(audio_chunk_size)
		for j in range(audio_chunk_size):
			audiosampleframedata.set(j, Vector2(-0.5,0.9) if (j%10)<5 else Vector2(0.6,0.1))
		audiosampleframetextureimage = Image.create_from_data(audio_chunk_size, 1, false, Image.FORMAT_RGF, audiosampleframedata.to_byte_array())
		audiosampleframetexture = ImageTexture.create_from_image(audiosampleframetextureimage)
		audiosampleframematerial.set_shader_parameter("chunktexture", audiosampleframetexture)

var miconbutton: Button = null
var optioninputdevice: OptionButton = null
var pttbutton: Button = null
var voxbutton: Button = null
var denoisebutton: Button = null

func _ready():
	set_process(false)

func _on_miconbutton(toggled_on):
	if toggled_on:
		if OS.get_name() == "Android" and not OS.request_permission("android.permission.RECORD_AUDIO"):
			print("Waiting for user response after requesting audio permissions")
			# Must enable Record Audio permission in on Android
			@warning_ignore("untyped_declaration")
			var x = await get_tree().on_request_permissions_result
			var permission: String = x[0]
			var granted: bool = x[1]
			assert(permission == "android.permission.RECORD_AUDIO")
			print("Android Audio permission granted ", granted)

		var err = AudioServer.set_input_device_active(true)
		if err != OK:
			print("Mic input err: ", err)
			miconbutton.set_pressed_no_signal(false)
	else:
		AudioServer.set_input_device_active(false)

func _on_optioninputdevice(index: int) -> void:
	var micwason = miconbutton.button_down
	if micwason:
		miconbutton.set_pressed(false)
	var input_device: String = optioninputdevice.get_item_text(index)
	print("Set input device: ", input_device)
	AudioServer.set_input_device(input_device)
	if micwason:
		miconbutton.set_pressed(true)

func _on_vox_toggled(toggled_on):
	pttbutton.toggle_mode = toggled_on
	pttbutton.set_pressed(false)

func initvoipmic(lmiconbutton: Button, loptioninputdevice: OptionButton, lpttbutton: Button, lvoxbutton: Button, ldenoisebutton: Button, laudiosampleframematerial: Material):
	miconbutton = lmiconbutton
	if miconbutton == null:
		miconbutton = Button.new()
		miconbutton.toggle_mode = true
		miconbutton.button_pressed = true
	assert(miconbutton.toggle_mode, "MicOn must be a toggle button")
	miconbutton.connect("toggled", _on_miconbutton)
	_on_miconbutton(miconbutton.button_pressed)

	pttbutton = (lpttbutton if lpttbutton else Button.new())

	voxbutton = lvoxbutton
	if voxbutton == null:
		voxbutton = Button.new()
		voxbutton.toggle_mode = true
		voxbutton.button_pressed = true
	assert(voxbutton.toggle_mode, "Vox must be a toggle button")
	voxbutton.connect("toggled", _on_vox_toggled)
	_on_vox_toggled(voxbutton.button_pressed)

	denoisebutton = ldenoisebutton
	if denoisebutton == null:
		denoisebutton = Button.new()
		denoisebutton.toggle_mode = true
	assert(denoisebutton.toggle_mode, "Denoise must be a toggle button")

	audiosampleframematerial = laudiosampleframematerial
	
	optioninputdevice = loptioninputdevice if loptioninputdevice else OptionButton.new()
	assert(optioninputdevice.item_count == 0)
	for d in AudioServer.get_input_device_list():
		optioninputdevice.add_item(d)
	assert(optioninputdevice.get_item_text(optioninputdevice.selected) == "Default")
	optioninputdevice.connect("item_selected", _on_optioninputdevice)

	set_process(true)

func processtalkstreamends():
	var talking = pttbutton.button_pressed
	if talking and not currentlytalking:
		talkingtimestart = Time.get_ticks_msec()*0.001
		var leadframes = leadtime/frametimesecs
		hangframes = hangtime/frametimesecs
		print("leadframes ", leadframes)
		#while leadframes > 0.0 and audioopuschunkedeffect.undrop_chunk():
		#	leadframes -= 1
		#	talkingtimestart -= frametimesecs
		var audiostreampacketheader = { 
			"opusframesize":opus_chunk_size, 
			"opussamplerate":opussamplerate, 
			"opuschannels":opuschannels,
			"lenchunkprefix":len(chunkprefix), 
			"opusstreamcount":opusstreamcount, 
			"opusframecount":0,
			"talkingtimestart":talkingtimestart
		}
		opusencoder.reset_opus_encoder()
		transmitaudiojsonpacket.emit(audiostreampacketheader)
		#get_parent().PlayerConnections.peerconnections_possiblymissingaudioheaders.clear()
		opusframecount = 0
		currentlytalking = true

	elif not talking and currentlytalking:
		currentlytalking = false
		var talkingtimeend = Time.get_ticks_msec()*0.001
		var talkingtimeduration = talkingtimeend - talkingtimestart
		var audiopacketstreamfooter = {
			"opusstreamcount":opusstreamcount, 
			"opusframecount":opusframecount,
			"talkingtimeduration":talkingtimeduration,
			"talkingtimeend":talkingtimeend 
		}
		print("My voice chunktime=", talkingtimeduration/opusframecount, " over ", talkingtimeduration, " seconds")
		transmitaudiojsonpacket.emit(audiopacketstreamfooter)
		opusstreamcount += 1

func set_voxthreshhold(lvoxthreshhold):
	voxthreshhold = lvoxthreshhold
	if audiosampleframematerial:
		audiosampleframematerial.set_shader_parameter("voxthreshhold", voxthreshhold)

func set_gain(gain):
	print("set microphone gain to ", gain)
	microphone_gain = gain

func processvox(chunkmax, audio_chunk):
	if audiosampleframematerial:
		if denoisebutton.button_pressed:
			audiosampleframematerial.set_shader_parameter("speechnoiseprobability", chunkmax)
		audiosampleframematerial.set_shader_parameter("chunkmax", chunkmax)

	if chunkmax >= voxthreshhold:
		if voxbutton.button_pressed and not pttbutton.button_pressed:
			pttbutton.button_pressed = true
		hangframescountup = 0
		if chunkmax > chunkmaxpersist:
			chunkmaxpersist = chunkmax
			if audiosampleframematerial:
				audiosampleframematerial.set_shader_parameter("chunkmaxpersist", chunkmaxpersist)
	else:
		if hangframescountup == hangframes:
			if voxbutton.button_pressed:
				pttbutton.button_pressed = false
			chunkmaxpersist = 0.0
			if audiosampleframematerial:
				audiosampleframematerial.set_shader_parameter("chunkmaxpersist", chunkmaxpersist)
		hangframescountup += 1

	if audiosampleframematerial:
		if pttbutton.button_pressed:
			audiosampleframematerial.set_shader_parameter("chunktexenabled", true)
			audiosampleframetextureimage.set_data(audio_chunk_size, 1, false, Image.FORMAT_RGF, audio_chunk.to_byte_array())
			audiosampleframetexture.update(audiosampleframetextureimage)
		else:
			audiosampleframematerial.set_shader_parameter("chunktexenabled", false)

func processopuschunk():
	assert(currentlytalking)
	if len(chunkprefix) == 2:
		chunkprefix.set(0, (opusframecount%256))  # 32768 frames is 10 minutes
		chunkprefix.set(1, (int(opusframecount/256)&127) + (opusstreamcount%2)*128)
	else:
		assert (len(chunkprefix) == 0)
	var opuspacket : PackedByteArray = opusencoder.encode_chunk(chunkprefix, microphone_gain)
	transmitaudiopacket.emit(opuspacket, opusframecount)
	opusframecount += 1
	
var audio_chunk = null
var last_chunkmax = 0.0

func _process(delta):
	microphoneaudiosamplescountSeconds += delta
	processtalkstreamends()
	while true:
		audio_chunk = AudioServer.get_input_frames(opusencoder.calc_audio_chunk_size(opus_chunk_size))
		if len(audio_chunk) == 0:
			break
		last_chunkmax = opusencoder.process_pre_encoded_chunk(audio_chunk, opus_chunk_size, denoisebutton.button_pressed, rootmeansquaremaxmeasurement)
		microphoneaudiosamplescount += len(audio_chunk)
		if microphoneaudiosamplescountSeconds > microphoneaudiosamplescountSecondsSampleWindow:
			print("measured mic audiosamples rate ", microphoneaudiosamplescount/microphoneaudiosamplescountSeconds)
			microphoneaudiosamplescount = 0
			microphoneaudiosamplescountSeconds = 0.0
			microphoneaudiosamplescountSecondsSampleWindow *= 1.5
		processvox(last_chunkmax, audio_chunk)
		if currentlytalking:
			processopuschunk()
	audio_chunk = null
