extends Node

var opuschunked : AudioEffectOpusChunked
var audiostreamopuschunked : AudioStreamOpusChunked
var prepend = PackedByteArray()
var opuspacketsbuffer = [ ]

@onready var playbackmic = null

var dorecord = true  # set false to playback short recording

func _ready():
	if ClassDB.class_has_method("AudioStreamPlaybackMicrophone", "start"):
		playbackmic = AudioStreamPlaybackMicrophone.new()

	var microphoneidx = AudioServer.get_bus_index("MicrophoneBus")
	opuschunked = AudioServer.get_bus_effect(microphoneidx, 0)

	audiostreamopuschunked = $AudioStreamPlayer.stream
	for r in opusaudiodata:
		opuspacketsbuffer.append(PackedByteArray(r))

	if dorecord and playbackmic:
		playbackmic.start(0.0)

func _process(delta):
	if dorecord:
		_process_record(delta)
	else:
		_process_playback(delta)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_D and playbackmic:
		print(playbackmic.is_playing())
		print(playbackmic.get_microphone_buffer(20)+playbackmic.get_microphone_buffer(20))
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		print("Stopping mic")
		$AudioStreamMic.stop()
		await get_tree().create_timer(1.0).timeout
		print("Starting mic")
		$AudioStreamMic.play()

var sampleratemeasurementtime = 1.5
var maxaudioduringmeasurement = 0.0
var nchunksduringmeasurement = 0
const measurementdurationsecs = 2.0
func _process_record(delta):
	var lastopusdata = null
	while opuschunked.chunk_available():
		var chunkmax = opuschunked.chunk_max(false, false)
		maxaudioduringmeasurement = max(maxaudioduringmeasurement, chunkmax)
		nchunksduringmeasurement += 1
		#print(chunkmax)
		var opusdata : PackedByteArray = opuschunked.read_opus_packet(prepend)
		opuschunked.drop_chunk()
		lastopusdata = opusdata
		#print("\t", opusdata, ",")
	sampleratemeasurementtime += delta
	if sampleratemeasurementtime > measurementdurationsecs:
		print("Measured sample rate ", nchunksduringmeasurement*opuschunked.audiosamplesize/sampleratemeasurementtime, " max ", maxaudioduringmeasurement)
		print("  Opus data ", lastopusdata)
		sampleratemeasurementtime = 0.0
		maxaudioduringmeasurement = 0.0
		nchunksduringmeasurement = 0

func _process_playback(delta):
	while audiostreamopuschunked.chunk_space_available() and len(opuspacketsbuffer) != 0:
		audiostreamopuschunked.push_opus_packet(opuspacketsbuffer.pop_front(), len(prepend), 0)

