extends Node

var audiostreamopuschunked : AudioStream = null
#var player_audiostreamplayer = null

#frametimems = opusframesize*1000.0/opusframesize
var audioserveroutputlatency = 0.015
var audiobufferregulationtimeLow = 0.6
var audiobufferregulationtime = 1.2
var audiobufferregulationpitchlow = 1.4
var audiobufferregulationpitch = 2.0
var audiobufferpitchscale = 1.0

const asciiopenbrace = 123 # "{".to_ascii_buffer()[0]
const asciiclosebrace = 125 # "}".to_ascii_buffer()[0]
var lenchunkprefix = -1
var opusstreamcount = 0
var opusframecount = 0
const Noutoforderqueue = 4
const Npacketinitialbatching = 2
var outoforderchunkqueue = [ ]
var opusframequeuecount = 0
var audiobuffersize = 50*882

signal sigplaystream()
signal sigvoicespeedrate(audiobufferpitchscale)

func _ready():
	audiostreamopuschunked = ClassDB.instantiate("AudioStreamOpusChunked")
	setrecopusvalues(48000, 960)

func setrecopusvalues(opussamplerate, opusframesize):
	var opusframeduration = opusframesize*1.0/opussamplerate
	audiostreamopuschunked.opusframesize = opusframesize
	audiostreamopuschunked.opussamplerate = opussamplerate
	audiostreamopuschunked.audiosamplerate = ProjectSettings.get_setting_with_override("audio/driver/mix_rate")  # AudioServer.get_mix_rate()
	audiostreamopuschunked.mix_rate = ProjectSettings.get_setting_with_override("audio/driver/mix_rate")  # AudioServer.get_mix_rate()
	audiostreamopuschunked.audiosamplesize = int(audiostreamopuschunked.audiosamplerate*opusframeduration)
	audiobuffersize = audiostreamopuschunked.audiosamplesize*audiostreamopuschunked.audiosamplechunks

func tv_incomingaudiopacket(packet):
	if audiostreamopuschunked == null:
		return
	if len(packet) <= 3:
		print("Bad packet too short")
	elif packet[0] == asciiopenbrace and packet[-1] == asciiclosebrace:
		var h = JSON.parse_string(packet.get_string_from_ascii())
		if h != null:
			print("audio json packet ", h)
			sigplaystream.emit()
			if h.has("talkingtimestart"):
				if audiostreamopuschunked.opusframesize != h["opusframesize"] or \
						audiostreamopuschunked.opussamplerate != h["opussamplerate"]:
					setrecopusvalues(h["opussamplerate"], h["opusframesize"])
				lenchunkprefix = int(h["lenchunkprefix"])
				opusstreamcount = int(h["opusstreamcount"])
				opusframecount = 0
				if h.has("opusframecount"):
					prints("Mid speech header!!! ", h["opusframecount"])
					opusframecount = h["opusframecount"]
				outoforderchunkqueue.clear()
				for i in range(Noutoforderqueue):
					outoforderchunkqueue.push_back(null)
				opusframequeuecount = 0
				assert (Npacketinitialbatching < Noutoforderqueue)
				audiostreamopuschunked.resetdecoder()
				
	elif lenchunkprefix == -1:
		pass

	elif lenchunkprefix == 0:
		audiostreamopuschunked.push_opus_packet(packet, lenchunkprefix, 0)
		
	elif packet[1]&128 == (opusstreamcount%2)*128:
		assert (lenchunkprefix == 2)
		var opusframecountI = packet[0] + (packet[1]&127)*256
		var opusframecountR = opusframecountI - opusframecount
		if opusframecountR < 0:
			print("framecount Wrapround 10mins? ", opusframecount, " ", opusframecountI)
			opusframecount = opusframecountI
			opusframecountR = 0
		if opusframecountR >= 0:
			while opusframecountR >= Noutoforderqueue:
				print("shifting outoforderqueue ", opusframecountR, " ", ("null" if outoforderchunkqueue[0] == null else len(outoforderchunkqueue[0])))
				if outoforderchunkqueue[0] != null:
					audiostreamopuschunked.push_opus_packet(outoforderchunkqueue[0], lenchunkprefix, 0)
					opusframequeuecount -= 1
				elif outoforderchunkqueue[1] != null:
					audiostreamopuschunked.push_opus_packet(outoforderchunkqueue[1], lenchunkprefix, 1)
				outoforderchunkqueue.pop_front()
				outoforderchunkqueue.push_back(null)
				opusframecountR -= 1
				opusframecount += 1
				assert (opusframequeuecount >= 0)
		
			if false and opusframecount != 0 and opusframequeuecount == 0:
				# optimize case to avoid using queue
				audiostreamopuschunked.push_opus_packet(packet, lenchunkprefix, 0)
				opusframecount += 1

			else:
				outoforderchunkqueue[opusframecountR] = packet
				opusframequeuecount += 1
				while outoforderchunkqueue[0] != null and opusframecount + opusframequeuecount >= Npacketinitialbatching:
					if not audiostreamopuschunked.chunk_space_available():
						print("!!! chunk space filled up")
						break
					audiostreamopuschunked.push_opus_packet(outoforderchunkqueue.pop_front(), lenchunkprefix, 0)
					outoforderchunkqueue.push_back(null)
					opusframecount += 1
					opusframequeuecount -= 1
					assert (opusframequeuecount >= 0)
			
	else:
		print("dropping frame with opusstream number mismatch")

func _process(delta):
	if audiostreamopuschunked != null:
		var bufferlengthtime = audioserveroutputlatency + audiostreamopuschunked.queue_length_frames()*1.0/audiostreamopuschunked.audiosamplerate
		if bufferlengthtime < audiobufferregulationtime:
			if audiobufferpitchscale != 1.0:
				if bufferlengthtime < audiobufferregulationtimeLow:
					audiobufferpitchscale = 1.0
					sigvoicespeedrate.emit(audiobufferpitchscale)
					print("SETTING audiobufferpitchscale ", audiobufferpitchscale)
		else:
			var w = inverse_lerp(audiobufferregulationtime, audioserveroutputlatency + audiobuffersize/audiostreamopuschunked.audiosamplerate, bufferlengthtime)
			audiobufferpitchscale = lerp(audiobufferregulationpitchlow, audiobufferregulationpitch, w)
			sigvoicespeedrate.emit(audiobufferpitchscale)
			print("SETTING audiobufferpitchscale ", audiobufferpitchscale)
