# Paused Parking Camera

- On the existing twenty-second inactivity timeout, request one preview frame before stopping the capture session. Retain a thumbnail of at most 640 pixels on its longest edge in memory only; no parking photo or file is created.
- Video-frame output is disabled except for this one-frame request and the first-frame readiness check when reopening. Conversion does not run continuously.
- Freeze the thumbnail immediately, animate its blur to 16 points, and retain the existing tap-to-reopen instruction. Reopening starts the session on its serial queue and waits for a new frame before fading / unblurring the frozen image over 0.8 seconds.
- A one-second timeout clears an interrupted frame request. Removing the preview stops the session and removes its photo notification observer. Capture, start and stop operations use the same serial queue.
- The capture button keeps its 66 by 166 point dimensions and original animated colored layer above interactive clear native glass. Only the opaque white background and automatic button styling are removed.
- The stationary Live Activity uses equal 90 point side columns so the address is centered independently of destination / ETA text lengths. Other activity states retain their layouts.

## Verification

- Full device-target build, including widget compilation.
- `CameraPauseUIProject.rb` generates an isolated simulator harness from the production preview, capture button and Live Activity info row. `CameraPauseUITests` checks address center, one snapshot per pause and a second pause after reopening; its screenshot verifies the glass appearance.
- Simulator frames are placeholders. Real camera freeze quality, portrait / landscape orientation, first-frame timing and permission / interruption handling must also be checked on a device.
