# Changelog

## 6.4.0 - Unreleased

- added persistent output chunk configuration and a parameter-free
  `process_chunk()` path which reports the number of input frames consumed;
- added manual gain and linked mono/stereo SpeexDSP automatic gain, with the
  currently applied gain available to the caller;
- added peak, RMS and speech-probability result accessors so processing options
  no longer need to be passed for each chunk;
- deprecated `process_pre_encoded_chunk()` and `calc_audio_chunk_size()` while
  retaining them as warning-once compatibility interfaces;
- removed the unused `fetch_pre_encoded_chunk()` method, whose implementation
  always returned an empty array;
- removed the optional gain argument from `encode_chunk()` so all gain is
  configured and applied during audio processing rather than during encoding;
- left the existing microphone oscilloscope connected to raw captured samples.

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
