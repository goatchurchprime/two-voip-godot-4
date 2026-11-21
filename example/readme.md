# VoIP-over-MQTT demo project

Here you can find an example of the VoIP addon working with MQTT.

## Before launching

This branch uses [GodotEnv](https://github.com/chickensoft-games/GodotEnv) to
restore the example's addons from `addons.jsonc`. From the directory that will
contain the clone, run:

```sh
git clone --branch godotenv-v6.6.2 --single-branch https://github.com/goatchurchprime/two-voip-godot-4.git
cd two-voip-godot-4
nix shell nixpkgs#dotnet-sdk_8 --command dotnet tool restore
cd example
nix shell nixpkgs#dotnet-sdk_8 nixpkgs#unzip --command dotnet tool run godotenv addons install
```

The install command downloads the pinned public MQTT V1.5 and TwoVoIP v6.6.2
release archives. The TwoVoIP release contains the compiled Opus, RNNoise, and
SpeexDSP libraries.

### Developing TwoVoIP through a symlink

After building the native libraries in this checkout, replace the `twovoip`
entry in `addons.jsonc` with:

```jsonc
"twovoip": {
  "url": "../addons/twovoip",
  "source": "symlink"
}
```

Running `godotenv addons install` will then create
`example/addons/twovoip` as a local development link. The link is generated and
ignored by Git; it is not committed. Keep the release entry for a fresh-clone or
CI installation, because the source checkout does not contain prebuilt native
libraries.

### Switching Git branches

Use a separate clone or worktree for another branch. Git normally permits a
checkout to overwrite ignored addon files. If you do switch this working tree,
use `git switch --no-overwrite-ignore <branch>` so Git aborts instead of
silently replacing the generated addon directories.
