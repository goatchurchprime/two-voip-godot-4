{

  # nix build -L --builders 'ssh-ng://nix-ssh@100.107.23.115 x86_64-linux,i686-linux - 16 - big-parallel'

  description = "A flake for Godot 4 VoIP extension";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    two-voip-godot-4 = {
      url = "git+https://github.com/goatchurchprime/two-voip-godot-4?submodules=1";
      flake = false;
    };
    flake-utils.url = "github:numtide/flake-utils";
  };
  
  outputs = { nixpkgs, flake-utils, two-voip-godot-4, self, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          name = "two-voip";
          src = two-voip-godot-4;
          nativeBuildInputs = [
            pkgs.scons
          ];
          buildInputs = [
            self.packages.${system}.third-party-opus
          ];
          preBuild = ''
            substituteInPlace SConstruct \
                --replace-fail 'env.Append(CPPPATH=["opus/include"], LIBS=["opus"], LIBPATH="opus/build")' \
                               'env.Append(CPPPATH=["opus/include"], LIBS=["opus"], LIBPATH="${self.packages.${system}.third-party-opus}/lib")'
          '';
          installPhase = ''
            mkdir $out/addons
            mkdir $out/addons/twovoip
            cp addons/twovoip/* $out/addons/twovoip
          '';
        };
        packages.third-party-opus = pkgs.stdenv.mkDerivation {
          src = two-voip-godot-4;
          name = "third-party-opus";
          postPatch = ''
            cd opus
            ls -lah
          '';
          cmakeFlags = [
            "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
          ];
          nativeBuildInputs = with pkgs; [
            cmake
          ];
        };



        # To hack the code, do:
        #  nix develop
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

