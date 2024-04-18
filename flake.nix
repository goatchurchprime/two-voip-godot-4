{

  # nix build -L --builders 'ssh-ng://nix-ssh@100.107.23.115 x86_64-linux,i686-linux - 16 - big-parallel'

  description = "A flake for Godot 4 VoIP extension";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    godot-cpp = {
      url = "github:godotengine/godot-cpp/48afa82f29354668c12cffaf6a2474dabfd395ed";
      flake = false;
    };
    opus = {
      url = "github:xiph/opus/ddbe48383984d56acd9e1ab6a090c54ca6b735a6";
      flake = false;
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
  };
  
  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      perSystem = { pkgs, system, self', ... }: {
        packages.default = pkgs.stdenv.mkDerivation {
          name = "two-voip";
          src = inputs.self;
          prePatch = ''
            cp -r --no-preserve=mode ${inputs.godot-cpp} ./godot-cpp
          '';
          nativeBuildInputs = [
            pkgs.scons
          ];
          buildInputs = [
            self'.packages.third-party-opus
          ];
          preBuild = ''
            substituteInPlace SConstruct \
                --replace-fail 'env.Append(CPPPATH=["opus/include"], LIBS=["opus"], LIBPATH="opus/build")' \
                               'env.Append(CPPPATH=["${inputs.opus}/include"], LIBS=["opus"], LIBPATH="${self'.packages.third-party-opus}/lib")'
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
        packages.third-party-opus = pkgs.stdenv.mkDerivation {
          name = "third-party-opus";
          src = inputs.self;
          prePatch = ''
            cp -r --no-preserve=mode ${inputs.opus} ./opus
          '';
          postPatch = ''
            ls -lah
            cd opus
          '';
          cmakeFlags = [
            "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
          ];
          nativeBuildInputs = with pkgs; [
            cmake
          ];
        };
      };
   };
}

