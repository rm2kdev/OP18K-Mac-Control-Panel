# OP1 Control stories

## M1 Core

### S-001 Set the polling rate
As the user, I pick 1000, 2000, 4000 or 8000 Hz and apply it to the mouse.
Screens: snapshot `main`
Acceptance:
- [self] Only settings byte 5 changes; dividers 8/4/2/1 match the official tool.
- [manual] Measure shows about the chosen rate after Apply.
Status: done

### S-002 Set DPI levels
As the user, I choose how many DPI levels the DPI button cycles through (1 to 4)
and set the DPI of each level, optionally with separate X and Y values.
Screens: snapshot `main`
Depends: S-001
Acceptance:
- [self] Levels read from settings bytes 35 to 54: per level a split flag, then X and Y as little-endian 16-bit values.
- [self] Values are clamped to 50 to 26000 and rounded to the nearest 50, as the official tool does.
- [self] The split flag is set exactly when X and Y differ; byte 13 (the mouse's current level) is never written.
- [snap] The DPI section shows the level count and four rows; levels beyond the count are dimmed.
- [manual] After Apply, the DPI button on the mouse cycles through the new levels.
UX:
- Flow: change values in the DPI section -> Apply in the toolbar saves polling rate and DPI together -> Revert undoes unsaved edits
- Surface: inline rows in the main form (changes values on screen)
- States: not connected shows "–" and disabled fields; a value out of range snaps to the nearest valid value when the field loses focus
- Words: "DPI levels", "Level 1", "Separate X and Y", "Apply", "Revert"
- Access: Return commits a field; each stepper moves by 50; VoiceOver "Level 1 DPI"
Status: done

### S-003 Try the experimental 500 and 250 Hz rates
As the user, I pick 500 or 250 Hz from an Experimental row under the polling rate.
Screens: snapshot `main`
Depends: S-001
Acceptance:
- [self] 500 and 250 Hz write dividers 16 and 32; the four official rates keep dividers 8/4/2/1.
- [snap] An "Experimental" row shows 250 Hz and 500 Hz; choosing one changes the footer to say Endgame Gear doesn't offer it.
- [manual] On firmware 1.24, 500 Hz measured about 500 Hz and tracked normally (2026-10-31). 250 Hz not yet tried.
Status: done

### S-004 A clearer main window
As the user, I see at a glance which mouse is connected and what's on it, and every
action is in the toolbar and the Mouse menu.
Screens: snapshots `main`, `split`, `saved`, `not-connected`, `no-permission`
Depends: S-001, S-002, S-003
Acceptance:
- [snap] A header shows the OP1 8k, its firmware, and Connected / Not connected / No access as a dot plus a word.
- [snap] Polling Rate has Supported and Experimental rows and the Measured rate row; a measurement shows a check when it is within 15% of the rate on the mouse and a warning otherwise.
- [snap] Without a mouse, one "Plug in your OP1 8k" card with Try Again replaces the settings; without Input Monitoring, one notice with Open Privacy Settings… does.
- [snap] After Apply, a "Saved to the mouse." notice names the backup file; editing again clears it.
- [snap] No field opens focused; DPI levels beyond Levels in use say "Not in use".
- [manual] Mouse menu: Apply Changes ⌘S, Revert Changes, Read Settings Again ⌘R, Measure Polling Rate ⇧⌘M, Show Backups in Finder.
UX:
- Flow: open -> header says Connected -> change rate or DPI -> Apply (⌘S) -> notice confirms and names the backup
- Surface: one fixed-size window, grouped form, toolbar at the trailing edge (Read Settings Again, Revert | Apply)
- States: reading (spinner in header), connected, not connected, no access, saved, problem
- Words: "Supported", "Experimental", "Measured rate", "Levels in use", "Not in use", "Saved to the mouse."
- Access: every toolbar action has a menu command and a shortcut in its tooltip; status never relies on color alone
Status: done
