# Orb Banding Mitigation

## Current Status: Optional Renderer

Update: Settings now offers an opt-in `Canvas Symbols + Dither` renderer for
the standard orb background. `orbCanvasDitherEnabled` defaults to false and is
included in full backups. The native selection bypasses Canvas, drawingGroup
and the dither shader entirely; the confirmed-clean native rendering stays the
default. Time-based orbs retain their native blur renderer. Historical notes
below describe the original experiment, which is now accessible only via the
explicit Canvas selection rather than imposed on all backgrounds.

The user traced the visible rings to Canvas symbols and confirmed that
restoring native Circle / blur / offset / blend rendering eliminated them on
their iPhone. Native is therefore the default; Canvas and noise processing
remain strictly opt-in. Simulator comparisons alone cannot establish the
physical display's appearance.

Restoration verification: all five OrbRenderingTests passed on the Duo
simulator. Twelve legacy comparisons (portrait/landscape, normal/additive
mixing, three animation times) and both dark-palette comparisons matched the
pre-Canvas native reference exactly. These are appearance-regression checks,
not a physical-display banding assessment.

## Diagnosis

The user reports visible contours in blurred orb gradients. The new legacy
Canvas uses its default non-linear rendering mode. Low-amplitude blur/alpha
variations and intermediate/final color quantization are plausible causes,
but source inspection and 8-bit PNG exports cannot establish the physical
display's complete rendering precision or prove a single cause.

Switching the canvas to a linear working space previously changed overlap
colors. Do not enable HDR/extended-linear rendering as a blind banding fix.

## Implementation

- `OrbDitherModifier` applies Apple's SwiftUI colorEffect shader API after the
  opaque background and orb composition, for both legacy and time-based orbs.
- `orbDither` in the existing compiled Metal source adds static luminance noise
  with amplitude +/-1/255. All RGB channels receive the same offset.
- Noise is keyed to physical pixel coordinates using displayScale; there is no
  time argument, random CPU loop, extra timer, or generated image each frame.
- Alpha remains unchanged. Clamp premultiplied RGB to the alpha range.
- UI controls, text, glass and maps are outside the filtered background.

This masks quantization contours; it does not recover lost precision, change
the palette, enable HDR, or guarantee removal of every visible contour.

## Verification

Three simulator tests passed:

1. Shader changes pixels, repeated renders match, alpha is unchanged, and
   output stays within two byte levels of a flat-color reference.
2. Twelve phone/Duo orb comparisons, mixing on/off and three elapsed times:
   mean RGBA difference with dither is under one byte level versus no dither.
3. Warmed alternating no-dither/dither/dither/no-dither CPU samples at 60 Hz:
   21.95% versus 21.13% process CPU. Treat this as no observed CPU regression,
   not evidence of faster rendering or lower physical-device GPU power.

Log: `/private/tmp/gorilla-dither-verified-tests.log`.
Physical-device visual inspection and sustained thermal profiling remain.

## Follow-up: Contours Still Visible on iPhone

The user's dark-mode screenshot still shows orb contours after the final
colorEffect noise. Final noise cannot restore precision already lost by an
upstream blur/alpha surface. This is an inference from the rendering path,
not a GPU capture establishing every intermediate pixel format.

Legacy orb symbols now draw into an extended-linear Canvas and use
`GraphicsContext.Filter.blur(radius:options: .dithersResult)`. The outer
motion Canvas also uses extended-linear mode. Blur padding is three radii
on each edge; symbol equality continues to cache unchanged fill/size/blur.
The native plusLighter blend stays outside the per-disc blur Canvas.

The `antiBanding` argument exists for regression fixtures, defaulting to true.
The time-based rendering path is not rewritten in this follow-up.

Twelve reference comparisons pass with mean RGBA differences below 0.26 byte
levels. Dark palette checks are below 0.29 byte levels. Moving plusLighter
inside a flattened drawingGroup changed colors (about 10.94 byte levels) and
was rejected. Using the native blur dither improves the exported dark image's
contours, but a physical-device visual check remains necessary.

Alternating warmed CPU samples with final noise on in both cases measured
21.10% before native blur dithering versus 20.70% after. This shows no obvious
simulator CPU regression, not a demonstrated performance gain. Float surfaces
may increase GPU memory/bandwidth; physical-device power remains unverified.
CPU log: `/private/tmp/gorilla-orb-native-blur-cpu.log`.

## Follow-up: Final Background Composition

The user still reports banding on the physical iPhone. No claim that the prior
native blur change solved it is justified by the simulator comparisons.

The legacy opaque background now uses an extended-linear drawingGroup for the
last background/orb composition, before the final shader. Shader.dithersColor
is explicitly enabled so native shader output conversion can also dither.
The custom shader's noise amplitude is not increased. The time-based path keeps
its existing composition (highPrecisionComposite: false); it receives only the
native shader-output dithering option.

Four visual tests passed. The final float-composite comparison's mean RGBA byte
error is 0.393; the dark palette comparison stays below 0.462 byte levels.
Static noise/alpha checks and all twelve phone/Duo comparisons pass.

Alternating final-composite CPU samples: 21.89% without the explicit float
group versus 20.72% with it. This is only no observed CPU regression; GPU cost,
bandwidth, device screenshots and sustained heat remain unverified.

Logs: `/private/tmp/gorilla-orb-final-composite-tests.log` and
`/private/tmp/gorilla-orb-final-composite-cpu.log`.

This is another controlled hypothesis, not a confirmed GPU root-cause capture.
If physical-device contours persist, obtain a new screenshot and GPU capture
before increasing noise or adding more offscreen layers.

Apple references:
- https://developer.apple.com/documentation/swiftui/graphicscontext/bluroptions/dithersresult
- https://developer.apple.com/documentation/swiftui/canvas/colormode

## Reversibility

Remove the two `OrbDitherModifier` applications to disable this experiment.
Do not revert the earlier orb optimization or unrelated worktree changes.
