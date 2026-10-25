# Speed Instrument Cards

Updated 2026-10-23. Portrait order is current driving action, centered speed,
then a circular G-force plot. Native regular Liquid Glass, 24-point corners;
no location card and no wave strip. Existing speed roller, glow and dot animation
remain; the background dots are softened behind the instrument surfaces.

## Layout

- Portrait: three equal-height wide cards, with speed in the middle.
- Landscape with at least 640 points of usable width: three columns, speed wider
  in the center. Compact-height speed typography uses 72 points instead of 96.
- iPad: same geometry-driven policy, no screen-size or device-model assumptions.
- Duo partially open: upper half in portrait, leading half in landscape. Cards
  never scroll; compact instruments adapt to the available height. Controls float
  above the cards without a reserved bottom row or reduced card heights.
- Tap outside the cards to show only the centered speed and unit; tap again to
  restore cards and controls. Taps inside cards do not change this state.
- Map, satellite and orb presentation is shared with Home. Both switches use
  Home's 44-by-44-point icon labels, native glass button style and shared appearance.
- Existing AC connection switch and long-press configuration stay available.
  A chart button opens AC metadata, RPM, gear, lap and pedal details in a sheet;
  these no longer cover the three-card dashboard.

## G-force

Phone readings use Core Motion gravity-free user acceleration in G units,
projected onto a horizontal screen-right/forward basis using gravity. This
assumes a fixed phone mount facing the direction of travel; arbitrary phone yaw
does not establish vehicle heading. Left/right landscape orientations are handled
separately. Phone capture requests 120 Hz and applies two time-based 1.5 Hz
low-pass poles before publishing at 30 Hz, suppressing alternating mount/engine
vibration before downsampling. Per-axis residuals below 0.015 G display as zero;
there is no blanket 0.12 G cutoff or GPS-speed gate, so sustained gentle forces
remain observable. Startup/reorientation and gaps over 0.25 seconds reset the
filter with a 0.35-second settling period. Filtering attenuates brief peaks and
adds latency; these are filtered maneuver forces, not raw vibration measurements.
The same filtered horizontal reading drives both instruments and phone G parallax;
visual gain is never applied to measured G. Sensor capture runs while the speed page is active, independently of
the parallax toggle, and stops in the background or when the page disappears.

AC uses the remote telemetry lateral/frontal G fields at offsets 32/36. Invalid G
fields yield no G reading without dropping an otherwise valid speed packet. While
AC is the selected live source, unavailable game G values never fall back to phone
motion. Real-world AC axis conventions still require testing on the Windows rig.
AC packets bypass the phone vibration filter. Speed digits again use 3D rotation
and foreground parallax opposite the dot plane; vertical travel is bounded with
padding so the unit remains stationary below the moving digits.

Unavailable samples are shown as dashes, not invented zeros. Both instruments use the
same physical reading. Plot range covers the resultant G so diagonal loads stay
inside the outer ring. Left/right labels are kept inside narrow cards. The plot
uses native shape rendering, not a static image or a simulator-only animation.

The action card shows the dominant lateral/longitudinal direction and its axis G,
duration and axis peak. The circular plot still shows the resultant G. A 0.06 G
entry threshold, 0.04 G exit threshold, 0.2-second candidate and 0.3-second quiet
period reduce jitter. Completion time is the first quiet sample, not the delayed
confirmation. The completed result stays in the same card for six seconds or
until a new confirmed action. No toast or sheet is created.
The completed row is labelled Score, not Smoothness score. Completion inserts
the score/feedback row with a bottom fade and a restrained 0.38-second spring;
the force/peak row and action content move into their new positions together.
Action/status/duration captions crossfade, with a numeric transition on the
duration value. Only structural phase changes trigger animation, never each
incoming force sample or duration tick. Reduce Motion uses a short fade/easing.
In-progress status text/dot follow the current theme's dot accent; completed
status text/dot are green. The underlying score formula is unchanged.

This is an acceleration description, not a route instruction or proof that the
brake pedal was pressed. Timing uses monotonic uptime; source changes, invalid
samples and gaps over 0.75 seconds discard the episode without awarding a score.
The UI also stops displaying an ongoing episode once its data is stale.
The phone Current Action tracker now accepts readings only while Home's shared
visit status is driving. The status refresh continues on the speed tab; leaving
driving clears the candidate, active action and completed result. Stationary
phone G readings can still appear on the force plot but cannot create actions.
Live AC telemetry independently enables its own tracker, without creating a
real-world driving/parking state.

## Smoothness Score

This is our own local comfort heuristic, not CAPDRIVE's unknown formula, a
validated safety rating, a whole-trip score or an insurance score. Per-action
scores appear only on completion, with at least 0.6 seconds of duration and
0.4 seconds of observed intervals. No persistent trip history is added.

- Intensity = clamp((axis peak G - 0.12) / 0.53, 0...1).
- Abruptness = clamp((time-weighted RMS axis jerk in G/s - 0.15) / 1.35, 0...1).
- Score = round(clamp(100 - 70 * intensity - 30 * abruptness, 0...100)).
- Jerk comes from signed axis differences and actual sample intervals, capped
  at 5 G/s to bound isolated spikes; integration uses interval durations rather
  than packet counts. This does not eliminate differences in sensor smoothing,
  mounting or game physics, so phone and AC scores are not directly calibrated.
- Feedback distinguishes generally smooth, stronger force, and abrupt changes.
  A necessary emergency maneuver can receive a low comfort score without being
  unsafe; the number is not a recommendation to avoid braking when needed.

Sources:
- https://developer.apple.com/documentation/coremotion/cmdevicemotion/useracceleration
- https://docs.google.com/document/d/1KfkZiIluXZ6mMhLWfDX1qAGbvhGRC3ZUzjVIt5FQpp4/pub

## Verification

The circular G-force plot keeps a 1.2-second fading, tapered trail of validated
readings (at most 90 samples). It resets on missing data, source/scene changes,
or gaps longer than 250 ms. Reduce Motion keeps the live dot without a trail.
This is presentation-only and does not change sensor filtering or recorded G.

Pure checks cover projection, both landscape directions, invalid values, smoothing,
plot range and full/half-screen layout policy. Packet tests cover valid G and invalid
G with valid speed. The UI fixture uses the production speed view and a mock UDP
server, checking card order/bounds, centered speed with its unit below, AC details,
source fallback, portrait/landscape, light/dark and Duo half-screen behavior.
Synthetic traces also verify inline ongoing/completed acceleration, braking and
turning, frozen completed durations, scores without sheets, and peak retention.
Pure checks compare smooth/abrupt forces and sample rates, and reject incomplete,
brief, invalid or interrupted episodes.
Vibration checks cover synthetic 0.12 G oscillations at 5/10/20/30/35/49 Hz with
100/120 Hz sampling and 30 Hz publication, and sustained 0.08 G maneuvers with
superimposed vibration. Actual engine/mount spectra and phone sensor bandwidth
still need in-car validation; low-frequency phone movement cannot always be
distinguished from a genuine vehicle maneuver using acceleration alone.
