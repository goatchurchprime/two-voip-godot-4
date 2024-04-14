{

  # nix build -L --builders 'ssh-ng://nix-ssh@100.107.23.115 x86_64-linux,i686-linux - 16 - big-parallel'

  description = "A flake for Godot 4 VoIP extension";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    one-voip-godot-4 = {
      url = "git+https://github.com/RevoluPowered/one-voip-godot-4?submodules=1";
      flake = false;
    };
    flake-utils.url = "github:numtide/flake-utils";
  };
  
  outputs = { nixpkgs, flake-utils, one-voip-godot-4, self, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          name = "one-voip";
          src = one-voip-godot-4;
          nativeBuildInputs = [
            pkgs.scons
          ];
          buildInputs = [
            self.packages.${system}.third-party-opus
          ];
          preBuild = ''
            substituteInPlace SConstruct \
                --replace-fail 'env.Append(CPPPATH=["thirdparty/opus/include"], LIBS=["opus"], LIBPATH="thirdparty/opus/build")' \
                               'env.Append(CPPPATH=["thirdparty/opus/include"], LIBS=["opus"], LIBPATH="${self.packages.${system}.third-party-opus}/lib")'
          '';
          installPhase = ''
            mkdir $out/addons
            mkdir $out/addons/onevoip
            cp demo_rtc/bin/* $out/addons/onevoip
            substituteInPlace $out/addons/onevoip/onevoip.gdextension --replace-fail 'res://bin' 'res://addons/onevoip'
          '';

        };
        packages.third-party-opus = pkgs.stdenv.mkDerivation {
          src = one-voip-godot-4;
          name = "third-party-opus";
          postPatch = ''
            cd thirdparty/opus
            ls -lah
          '';
          cmakeFlags = [
            "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
          ];
          nativeBuildInputs = with pkgs; [
            cmake
          ];
        };


#  cd opus; cmake -Bbuild -DCMAKE_POSITION_INDEPENDENT_CODE=ON
#  cd build; make
#  cd ../..; scons 


        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            scons
            cmake
         ];
        };
      });
}