var opusaudiodata = [
	[72, 11, 228, 193, 34, 35, 97, 240],
	[72, 7, 201, 121, 197, 18, 247, 188],
	[72, 7, 201, 121, 197, 18, 247, 188],
	[72, 7, 201, 114, 39, 225, 62, 83],
	[72, 7, 201, 114, 39, 225, 62, 83],
	[72, 7, 201, 121, 197, 18, 247, 188],
	[72, 7, 228, 128, 230, 153, 15, 33, 94],
	[72, 134, 252, 141, 109, 140, 48, 148, 146, 113, 164, 221, 55, 247, 137, 18, 82, 232, 138, 165, 153, 124, 30, 64],
	[72, 134, 248, 28, 33, 137, 169, 198, 191, 27, 252, 176, 229, 213, 86, 91, 24, 126, 165, 21, 151, 64, 4, 48],
	[72, 134, 250, 61, 93, 9, 66, 80, 179, 202, 253, 154, 252, 199, 144, 16, 64, 60, 47, 180, 140, 251, 144, 105, 182, 25, 91],
	[72, 135, 6, 84, 241, 174, 23, 7, 209, 141, 165, 114, 254, 136, 59, 214, 89, 139, 123, 216, 183, 118, 120, 198, 132],
	[72, 134, 248, 28, 226, 119, 141, 67, 52, 112, 185, 0, 185, 65, 8, 141, 194, 146, 17, 164, 196, 239],
	[72, 30, 146, 240, 182, 242, 250, 255, 58, 180, 217, 155, 176, 92, 88, 201, 21, 66, 230, 121],
	[72, 30, 191, 213, 85, 142, 211, 173, 128, 153, 27, 182, 39, 144, 100, 106, 47, 166, 156, 249, 248, 238, 200],
	[72, 30, 146, 241, 20, 241, 170, 127, 196, 227, 36, 215, 55, 14, 31, 83, 197, 63, 128],
	[72, 30, 146, 236, 60, 60, 229, 31, 32, 50, 121, 17, 203, 128, 77, 81, 123, 52, 121, 210, 40],
	[72, 30, 146, 242, 98, 100, 9, 112, 255, 194, 145, 225, 5, 9, 64, 102, 220, 168],
	[72, 30, 153, 6, 241, 0, 255, 179, 84, 33, 130, 144, 156, 2, 191, 225, 238, 68, 96, 160, 202],
	[72, 30, 146, 236, 38, 150, 162, 181, 228, 85, 220, 106, 152, 11, 165, 145, 248],
	[72, 30, 146, 222, 25, 205, 26, 73, 138, 157, 57, 119, 137, 157, 200, 10, 102, 125, 186, 147, 48, 176],
	[72, 30, 147, 219, 208, 233, 14, 47, 98, 209, 219, 62, 9, 59, 235, 125, 204, 240, 220, 130, 187, 8, 192],
	[72, 30, 146, 80, 17, 146, 106, 29, 160, 124, 135, 180, 40, 103, 85, 118, 222, 130, 216],
	[72, 30, 146, 248, 44, 122, 250, 144, 207, 137, 33, 173, 227, 151, 136, 167, 132, 108, 149, 182, 187],
	[72, 134, 254, 204, 219, 66, 104, 245, 28, 238, 161, 145, 42, 60, 5, 188, 72, 254, 20, 117, 12, 78, 62, 222, 221, 185, 248, 128],
	[72, 129, 101, 62, 76, 155, 231, 25, 164, 116, 140, 222, 65, 235, 133, 42, 78, 182, 54, 105, 16, 116, 43, 200],
	[72, 37, 8, 139, 187, 17, 23, 206, 101, 52, 226, 236, 241, 162, 242, 205, 191, 100],
	[72, 36, 146, 138, 152, 144, 187, 198, 236, 90, 189, 139, 202, 106, 243, 155, 3, 128],
	[72, 33, 98, 216, 1, 191, 125, 193, 203, 182, 155, 222, 234, 38, 163, 26, 125, 238, 55, 200, 140, 148],
	[72, 30, 146, 242, 53, 125, 63, 240, 187, 11, 254, 60, 7, 62, 21, 78, 238, 124, 220],
	[72, 30, 153, 12, 138, 20, 90, 91, 28, 203, 90, 222, 162, 199, 74, 109, 230, 116, 210, 91, 89, 96],
	[72, 31, 182, 27, 87, 36, 8, 41, 136, 204, 192, 1, 146, 87, 107, 218, 131, 1, 42, 11],
	[72, 31, 67, 166, 233, 183, 8, 30, 30, 171, 121, 252, 210, 195, 255, 28, 233, 165, 101, 91, 192],
	[72, 128, 142, 161, 218, 70, 97, 169, 169, 52, 93, 141, 211, 206, 158, 61, 120, 99, 76, 7, 158, 111, 185, 166, 32, 12],
	[72, 167, 104, 13, 55, 144, 236, 110, 84, 199, 167, 226, 27, 228, 124, 42, 243, 118, 6, 27, 236, 19, 172, 159, 10, 76, 34, 215, 93],
	[72, 178, 169, 72, 219, 165, 221, 121, 211, 161, 103, 99, 179, 150, 145, 144, 237, 193, 188, 53, 224, 133, 241, 84, 37, 98, 143, 95, 28, 114, 128],
	[72, 181, 231, 243, 10, 89, 72, 150, 89, 77, 191, 17, 95, 215, 133, 108, 83, 231, 8, 127, 136, 207, 166, 97, 31, 201, 86, 4, 163, 225, 92, 23, 173, 29, 61, 136],
	[72, 132, 113, 156, 203, 222, 158, 96, 90, 153, 221, 6, 113, 116, 172, 51, 213, 76, 37, 42, 59, 105, 183, 94, 46, 126, 219, 168],
	[72, 148, 140, 239, 144, 8, 223, 88, 94, 29, 250, 99, 45, 67, 212, 177, 167, 184, 63, 97, 78, 31, 52, 149, 164, 126, 96, 197, 71, 178, 64],
	[72, 149, 89, 49, 117, 174, 105, 160, 171, 3, 94, 213, 18, 203, 89, 145, 41, 233, 254, 46, 50, 190, 218, 251, 22, 132, 31, 197, 195],
	[72, 149, 116, 229, 162, 100, 164, 112, 248, 61, 107, 76, 195, 208, 177, 72, 255, 235, 78, 42, 240, 242, 133, 179, 176, 90, 49, 142, 231, 152],
	[72, 148, 186, 58, 127, 107, 182, 181, 48, 87, 123, 211, 155, 8, 82, 243, 35, 249, 12, 66, 1, 77, 253, 74, 111, 103, 80, 192, 226, 80, 64],
	[72, 132, 9, 253, 34, 121, 102, 1, 206, 66, 135, 140, 214, 248, 164, 50, 249, 233, 26, 191, 42, 57, 149, 161, 249, 223, 128],
	[72, 131, 132, 55, 153, 184, 197, 239, 237, 42, 254, 168, 200, 52, 78, 105, 76, 249, 1, 76, 35, 84, 17, 198, 68, 128],
	[72, 167, 76, 56, 243, 177, 71, 2, 11, 187, 128, 201, 212, 43, 35, 225, 120, 173, 99, 39, 32],
	[72, 165, 118, 232, 192, 147, 90, 214, 236, 210, 8, 234, 2, 171, 50, 230, 11, 23, 141, 77, 106, 145, 235, 12, 26, 170, 74, 183, 194, 64],
	[72, 190, 19, 239, 61, 219, 248, 57, 8, 70, 2, 254, 240, 201, 174, 64, 88, 208, 121, 75, 255, 251, 185, 250, 53, 113, 11, 208, 132, 20, 128],
	[72, 129, 250, 255, 84, 173, 75, 236, 76, 241, 119, 249, 25, 240, 169, 158, 173, 185, 192, 122, 76, 96],
	[72, 129, 247, 248, 149, 237, 234, 178, 58, 90, 88, 68, 99, 145, 102, 162, 231, 122, 202, 9, 236, 173, 58, 109, 185, 16],
	[72, 148, 15, 109, 242, 174, 106, 158, 91, 77, 168, 15, 162, 36, 147, 198, 184, 228, 161, 168, 91, 170, 55, 37, 6, 70, 150, 50, 49, 103, 181, 128],
	[72, 132, 130, 121, 191, 87, 232, 11, 189, 69, 188, 15, 147, 214, 25, 156, 78, 95, 94, 151, 11, 123, 115, 155, 255, 48],
	[72, 131, 139, 188, 59, 166, 126, 95, 73, 182, 96, 99, 113, 58, 51, 14, 7, 166, 116, 202, 124, 120, 65, 45],
	[72, 131, 119, 199, 126, 196, 62, 148, 20, 209, 209, 222, 60, 170, 75, 181, 228, 229, 180, 195, 194, 124],
	[72, 142, 8, 112, 130, 248, 164, 61, 246, 202, 66, 160, 32, 229, 118, 13, 238, 115, 231, 5, 73, 32, 199, 104, 152],
	[72, 130, 121, 2, 173, 190, 94, 165, 112, 29, 162, 234, 97, 31, 216, 19, 187, 96, 215, 8, 160],
	[72, 130, 248, 223, 122, 206, 177, 231, 235, 213, 224, 149, 160, 75, 236, 159, 238, 185, 249, 143, 120, 18, 73, 93, 201, 111, 125, 129, 232],
	[72, 167, 234, 181, 23, 189, 131, 156, 164, 36, 217, 139, 168, 87, 213, 176, 35, 216, 156, 52, 136, 204, 78, 96, 45, 224, 192],
	[72, 168, 119, 158, 219, 39, 49, 96, 223, 86, 180, 76, 114, 193, 242, 73, 189, 76, 174, 170, 6, 117, 185, 72, 214, 232, 255, 79, 78, 250, 153, 169, 245, 188, 188, 40],
	[72, 190, 141, 239, 123, 188, 226, 150, 214, 126, 217, 108, 68, 192, 172, 218, 78, 53, 32, 97, 211, 166, 52, 21, 189, 136, 165, 4, 167],
	[72, 190, 157, 177, 138, 27, 158, 96, 4, 204, 68, 137, 179, 171, 167, 92, 172, 242, 166, 48, 105, 120, 248, 132, 119, 58, 71, 31, 16, 198, 140],
	[72, 130, 219, 228, 41, 3, 3, 178, 125, 71, 188, 146, 128, 212, 124, 145, 73, 81, 113, 217, 110, 247, 252, 198, 2, 17, 96]
]
