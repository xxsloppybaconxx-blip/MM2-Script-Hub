# Adopt Me Halloween Helper v4 (experimental)

Updated October 16, 2026. Independent file in \`MM2-Script-Hub/adoptme/\`, no MM2 scripts or root loader changed.

## Delta loader

\`\`\`lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/xxsloppybaconxx-blip/MM2-Script-Hub/main/adoptme/halloween_hub.lua"))()
\`\`\`

The same loader always fetches the current published script. Re-running attempts to unload an older version.

## Ghost Gallery changes in v4

Ghost Gallery gameplay: ghosts possess furniture, then emerge when you blast occupied pieces; a boss appears during the round. **A picture frame alone is not proof of a ghost.** The old script incorrectly treated decorations as targets.

- **Ghost ESP** now looks for nearby ghost/spirit/boss entities and separately for **explicit client-visible possession evidence** (tags, attributes, ghost counts). Generic picture frames, posters, and paintings without possession evidence are ignored.
- **Teleport to ghosts** replaces Auto Walk. Enable it to move near each chosen ghost target. This can still be reversed by the server.
- **Auto fire Ghost Blaster** tries \`Tool:Activate()\` when an applicable Tool exists, plus available client mouse-click input methods (e.g. \`mouse1click\` or virtual input). It aims the camera toward the target for each attempt. **Firing or hit registration is not guaranteed.** The real game may use an input controller or server validation that this generic approach cannot access.
- Targets are held for several shots and rotated if multiple are found, prioritizing bosses and visible ghosts over possessed furniture.
- Ghost Gallery nearby scanning is capped at 650 spatial-query parts every ~1.8 seconds. ESP caps at 12 highlights.
- **Copy ghost debug** is shown when Ghost Gallery mode is active. Run it **during the active round**, copy the result, and paste it into chat if target counts stay zero or Auto Fire fails. It reports live candidate object paths and available click APIs.

**Recommended initial test:** Switch to Ghost Gallery; turn on **Ghost ESP**, **Teleport to ghosts**, and **Auto fire Ghost Blaster**, enter an *active* minigame round. ESP shows \`VISIBLE GHOST\`, \`GHOST BOSS\`, or \`POSSESSED\` for qualifying targets. If these are missing, use **Copy ghost debug**. The script deliberately will not randomly attack empty paintings.

## Hauntlet 2 (retained from v3)

The exact live door structure was identified from a real user diagnostic:

\`Workspace.Interiors.HauntletInterior::<instance-id>.Rooms.<room>.Doors.<1|2|3>.DoorPart\`

The helper targets those three actual door parts, ignoring decorative \`DoorJoinCircles\`, \`DoorArrows\`, and \`DoorPositions\`. It supports door ESP, Auto WALK toward the near side and across an entrance, optional teleport near the door, numbered door selection (AUTO, 1, 2, 3), and copying a door diagnostic.

**Yellow UNKNOWN does not mean safe.** Confirmed-safe only requires a visible game marker. The script does not claim knowledge of hidden ghost doors.

## Limitations

This is a **not-live-verified prototype**. GitHub upload verification is not the same as a successful gameplay test. Client ESP can't reveal ghosts hidden solely on the server. Mouse/tool activation might not register as a blaster hit, and teleporting can fail under server validation. Using third-party scripts in a Roblox game may violate its rules and risk account moderation.

[Script source](./halloween_hub.lua)
