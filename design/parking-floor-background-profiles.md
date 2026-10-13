# Parking Floor Capture and Height Profiles

## Rules

- Automatic capture starts when a recent driving speed of at least 30 km/h falls below 30 km/h. Foreground capsule visibility is not a prerequisite.
- Capture remains continuous through a brief stop or gate wait. The brief-stop stage is 5 seconds; the final stable-stop stage is 1 additional second.
- Without a bound parking visit, an unanswered confirmation prompt does not stop sampling. A bound visit and stable height can finalize automatically. Walking can finalize the last stable stopped snapshot before subsequent pedestrian height changes.
- Estimates are saved without a tick. Automatic confirmation is not human confirmation and does not train calibration.
- Training requires human confirmation, a promptly captured approach reference, no sensor gap longer than 2.5 seconds, and a stable stopping segment with sufficient samples.
- Calibration uses measured height distributions per floor and reference floor. A confirmed 9.7 m approach-to-1/F measurement is not interpreted as three floors.
- Historical measurements without completeness metadata remain stored but are excluded from calibration. Manual floor correction alone does not make an incomplete measurement eligible.
- The live curve labels learned floor heights. Without a reliable height profile, the axis labels meters rather than asserting uniform floor spacing.

## Verification

- `ruby Tests/ParkingAltitudeChecks.rb`: stop timing, continuous gate capture, stable altitude and sensor gaps.
- `ruby Tests/ParkingLevelChecks.rb`: background capture, unattended persistence, late visits, floor corrections, podium prediction, exclusion of incomplete/legacy measurements, and preservation of records.
- Debug physical-device build with the GorillaTranslate scheme.

## Physical Test Checklist

- [ ] Drive above 30 km/h, reduce below 30, and check that the foreground capsule appears with one continuous curve.
- [ ] Stop briefly at a gate, resume, and check that the curve does not restart.
- [ ] Repeat with the app backgrounded or screen locked; reopen after parking and check that an estimated floor exists without pressing tick.
- [ ] Confirm a complete 1/F measurement around 9.7 m, then verify the learned height and next estimate.
- [ ] Correct an incomplete historical record; verify the correction is saved but calibration counts do not increase.
- [ ] Verify historical record count is unchanged and an automatic estimate is not marked human-confirmed.

## Limits

Background location mode permits GPS updates but does not guarantee barometer or motion delivery when iOS suspends or terminates the process. Missing samples are excluded from training rather than reconstructed. A speed-triggered approach reference is still an estimate of ground level, not proof of entrance elevation. Early visit events and long stationary gate waits can remain ambiguous and require manual correction. Background location also has a power cost; compare actual drive diagnostics before asserting an energy improvement.
