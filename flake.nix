{
  description = "A flake for Godot 4 Opus VoIP gdextension";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41";
    nixpkgs-old = {
      # Match GitHub Actions' Ubuntu 22.04 GLIBC ceiling while retaining a
      # compiler new enough for current godot-cpp.
      url = "github:NixOS/nixpkgs/nixos-22.11";
      flake = false;
    };
    godot-cpp = {
      # Keep the clean Nix build on the same binding revision as the submodule.
      url = "github:godotengine/godot-cpp/58d1de720b8ffe9f8ffcdfe3a85148582cfd2e74";
      flake = false;
    };
    speexdsp = {
      url = "github:xiph/speexdsp/1b28a0f61bc31162979e1f26f3981fc3637095c8";
      flake = false;
    };
    android.url = "github:tadfisher/android-nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };
  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      perSystem = { pkgs, system, self', ... }: let
        androidenv = inputs.android.sdk.x86_64-linux (sdkPkgs: with sdkPkgs; [
          build-tools-34-0-0
          cmdline-tools-latest
          platform-tools
          platforms-android-34
          ndk-23-2-8568313
        ]);
        # Build the final extension with the same GLIBC generation as the
        # Ubuntu 22.04 GitHub runner instead of the host NixOS toolchain.
        nixpkgs-old = import inputs.nixpkgs-old { inherit system; };
        stdenv-old = nixpkgs-old.stdenv;
        opus-static = pkgs.libopus.overrideAttrs (old: {
          mesonFlags = old.mesonFlags ++ [ "-Ddefault_library=static" ];
        });
        rnnoise-static = pkgs.rnnoise.overrideAttrs (old: {
          configureFlags = (old.configureFlags or []) ++ [
            "--disable-shared"
            "--enable-static"
          ];
          # We only need the library; do not install the demo executable.
          postInstall = "";
        });
        commonEnv = {
          # A distributable GDExtension must resolve libc/libstdc++ from the
          # target system, not from this machine's immutable Nix store.
          NIX_DONT_SET_RPATH = "1";
          TWOVOIP_PATCHELF = "${nixpkgs-old.patchelf}/bin/patchelf";
          # Meson executes a compiler sanity binary while configuring APM.
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ stdenv-old.cc.cc.lib ];
        };
        packagedDependencyEnv = commonEnv // {
          TWOVOIP_OPUS_INCLUDE_DIR = "${pkgs.libopus.dev}/include/opus";
          TWOVOIP_OPUS_LIBRARY_DIR = "${opus-static}/lib";
          TWOVOIP_RNNOISE_INCLUDE_DIR = "${rnnoise-static}/include";
          TWOVOIP_RNNOISE_LIBRARY_DIR = "${rnnoise-static}/lib";
          TWOVOIP_RNNOISE_LIBRARY = "rnnoise";
        };
      in rec {
        packages.android = packages.default.overrideAttrs (_: {
          ANDROID_HOME = "${androidenv}/share/android-sdk";
          sconsFlags = [
            "platform=android"
            "webrtc_apm=no"
            "rnnoise=false"
            "opus_include_dir=${pkgs.libopus.dev}/include/opus"
            "opus_library_dir=${pkgs.pkgsCross.aarch64-multiplatform.pkgsStatic.libopus}/lib"
          ];
          doCheck = false;
        });
        packages.default = stdenv-old.mkDerivation (packagedDependencyEnv // {
          name = "opus-voip";
          src = inputs.self;
          sconsFlags = [ "webrtc_apm=no" ];
          prePatch = ''
            rm -rf godot-cpp speexdsp
            cp -r --no-preserve=mode ${inputs.godot-cpp} ./godot-cpp
            cp -r --no-preserve=mode ${inputs.speexdsp} ./speexdsp
            patch -d godot-cpp -p1 < patches/godot_cpp_exclude_unused_classes.patch
            patch -d godot-cpp -p1 < patches/unity_build.patch
          '';
          nativeBuildInputs = [
            nixpkgs-old.binutils
            pkgs.godot_4_6
            nixpkgs-old.patchelf
            nixpkgs-old.scons
          ];
          buildInputs = [
            opus-static
            rnnoise-static
          ];
          doCheck = true;
          dontPatchELF = true;
          checkPhase = ''
            runHook preCheck
            bash scripts/check_linux_abi.sh addons/twovoip/libs/libtwovoip.linux.template_debug.x86_64.so
            export XDG_DATA_HOME="$TMPDIR/twovoip-smoke/data"
            export XDG_CONFIG_HOME="$TMPDIR/twovoip-smoke/config"
            export XDG_CACHE_HOME="$TMPDIR/twovoip-smoke/cache"
            mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" .godot
            printf '%s\n' 'res://addons/twovoip/twovoip.gdextension' > .godot/extension_list.cfg
            env -u LD_LIBRARY_PATH godot4 --headless --path . --script res://tests/native_load_smoke.gd
            env -u LD_LIBRARY_PATH godot4 --headless --path . --script res://tests/resample_conditioner_smoke.gd
            env -u LD_LIBRARY_PATH godot4 --headless --path . --script res://tests/two_voip_opus_encoder_smoke.gd
            runHook postCheck
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p $out/addons
            cp -r addons/twovoip $out/addons/
            touch $out/.gdignore
            runHook postInstall
          '';
        });

        # Development deliberately builds the pinned submodules. Do not set
        # TWOVOIP_* dependency paths here: SCons defaults them to the local
        # Opus and RNNoise build directories.
        devShells.default = pkgs.mkShell.override { stdenv = stdenv-old; } (commonEnv // {
          packages = [
            nixpkgs-old.binutils
            pkgs.godot_4_6
            nixpkgs-old.patchelf
            nixpkgs-old.scons
            nixpkgs-old.cmake
            nixpkgs-old.meson
            nixpkgs-old.ninja
            nixpkgs-old.pkg-config
          ];
        });
      };
   };
}
