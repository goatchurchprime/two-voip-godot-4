# Godot MQTT client

This folder is the installable addon. Copy `addons/mqtt` into a Godot 4
project, then instantiate `mqtt.tscn` or preload `mqtt.gd`.

Two optional native-LAN scenes are also included:

- `simulated_broker.tscn` is a limited, in-process TCP broker;
- `lan_broker.tscn` discovers an advertised broker over UDP and elects one
  instance to host the simulated broker when none is found.

Call `start()` on the LAN broker and pass the URL emitted by
`broker_available(url, hosted_here)` to the MQTT client's
`connect_to_broker(url)`.

The client implements the small MQTT 3.1.1 subset used by the included demos:

- TCP, TLS, WebSocket and secure WebSocket connections;
- publish and subscribe with QoS 0 or QoS 1;
- retained messages;
- last-will messages; and
- binary or text payloads.

QoS 2 is not implemented. Web exports must use `ws://` or `wss://`, because
browsers do not provide applications with raw TCP sockets.

The simulated broker is intended for trusted LAN development. It deliberately
omits authentication, TLS, persistence, WebSockets and QoS 2. Web exports remain
clients of an explicitly configured WebSocket broker.

For deterministic local network testing, call `configure_faults(profile)` on
either broker scene. Matching outbound `PUBLISH` messages can be delayed,
jittered, dropped, duplicated, reordered, held for a burst, or used to interrupt
a subscriber connection. MQTT control packets are not fuzzed. The hosting LAN
broker also exposes `hold_deliveries(milliseconds)` and `get_fault_counters()`.

The full source repository contains demonstrations, editor-friendly tests and
public-broker diagnostics:

https://github.com/goatchurchprime/godot-mqtt

This addon is distributed under the MIT license in `LICENSE.md`.
