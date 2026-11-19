# VoIP-over-MQTT demo project

Here you can find an example of the VoIP addon working with MQTT.

## Before launching

Install [`gdaddon`](https://github.com/brohd11/gdaddon), then run:

```sh
git clone --branch gdaddon-v6.6.2 --single-branch https://github.com/goatchurchprime/two-voip-godot-4.git
gdaddon install --all --root two-voip-godot-4/example
```

That one install command downloads the tagged MQTT V1.4 source and the public,
pinned TwoVoIP 6.6.2 release. The TwoVoIP release already contains the compiled
Opus, RNNoise, and SpeexDSP libraries; they are not separate Godot addons.
