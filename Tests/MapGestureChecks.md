# Native Map Gesture Checks

`MapGestureUITests.swift` sends native touch gestures through XCTest. Direct
camera-setter assertions alone cannot detect gesture-recognition deadlocks.

The harness compiles the production `MapInteraction.swift`, runs a 60 Hz camera
writer until touch-down, and checks first pan, first pinch, rotation, a six-second
hold followed by pan, and repeated pan. The full-app check additionally verifies
the production coordinator gives manual control to the first single-finger drag.
The padded-fit check verifies that calculating the meter-overview target preserves
the starting camera and frames both points in portrait, landscape and narrow
viewports, including a pitched starting camera and asymmetric safe-area padding.
It also checks the 40pt downward tracking offset preserves full map coverage and
does not change the existing hinge center. The annotation test exercises native
cluster/member replacements, removal and reuse. It samples actual intermediate
opacity values, checks that fade-out images contain visible pixels, and verifies
snapshot cleanup, disabled snapshot interaction and fully opaque reused markers.
The moving-fade test removes markers while simultaneously changing camera center,
distance, heading and pitch, and checks that outgoing images stay within 2pt of
their projected geographic anchors rather than remaining fixed on screen.
Its `--map-camera-checks` launch argument exposes camera values only in DEBUG;
normal launches and release builds do not alter accessibility.

Generate the disposable Xcode project with the existing CocoaPods Ruby runtime:

```sh
env GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.16.2_1/libexec \
  /opt/homebrew/opt/ruby/bin/ruby Tests/MapGestureProject.rb
```

Install the latest DEBUG GorillaTranslate app on the target simulator before the
full-app check. Use a fixed simulated location so marker movement cannot be
mistaken for camera movement, then restore the previous location scenario.

```sh
xcodebuild -project /private/tmp/GorillaGestureTests/GestureChecks.xcodeproj \
  -scheme GestureChecks -destination 'platform=iOS Simulator,id=<device-id>' \
  -derivedDataPath /private/tmp/gorilla-gesture-tests \
  -parallel-testing-enabled NO -collect-test-diagnostics never test
```

To run only the standalone harness without an installed Gorilla app, add
`-skip-testing:MapGestureUITests/MapGestureUITests/testGorillaAppFirstSingleFingerDrag`.

Remove the two test-only simulator apps after testing:
`com.gorilla.map-interaction-checks` and `com.gorilla.map-gesture-uitests.xctrunner`.
