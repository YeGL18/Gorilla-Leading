# Color Group Modes

One persisted selector (`colorGroupMode`) owns the three exclusive modes. When
absent, the old `darkKnightMode` preference supplies the initial choice. Orb
preferences are retained while their controls are hidden outside Normal mode.

- Normal: existing orb/background and dot presets.
- Dark Knight: black backgrounds and existing inset/vignette map; independent
  gold-to-orange-red dot interpolation above 100 km/h.
- M3 Concept: sampled orange-red dots at every speed, yellow Gorilla title,
  paper-white foregrounds, gray glass accents, and orange/yellow/deep-indigo
  (`20245C`) home orbs with the existing white/additive mixing enabled.
  The speed screen retains a near-black background behind its orange-red dots.
  Uses the normal full-screen map and respects the existing map appearance.

The PNG is Display P3. Its raw pixels must be interpreted in that space before
conversion to sRGB: `EF363B`, `DDD11B`, `E6EFEA`, `5C575D`, `0D0B0E`.
Do not sample through AppKit's calibrated RGB representation, which desaturates
the supplied orange-red/yellow. Status colors (GPS/warnings) remain semantic.
The original five setting swatches retain their black; only the third home orb
uses deep indigo. The near-black base, map and speed-dot colors are unchanged.
Extreme Focus temporarily selects Dark Knight and restores the prior group on
exit, unless the user selects a different group while Focus is active.

The mode is included in backups. No TestFlight upload or phone installation is
performed here. Checks cover compatibility, mode/dot policies, picker persistence,
conditional orb controls and the actual WebKit dot renderer's visible pixels.
