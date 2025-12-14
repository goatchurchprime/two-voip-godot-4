extends Node

var audioopuschunkedeffect : AudioEffectOpusChunked = AudioEffectOpusChunked.new()
var chunkprefix : PackedByteArray = PackedByteArray([0,0]) 

var leadtime : float = 0.15
var hangtime : float  = 1.2
var voxthreshhold = 0.2
var speakingvolume = 0.0

var currentlytalking = false
var opusframecount = 0
var opusstreamcount = 0

var hangframes = 25
var hangframescountup = 0
var chunkmaxpersist = 0.0

var audiosampleframetextureimage : Image
var audiosampleframetexture : ImageTexture
var audiosampleframematerial = null

signal transmitaudiopacket(opuspacket, opusframecount)
signal transmitaudiojsonpacket(audiostreampacketheader)
signal micaudiowarnings(name, value)

var micnotplayingwarning = false

const rootmeansquaremaxmeasurement = false

var microphoneaudiosamplescountSeconds = 0.0
var microphoneaudiosamplescount = 0
var microphoneaudiosamplescountSecondsSampleWindow = 10.0

var talkingtimestart = 0

func setopusvalues(audiosamplerate, opussamplerate, opusframedurationms, opusbitrate, opuscomplexity, opusoptimizeforvoice):
	assert (not currentlytalking)
	audioopuschunkedeffect.opussamplerate = opussamplerate
	audioopuschunkedeffect.opusframesize = int(opussamplerate*opusframedurationms/1000.0)
	audioopuschunkedeffect.opusbitrate = opusbitrate
	audioopuschunkedeffect.opuscomplexity = opuscomplexity
	audioopuschunkedeffect.opusoptimizeforvoice = opusoptimizeforvoice

	audioopuschunkedeffect.audiosamplerate = audiosamplerate
	audioopuschunkedeffect.audiosamplesize = int(audioopuschunkedeffect.audiosamplerate*opusframedurationms/1000.0)

	var audiosampleframedata = PackedVector2Array()
	audiosampleframedata.resize(audioopuschunkedeffect.audiosamplesize)
	for j in range(audioopuschunkedeffect.audiosamplesize):
		audiosampleframedata.set(j, Vector2(-0.5,0.9) if (j%10)<5 else Vector2(0.6,0.1))
	audiosampleframetextureimage = Image.create_from_data(audioopuschunkedeffect.audiosamplesize, 1, false, Image.FORMAT_RGF, audiosampleframedata.to_byte_array())
	audiosampleframetexture = ImageTexture.create_from_image(audiosampleframetextureimage)
	audiosampleframematerial.set_shader_parameter("chunktexture", audiosampleframetexture)

var miconbutton: Button = null
var optioninputdevice: OptionButton = null
var pttbutton: Button = null
var voxbutton: Button = null
var denoisebutton: Button = null

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
	pttbutton = lpttbutton
	voxbutton = lvoxbutton
	denoisebutton = ldenoisebutton
	audiosampleframematerial = laudiosampleframematerial
	
	assert(miconbutton.toggle_mode == true)
	optioninputdevice = loptioninputdevice
	assert(optioninputdevice.item_count == 0)
	for d in AudioServer.get_input_device_list():
		optioninputdevice.add_item(d)
	assert(optioninputdevice.get_item_text(optioninputdevice.selected) == "Default")
	optioninputdevice.connect("item_selected", _on_optioninputdevice)
	miconbutton.connect("toggled", _on_miconbutton)
	voxbutton.connect("toggled", _on_vox_toggled)

