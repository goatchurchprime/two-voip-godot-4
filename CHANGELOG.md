# Changelog

## Unreleased

- separated manual gain from Speex automatic gain and exposed the latter as a
  read-only diagnostic value;
- replaced TwoVoIP's simulated AGC multiplier with SpeexDSP's native in-place
  preprocessing output;
- added explicit disabled, Speex and RNNoise denoiser modes for mono voice;
- reject unsupported RNNoise, stereo voice processing and processing-mode
  changes after a stream has started instead of silently degrading the signal;
- made RNNoise genuinely optional at compile time without a pass-through stub.
- made denoiser and AGC modes required `create_sampler()` configuration and
  changed its result to an `Error`, removing the unusable runtime mode setters.
- added an AGC monitor mode using a separate native Speex state whose processed
  output is discarded rather than simulated or applied.

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
