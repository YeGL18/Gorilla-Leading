# Interaction And Reminder Policy

Updated 2026-10-25.

## Familiar Parking

The former long-parking helper always returned false and scheduling did not
consult it. Both scheduling and foreground timer checks now use completed real
driving visits within 100 metres of the parking anchor. The latest five matching
completed visits form an average; at least one must exist, and an average of
3.5 hours or longer suppresses parking-time notifications. Ongoing/future visits,
walking/transit arrivals and invalid coordinates do not train this rule.

The current session is excluded. This is historical learning, not a delay that
waits 3.5 hours before deciding whether the first reminder should fire. Existing
25/55/85/115/145/175-minute reminder scheduling remains for other places, but the
timer no longer generates a duplicate immediate notification. Disabling or
ending the session removes scheduled requests. Existing visit history is kept;
no new location tracking or remote inference is introduced.

## Contrast And Feedback

Expanded address-capsule action labels choose black or white from the luminance
of the configured button fill blended with the light/dark base at its effective
opacity. This covers custom parking-memory and best-route colors without
changing those saved colors. Dynamic map content can still alter perceived
contrast through glass and needs device inspection.

App-added touch feedback defaults on, with one Settings switch. Window-level
non-consuming gesture observation covers sheets, coalesces feedback within
120 ms and excludes text entry. Soft taps, selection changes and medium long
presses differ; continuous dragging does not generate repeated tap feedback.
The preference is included in backups. Switching it off disables app-added
feedback, not operating-system feedback owned by native controls.

Settings labels are shortened to Color Group, Appearance and Glass. Orbs and
Dark Knight replace the old mode names. Launch sound choices are Default/Gentle;
movement choices are Gentle/Minimal. Only the parking-reminder preview button
is removed; its actual notification sound remains.

## VLM Recognition

Both production parking memory and the recognition test use the same scoped
action-button prompt. Its native alert actions are white in dark appearance and
retain the normal accent in light appearance. Only the alert's transparent
presenter receives this tint; custom parking-button colors are not changed.

Loading and successful-recognition audio now drive Core Haptics from the playing
AVAudioPlayer's metered amplitude at 50 Hz. The envelope ignores levels below
approximately -48 dB, uses a square-root response and caps intensity at 0.65.
Audio volume scales the envelope so fades also fade the haptics. Loading loops
follow the actual audio; success remains a one-shot sound. Pending fade/done
transitions are cancelled before restarting or cancelling recognition.

The existing haptics preference applies, and unsupported hardware, inactive apps,
stopped audio and haptic-engine failures stop/skip tactile playback without
interrupting the sound. This tracks amplitude, not pitch or an exact waveform.
Metering/scheduling introduces some latency; physical synchrony and comfort need
testing on the phone. Simulator tests cannot reproduce the Taptic Engine.
