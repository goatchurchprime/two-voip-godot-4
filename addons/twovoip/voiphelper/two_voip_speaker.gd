extends Node

var audioplayeropus = null
var audiostreamopus : AudioStreamOpus = null
var audio_stream_playback_opus : AudioStreamPlaybackOpus = null

# Consider looking at netem for simulating network traffic
# https://man7.org/linux/man-pages/man8/tc-netem.8.html

#frametimems = opusframesize*1000.0/opusframesize
var audioserveroutputlatency = AudioServer.get_output_latency()
@export var audio_buffer_lag_time_target = 0.6
@export var audio_buffer_length = 2.0
@export var maximum_simultaneous_episodes = 3
@export var stale_episode_timeout = 2.0

const asciiopenbrace = 123 # "{".to_ascii_buffer()[0]
const asciiclosebrace = 125 # "}".to_ascii_buffer()[0]
var lenchunkprefix = 2
var opusstreamcount = 0
var inopusstream = false
var opusframecount = 0
var opusframesize = 960
const Noutoforderqueue = 4
const Npacketinitialbatching = 2
var outoforderchunkqueue = [ ]
var opusframequeuecount = 0
var opus_sample_rate = 48000
var opus_channels = 2
var runninglagtimeminimum = -1.0


func _ready():
	audioplayeropus = get_parent().findaudioplayer() if get_parent().has_method("findaudioplayer") else get_parent()
	if audioplayeropus.has_method("set_stream"):
		audiostreamopus = AudioStreamOpus.new()
		audioplayeropus.set_stream(audiostreamopus)
		audioplayeropus.max_polyphony = maximum_simultaneous_episodes
	else:
		audioplayeropus = null
		assert(false, "Audiostream player not found!")


func setrecopusvalues(new_opus_sample_rate, new_opus_channels):
	opus_sample_rate = new_opus_sample_rate
	opus_channels = new_opus_channels
	audioplayeropus.play()  # Every talking episode gets its own playback.
	audio_stream_playback_opus = audioplayeropus.get_stream_playback()
	var result = audio_stream_playback_opus.initialize(opus_sample_rate, opus_channels, audio_buffer_length, audio_buffer_lag_time_target, stale_episode_timeout)
	if result != OK:
		push_error("Could not initialize Opus playback: %s" % error_string(result))
		audio_stream_playback_opus.stop()
		audio_stream_playback_opus = null
		return
	set_sinewave_out(sinewaveoutmode)
	pausereached = false

func external_end_stream():
	if inopusstream:
		print(":externally ending the stream at cutout")
		receive_audio_packet(JSON.stringify({"talkingtimeend":-1}).to_ascii_buffer())

func receive_audio_packet(packet):
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
				opusframesize = int(h["opusframesize"])
				opusframecount = 0
				if h.get("opusframecount", 0) != 0:
					prints("Mid speech header!!! ", h["opusframecount"])
					opusframecount = int(h["opusframecount"]) + 1
				outoforderchunkqueue.clear()
				for i in range(Noutoforderqueue):
					outoforderchunkqueue.push_back(null)
				opusframequeuecount = 0
				assert (Npacketinitialbatching < Noutoforderqueue)
				runninglagtimeminimum = -1.0
				inopusstream = true

			elif h.has("talkingtimeend"):
				if audio_stream_playback_opus:
					audio_stream_playback_opus.finish_episode()
				pausereached = false
				print("runninglagtimeminimum: ", runninglagtimeminimum, " (target: ", audio_buffer_lag_time_target, ")")
				inopusstream = false

	elif lenchunkprefix == -1:
		pass

	elif lenchunkprefix == 0:
		if audio_stream_playback_opus == null:
			return
		audio_stream_playback_opus.push_opus_packet(packet, lenchunkprefix, 0)
		opusframecount += 1

	elif packet[1]&128 == (opusstreamcount%2)*128:
		if audio_stream_playback_opus == null:
			return
		assert (lenchunkprefix == 2)
		var opusframecountI = packet[0] + (packet[1]&127)*256
		var opusframecountR = opusframecountI - opusframecount
		if opusframecountR < 0:
			if opusframecountR < -30000:
				print("framecount Wrapround 10mins? ", opusframecount, " ", opusframecountI)
				opusframecount = opusframecountI
				opusframecountR = 0
			else:
				print("late arriving frame ignored ", opusframecountR)
			
		if opusframecountR >= 0:
			while opusframecountR >= Noutoforderqueue:
				print("shifting outoforderqueue ", opusframecountI, " ", ("null" if outoforderchunkqueue[0] == null else len(outoforderchunkqueue[0])))
				if outoforderchunkqueue[0] != null:
					audio_stream_playback_opus.push_opus_packet(outoforderchunkqueue[0], lenchunkprefix, 0)
					opusframequeuecount -= 1
				else:
					var nextvalidpacketforfec = packet
					for i in range(1, Noutoforderqueue):
						if outoforderchunkqueue[i] != null:
							nextvalidpacketforfec = outoforderchunkqueue[i]
							break
					audio_stream_playback_opus.push_opus_packet(nextvalidpacketforfec, lenchunkprefix, 1)
				outoforderchunkqueue.pop_front()
				outoforderchunkqueue.push_back(null)
				opusframecountR -= 1
				opusframecount += 1
				assert (opusframequeuecount >= 0)

			outoforderchunkqueue[opusframecountR] = packet
			opusframequeuecount += 1
			while outoforderchunkqueue[0] != null and opusframecount + opusframequeuecount >= Npacketinitialbatching:
				if opusframesize > audio_stream_playback_opus.available_space_frames():
					print("!!! segment space filled up")
					break
				audio_stream_playback_opus.push_opus_packet(outoforderchunkqueue.pop_front(), lenchunkprefix, 0)
				outoforderchunkqueue.push_back(null)
				opusframecount += 1
				opusframequeuecount -= 1
				assert (opusframequeuecount >= 0)

	else:
		prints("dropping frame with opusstream number mismatch", opusstreamcount, packet[0], packet[1], "streamcount", opusstreamcount)

var playingrecording = false
var pausereached = false
var prevskips = 0
func _physics_process(delta):
	if audio_stream_playback_opus == null:
		return
	if playingrecording:
		return
	var queuelengthframes = audio_stream_playback_opus.queue_length_frames()
	if not pausereached and queuelengthframes == 0:
		pausereached = true
		var currskips = audio_stream_playback_opus.get_skips(false)
		print("Skips during playback: ", currskips - prevskips)
		prevskips = currskips
		
	var bufferlengthtime = audioserveroutputlatency + queuelengthframes*1.0/opus_sample_rate
	if runninglagtimeminimum < 0.0 or bufferlengthtime < runninglagtimeminimum:
		runninglagtimeminimum = bufferlengthtime


func replayrecording(_speedup, recordedheader, recordedopuspackets, recordedfooter):
	playingrecording = true
	receive_audio_packet(JSON.stringify(recordedheader).to_ascii_buffer())
	for x in recordedopuspackets:
		if recordedheader["opusframesize"] > audio_stream_playback_opus.available_space_frames():
			var tmm = audio_stream_playback_opus.queue_length_frames()*0.5/opus_sample_rate
			await get_tree().create_timer(tmm).timeout
		receive_audio_packet(x)
	receive_audio_packet(JSON.stringify(recordedfooter).to_ascii_buffer())
	playingrecording = false

var sinewaveoutmode = false
func set_sinewave_out(toggled_on):
	sinewaveoutmode = toggled_on
	if audio_stream_playback_opus:
		audio_stream_playback_opus.set_sinewave_frames(opus_sample_rate/440 if toggled_on else 0, 0.05)
