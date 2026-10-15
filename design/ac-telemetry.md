# Assetto Corsa Direct Telemetry

Original Windows AC only; not ACC or EVO. No PC relay dependency.

## Source Boundary

The lower-left computer control toggles automatic connection on tap and opens
connection settings on long press, with exclusive gestures to avoid toggling on
a long press. The host and enabled setting persist. The root owns the client without
observing physics packets; the speed view observes it. Listening continues across
tabs while foregrounded. Backgrounding dismisses the subscription; foregrounding
reconnects when enabled. The phone does not maintain a background game connection.

The computer control is green when disabled, yellow while waiting and purple on
fresh AC packets. Waiting explicitly says GPS and uses real GPS speed. Fresh AC
packets automatically select game speed; loss of packets explicitly returns to GPS.
Both sources use the existing speed roller, centered digits and dot canvas.
The AC overlay sits around the speed display, not behind an opaque dashboard.
AC never writes to LocationManager, visits, parking, prediction or motion history.

## Protocol

- User supplies a Windows LAN host; UDP port 9996.
- Handshake operation 0; subscribe updates operation 1; dismiss operation 3.
- Handshake response: 408 bytes, UTF-16LE names, marker 4242 and version 1.
- Physics response: 328 bytes, identifier a, aligned little-endian fields.
- Gear is 0 reverse, 1 neutral, 2 first forward gear.
- Receive every packet; coalesce UI publication to 30 Hz.
- No valid physics packet for 3 seconds clears readings and shows waiting.
- Retry handshake every 2 seconds while waiting; refresh metadata every 15 seconds.
- Transport failures recreate the connection every 3 seconds until disabled.
- RPM bar has an explicit 30,000 RPM display scale, not a claimed car redline.
- Throttle/brake are finite 0...1 floats; shown as green/red bars and percentages.
- Pedals are fixed-size vertical columns filled from bottom to top: brake left,
  throttle right. Landscape side information uses mirrored 32-degree Y-axis
  perspective toward the center. This is a static projection, not an animated
  motion effect, so Reduce Motion does not flatten it.

Protocol reference: https://docs.google.com/document/d/1KfkZiIluXZ6mMhLWfDX1qAGbvhGRC3ZUzjVIt5FQpp4/pub
Wire-layout cross-check: https://github.com/rickwest/ac-remote-telemetry-client/tree/master/src/parsers

## Focus Removal

The three-level focus sheet, button, temporary Dark Knight override and detection,
ETA and Live Activity gates have been removed. Connection choice no longer changes
the color group or suppresses parking/stay updates. Existing animation preferences
remain available; parallax is still capped at 60 Hz.

## Verification

Packet checks cover speed/RPM/gear/lap, UTF-16 metadata, commands, truncation,
invalid markers, non-finite speed and invalid gears. An actual Windows AC session
is still required to verify game configuration, firewall, Wi-Fi and packet delivery.
Do not expose UDP through an internet router for this feature.

An isolated UI fixture runs a mock AC UDP server against the real production
client, verifies received readings and metadata, rotates the dashboard and stops
transmission to verify that stale speed/RPM disappear. Mock data is not present in
the production app.
