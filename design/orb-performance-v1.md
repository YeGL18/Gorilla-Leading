# Home Orb Rendering: First Pass

## Rendering Restoration

Canvas symbols were removed after the user reported new visible gradient rings.
Legacy orbs again use native Circle views with the original blur, sizes, motion
and isolated blend group. No grain or dither is added. Static palette preparation,
clock isolation and cached star data remain. Canvas performance measurements
below are historical and do not describe the restored renderer.

## Evidence

The supplied Gorilla-performance.csv covers 1,943 seconds. The user kept the
home orb background visible, not the map, while wirelessly charging in a car.
Thermal state reached serious at 220 seconds and stayed there. Process CPU
averaged approximately 33.7%. The file cannot attribute GPU power, temperature
or charging/sun exposure to individual app features.

The home animation clock already observes only its rendering surfaces. There
was no evidence that it was rebuilding the entire home page every frame.

## Changes

- Keep the static gradient and palette preparation outside the animation tick.
- Draw legacy orbs using Canvas symbols. Equatable symbol views preserve the
  unchanged disc fill, size and blur while each tick changes drawing positions.
- Keep the original SwiftUI plusLighter blend on the symbols. Using the Canvas
  context's plusLighter blend changed overlap colors and was rejected.
- Calculate time-phase parameters outside the clock-observing child.
- Precompute the 90 stars' fixed seeds, positions, sizes and frequencies. Keep
  native star shapes and opacity: rasterized Canvas stars changed subpixel
  brightness and were rejected.

No frame-rate reduction, thermal throttling policy, reduced blur, altered
motion, disabled mixing, lower-resolution textures or location changes.

## Verification

Tests/OrbRenderingTests.swift compares twelve old/new legacy-orb images at
multiple elapsed times and sizes, with mixing both on and off. Mean RGBA byte
differences are below 0.13 out of 255. Native-star comparison is also tested,
alongside seed and breathing equivalence.

The live CPU check alternates old/new/new/old at the same requested 60 Hz,
warming each run for two seconds and sampling five seconds of process CPU.
Simulator results are only a short regression check: they are not a prediction
of physical iPhone GPU cost, a thirty-minute battery test, or proof of lower
temperature. Earlier first-launch measurements were inconsistent; only the
alternated warmed comparison should be used.

The final alternated simulator run averaged 21.70% process CPU for the old
renderer and 20.27% for the optimized renderer (about 6.6% relative reduction).
All four rendering tests passed. Star-image pixel differences were zero.

Production changes for this pass are limited to AnimatedBackground.swift and
TimeBasedOrbView.swift. No user settings or stored parking data are migrated.
Existing unrelated working-tree changes must not be reverted with this pass.

## Remaining Work

Physical-device profiling is still needed to attribute remaining GPU/render
server work, especially moving blurred backgrounds behind Liquid Glass. A
completed build or a lower simulator CPU sample does not establish that the
reported sustained thermal issue is solved.
