extends Node

var audiostreamopus : AudioStreamOpus = null
var audiostreamplaybackopus : AudioStreamPlaybackOpus = null

# Consider looking at netem for simulating network traffic
# https://man7.org/linux/man-pages/man8/tc-netem.8.html

#frametimems = opusframesize*1000.0/opusframesize
var audioserveroutputlatency = AudioServer.get_output_latency()
@export var audiobufferlagtimetarget = 0.6
@export var audiobufferlagtimetargettolerance = 0.35

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

enum { AUDIOBUFFER_UNTOUCHED, AUDIOBUFFER_FILLING, AUDIOBUFFER_FLOWING, AUDIOBUFFER_CLEARING }	
var currentlyreceivingtalkingstate = AUDIOBUFFER_UNTOUCHED

signal sigvoicespeedrate(audiobufferpitchscale)

var lastemittedaudiobufferpitchscale = 1.0

func _ready():
	audiostreamopus = get_parent().stream
	assert(audiostreamopus.resource_local_to_scene, "AudioStream should be local_to_scene")

func setrecopusvalues(opus_sample_rate, opus_channels):
	if not get_parent().playing or audiostreamopus.opus_sample_rate != opus_sample_rate or audiostreamopus.opus_channels != opus_channels:
		audiostreamopus.opus_sample_rate = opus_sample_rate
		audiostreamopus.opus_channels = opus_channels
		get_parent().play()
		audiostreamplaybackopus = get_parent().get_stream_playback()
		
func tv_incomingaudiopacket(packet):
	if audiostreamopus == null:
		return
	if len(packet) <= 3:
		print("Bad packet too short")
	elif packet[0] == asciiopenbrace and packet[-1] == asciiclosebrace:
		var h = JSON.parse_string(packet.get_string_from_ascii())
		if h != null:
			print("audio json packet ", h)
			if h.has("talkingtimestart"):
				setrecopusvalues(h["opussamplerate"], h.get("opuschannels", 2))
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
				audiostreamplaybackopus.reset_opus_decoder()
				currentlyreceivingtalkingstate = AUDIOBUFFER_FILLING
			elif h.has("talkingtimeend"):
				currentlyreceivingtalkingstate = AUDIOBUFFER_CLEARING

	elif lenchunkprefix == -1:
		pass

	elif lenchunkprefix == 0:
		audiostreamopus.push_opus_packet(packet, lenchunkprefix, 0)
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
					audiostreamplaybackopus.push_opus_packet(outoforderchunkqueue[0], lenchunkprefix, 0)
					opusframequeuecount -= 1
				elif outoforderchunkqueue[1] != null:
					audiostreamplaybackopus.push_opus_packet(outoforderchunkqueue[1], lenchunkprefix, 1)
				outoforderchunkqueue.pop_front()
				outoforderchunkqueue.push_back(null)
				opusframecountR -= 1
				opusframecount += 1
				assert (opusframequeuecount >= 0)

			outoforderchunkqueue[opusframecountR] = packet
			opusframequeuecount += 1
			while outoforderchunkqueue[0] != null and opusframecount + opusframequeuecount >= Npacketinitialbatching:
				if not audiostreamplaybackopus.opus_segment_space_available():
					print("!!! segment space filled up")
					break
				audiostreamplaybackopus.push_opus_packet(outoforderchunkqueue.pop_front(), lenchunkprefix, 0)
				outoforderchunkqueue.push_back(null)
				opusframecount += 1
				opusframequeuecount -= 1
				assert (opusframequeuecount >= 0)
	else:
		prints("dropping frame with opusstream number mismatch", opusstreamcount, packet[0], packet[1])

func setpitchscale(pitchscale):
	if pitchscale != lastemittedaudiobufferpitchscale:
		if pitchscale != 0.0:
			if lastemittedaudiobufferpitchscale == 0.0:
				get_parent().stream_paused = false
			get_parent().pitch_scale = pitchscale
		else:
			get_parent().stream_paused = true
		lastemittedaudiobufferpitchscale = pitchscale

func _physics_process(delta):
	if currentlyreceivingtalkingstate == AUDIOBUFFER_UNTOUCHED:
		return
	var bufferlengthtime = audioserveroutputlatency + audiostreamplaybackopus.queue_length_frames()*1.0/audiostreamopus.opus_sample_rate
	if currentlyreceivingtalkingstate == AUDIOBUFFER_FILLING:
		if bufferlengthtime < audiobufferlagtimetarget:
			setpitchscale(0.0)
		else:
			setpitchscale(1.0)
			currentlyreceivingtalkingstate = AUDIOBUFFER_FLOWING
	
	if currentlyreceivingtalkingstate == AUDIOBUFFER_FLOWING:
		if lastemittedaudiobufferpitchscale == 1.0:
			if abs(bufferlengthtime - audiobufferlagtimetarget) > audiobufferlagtimetargettolerance:
				setpitchscale(0.7 if (bufferlengthtime < audiobufferlagtimetarget) else 1.4)
				print(" set lastemittedaudiobufferpitchscale to ", lastemittedaudiobufferpitchscale)
			
		elif (lastemittedaudiobufferpitchscale < 1.0) == (bufferlengthtime > audiobufferlagtimetarget):
			setpitchscale(1.0)
			print(" set lastemittedaudiobufferpitchscale to ", lastemittedaudiobufferpitchscale)

	if currentlyreceivingtalkingstate == AUDIOBUFFER_CLEARING:
		currentlyreceivingtalkingstate = AUDIOBUFFER_UNTOUCHED
		setpitchscale(1.0)
