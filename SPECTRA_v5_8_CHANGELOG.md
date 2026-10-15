# SPECTRA MM2 Hub v5.8

## New
- **Dropped-gun Grab + Return** in TELEPORT and FARM: saves your exact HumanoidRootPart CFrame, teleports briefly to a named dropped gun, checks for the actual `Gun` Tool in the character or Backpack, then attempts to restore your prior position whether or not pickup succeeded.
- **AUTO Grab GunDrop + Return** (off by default). Looks for named gun drops on a 0.65-second poll; each failed target has a 12-second retry delay. Auto gun pickup pauses the active coin-route movement to avoid conflicting teleports. Repeats only when a relevant drop is detected and you do not already have the Gun.
- **Gun pickup status** on FARM and STATUS pages. No fabricated pickup confirmation; server-owned tools cannot be granted by a client GUI.
- **ANIMS tab** with basic equipped-avatar emote buttons, custom animation asset ID preview, playback speed selector, and Stop control. Animations must be accessible for that account/experience. The hub does **not** unlock paid/unowned assets or change your inventory.
- Existing live role ESP, player dropdown, aim controls, coin farm, controller input, fly HUD and minimized icon are retained.

## Fling explanation
- Screenshot reported **20.3 studs observed locally and 90 spatial-overlap frames**. The overlap count does *not* show actual applied force or another client's view. A locally moving target is not a confirmed successful fling. Roblox network ownership, collision groups and server corrections can prevent reliable cross-client displacement. The experimental fling routine is not claimed fixed in this release.

## Testing
- Lua 5.2-compatible transformed grammar parsed with `luatex` (`+=` expanded only for the check; shipped file remains Luau).
- 31 static invariant checks and menu-toggle flag validation passed.
- No direct live MM2/Delta runtime tests were possible. Actual GunDrop pickup, animations availability, server replication and movement corrections must be verified in-game.

## Restore
- v5.7 remains available: `spectra_v5_7.lua`.