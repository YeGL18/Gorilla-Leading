# Shenzhen Tracking And Parking Flow

These changes are later than TestFlight build 3 and are not included in that uploaded build.

- Camera fixes: MapKit camera initialization, tracking flights, meter overview and continuous driving tracking now use the same mainland display coordinate frame as annotations. Raw GPS coordinates remain unchanged for distance, speed and storage. The driving predictor caches the display offset per GPS fix rather than converting coordinates at 120 Hz.
- Phone landscape controls: the two-button and three-button stacks are vertically centered using the available view height. Duo and iPad layouts retain their previous positioning.
- Prediction: exclude the origin place and places within 180 m of the origin or current GPS reference; add a neutral Not Leaving Yet action. It does not count as a denial and resets the departure prediction token / observed departure so a later driving transition can try again. Outside dismissal also does not penalize the model. Prediction controls ignore input for the first second after presentation.
- Parking flow: the foreground parking question auto-confirms after ten seconds without input. Moving again removes the question; choosing Not Parked continues sampling. The question ID remains stable instead of being replaced at the timeout. The floor picker auto-confirms after two seconds of inactivity, preserving manual changes and keeping unattended estimates out of calibration learning. Two seconds after confirmation, the floor view returns to the expanded capsule; after that transition, parking memory opens only if still on Home, foregrounded and not driving again.
- Parking visuals: sharing uses a fixed 44 pt native glass circle; the camera button's glass backing no longer has an opaque shape fill.

## Manual Checks

1. In Shenzhen, compare the blue dot, parking annotations and camera after initial map flight and while driving. Verify Hong Kong remains unchanged.
2. Rotate iPhone 16 Pro to landscape and switch orbs / map: both button stacks should have the same vertical center.
3. Trigger a prediction while tapping another control: the arriving card must not register denial. Not Leaving Yet and outside dismissal must not alter candidate feedback scores.
4. At the origin, verify its own name (including aliases) is never offered as the destination.
5. During a floor capture, leave the parking question untouched for ten seconds; wait two seconds for floor confirmation, then two seconds for return and the expanded-capsule animation before memory opens. Repeat with manual confirmation and manual floor changes.
6. Resume moving, choose Not Parked, switch tabs or background the app during the countdown: no stale confirmation or unwanted memory reopening.
7. Check parking sharing / camera glass in light, dark and Dark Glass appearance.

Automated coverage: MapCameraMotionChecks, PredictionScoreChecks, ParkingAltitudeChecks, ParkingLevelChecks and NoAMapChecks. Physical Shenzhen driving and native glass visual behavior still require device validation.
