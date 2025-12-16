extends Node

var audiostreamopuschunked : AudioStream = null
#var player_audiostreamplayer = null

#frametimems = opusframesize*1000.0/opusframesize
var audioserveroutputlatency = AudioServer.get_output_latency()
var audiobufferlagtimetarget = 0.8
var audiobufferlagtimetargettolerance = 0.15

const asciiopenbrace = 123 # "{".to_ascii_buffer()[0]
const asciiclosebrace = 125 # "}".to_ascii_buffer()[0]
var lenchunkprefix = -1
var opusstreamcount = 0
var asbase64 = false
var opusframecount = 0
const Noutoforderqueue = 4
const Npacketinitialbatching = 2
var outoforderchunkqueue = [ ]
var opusframequeuecount = 0
var audiobuffersize = 50*882

enum { AUDIOBUFFER_UNTOUCHED, AUDIOBUFFER_PAUSED, AUDIOBUFFER_FLOWING, AUDIOBUFFER_CLEARING }	
var currentlyreceivingtalkingstate = AUDIOBUFFER_UNTOUCHED

signal sigvoicestartstream()
signal sigvoicespeedrate(audiobufferpitchscale)

var lastemittedaudiobufferpitchscale = 1.0

func _ready():
	audiostreamopuschunked = get_parent().stream
	assert(audiostreamopuschunked.resource_local_to_scene, "AudioStream must be local_to_scene")
	setrecopusvalues(48000, 960)

func setrecopusvalues(opussamplerate, opusframesize):
	var opusframeduration = opusframesize*1.0/opussamplerate
	audiostreamopuschunked.opusframesize = opusframesize
	audiostreamopuschunked.opussamplerate = opussamplerate
	audiostreamopuschunked.audiosamplerate = AudioServer.get_mix_rate()
	audiostreamopuschunked.mix_rate = AudioServer.get_mix_rate()
	audiostreamopuschunked.audiosamplesize = int(audiostreamopuschunked.audiosamplerate*opusframeduration)
	audiostreamopuschunked.audiosamplechunks = int(audiobufferlagtimetarget*2.0*audiostreamopuschunked.audiosamplerate/audiostreamopuschunked.audiosamplesize)
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
			if h.has("talkingtimestart"):
				sigvoicestartstream.emit()
				if audiostreamopuschunked.opusframesize != h["opusframesize"] or \
						audiostreamopuschunked.opussamplerate != h["opussamplerate"]:
					setrecopusvalues(h["opussamplerate"], h["opusframesize"])
				lenchunkprefix = int(h["lenchunkprefix"])
				opusstreamcount = int(h["opusstreamcount"])
				asbase64 = (h["mqttpacketencoding"] == "base64")
				opusframecount = 0
				if h.has("opusframecount"):
					prints("Mid speech header!!! ", h["opusframecount"])
					opusframecount = int(h["opusframecount"]) + 1
				outoforderchunkqueue.clear()
				for i in range(Noutoforderqueue):
					outoforderchunkqueue.push_back(null)
				opusframequeuecount = 0
				assert (Npacketinitialbatching < Noutoforderqueue)
				audiostreamopuschunked.resetdecoder()
				currentlyreceivingtalkingstate = AUDIOBUFFER_PAUSED
			elif h.has("talkingtimeend"):
				currentlyreceivingtalkingstate = AUDIOBUFFER_CLEARING
				
	elif lenchunkprefix == -1:
		pass

	elif lenchunkprefix == 0:
		audiostreamopuschunked.push_opus_packet(packet, lenchunkprefix, 0)
		opusframecount += 1
		
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
				print("shifting outoforderqueue ", opusframecountI, " ", ("null" if outoforderchunkqueue[0] == null else len(outoforderchunkqueue[0])))
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
		prints("dropping frame with opusstream number mismatch", opusstreamcount, packet[0], packet[1])

func _physics_process(delta):
	if currentlyreceivingtalkingstate == AUDIOBUFFER_UNTOUCHED:
		return
	var bufferlengthtime = audioserveroutputlatency + audiostreamopuschunked.queue_length_frames()*1.0/audiostreamopuschunked.audiosamplerate
	if currentlyreceivingtalkingstate == AUDIOBUFFER_PAUSED:
		if bufferlengthtime < audiobufferlagtimetarget:
			if lastemittedaudiobufferpitchscale != 0.0:
				emit_signal("sigvoicespeedrate", 0.0)
				print(" bufferlengthtime ", bufferlengthtime)
				lastemittedaudiobufferpitchscale = 0.0
		else:
			emit_signal("sigvoicespeedrate", 1.0)
			print(" bufferlengthtime ", bufferlengthtime)
			lastemittedaudiobufferpitchscale = 1.0
			currentlyreceivingtalkingstate = AUDIOBUFFER_FLOWING
	
	if currentlyreceivingtalkingstate == AUDIOBUFFER_FLOWING:
		if lastemittedaudiobufferpitchscale == 1.0:
			if abs(bufferlengthtime - audiobufferlagtimetarget) > audiobufferlagtimetargettolerance:
				lastemittedaudiobufferpitchscale = 0.7 if (bufferlengthtime < audiobufferlagtimetarget) else 1.4
				emit_signal("sigvoicespeedrate", lastemittedaudiobufferpitchscale)
				print(" bufferlengthtime ", bufferlengthtime)
			
		elif (lastemittedaudiobufferpitchscale < 1.0) == (bufferlengthtime > audiobufferlagtimetarget):
			emit_signal("sigvoicespeedrate", 1.0)
			print(" bufferlengthtime ", bufferlengthtime)
			lastemittedaudiobufferpitchscale = 1.0

	if currentlyreceivingtalkingstate == AUDIOBUFFER_CLEARING:
		currentlyreceivingtalkingstate = AUDIOBUFFER_UNTOUCHED
		emit_signal("sigvoicespeedrate", 1.0)
		print(" bufferlengthtime ", bufferlengthtime)
		lastemittedaudiobufferpitchscale = 1.0
