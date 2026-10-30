# Fix log

## Apply hidden in the toolbar overflow menu
- Symptom: at the 420 pt window width, Apply sat behind the toolbar's » menu once Revert was added.
- Cause: the window title took toolbar space; snapshots render only the content view, so they did not show it.
- Fix: `.toolbar(removing: .title)` on the window content.
- Rule: check toolbar changes in the running app, not only in snapshots.

## Settings report rejected on macOS
- Symptom: "unexpected reply from the mouse: settings report starts 00 01".
- Cause: on macOS byte 0 of the 0xA0 feature report comes back as 00 or A1, not the A0 report ID.
- Fix: check only byte 1 (status 01), as the official Windows tool does.
- Rule: match the official tool's checks; do not assume HID report-ID bytes survive on macOS.
