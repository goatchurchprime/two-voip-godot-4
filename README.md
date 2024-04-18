hand made clone of https://github.com/RevoluPowered/one-voip-godot-4/
for the purpose of experimental hacking
and learning how to make small GDExtensions

Instructions:

The build system is defined by the flake.nix file

> nix build  # makes the result directory that links into the nix store
> cd addons
> ln -s ../result/addons/twovoip/ twovoip


