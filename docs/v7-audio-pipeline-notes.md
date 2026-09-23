# TwoVoIP v7 audio pipeline notes

These notes record decisions and unresolved work while the playback and capture
pipeline is being redesigned. They are not a promise that every experiment
belongs in the first v7 release.

## Order of work

1. Completed in v6.6: harden and understand `AudioStreamPlaybackOpus`.
2. Implemented for v7: give each talk episode its own playback, decoder and
   bounded PCM ring.
3. Implemented for v7: take ownership of output resampling and initial playout
   delay.
4. Implemented for v7: make Opus encoder bitrate, complexity and signal type
   runtime controls.
5. Next: move microphone capture into C++ and evaluate the singleton/autoload
   shape.

Playback comes before the encoder API refactor because it can reveal additional
timing, packet-duration and diagnostic requirements without first breaking the
current encoder-facing GDScript API.

## Encoder runtime controls

Successful `TwovoipOpusEncoder.initialize()` now creates the Opus encoder.
The input sample rate, channel count and `OPUS_APPLICATION_VOIP` application
mode remain fixed for that encoder instance. Bitrate, complexity and the
auto/voice/music signal hint are mutable while encoding; failed setters report
an error and preserve the previous value. `reset_opus_encoder()` remains
available for the start of an unrelated stream.

Remaining encoder cleanup should:

- rename `output_chunk_size` to describe its real role, such as
  `packet_frame_size` or `processing_frame_size`;
- make clear that this frame size is passed to each `opus_encode_float()` call
  and is not part of the persistent Opus encoder identity;
- nevertheless keep frame duration fixed within a TwoVoIP stream initially,
  because the transport header, jitter policy and FEC recovery currently assume
  one duration;
- leave the helper and demonstration GDScript migration for Julian to perform
  as an API fitness review.

If variable packet duration is added later, conditioning should operate on a
fixed small quantum (normally 10 ms) and aggregate conditioned quanta into Opus
packets. Changing packet duration must not recreate warmed denoiser or AGC
state. RNNoise and Speex preprocessing constraints need to be considered
separately from the legal Opus frame durations.

## Present playback model

`AudioStreamOpus` is a stateless factory. Each `AudioStreamPlayer.play()` call
creates a new `AudioStreamPlaybackOpus`, and that playback represents exactly
one talk episode. The helper provisions it from the episode header with its
Opus rate, channel count, buffer capacity and initial playout delay.

Each playback owns its Opus decoder, decoded PCM ring, Speex output resampler
and episode state. `finish_episode()` closes only that playback; it drains and
then stops itself. A playback whose footer is lost also stops after its receive
queue has remained empty for the configured stale timeout. The
`AudioStreamPlayer` and AudioServer mix overlapping playbacks, while
`max_polyphony` bounds their number and determines when the oldest voice is
discarded.

This removes the need for an end-marker FIFO or `OpusPlaybackTimeline`. It also
keeps gaps honest: two episodes are not physically concatenated in one PCM
ring. The current two-byte packet prefix can still identify only the current
receiving episode, however. It permits an older episode to drain while a newer
one receives, but truly interleaved voice and instrument streams will require a
wider episode identifier and a playback lookup in the transport helper.

## Toward timestamped episodes

Do not insert potentially long silence into a playback's PCM ring merely to
preserve gaps. The playback itself is the episode record. It will eventually
need at least:

- an episode/stream identifier;
- its source-frame begin and end positions;
- source capture position or timestamp for its first sample;
- whether its end has been received or inferred after a source/network stall;
- its desired presentation start or the intended source-time gap from the
  previous episode;
- discontinuity flags describing dropped, concealed or deliberately omitted
  source audio;
- references or source positions for viseme events belonging to the episode.

Accurate synchronization still requires source timestamps and a mapping to the
destination mix clock. Episode objects remove cross-episode ring bookkeeping;
they do not create that clock mapping by themselves. Every playback buffer must
remain preallocated and safe for one producer and the audio mixing consumer.
The audio callback must not allocate, lock, decode Opus or call GDScript.

## Leadtime

Voice-activation leadtime means the first transmitted PCM in an episode was
captured before the threshold crossing which opened the episode. It can make an
initial playback target fill sooner and reduce perceived clipped onsets, but it
also means that `talkingtimestart` is not automatically the timestamp of the
first sample.

The capture side should distinguish:

- first captured sample included in the episode;
- VOX trigger time;
- first packet transmission time.

Buffer capacity must allow for leadtime plus the target playout buffer, network
jitter and correction margin. These quantities should be visible separately in
diagnostics rather than collapsed into one queue-length value.

## Audio, viseme and karaoke time

Arrival time must not be treated as presentation time. The eventual system
needs an explicit mapping between:

1. source capture frames;
2. Opus packet/source frames;
3. decoded PCM ring positions;
4. destination audio mix frames;
5. estimated audible time after device output latency;
6. viseme source positions and their model delay/alignment correction.

Adaptive resampling changes the slope of the source-to-output mapping. Dropping
or inserting frames changes its offset. Every correction must therefore update
one shared presentation mapping used by audio diagnostics and viseme delivery.
Visemes should be applied according to the audio frame expected to be audible,
not when their packet arrives or is decoded.

