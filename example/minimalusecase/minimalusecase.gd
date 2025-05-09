extends Node

var prepend = PackedByteArray()
var opuspacketsbuffer = [ ]

func _ready():
	var xxx = AudioEffectOpusChunked.new()
	#var xxx = AudioEffectCapture.new()
	await get_tree().create_timer(0.1).timeout
	xxx.unreference()
	#get_tree().quit()

func D_ready():
	print("*********************Hi there")
	#var microphoneidx = AudioServer.get_bus_index("MicrophoneBus")
	#AudioServer.remove_bus(microphoneidx)
	#$AudioStreamPlayer.queue_free()
	await get_tree().create_timer(1.0).timeout
	await get_tree().create_timer(0.5).timeout
	#var xxx = AudioEffectOpusChunked.new()
	var xxx = AudioEffectCapture.new()
	#AudioServer.add_bus_effect(1, xxx, 0)
	await get_tree().create_timer(0.1).timeout
	AudioServer.add_bus_effect(0, AudioEffectCapture.new())
	#AudioServer.remove_bus_effect(1, 0)
	xxx.unreference()
	print("qqqqqqquit")
	get_tree().quit()
	print("----qqqqqqquit")
