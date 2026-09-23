# Changelog

## Unreleased

- give each incoming talk episode its own independently provisioned
  `AudioStreamPlaybackOpus`, allowing Godot player polyphony to mix overlaps;
- replace `AudioStreamPlaybackResampled` with a playback-owned Speex resampler
  and virtual initial playout delay;
- create the Opus encoder during `TwovoipOpusEncoder.initialize()` and replace
  the separate creation call with live bitrate, complexity and signal controls;
- allow a new Speex AGC state to be warmed toward a previously observed gain
  using a short synthetic voiced signal;
- add a deferred RNNoise mode and an explicit `denoise_chunk()` operation so
  GDScript controls episode warm-up and which prepared chunks are denoised.

## 6.6.0 - 2026-09-23

- keep up to one second of conditioned microphone chunks in a bounded ring and
  let `encode_chunk()` select an earlier chunk for voice-activation rewind;
- restore configurable VOX lead time in `TwoVoipMic` so speech immediately
  before the trigger is included without continuously running the Opus encoder;

- make the decoded Opus playback ring safe between its single packet-producing
  thread and Godot's audio mixing thread, using monotonic 64-bit positions;
- report exact playback underflow, overflow and decoder-error diagnostics, and
  return the decoded frame count or libopus error from `push_opus_packet()`;
- size the Opus decode workspace correctly for packets containing up to 120 ms
  of mono or stereo audio;
- validate Opus sample rates and frame durations when initializing the encoder;
- fail encoder creation atomically when Opus rejects an option, and return an
  empty packet instead of slicing the output buffer when encoding fails;
- propagate encoder-creation failures through `TwoVoipMic.set_opus_values()`;
- use the encoder's conservative input-frame requirement for 5 ms frames at
  fractional input/output ratios instead of asserting a truncated value;
- report stereo RMS per sample rather than scaling it by the channel count;
- remove the incorrect claim that the Opus VOIP application mode enables
  in-band FEC by itself.
- document the clock-scheduled playback and v7 audio-pipeline work separately
  from the stable 6.x implementation.

## 6.5.0 - 2026-09-04

- separated manual gain from Speex automatic gain and exposed the latter as a
  read-only diagnostic value;
- replaced TwoVoIP's simulated AGC multiplier with SpeexDSP's native in-place
  preprocessing output;
- added explicit disabled, Speex and RNNoise denoiser modes for mono voice;
- reject unsupported RNNoise, stereo voice processing and processing-mode
  changes after a stream has started instead of silently degrading the signal;
- made RNNoise genuinely optional at compile time without a pass-through stub.
- made denoiser and AGC modes required one-shot `initialize()` configuration;
  failed initialization can be retried, while successful initialization keeps
  warmed voice-processing state for the object's lifetime.
- added an AGC monitor mode using a separate native Speex state whose processed
  output is discarded rather than simulated or applied.
- moved denoiser and AGC selection into `TwoVoipMic.set_opus_values()` and kept
  stream shutdown or reconfiguration policy outside the helper.
- normalized SpeexDSP's dedicated 0–100 speech probability to 0–1 instead of
  incorrectly treating `speex_preprocess_run()`'s VAD Boolean as a probability.
- kept the radio's last completed-sample AGC gain at the PTT falling edge and
  used it with manual gain when reprocessing the stored raw recording.
- added experimental `get_current_chunk_16khz(reset_sampler)` as a lazy,
  caller-managed adapter for external speech and viseme analysers; it performs
  no work in the main processing loop and can reset history after skipped chunks.
- removed immutable-configuration getters and the legacy chunk-size and
  reprocessing methods; retained only the derived input-size requirement,
  mutable gain, and per-chunk processing results.

## 6.4.0 - 2026-09-04

- configured the output chunk size with `create_sampler()` and added a
  parameter-free `process_chunk()` path which reports consumed input frames;
- added manual gain and linked mono/stereo SpeexDSP automatic gain, with the
  currently applied gain available to the caller;
- made AGC start explicitly at SpeexDSP's fixed gain of 1.0, reject manual gain
  changes while active, and return configuration failures as errors;
- exposed gain, AGC state, chunk sizes and measurements as read-only Inspector
  properties;
- added peak, RMS and speech-probability result accessors so processing options
  no longer need to be passed for each chunk;
- deprecated `process_pre_encoded_chunk()` and `calc_audio_chunk_size()` while
  retaining them as warning-once compatibility interfaces;
- removed the unused `fetch_pre_encoded_chunk()` method, whose implementation
  always returned an empty array;
- removed the optional gain argument from `encode_chunk()` so all gain is
  configured and applied during audio processing rather than during encoding;
- left the existing microphone oscilloscope connected to raw captured samples.

Development disclosure: this release was prepared with assistance from OpenAI
Codex, an AI coding agent based on GPT-5. Codex assisted with API analysis,
implementation, documentation, builds, runtime testing and SpeexDSP behaviour
verification. The work was directed and reviewed by Julian Todd.

## 6.3.0 - 2026-09-03

- replaced the copied Speex resampler sources with the official SpeexDSP
  submodule pinned to release `SpeexDSP-1.2.1`, preserving the same resampler
  implementation and public TwoVoIP API.

Development disclosure: this release was prepared with assistance from OpenAI
Codex, an AI coding agent based on GPT-5. Codex assisted with dependency
provenance analysis, implementation, documentation, builds, runtime resampler
testing, CI verification and release preparation. The work was directed and
reviewed by Julian Todd.

## 6.2.0 - 2026-09-03

- replaced the `noise-suppression-for-voice` wrapper with a direct Xiph
  RNNoise submodule pinned to the same upstream source revision;
- added a minimal cross-platform CMake adapter which retrieves the matching
  Xiph default model and verifies its SHA-256 checksum.

Development disclosure: this release was prepared with assistance from OpenAI
Codex, an AI coding agent based on GPT-5. Codex assisted with repository
inspection, implementation, documentation, builds, runtime smoke testing, CI
verification and release preparation. The work was directed and reviewed by
Julian Todd.

## 6.1.0 - 2026-09-03

- removed the obsolete proprietary OVRLipSync integration, alternate addon and
  duplicate CI build variants without changing the Opus packet interface;
- changed routine decoder and RNNoise initialization messages to verbose
  logging (contributed in pull request #93);
- pinned godot-cpp to its official Godot 4.6-stable release.

Development disclosure: this release was prepared with assistance from OpenAI
Codex, an AI coding agent based on GPT-5. Codex assisted with repository
inspection, implementation, documentation, builds, smoke testing and release
preparation. The work was directed and reviewed by Julian Todd.

## 6.0

- Converted the public GDScript helper API to snake_case and simplified the
  example and stream-header handling.
