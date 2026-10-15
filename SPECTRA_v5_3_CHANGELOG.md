# SPECTRA MM2 Hub v5.3 — Player Picker & Diagnostics

## Implemented
- HOME: searchable roster replaced with a live, touch-friendly, alphabetically sorted **name dropdown** with display name, @username, observed/confirmed role and selected state.
- FUN: direct **Choose Target** shortcut to open the HOME dropdown.
- Player roster refreshes when someone joins or leaves and about every 0.55 seconds; selection clears when a player leaves; spectate camera resets when that player leaves.
- MM2 game-reported role refresh continues at its existing six-second cadence. Role-feed UI shows age of the latest successful data; timed-out calls no longer permanently lock the refresh loop, and late responses are ignored.
- FUN: **Diagnose selected player collision** checks locally collidable character parts and collision-group compatibility.
- The experimental fling attempt stops instead of circling when no compatible contact parts are detectable.
- Earlier ESP, aim, farm, role radar, movement, minimization icon and Settings full-unload controls are retained.

## Verification
- Code-level feature and structure checks complete; GitHub file publication verified.
- No Roblox/Delta live runtime environment is available. Fling displacement, MM2 remote-role accuracy, gun shot registration and coin rewards are NOT independently verified.

## Why fling may still fail
Roblox distributes physics simulation across server and clients. Even compatible collision groups do not guarantee force transfer to another client-owned character. The diagnostics only observe locally exposed settings; they do not bypass network ownership.

## Research-based priorities for future versions
1. **Dropped Gun spawn alerts** with throttling, plus marker distance and status. Current gun markers are name-based and may miss renamed objects.
2. **Performance settings and overlay budgets**: ESP update frequency and max highlighted objects to reduce mobile lag.
3. **Optional recent-role event log** distinguishing game-confirmed roles from weapon-based guesses.
4. **Saved UI presets** for overlay, farm, and camera options; requires a supported persistence mechanism.
5. **Coin farming feedback** separating targets visited from confirmed server rewards.
6. **Round timing and map-awareness** based only on observable game state.

Do not equate external script-hub marketing with working MM2 functionality. Server-side inventory, rewards, damage, trades, and guaranteed wins are not established by client-only controls.