func processtalkstreamends():
	var talking = pttbutton.button_pressed
	if talking and not currentlytalking:
		var frametimesecs = audioopuschunkedeffect.opusframesize*1.0/audioopuschunkedeffect.opussamplerate
		talkingtimestart = Time.get_ticks_msec()*0.001
		var leadframes = leadtime/frametimesecs
		hangframes = hangtime/frametimesecs
		print("leadframes ", leadframes)
		while leadframes > 0.0 and audioopuschunkedeffect.undrop_chunk():
			leadframes -= 1
			talkingtimestart -= frametimesecs
		var audiostreampacketheader = { 
			"opusframesize":audioopuschunkedeffect.opusframesize, 
			"opussamplerate":audioopuschunkedeffect.opussamplerate, 
			"lenchunkprefix":len(chunkprefix), 
			"opusstreamcount":opusstreamcount, 
			"talkingtimestart":talkingtimestart
		}
		audioopuschunkedeffect.resetencoder(false)
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
	audiosampleframematerial.set_shader_parameter("voxthreshhold", voxthreshhold)

func processvox():
	if denoisebutton.button_pressed:
		audioopuschunkedeffect.denoise_resampled_chunk()
	var chunkmax = audioopuschunkedeffect.chunk_max(rootmeansquaremaxmeasurement, denoisebutton.button_pressed)
	audiosampleframematerial.set_shader_parameter("chunkmax", chunkmax)
	if chunkmax >= voxthreshhold:
		if voxbutton.button_pressed and not pttbutton.button_pressed:
			pttbutton.button_pressed = true
		hangframescountup = 0
		if chunkmax > chunkmaxpersist:
			chunkmaxpersist = chunkmax
			print("chunkmaxpersist ", chunkmaxpersist)
			audiosampleframematerial.set_shader_parameter("chunkmaxpersist", chunkmaxpersist)
	else:
		if hangframescountup == hangframes:
			if voxbutton.button_pressed:
				pttbutton.button_pressed = false
			chunkmaxpersist = 0.0
			audiosampleframematerial.set_shader_parameter("chunkmaxpersist", chunkmaxpersist)
		hangframescountup += 1

	if pttbutton.button_pressed:
		audiosampleframematerial.set_shader_parameter("chunktexenabled", true)
		var audiosamples = audioopuschunkedeffect.read_chunk(false)
		audiosampleframetextureimage.set_data(audioopuschunkedeffect.audiosamplesize, 1, false, Image.FORMAT_RGF, audiosamples.to_byte_array())
		audiosampleframetexture.update(audiosampleframetextureimage)
		return chunkmax

	else:
		audiosampleframematerial.set_shader_parameter("chunktexenabled", false)
		return 0.0

func processopuschunk():
	assert(currentlytalking)
	if len(chunkprefix) == 2:
		chunkprefix.set(0, (opusframecount%256))  # 32768 frames is 10 minutes
		chunkprefix.set(1, (int(opusframecount/256)&127) + (opusstreamcount%2)*128)
	else:
		assert (len(chunkprefix) == 0)
	if denoisebutton.button_pressed:
		audioopuschunkedeffect.denoise_resampled_chunk()
	var opuspacket = audioopuschunkedeffect.read_opus_packet(chunkprefix)
	transmitaudiopacket.emit(opuspacket, opusframecount)
	opusframecount += 1
	
func _process(delta):
	var kk = AudioServer.get_input_frames_available()
	var microphonesamples = AudioServer.get_input_frames(AudioServer.get_input_frames_available())
	audioopuschunkedeffect.push_chunk(microphonesamples)
	microphoneaudiosamplescount += len(microphonesamples)
	microphoneaudiosamplescountSeconds += delta
	if microphoneaudiosamplescountSeconds > microphoneaudiosamplescountSecondsSampleWindow:
		print("measured mic audiosamples rate ", microphoneaudiosamplescount/microphoneaudiosamplescountSeconds)
		microphoneaudiosamplescount = 0
		microphoneaudiosamplescountSeconds = 0.0
		microphoneaudiosamplescountSecondsSampleWindow *= 1.5

	processtalkstreamends()
	var GG = 0
	while audioopuschunkedeffect.chunk_available():
		speakingvolume = processvox()
		processtalkstreamends()
		if currentlytalking:
			processopuschunk()
			GG += 1
		audioopuschunkedeffect.drop_chunk()
	if GG > 5:
		print(" GG ", GG, "  ", kk)
