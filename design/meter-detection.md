# Hong Kong Meter Detection

## Data Sources

- Official dataset: https://data.gov.hk/en-data/dataset/hk-td-msd_1-metered-parking-spaces-data
- Locations, tariffs and vehicle classes: https://resource.data.one.gov.hk/td/psiparkingspaces/spaceinfo/parkingspaces.csv
- Occupancy: https://resource.data.one.gov.hk/td/psiparkingspaces/occupancystatus/occupancystatus.csv
- Current dictionary (use this URL, not the older filemanager copy): https://www.td.gov.hk/datagovhk_td/metered-parking-spaces-data/resources/en/dataspec/metered_parking_spaces_data_dataspec.pdf
- Classification limitations, Q15: https://www.td.gov.hk/en/transport_in_hong_kong/parking/parking_meters/npm/parking_meters_tips/index.html
- Alternate CSDI listing: https://portal.csdi.gov.hk/geoportal/?datasetId=td_rcd_1638930345315_81787

The location feed is cached on disk, loaded at launch and refreshed after 24 hours.
The documented CSV status endpoint is a whole-Hong-Kong snapshot; it is not a
radius-filtered HTTP API. We download at most once a minute while a map or
destination query needs it, and share that snapshot across consumers. The test
page intentionally requests all statuses. The CSDI listing is not assumed to
provide a verified radius-query contract. No backend or private API is used.

Headers, quoted CSV fields, BOM, introductory date/empty records and malformed
payloads are handled explicitly. Data is keyed by the full ParkingSpaceId.
The actual feed contains a lowercase vehicle code, so codes are normalized.
Pole IDs above 90000 are test meters and excluded from production selection,
street seeding and recommendations. Invalid coordinates are excluded.

## Vehicle Matching

| Official class | Driver choices matched |
| --- | --- |
| A: vehicles other than medium/heavy goods, buses, motorcycles and cycles | Private car, taxi, light goods |
| G: goods vehicles | Light goods, medium/heavy goods |
| C: coaches; official FAQ groups these as buses | Bus/coach |
| Unknown | No automatic recommendation |

This is a broad classification, not a complete permission record. Official Q15
explicitly notes that additional onsite signs, such as private-cars-only signs,
may restrict a general-class bay. Details show an onsite-signs reminder. Do not
label every A-class bay as private-car-only or promise that open data captures
all restrictions.

N = normal; NU = not for use. V = vacant; O = occupied. NU, missing/unrecognized
status and status snapshots older than three minutes are gray. The individual
OccupancyDateChanged field is a change timestamp, not a snapshot freshness
timestamp; an unchanged occupied bay is not made stale merely by that field.

Green = compatible vacancy (or vacancy before choosing a vehicle); yellow =
incompatible vacancy; red = occupied; gray = unknown. Clusters use that priority,
with red only when every member is occupied. Cluster membership is separated by
official A/G/C class. Fixed-size markers show the vehicle icon and total count
together. Selection prefers a compatible vacancy, then another vacancy, then the
nearest bay. Driver changes recolor markers without a fresh download.

## Range and Prompts

- Map radius R: 500 m by default, 100-800 m in 10 m increments.
- Seed streets only from real bays within R; include those streets up to 2R
  measured from the current location. Never recursively seed more streets.
- Streets expire five seconds after the last in-R member; the 2R cap is strict.
- Hide after five continuous seconds above 50 km/h; restore after three seconds
  at or below 50. Invalid/stale GPS does not create parking alerts.
- Destination radius: 500 m, adjustable 50-800 m in 10 m increments. Use driving
  distance <= 2 km, queried separately from local map demand. A route result
  belongs to its destination ID and expires after two minutes.
- Nearby prompt radius: 100 m, adjustable 10-200 m in 10 m increments.
- Stationary prompt: compatible bay within 10 m, accuracy <= 15 m, speed <=
  0.5 km/h and stable position for ten seconds, including occupied/unknown bays.
- Priority: stationary > nearby > destination. All notices expire after ten
  seconds. Destination suppression lasts for the current destination journey;
  arrival followed by departure or changing the destination rearms it.
- Nearby notices are suppressed on the same street until leaving it and a
  three-minute cooldown has elapsed. Stationary payment still gets one notice
  per stop and rearms after driving again.
- Original destination remains selected while the temporary meter route is
  shown. Apple Map route recalculation uses the temporary target until another
  destination/route is chosen or the route is dismissed.
- Meter routing uses only Apple MapKit/MKDirections, following the existing
  optimal-route button. There is no new AMap integration in the meter feature.

## Payment Integration Limitation

App Store: https://apps.apple.com/hk/app/id1508101096

No public, verified iOS launch/deep-link contract was found. The operator site
redirected to maintenance during verification. The payment action currently
offers the App Store/manual-open fallback; it does not falsely claim to open a
specific bay or start a payment. `HKeMeterLaunchURL` can be added to Info.plist
only after a supported launch URL is verified on a device. No guessed private
scheme is shipped. Payment pairing and purchase remain inside HKeMeter.

## Verification

Run the standalone model checks on macOS (no app or simulator needed):

```sh
swiftc -module-cache-path /tmp/gorilla-swift-module-cache GorillaTranslate/Models/MeterData.swift Tests/MeterDataChecks.swift -o /tmp/gorilla-meter-checks
/tmp/gorilla-meter-checks
swiftc -swift-version 5 -module-cache-path /tmp/gorilla-swift-module-cache GorillaTranslate/Models/MeterData.swift GorillaTranslate/Models/ParkingMeterManager.swift Tests/MeterNoticeChecks.swift -o /tmp/gorilla-meter-notice-checks
/tmp/gorilla-meter-notice-checks
```

The first executable also accepts location CSV and occupancy CSV paths to check
real data. Use `pod install --deployment` and the generated
`GorillaTranslation.xcworkspace` for full app builds.

Settings > Meter > Hong Kong meter test opens the full map. Search IDs, streets
or districts, filter vehicle class and optionally include internal test meters.
The speedometer control opens an isolated range/speed simulation; it does not
replace real GPS or trigger real driving/payment alerts. Blue rings show R and
2R. Real-world GPS accuracy, street-level access and HKeMeter launching still
require device testing.
