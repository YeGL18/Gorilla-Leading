# Driving Prediction Trigger

- The foreground status transitions to driving or driving-before-native-departure trigger prediction using the latest known visit as origin. The origin's arrival transport classification does not gate this action.
- The origin visit ID is persisted as a deduplication token. Traffic stops, repeated callbacks and reopening the same visit do not repeat the card. A new visit supplies a new token. Missing origin visits remain a limitation; this does not infer new visits.
- The prediction uses the driving transition's current weekday/time slot. Native arrivals no longer trigger destination cards.
- Feedback captures the exact pattern used to predict instead of recomputing it from the time/history when the button is pressed.
- The test page gives confidence its own row. Settings uses the same effective-score proportion, not raw hit proportion.
- The driving trigger persists a separate observed start time. It does not change visit departure timestamps or claim an exact departure time.
- Training occurs when the next arrival has a known address and a driving classification, using the origin's native departure date or its saved driving trigger time. Delayed native departures/address enrichment retry adjacent trips. Learned arrival IDs persist across relaunch, preventing duplicate samples. Historical patterns are not migrated or rebuilt by this change.

## Validation

`ruby Tests/PredictionScoreChecks.rb` checks one-sample confidence, competing candidates, feedback weights, zero scores and source wiring. It also executes the actual departure/learning methods with isolated preferences: non-driving origin arrival, repeated driving callbacks, missing native departure, arrival-time learning, persisted deduplication and delayed native departure retry.

`ruby Tests/VisitEventChecks.rb` checks protected-data queuing, delayed departure/arrival ordering and visit identity preservation. These are synthetic event tests, not proof that iOS delivers every departure.

## Pending Decision

Missing native departure times are not fabricated. A separately marked estimated departure requires user approval and must be superseded by later native events. Driving recognition can itself lag; this change removes the additional wait for a native visit callback, not Core Motion/GPS latency.
