# SPECTRA MM2 Hub v4 — change log and test status

This is a client-side Luau learning project. It uses Roblox APIs; it has **not** been tested in live MM2, Delta, or against MM2's authoritative server.

## Newly implemented in v4

- **Phone layout:** portrait view switches to horizontally scrolling navigation with full-width controls; landscape keeps a left sidebar. Larger headings and touch targets. Right Shift toggles the window on desktop.
- **Aim UI:** optional circular on-screen aim radius, and a toggle to require confirmed Sheriff/Hero role data for aim assist. Camera aim assist and wall check remain from v3; this does **not** change shots, damage, or hit detection.
- **Coin-farm scheduler:** caches collectible candidates for two seconds, walks/attempts local teleports to named coin parts, skips unreachable targets after six seconds without progress, logs visits and skipped objects separately, supports cancel/reset, and can pause after twenty *visits* (not verified pickups).
- **Seasonal objects:** optional named detection for `Candy`, `Shell`, `Gem`, `Snowflake`, `EventToken`, and `PumpkinPickup` (not guaranteed to match every MM2 event).
- **Local ghost:** ghosted view of your own avatar on your client. **Does not hide you from other players**. Restores local transparency when disabled/unloaded.
- **STATUS tab:** reports whether the role data feed is fresh, farm visits, markers, aim and fling toggles; offers rescan, role refresh and a stop-all control.
- **Movement restore:** stores original WalkSpeed, JumpPower, and UseJumpPower per humanoid before changing them and restores those values when toggles are disabled or the hub is unloaded.

## Carried over from v3 (not retested in live MM2)

Player highlights, visible-weapon hints, MM2 game role feed (when accessible), name/distance/health labels, object markers, Fullbright/LowFX/NoFog, spectate, teleports, sprint/jump/fly/noclip, anti-void/anti-fling, camera aim assist and a one-second experimental player fling.

## Not implemented or not verifiable from a client

Silent hit redirection, automatic firing/damage, knife aura, kill-all, guaranteed auto-win, god mode, server-wide invisibility, bag resets, verified in-game coin/candy payout, automated trades/purchases/crafting/battle-pass claims, Discord webhook, account management sync, frame cap bypass and automatic server-hop. These require game-specific permission or server behavior; listing them as functioning would be misleading.

## Verification performed

- Lua grammar syntax parse after mechanically translating Luau `+=` operators for the validator.
- 15 static code/feature checks and 40 UI toggle keys checked against declared state flags.
- No Roblox runtime or Delta test is possible here. Static tests do not prove gameplay functionality.

## Testing and rollback

In **your own Roblox Studio place**, paste `spectra_v4.lua` into a `LocalScript` under `StarterPlayerScripts` to test the UI and locally created demo objects. MM2 server-specific behavior can't be reproduced outside MM2. Keep v3 at `spectra_v3.lua` for rollback; v4 publishes as a separate file.