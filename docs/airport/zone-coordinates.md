# Airport drop-off zone positions

Updated 2026-11-04.

The user explicitly authorised approximate zone positions, and supplied a map sketch: T1 zones 1–5 progress south to north; T2 zones 6–9 progress north to south. The original spreadsheet coordinates remain excluded: they are approximately 7 km away from the terminals.

No authoritative individual door coordinates were found. Positions are interpolated on these public OpenStreetMap departure road geometries, using the user's ordering and approximate spacing:

- T1: https://www.openstreetmap.org/way/251613612 (Cheong Hong Road, elevated departure road).
- T2: https://www.openstreetmap.org/way/1461971881 (Sky Plaza Road, elevated departure road).

T1 latitude range: 22.3148–22.3178. T2 latitude range: 22.31515–22.3171. Longitude is interpolated along each road, rather than putting points along a line between the terminals.

All nine records in `airport_drop_off.json` have `approximate: true`. These are approximate drop-off targets, not surveyed entrance/door positions. The result card and native map callout label this explicitly. Route distances are driving-route distances to those approximate targets, not measurements to exact doors. A recommendation marker appears even if the phone has not acquired a usable GPS fix; route calculation waits for one.

Coordinate attribution: © OpenStreetMap contributors, ODbL 1.0. Attribution and the copyright link are available in the guide's details card: https://www.openstreetmap.org/copyright . Zone numbering/placement is interpreted from the user-provided sketch, not from an OpenStreetMap zone dataset.

Airline card accents are decorative approximations of airline brand/livery colours, not a claim that every hex value is an official brand specification. Cathay's `005D63` uses the RGB value (0, 93, 99) from its published guidelines: https://www.cxagents.com/content/dam/cathay-agents/hk/documents/CX%20Brand%20Guidelines.pdf . No airline logos are copied.
