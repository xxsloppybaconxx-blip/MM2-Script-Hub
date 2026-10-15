# SPECTRA MM2 Hub v5.7

Updated from v5.6. Existing v5.6 remains available.

## UI
- Smaller, centered, ImGui-inspired panel with less unused space and compact category buttons
- Text descriptions automatically size to content instead of reserving excessive vertical whitespace
- Dragging the panel keeps it fully within the viewport
- Retains gamepad navigation, in-FUN player picker, floating launcher, role and player refresh, ESP and outside-menu flight HUD

## Aim
- Camera aim response increased from 18% to 54% per frame by default
- SMOOTH (34%), FAST (72%), and INSTANT (100%) aim-response presets
- Existing controller L1/LB hold aim, optional R1/RB shot request and wall check retained

## Farm completion
- Ends the current farm session after 10 seconds without eligible targets **after visiting at least one target**, or when the optional visit limit is reached
- Default after-farm choice is NOTIFY ONLY
- Opt-in ROLE ACTIONS: Innocent local reset request, Sheriff/Hero one gun request plus Murderer aim, Murderer normal Knife Tool:Activate sweep
- Stops cycling when automation is canceled or script is unloaded
- **Visits are not confirmed coin collection; client requests are not confirmed kills or server round wins**

## Fling diagnosis
- No claim of guaranteed fling: shows overlap count and local target displacement directly on FUN tab
- Diagnostics describe when client physics spin fails to transfer motion; results are not server validated

## Verification
- Lua-compatible grammar parser passed after normalizing Luau compound operators for parsing
- 15 static feature assertions passed
- Not tested in live MM2 / Delta / controller hardware; game server validation can reject physics, coin pickup, death, attack or teleport requests