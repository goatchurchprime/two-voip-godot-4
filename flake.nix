{
  description = "A flake for Godot 4 Opus VoIP gdextension";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-old = {
      url = "github:NixOS/nixpkgs/nixos-19.09";
      flake = false;
    };
    godot-cpp = {
      url = "github:godotengine/godot-cpp/48afa82f29354668c12cffaf6a2474dabfd395ed";
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
        # older glibc to make gdextension work on older linux distributions
        nixpkgs-old = import inputs.nixpkgs-old { inherit system; };
        glibc-old = nixpkgs-old.glibc // { pname = "glibc"; };
        cc-old = pkgs.wrapCCWith {
          cc = nixpkgs-old.buildPackages.gcc-unwrapped;
          libc = glibc-old;
          bintools = pkgs.binutils.override {
            libc = glibc-old;
          };
        };
        stdenv-old = (pkgs.overrideCC pkgs.stdenv cc-old);
      in rec {
        packages.android = packages.default.overrideAttrs {
          ANDROID_HOME = "${androidenv}/share/android-sdk";
          sconsFlags = [
            "platform=android"
          ];
          preBuild = ''
            substituteInPlace SConstruct \
                --replace-fail 'env.Append(CPPPATH=["opus/include"], LIBS=["opus"], LIBPATH="opus/build")' \
                               'env.Append(CPPPATH=["${pkgs.libopus.dev}/include/opus"], LIBS=["opus"], LIBPATH="${pkgs.pkgsCross.aarch64-multiplatform.pkgsStatic.libopus}/lib")'
          '';
        };
        packages.default = stdenv-old.mkDerivation {
          name = "opus-voip";
          src = inputs.self;
          prePatch = ''
            cp -r --no-preserve=mode ${inputs.godot-cpp} ./godot-cpp
          '';
          nativeBuildInputs = [
            pkgs.scons
          ];
          buildInputs = [
            pkgs.pkgsStatic.libopus
          ];
          preBuild = ''
            substituteInPlace SConstruct \
                --replace-fail 'env.Append(CPPPATH=["opus/include"], LIBS=["opus"], LIBPATH="opus/build")' \
                               'env.Append(CPPPATH=["${pkgs.libopus.dev}/include/opus"], LIBS=["opus"], LIBPATH="${pkgs.pkgsStatic.libopus}/lib")'
          '';
          installPhase = let
            configFile = builtins.toFile "configFile.toml" ''
              [configuration]

              entry_symbol = "two_voip_library_init"
              compatibility_minimum = 4.2

              [libraries]
              linux.x86_64="res://addons/twovoip/libtwovoip.linux.template_debug.x86_64.so"
            '';
          in ''
            mkdir $out/addons
            mkdir $out/addons/twovoip
            cp addons/twovoip/* $out/addons/twovoip

            cp ${configFile} $out/addons/twovoip/twovoip.gdextension

            echo "" > $out/.gdignore
            ls -lah $out
          '';
        };
      };
   };
}
