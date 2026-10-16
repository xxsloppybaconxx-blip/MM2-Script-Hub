# Adopt Me Halloween Helper v3 (experimental)

Updated October 16, 2026. This standalone client Lua file is stored in \`MM2-Script-Hub/adoptme/\`; **none of the original MM2 scripts or root loader were modified**.

## Delta loader

\`\`\`lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/xxsloppybaconxx-blip/MM2-Script-Hub/main/adoptme/halloween_hub.lua"))()
\`\`\`

The raw URL loads the current GitHub version. Re-executing attempts to stop the previous helper.

## Hauntlet 2: exact doors from live diagnostics

The v2 diagnostic confirmed the real hierarchy inside each live Hauntlet interior:

\`Workspace.Interiors.HauntletInterior::<instance ID>.Rooms.<room>.Doors.1.DoorPart\`

And likewise \`Doors.2.DoorPart\` and \`Doors.3.DoorPart\`.

**v3 changes:**
- Recognizes those three door slots instead of irrelevant \`DoorJoinCircles\`, \`DoorArrows\`, and \`DoorPositions\` markers.
- Finds the closest currently loaded Hauntlet room; handles changing interior ID/room when the event advances.
- ESP attaches directly to each **DoorPart**, with the number 1, 2, or 3.
- **Auto WALK to doors** attempts to approach the near side of an entrance, then walk through. Optional teleport to the near side is independent. Neither movement nor door crossing is guaranteed by the game server.
- **Door choice** button cycles \`AUTO -> 1 -> 2 -> 3 -> AUTO\`. AUTO prefers the nearest candidate without a client-exposed danger signal. It does **not** know which door is actually safe.
- **Confirmed safe only** refuses unknown doors unless the game exposes an explicit safe attribute/tag, which may never occur.
- **Copy nearby door debug** now reports the exact current room, detected numbered DoorParts, collision setting, any detected prompt, and current risk label.

## Ghost Gallery

Ghost ESP, Auto WALK to ghosts, and Ghost Blaster Tool:Activate are unchanged from v2. The live Ghost Gallery client hierarchy is not yet diagnosed or tested, so ghost features remain experimental.

## Performance and limits

v3 stops the broad part scans for Hauntlet mode and checks the \`Interiors -> Rooms -> Doors\` hierarchy directly every four seconds. ESP renders only the actual nearby door parts. Ghost Gallery still uses a capped nearby spatial query.

No guaranteed safe-door information or hidden server actions are available in this script. Yellow \`UNKNOWN\` is **not safe**. Automated client character movement, GUI ESP, and tool actions can be rejected or overridden by the game. Using third-party scripts in Roblox may violate its rules and risk moderation.

For troubleshooting, enter a Hauntlet room with the event running, select Hauntlet 2, enable Door ESP, then copy the debug output. If the displayed door count is 3 but walking fails, report whether the status says \`approaching entrance\` or \`moving through\`.

[Source code](./halloween_hub.lua)