Karaoke adds an external authoritative song clock. Voice packets intended to
align with a song need a song-relative source timestamp (or an accurately
convertible shared clock). The receiver should schedule them against that clock
and use an explicit late-data policy. Independently chasing a generic queue
target with `AudioStreamPlayer.pitch_scale` cannot guarantee song or viseme
alignment.

## Reference clocks and cross-machine capture

Every captured sample has an exact position in its source device's media
clock. It does not automatically have an exact UTC capture time. The device
oscillator runs independently of the operating-system clock, its nominal
48 kHz is not exact, and an application may only learn that a block was
captured after driver and input-buffer delay.

NTP does estimate a computer's offset from a shared reference clock while
accounting for round-trip network delay. This is sufficient to give machines a
common, approximate timebase, but asymmetric network paths and software/device
latency leave uncertainty. Ordinary Internet NTP must therefore not be treated
as sample-accurate capture timing. PTP with hardware timestamping can be much
more accurate on a controlled LAN, but cannot be assumed for normal TwoVoIP
users.

UTC itself is optional. All participants only need a common session reference.
A session host can periodically exchange four timestamps with each client to
estimate offset, round-trip time, drift and uncertainty. Wall time should be an
anchor for that mapping, not the clock used directly inside the audio callback:
system time may be corrected, whereas the callback needs a monotonic timeline.

For each source, retain a monotonic capture-frame counter and estimate an
affine mapping such as:

```
session_time = source_time_offset + source_frame / observed_source_rate
```

Periodically refreshed timestamp pairs estimate both the offset and the real
device rate. Packets carry the source frame position (or a compact delta from
it), while less frequent control packets carry its mapping to session time and
an uncertainty estimate. This follows the same broad model as RTP timestamps
paired with NTP-format time in RTCP Sender Reports. A capture-time extension
can make the first sample's reference time explicit.

This can align two remote sources to a useful tolerance and schedule both for
the same future presentation deadline. It cannot by itself remove different
microphone-driver capture latencies, sound propagation time, or destination
output latency. Closely colocated microphones recording the same sound can use
cross-correlation as an optional calibration/measurement of their remaining
offset. A future Godot audio-driver change may be needed for trustworthy
hardware capture timestamps; the C++ microphone owner can meanwhile maintain
the frame counter and best available monotonic-clock correlation.

Relevant standards are [NTPv4 (RFC 5905)](https://www.rfc-editor.org/rfc/rfc5905),
[RTP/RTCP (RFC 3550)](https://www.rfc-editor.org/rfc/rfc3550), and
[RTP clock source signalling (RFC 7273)](https://www.rfc-editor.org/rfc/rfc7273).

## Scheduled pre-roll instead of pause/unpause

The proposed 400 ms of zeros is a good conceptual simplification if it is a
receiver-side playout reserve, not silence transmitted over the network. On the
first packet of an episode, schedule its first sample for a deadline such as:

```
presentation_time = mapped_capture_time + target_playout_delay
```

Until that deadline the episode playback emits zero. Packets accumulate during
the reserve, so playback begins with the intended amount of jitter protection.
If the episode arrives late or catch-up policy requests it, the reserve can be
shortened or skipped.

The current playback represents this as a scheduled output frame rather than
physically filling the decoded PCM ring with zeros. Physical zeros would consume
ring capacity, inflate the PCM queue metric and become indistinguishable from
real recorded silence. At present the deadline is relative to playback
initialization; a later change must derive it from the episode's mapped capture
time.

At minimum, timeline spans must distinguish:

- discardable playout reserve;
- real source silence or a deliberate between-episode gap;
- packet-loss concealment;
- decoded source audio.

Only the first category is freely skippable. Real source silence is meaningful
for synchronization, visemes and karaoke unless an explicit speed-up policy
chooses to remove it. Concealment needs its own diagnostics and correction
policy.

A deadline-driven timeline makes queue length a safety diagnostic rather than
the primary clock. The initial target should be configurable and later
adaptive; 400 ms is a sensible experiment, not a protocol constant. Scheduling
must subtract or otherwise account for known output latency and processing
delay when converting the desired audible time to a destination mix frame.
Karaoke should use the song clock as the authoritative presentation timeline.

Useful playback observability will include:

- current source frame and decoded ring position;
- queued PCM duration and active episode count;
- each episode's intended presentation time;
- underflow, overflow, concealment, insertion, drop and resampling totals;
- source-to-mix and source-to-audible timing estimates;
- current resampling ratio and correction state;
- viseme source frame, scheduled mix frame and observed lateness.

## Playback implementation stages

1. Implemented: give every episode an independently provisioned playback and
   verify Godot player polyphony with deterministic tests.
2. Implemented: replace `AudioStreamPlaybackResampled` with a playback-owned
   Speex resampler and a virtual initial playout delay.
3. Next: add source timestamps and explicit gap policy to the episode header.
4. Add an episode identifier and playback lookup if packets from multiple
   episodes may be interleaved.
5. Add a source-frame-to-session-clock estimator and schedule playback against
   deadlines while reporting its current timing uncertainty.
6. Drive small Speex ratio corrections from the intended presentation timeline.
7. Keep large backlog recovery, Signalsmith stretching and realtime microphone
   monitoring out of this first implementation.
8. Add a replay fixture with audio and viseme timestamps before claiming
   synchronization accuracy.
9. Add a karaoke-oriented fixture driven by an authoritative song clock before
   designing its final public scheduling API.
