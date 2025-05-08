extends Node

var opuschunked : AudioEffectOpusChunked
var audiostreamopuschunked : AudioStreamOpusChunked
var prepend = PackedByteArray()
var opuspacketsbuffer = [ ]

func _ready():
	print("*********************Hi there")
	var microphoneidx = AudioServer.get_bus_index("MicrophoneBus")
	#opuschunked = AudioServer.get_bus_effect(microphoneidx, 0)
	AudioServer.remove_bus_effect(microphoneidx, 0)
	AudioServer.remove_bus(microphoneidx)
	await get_tree().create_timer(1.0).timeout
	print("*********************Hi there")
	AudioServer.add_bus_effect(0, AudioEffectCapture.new())
	var xxx = AudioEffectOpusChunked.new()
	await get_tree().create_timer(0.5).timeout
	print(xxx)
	AudioServer.add_bus_effect(0, xxx, 0)
	await get_tree().create_timer(0.1).timeout
	AudioServer.remove_bus_effect(0, 0)
	print("qqqqqqquit")
	get_tree().quit()


