# Changelog

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
