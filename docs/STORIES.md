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
