hand made clone of https://github.com/RevoluPowered/one-voip-godot-4/
for the purpose of experimental hacking
and learning how to make small GDExtensions

Instructions:

The build system is defined by the flake.nix file

 * makes a result directory that needs to be copied into addons
> nix build
> cp result/addons/twovoip/*so addons/twovoip

 * android version:
> nix build .#android
> cp result/addons/twovoip/*so addons/twovoip

Make sure addons/twovoip/twovoip.gdextension point to these files:
