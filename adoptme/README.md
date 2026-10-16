# Adopt Me Halloween 2026 Hub (experimental)

A **separate**, self-contained Roblox client script for **Ghost Gallery** and **Hauntlet 2**. It lives in the \`adoptme/\` folder to keep it isolated from the existing MM2 hub.

## Files

- [halloween_hub.lua](./halloween_hub.lua) — two-mode Lua helper with its own menu.
- Existing MM2 scripts, loaders, and root README were **not changed**.

## Features

**Ghost Gallery**
- ESP for client-visible ghosts and haunted objects, based on names, attributes, or tags.
- Optional teleport toward the detected target.
- Optional aim and normal Tool activation for an equipped Ghost Blaster or vacuum.

**Hauntlet 2**
- Door ESP with client-visible risk labels.
- Optional teleport toward selected doors.
- Optional auto-choice and attempt to enter doors with exposed ProximityPrompts or ClickDetectors.
- Optional **Require confirmed-safe signal**: refuses to choose unknown doors unless the client explicitly exposes a safe-door attribute/tag. This can result in no automatic actions.

The interface starts with ESP enabled and automatic actions **off**. Tap the mode button to switch. F6 hides/shows the desktop UI; use **Unload / Close** to stop. Running the script again unloads the previous copy.

## Source / use

Raw Lua:
\`https://raw.githubusercontent.com/xxsloppybaconxx-blip/MM2-Script-Hub/main/adoptme/halloween_hub.lua\`

Run **only this Lua file** in Adopt Me using an environment that supports Roblox client Lua, GUI creation, and the needed APIs. The script doesn't load other code, reference the MM2 loader, or require a web service.

## Limits: please read

**This is a prototype, not a game-tested guaranteed autofarm.** We cannot inspect or execute Adopt Me's live game hierarchy here. No private RemoteEvents or hidden answers are assumed. Client-side names, tags, prompts, and tool activation may not match the real game, and the server may reject teleport/action attempts. The script **does not auto-queue or guarantee round completion**.

**Hauntlet:** Yellow \`UNKNOWN\` is **not** a safe-door indication. Orange/red mean estimated/visible danger; green \`SAFE SIGNAL\` only appears when an explicit attribute or tag is exposed. For 2026, Bolt's Phone arrow points toward a ghost; a matching exposed \`PhoneMarked\` or \`BoltPhoneTarget\` indicator is treated as danger. The live game may not expose either attribute. Doors may still be risky when they aren't marked.

**Ghost Gallery:** Hidden ghosts within furniture and the boss phases may require information or mechanics that are not visible to a generic client-side scanner. Tool:Activate() alone may not actually catch them.

Using third-party scripts in a live Roblox game may violate the experience's or Roblox's rules and can result in moderation. No guarantee of compatibility or account safety is provided.
