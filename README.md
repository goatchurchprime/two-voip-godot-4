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

eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiI1YjM0OWE1YmUxMmQ0M2EwOTRiNmY2OGY0YmNlMDQ2OCIsImlhdCI6MTcxNDkxMjY2MywiZXhwIjoyMDMwMjcyNjYzfQ.D6ejMB5DGDTxEQTxAhBZqymlgSqXqMc96KCpZ3w8O5U

wss://192.168.0.101

https://4gkw847c6plmeh6tlc8jn7i86m3f653a.ui.nabu.casa/
