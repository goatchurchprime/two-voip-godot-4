# Optional WebRTC Audio Processing Module

TwoVoIP pins the standalone freedesktop.org `webrtc-audio-processing` v2.1
submodule at commit `846fe90a289f58b7c9303a635142aa2c7caa93e5`. This is the
PulseAudio/PipeWire packaging of WebRTC APM, not the Chromium/WebRTC monorepo.

The integration is initially Linux x86_64 development-only and defaults off.
The normal build does not compile WebRTC headers, expose WebRTC objects, or add
WebRTC runtime dependencies.

## Linux development build

```bash
git submodule update --init --recursive
nix-shell -p scons meson ninja pkg-config cmake autoreconfHook
scons apply_patches
scons build_opus
scons build_rnnoise
scons build_webrtc_apm platform=linux arch=x86_64 target=template_debug
scons webrtc_apm=yes platform=linux arch=x86_64 target=template_debug
```

The APM build uses C++20 and the checksum-pinned Abseil fallback declared by
upstream. Abseil is linked statically into one companion library:

`addons/twovoip/libs/libwebrtc-audio-processing-2.so.1`

The enabled `libtwovoip` has a direct `DT_NEEDED` dependency on that companion
and an `$ORIGIN` runpath, so both files must remain together in the addon
`libs` directory. If the companion is absent, Godot cannot load the enabled
GDExtension. This deliberate link-time contract is safer than resolving a C++
API dynamically. A future independently optional binary should expose a small
stable C ABI shim rather than dynamically loading WebRTC C++ symbols.

Run the enabled smoke test with a compatible Godot binary:

```bash
godot --headless --path example --script res://tests/webrtc_apm_smoke.gd
```

The wrapper owns APM lifecycle, reset, mono-float 10 ms capture processing, and
reverse/render processing for later AEC. `DENOISER_WEBRTC` enables the APM
moderate noise suppressor in TwoVoIP's existing `denoise_chunk()` path. It
accepts mono 8, 16, or 48 kHz audio in chunks made from whole 10 ms frames.
The smoke test exercises both the low-level seam and this live encoder path.

Other platforms, release packaging, delay alignment, and live AEC/AGC2 policy
remain out of scope for this noise-suppression integration.

## Current portability result

The first NixOS development companion requires `GLIBC_2.38`, dynamically uses
`libstdc++.so.6` and `libgcc_s.so.1`, and contains Nix-store runpaths. The
existing release ABI check therefore rejects it against TwoVoIP's Ubuntu 22.04
`GLIBC_2.35` ceiling. It is suitable for the matched local smoke test, not for
release packaging. A distributable Linux companion must be built and checked
on the existing Ubuntu 22.04 CI runner. Because the APM C++ object lifetime
crosses the extension/companion boundary, both must also use one compatible
dynamic C++ runtime; statically embedding a second `libstdc++` is not treated
as isolation.
