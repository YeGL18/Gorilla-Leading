# A-to-B Trip Summary

This change affects transport summaries between visits, not visit arrival/departure timestamps or dwell timers. Native visits and raw motion segments remain unchanged.

- Brief stopped/unknown runs of at most 120 seconds, bounded by the same movement mode, are included in that continuous journey's displayed duration.
- Consecutive stopped/unknown fragments display as a single unresolved interval. Genuine movement-mode changes and longer unresolved intervals remain visible.
- Unresolved transport is explicitly labeled in all four supported languages instead of a question-mark symbol. Missing departure time remains explicit rather than inventing a trip start.
- Each separator, mode icon and duration form one vertically centered layout item, so separators cannot wrap independently.

Checks: `ruby Tests/VisitHistoryChecks.rb` covers clipping, mixed journeys, duration conservation, noise merging and preservation of raw records. `ruby Tests/TripSummaryUIProject.rb` generates a simulator fixture using the production summary/layout code; `TripSummaryUITests` captures portrait/landscape screenshots at narrow widths.

Core Motion classifies walking, running, cycling and automotive activity; it does not provide a reliable car/bus/metro distinction. This change does not add vehicle-specific automatic classification or infer a route from missing GPS data. Existing TestFlight build 4 is unchanged; these edits are local until a new build is explicitly requested.
