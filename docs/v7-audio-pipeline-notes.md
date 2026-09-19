# TwoVoIP v7 audio pipeline notes

These notes record decisions and unresolved work while the playback and capture
pipeline is being redesigned. They are not a promise that every experiment
belongs in the first v7 release.

## Order of work

1. Harden and understand `AudioStreamPlaybackOpus`.
2. Replace its single end marker with an explicit episode/timeline model.
3. Take ownership of output resampling and buffer correction.
4. Revisit `TwovoipOpusEncoder` creation and runtime controls.
5. Move microphone capture into C++ and evaluate the singleton/autoload shape.

Playback comes before the encoder API refactor because it can reveal additional
timing, packet-duration and diagnostic requirements without first breaking the
current encoder-facing GDScript API.

## Deferred encoder API work

The present `create_opus_encoder(bit_rate, complexity, voice_optimal)` method
mixes creation identity with controls which libopus permits changing while an
encoder is running.

The encoder refactor should:

- create the `OpusEncoder` as part of successful `initialize()`;
- keep the Opus input sample rate and channel count fixed for that encoder
  instance;
- keep the Opus application mode fixed after encoding starts (initially
  `OPUS_APPLICATION_VOIP`, unless an initialization enum is justified);
- replace `create_opus_encoder()` with mutable bitrate, complexity and signal
  type controls;
- expose signal type as auto/voice/music rather than the ambiguous
  `voice_optimal` Boolean;
- support libopus complexity values 0 through 10;
- make failed setters preserve the previous valid value and report the error;
- retain `reset_opus_encoder()` for the start of an unrelated stream;
- rename `output_chunk_size` to describe its real role, such as
  `packet_frame_size` or `processing_frame_size`;
- make clear that this frame size is passed to each `opus_encode_float()` call
  and is not part of the persistent Opus encoder identity;
- nevertheless keep frame duration fixed within a TwoVoIP stream initially,
  because the transport header, jitter policy and FEC recovery currently assume
  one duration;
- avoid compatibility wrappers if this is released as the v7 breaking API;
- leave the helper and demonstration GDScript migration for Julian to perform
  as an API fitness review.

If variable packet duration is added later, conditioning should operate on a
fixed small quantum (normally 10 ms) and aggregate conditioned quanta into Opus
packets. Changing packet duration must not recreate warmed denoiser or AGC
state. RNNoise and Speex preprocessing constraints need to be considered
separately from the legal Opus frame durations.

## Present playback marker model

The decoded PCM ring uses monotonic positions:

- `bufferbegin`: the next decoded PCM frame to mix;
- `buffertail`: the position after the last decoded PCM frame written;
- `bufferstreamend`: a single position at which mixing must pause.

When a talk episode ends, `mark_end_opus_stream(false)` stores the current
`buffertail` as `bufferstreamend`. The next episode can be decoded into the same
PCM ring beyond that position. `mark_end_opus_stream(true)` removes the pause,
allowing playback to cross the boundary once the application believes enough
audio is buffered.

This is not a representation of silence. It represents one application-held
gate in a physically contiguous PCM queue. Consequently:

- only one pending boundary can be represented;
- a later end marker can overwrite an earlier unconsumed marker;
- clearing early concatenates two episodes with no audible gap;
- clearing late creates arrival-dependent silence;
- queue length measures PCM, not source-time distance or intended silence;
- the buffer cannot explain where an episode or its associated animation is on
  the presentation timeline.

The original one-marker design was reasonable when hangtime made it unlikely
that a complete episode, gap and later episode would coexist in a short ring.
Short disconnected episodes and lead-in audio make that assumption less safe.

## Generalizing to multiple episodes

Do not insert potentially long silence into the PCM ring merely to preserve
gaps. Keep decoded PCM in the existing bounded ring and add a bounded FIFO of
episode metadata. A useful episode record will eventually need at least:

- an episode/stream identifier;
- absolute PCM begin and end positions in the decoded ring timeline;
- source capture position or timestamp for its first sample;
- whether its end has been received or inferred after a source/network stall;
- its desired presentation start or the intended source-time gap from the
  previous episode;
- discontinuity flags describing dropped, concealed or deliberately omitted
  source audio;
- references or source positions for viseme events belonging to the episode.

As an incremental compatibility step, the existing Boolean marker API can be
implemented as a FIFO of absolute end positions:

- `mark_end_opus_stream(false)` appends a boundary at the current write tail;
- `mark_end_opus_stream(true)` releases the oldest unreleased boundary;
- the audio thread consumes released boundaries in order and waits at the
  first unreleased boundary;
- marker overflow is diagnosed rather than overwriting an earlier boundary.

This would correctly retain N short episodes in one PCM ring, but it still
would not reconstruct an intentional source-time gap. Accurate synchronization
requires the fuller timestamped episode model.

The metadata queue must be preallocated and safe for one producer and the audio
mixing consumer. The audio callback must not allocate, lock, decode Opus or call
GDScript.

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

Useful playback observability will include:

- current source frame and decoded ring position;
- queued PCM duration and queued episode count;
- the next unreleased boundary and its intended presentation time;
- underflow, overflow, concealment, insertion, drop and resampling totals;
- source-to-mix and source-to-audible timing estimates;
- current resampling ratio and correction state;
- viseme source frame, scheduled mix frame and observed lateness.

## Playback implementation stages

1. Add deterministic tests for two and several short episodes sharing one ring,
   including a later footer arriving before an earlier boundary is consumed.
2. Replace the single marker with the bounded FIFO compatibility model.
3. Add timestamped episode metadata and explicit gap policy.
4. Replace `AudioStreamPlaybackResampled` with an owned Speex resampler whose
   normal correction is driven by the intended presentation timeline.
5. Keep large backlog recovery, Signalsmith stretching and realtime microphone
   monitoring out of this first implementation.
6. Add a replay fixture with audio and viseme timestamps before claiming
   synchronization accuracy.
7. Add a karaoke-oriented fixture driven by an authoritative song clock before
   designing its final public scheduling API.
