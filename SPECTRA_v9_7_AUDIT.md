# SPECTRA v9.7 — MM2 logic audit and test plan
Date: 2026-10-16. Scope: review of SPECTRA v9.6/v9.7, public Roblox engine docs, MM2 community descriptions. The game server's private code is unavailable.

## Implemented 9.7 changes
1. Role/Hero: backpack and equipped Tool watchers. Picked-up Gun immediately shows Hero? hint even when the game-reported Innocent role lags. No false game-confirmation.
2. Gun/crosshair: detect the shooting interface instead of only Gun names, let Heroes equip a picked-up gun, and show crosshair with an owned gun.
3. 2D ESP: project the actual body BaseParts and custom named hitbox parts, rather than estimate body size. Excludes self and accessory/tool descendants. This is local replicated geometry, not the server's secret hitboxes.
4. Gun aiming: shared R6/R15 Torso/Head target choice across camera aim, controller, and auto-shot; a selectable velocity lead; fix camera-torso versus fired-head mismatch.
5. Gun method: optional preference for CreateBeam/AH2 vs ShootGun/AH. Report remote path and returned value without falsely confirming a hit.
6. Muzzle diagnostic: inspect local muzzle-to-hitbox obstruction without firing.
7. Fling: high-energy billion-velocity collision test, safe-on-error physics cleanup, and fixed an out-of-scope completion-report variable that broke callbacks/Fling All. Physical success remains unconfirmed.
8. Performance: 2D boxes approx. 8Hz, aim preview approx. 15Hz, combat-ring approx. 7Hz; event-triggered role refresh plus 1.2-second polling.

## MM2 mechanics and missed Sheriff hits
MM2 Sheriff/Hero shooting and Murderer knife contact are separate weapon paths. A client-side tracer intersecting a head does not prove a registered server hit. Camera and gun muzzle are separate ray origins (third-person parallax). A tiny moving Head is less forgiving under latency than Torso, so the selected hitbox must be the same for aiming and shot arguments. Successful Lua RemoteFunction InvokeServer calls do not prove actual eliminations; server weapon cooldown, current round state, target positions and collision rules apply.

## Physics fling constraints
Roblox network-ownership documentation acknowledges that extreme client physics velocity can affect other assemblies, but only if contact/replication is actually processed. The server can correct both your position and another character's motion. Local overlap/displacement is observational only. The experimental billion-velocity mode may cause client reset, desync, or kick. Moondiety's exact private code was not available to audit.

## Further improvement opportunities
- Round epochs: clear stale role attributes and dead flags on actual round change rather than treating old snapshots as live.
- Sheriff shooting: compare CreateBeam vs ShootGun logs using the new diagnostics; add ping-aware lead defaults only after measured results.
- Kill all: do not generalize knife-contact success to guns. Legacy client reposition of others is visual-only until server confirmation.
- ESP: handle absent/out-of-stream characters and ensure highlight/connection cleanup after round reset.
- Pickups: confirm gun transfer from world to Backpack/Character; distinguish a detected marker from server-awarded pickup.
- UI cleanup: use a targeted result-panel allowlist instead of increasingly broad heuristics to avoid hiding unrelated HUD.
- Animations: avoid playing over tool attack/equip tracks; explicitly stop restored previews on respawn/unload.
- Controller: L2 should respond to Hero pickup even while the role feed is behind, without consuming native fire/equip inputs.

## Live test matrix
| Scenario | Evidence to check |
| --- | --- |
| Fresh Sheriff with Gun | Confirmed role, crosshair, gun method |
| Innocent picks up Gun | Hero? local hint + crosshair before equipping |
| Equip Hero Gun on controller | L2 aim works when tool is present |
| R6/R15 characters on screen edge | 2D box traces body only, never self |
| Torso aim ON/OFF | target and remote aim location agree |
| Test gun muzzle/hitbox | diagnostic shows clear or blocked; no shot |
| Front Sheriff with move-self ON | waits for position to settle; no fake local target |
| Fling one / Fling All / STOP | local readings, callbacks, restore character physics |
| Reload v9.7 loader | no duplicate GUI or ESP connections |
| High-population mobile server | low overdraw and responsive GUI |

## Primary documentation
- https://create.roblox.com/docs/scripting/security/network-ownership
- https://create.roblox.com/docs/workspace/collisions
- https://create.roblox.com/docs/workspace/raycasting
- https://create.roblox.com/docs/reference/engine/classes/RemoteFunction
- https://mm2wiki.org/wiki/roles/
- https://gist.github.com/moti503/794159fca6862d741d75d36d84e944c1

**Verification:** Code changes have been committed to GitHub, but neither a live MM2 server nor the Delta executor is available here to confirm successful hits or fling replication.
