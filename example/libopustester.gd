extends AudioStreamPlayer



# See https://xiph.org/ogg/doc/framing.html
func _ready():
	var fin = FileAccess.open("res://sound.ogg", FileAccess.READ)
	var oggsblocks = [ ]
	for i in range(24):
		var gg = { }
		gg["oggs"] = fin.get_buffer(4)
		if gg["oggs"] != "OggS".to_ascii_buffer():
			break
		gg["zero"] = fin.get_8()
		gg["bitflags"] = fin.get_8()
		gg["absolute_granule_position"] = fin.get_64()
		gg["stream_serial_number"] = fin.get_32()
		gg["page_sequence_number"] = fin.get_32()
		gg["page_checksum"] = fin.get_32()
		gg["page_segments"] = fin.get_8()
		gg["segment_table"] = fin.get_buffer(gg["page_segments"])
		var packet_size = 0
		for s in gg["segment_table"]:
			packet_size += s
		gg["buff"] = fin.get_buffer(packet_size)
		oggsblocks.push_back(gg)

	print(len(oggsblocks), " blocks")
	var oh = oggsblocks[0]["buff"]
	assert(oh.slice(0, 8) == "OpusHead".to_ascii_buffer())
	var ohd = { "version":oh[8], "channelcount":oh[9], "preskip":oh.decode_u16(10), "sample_rate":oh.decode_u32(12), "outputgain":oh.decode_u16(16) }
	print(ohd)

	for gg in oggsblocks.slice(3, 8):
		print([gg["absolute_granule_position"], gg["page_sequence_number"]])
	
	var gg = oggsblocks[3]
	print(gg["segment_table"])
	print(gg["buff"].slice(0, 8).get_string_from_ascii())
	
	for bb in buffblocks(gg["segment_table"], gg["buff"]):
		print(bb)
	
func buffblocks(st, buff):
	var siprev = 0
	var si = 0
	var buffblocks = [ ]
	for s in st:
		si += s
		if si != 255:
			buffblocks.push_back(buff.slice(siprev, si))
			siprev = si
	return buffblocks
