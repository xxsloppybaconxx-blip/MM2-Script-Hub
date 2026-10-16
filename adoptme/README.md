# Adopt Me Halloween Helper v2 (experimental)

**Updated October 16, 2026.** This standalone Lua file lives in \`adoptme/\` within the existing MM2 repo. The root-level MM2 scripts/loaders/README remain untouched.

## Load in Delta (Adopt Me only)

\`\`\`lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/xxsloppybaconxx-blip/MM2-Script-Hub/main/adoptme/halloween_hub.lua"))()
\`\`\`

This loader always fetches the latest published file. Close/unload older versions before testing; running v2 will also attempt to unload the previous hub.

## Changes since v1

- **Fixed major lag cause:** removed repeated \`Workspace:GetDescendants()\` calls, which scanned the entire game every 0.85 seconds. v2 performs a spatial query for nearby parts every **4 seconds**, caps the results to 700 parts, and limits ESP to 12 highlighted targets.
- **Improved ESP attachment:** highlights are parented to a local folder under Workspace instead of ScreenGui, improving compatibility.
- **Actual auto WALK mode:** \`Humanoid:MoveTo\` is now used for Hauntlet doors. Optional nearby teleport is separate and might be rejected by the game.
- **Broader detection:** door names, certain client tags/attributes, and open/enter ProximityPrompts can be detected. This is still **heuristic**, not a real Adopt Me game-object API.
- **Manual door marking:** aim the **center of your screen** at a door and tap **Mark door at screen CENTER**. Repeat for each door. Auto Walk can select marked doors even when automatic discovery cannot.
- **Copy nearby door debug:** while **inside a Hauntlet room**, tap **Copy nearby door debug**. If supported, this copies a diagnostics report to your clipboard. Otherwise it prints to the developer console. Share the report to help identify the game's actual door models without guessing.

## Features and limitations

### Hauntlet 2
- Door ESP highlights detected doors and shows a risk indicator. **Yellow UNKNOWN is not safe.**
- Automatic walking toward door candidates is a best-effort movement request, **not guaranteed entry**. Some entrances may require game-specific interactions.
- Auto Walk attempts a nearby ProximityPrompt, if found, or simply walks toward a door.
- \`Confirmed safe only\` requires an explicit client-exposed safe tag/attribute; often **no door will qualify**. Door ESP cannot reveal server-only ghost information, and this script cannot promise a ghost-free choice.
- If nothing appears, point at a real door and use **Mark door**, then **Copy nearby door debug** and share the result for a game-specific fix.

### Ghost Gallery
- Searches nearby parts for ghost/haunted names or metadata.
- Ghost ESP, Auto Walk, and Tool:Activate() for a Ghost Blaster are toggles. The game may hide possessed furniture from the client or use other interaction mechanics.
- **Not live-tested**: these features may not function, even if the menu appears.

## Safety / testing

This script is an **experimental helper**, not a validated auto-farming tool. We cannot inspect Adopt Me's live internal hierarchy, verify targets, or bypass server actions from GitHub. No service calls, third-party libraries, login prompts, or MM2 integration are included. Client scripts can violate Roblox or experience rules and risk account moderation.

## File
[halloween_hub.lua](./halloween_hub.lua)
