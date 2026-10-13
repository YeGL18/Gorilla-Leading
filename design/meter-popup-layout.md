# Meter Popup Layout

- Scope dark appearance and control tint to meter popups, never the entire settings page.
- Glass navigation, close and refresh controls use white in dark appearance and the existing deep teal in light appearance.
- Payment actions use native `glassProminent` with the existing teal tint and white labels. Nearby, stationary and detail popups share this treatment.
- Detail content uses a centered status block with leading-aligned icon/text rows. In wider landscape regions, status and details form two columns; actions remain below.
- Maximum detail width is 420 pt in the stacked layout and 600 pt in the two-column layout. Notice width remains at most 420 pt.
- Folded seated regions are left half in landscape and upper half in portrait. Layout decisions use that region's dimensions rather than the entire display.
- Text is retained in full, including Japanese multiline actions. Icons align vertically to the whole label. Scrolling is a fallback only when the content cannot fit vertically, including accessibility text sizes.

## Checks

Generate the isolated real-view fixture with `ruby Tests/MeterPopupUIProject.rb` and run its `MeterPopupChecks` scheme.

Verified on iPhone Duo: light portrait, dark glass on light appearance, dark landscape, upper-half region, left-half region and nearby notice. Also verified iPad portrait/landscape and iPhone 16 Pro portrait/landscape/nearby notice. UI checks cover Japanese navigation labels, actionable buttons, minimum hit height and region bounds. The fixture stubs network status; it does not contact meter services.

Reference: [Apple HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials).
