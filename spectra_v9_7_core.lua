--[[
  MM2 SPECTRA HUB 9.7 - ROLE ESP / HITBOX AIM / HIGH ENERGY FLING
  Original, readable, client-side Luau example.
  Best tested in a Roblox Studio LocalScript in StarterPlayerScripts.
  Also uses ordinary Roblox client APIs for executor compatibility,
  but has NOT been tested in Delta or the live MM2 experience.

  Features: MM2 game-reported roles (if available), live role radar,
  player ESP, nametags, distance, visible-weapon hints,
  through-wall outlines, player tracers, rainbow ESP, dropped-gun
  and coin markers (name-based), spectate, camera tracking, selected
  player cycling, movement options, background farm flight, teleport attempts,
  fullbright, post-effect reduction, player count, anti-void,
  local demo target, mobile-friendly draggable UI and cleanup.

  Scribd reference exposes redacted snippets; the fling code restores v6.9 rather than copying unavailable source.
  Role information is only definitive when MM2 provides readable role data.
  Visible weapon hints are explicitly marked unconfirmed. Combat requests never guarantee kills. Flings and farming may be corrected by the game server.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
if not localPlayer then
    warn("This hub must run on a Roblox client.")
    return
end
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Allow running the script twice without leaving connections behind.
local environment = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then environment = value end
end
if type(environment.MM2LearningHubUnload) == "function" then
    pcall(environment.MM2LearningHubUnload)
end
if type(environment.SpectraExtrasUnload) == "function" then
    pcall(environment.SpectraExtrasUnload)
end
-- An earlier core could fail after creating UI but before registering Unload.
-- Remove only known SPECTRA leftovers so duplicate ESPs/launchers cannot
-- keep rendering and multiplying frame cost across loader retries.
for _, node in ipairs(playerGui:GetChildren()) do
    if node.Name == "SpectraMM2Hub" or node.Name == "SpectraESPOverlay" then
        pcall(function() node:Destroy() end)
    end
end
local staleEffects = Workspace:FindFirstChild("SpectraMM2Effects")
if staleEffects then pcall(function() staleEffects:Destroy() end) end

local connections = {}
local function watch(connection)
    table.insert(connections, connection)
    return connection
end

local enabled = {
    PlayerESP = true,
    RoleESP = true,
    ShowRoles = true,
    ThreatsOnly = false,
    RangeLimit = false,
    RoleAlerts = true,
    Names = true,
    Distances = true,
    Health = true,
    WeaponHints = true,
    XRay = true,
    Tracers = false,
    BoxESP2D = false,
    CombatRadius = true,
    AutoShootRadiusGate = true,
    Rainbow = false,
    GunESP = false,
    GunAlerts = false,
    GunAlertTime = -100,
    GunAlertMessage = "No gun alerts",
    KnifeESP = false,
    CoinESP = false,
    Sprint = false,
    CustomJump = false,
    InfiniteJump = false,
    Noclip = false,
    AutoHideRoundResults = true, -- only hide recognized reward/win panels; user can turn OFF
    Fly = false,
    AntiFling = false,
    Fullbright = false,
    LowFX = false,
    NoFog = false,
    HideOwnName = false,
    AntiSlip = false,
    AntiVoid = false,
    CameraLock = false,
    AutoCoinFarm = false,
    CoinTeleport = false, -- default to walking to avoid sudden movement validation
    CoinFlight = false,
    AutoGunApproach = false, -- deprecated approach mode; not surfaced in v5.8
    AutoGunPickup = false,
    AimAssist = false,
    AimWallCheck = true,
    SpinMode = false,
    FlingActive = false,
    EventESP = false,
    FarmEvents = false,
    FarmVisitLimit = false,
    AimFOVRing = false,
    AimRequireSheriff = true, -- all camera aim always Sheriff-only
    AutoAimMurderer = false,
    AutoShootMurderer = false,
    SilentAim = false,
    AutoSilentShot = false,
    SheriffRapidFire = false,
    ShowSheriffCrosshair = true,
    SheriffDpadFrontLock = true, -- Down runs front-lock test; toggle OFF for ordinary auto aim
    SheriffFrontMoveSelf = true, -- Place your character near the Murderer; don't fabricate target positions on your client
    SheriffRequireVisibleKnife = true, -- Normal sheriff auto aim/shoot only; NEVER gate front-stack
    MurderAura = false,
    MurderAuraApproach = false, -- opt-in limited approach; off by default to avoid Invalid Location
    ControllerHoldAim = true,
    LocalGhost = false,
}
local numbers = { Speed = 24, Jump = 65, FlySpeed = 45, FOV = 70, ESPRange = 250, FarmRadius = 1000, FarmFlySpeed = 25, FarmTeleportDelay = 2.5, AimRadius = 210, AimSmooth = 0.54, FarmVisitCap = 40, KnifeAuraRadius = 12, SheriffFrontDistance = 14, SpinFlingSpeed = 2400, SpinFlingDuration = 2.25, TouchSpinSpeed = 8000, TouchDuration = 1.55, LaunchSpeed = 480, LaunchDuration = 1.65, SheriffRapidInterval = 1.1, CrosshairSize = 16, CrosshairOpacity = 0.96, Gravity = Workspace.Gravity }
-- Save a copy of defaults before users customize settings.
local playerEffects = {}
local objectEffects = {}
local originalCollisions = {}
local originalFX = {}
local demoParts = {}
local selectedPlayer = nil
local refreshPlayerDropdown = function() end

local dropdownOpen = false
local lastPlayerChange = "Waiting for players"
local spectateTarget = nil
local flyAttachment = nil
local flyVelocity = nil
local flyRoot = nil
local flyUp, flyDown = false, false
local v54 = {
    updateFlyHUD = function() end,
    refreshFunPicker = function() end,
    setFlight = function() end,
    farmFlightBusy = false,
    farmTravelToken = 0,
    farmTravelDetail = "Idle",
    savedWaypoint = nil,
    postFarmMode = "notify", -- notify / role (explicit opt-in)
    resetAt40Enabled = false, -- separate opt-in; counts visits, not verified coins
    postFarmFinished = false,
    postFarmIdleSince = nil,
    postFarmStatus = "Idle",
    postActionToken = 0,
    flingFunLine = nil,
    flingAllActive = false,
    flingAllToken = 0,
    flingAllProgress = "No batch running",
    aimRateLabel = nil,
    gunPickupBusy = false,
    gunPickupLastAt = 0,
    gunReturnCF = nil,
    gunPickupTried = setmetatable({}, {__mode="k"}),
    gunPickupStatus = "Ready: no pickup attempted",
    gunPickupStatusLabel = nil,
    animationTrack = nil,
    animationAsset = nil,
    animationSpeed = 1,
    animationStatus = "Ready. Emotes require avatar access; custom assets need permission.",
    animationStatusLabel = nil,
    lastCoinTeleportAt = -100,
    settingsStatus = "No saved settings loaded",
    settingsStatusLabel = nil,
    roundResultManualUntil = 0,
    roundResultLastScan = -100,
    roundResultHiddenTotal = 0,
    roundResultStatusLabel = nil,
    roundResultNotice = "Ready • auto-hide ON (reward/win panels)",
}
-- Controller buttons operate alongside touch/keyboard without consuming Roblox inputs.
-- L2/LT is Sheriff hold-to-aim. L1/LB and R1/RB remain native weapon controls.
-- D-pad up Murderer Kill All, down Sheriff auto aim/shoot.
v54.defaultEnabled = table.clone(enabled)
v54.defaultNumbers = table.clone(numbers)
v54.gamepadAimHeld = false
v54.gamepadFlyUp, v54.gamepadFlyDown = false, false
v54.lastGamepadInput = "No controller input"
v54.gamepadInputCount = {up=0, down=0, l2=0}
v54.lastObjectMarkerTick = -100
v54.targetTeleportBusy = false
v54.targetTeleportToken = 0
v54.targetTeleportReport = "Target teleport test idle"
v54.targetTeleportLabel = nil
v54.gamepadLastDispatch = {}
v54.sheriffFrontArmed = false
v54.sheriffFrontLastTry = -100
v54.sheriffFrontShotActive = false -- front-stack shots bypass regular FOV gate
v54.sheriffFrontMoveNotice = "No Sheriff approach attempted"
v54.sheriffFrontRelocations = 0
v54.silentAimLast = -100
v54.silentAimReport = "OFF"
v54.silentAimSeenGun = setmetatable({}, {__mode="k"})
v54.silentAimLabel = nil

v54.isGamepadInput = function(input)
    return input and string.match(input.UserInputType.Name, "^Gamepad") ~= nil
end
local lastSafeCFrame = nil
local destroyed = false
local lastVisualTick = 0
local previousGravity = Workspace.Gravity
local previousFOV = Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView or 70
local originalLocalTransparency = setmetatable({}, {__mode = "k"})
local baseHumanoidSettings = setmetatable({}, {__mode = "k"})
local farmFocus, farmFocusStart, farmProgressDistance = nil, 0, math.huge
local farmSkipped = 0
local farmLastScan = 0
local farmCache = {}
local refreshDiagnostics = function() end
local fogOriginal = {}
local ownNameOriginal = setmetatable({}, { __mode = "k" })
local roleMap, roleFetchBusy, lastRoleFetch = {}, false, -100
local roleRequestId = 0
local roleLastUpdate, roleSyncMessage = 0, "Waiting for MM2 role data"
local roleChangeSignature = ""
local farmVisited = setmetatable({}, { __mode = "k" })
local farmAttempts = 0
local farmNotice = "Ready to scan coins"
local flingBusy = false
local flingToken = 0
local wasFlinging = false
local shotAttemptCount = 0
local shotNotice = "Auto Shoot idle"
local lastShotAttempt = -100
local shotInFlight = false
local flingNotice = "Fling not tested in this session"
-- The original v6.9-style method remains default. Only one fling engine runs.
v54.flingMode = "classic" -- classic, spin, launch, or touch
v54.flingModeToggle = nil
local lastRoleUI = 0
local lightOriginal = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    GlobalShadows = Lighting.GlobalShadows,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
}

local function characterOf(p)
    return p and p.Character or nil
end
local function rootOf(p)
    local char = characterOf(p)
    return char and char:FindFirstChild("HumanoidRootPart") or nil
end
local function humanOf(p)
    local char = characterOf(p)
    return char and char:FindFirstChildOfClass("Humanoid") or nil
end
local function alive(p)
    local humanoid = humanOf(p)
    return humanoid and humanoid.Health > 0
end
local function distanceTo(part)
    local ownRoot = rootOf(localPlayer)
    return ownRoot and (ownRoot.Position - part.Position).Magnitude or nil
end

-- Hints ONLY based on an equipped Tool that other players can see.
local function visibleWeaponHint(p)
    local char = characterOf(p)
    if not char then return "Unknown" end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            local name = child.Name:lower()
            if name:find("knife", 1, true) then return "Knife visible" end
            if name:find("gun", 1, true) or name:find("revolver", 1, true) then
                return "Gun visible"
            end
        end
    end
    return "Unknown"
end
local function colorForHint(hint)
    if hint == "Knife visible" then return Color3.fromRGB(255, 86, 88) end
    if hint == "Gun visible" then return Color3.fromRGB(85, 176, 255) end
    return Color3.fromRGB(95, 245, 160)
end

-- Non-overlapping fast role feed: default 1.5s; no blind trust in hints.
local validRole = { Murderer=true, Sheriff=true, Innocent=true, Hero=true }
v54.roleRefreshSeconds = 0.9 -- bounded polling, with event-triggered local role refresh
v54.roleRemote = nil
v54.roleRemoteNextSearch = -100
v54.normalizeRole = function(value)
    if type(value) ~= "string" then return nil end
    local role = value:sub(1, 1):upper() .. value:sub(2):lower()
    return validRole[role] and role or nil
end
local function refreshRoles()
    if roleFetchBusy or destroyed then return end
    roleFetchBusy = true
    roleRequestId += 1
    local request = roleRequestId
    task.delay(4, function()
        if not destroyed and roleRequestId == request and roleFetchBusy then
            roleRequestId += 1
            roleFetchBusy = false
            roleSyncMessage = "Role feed timeout; retrying"
        end
    end)
    task.spawn(function()
        local remote = v54.roleRemote
        if not remote or not remote.Parent then
            if os.clock() < v54.roleRemoteNextSearch then
                roleSyncMessage = "Waiting for MM2 role feed or replicated attributes"
                roleFetchBusy = false
                return
            end
            v54.roleRemoteNextSearch = os.clock() + 4
            remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
            if remote and remote:IsA("RemoteFunction") then
                v54.roleRemote = remote
            else
                roleSyncMessage = "No role remote; checking attributes and weapon hints"
                roleFetchBusy = false
                return
            end
        end
        local ok, data = pcall(function() return remote:InvokeServer() end)
        if destroyed or roleRequestId ~= request then return end
        if ok and type(data) == "table" then
            local received, count = {}, 0
            for key, info in pairs(data) do
                if type(info) == "table" then
                    local role = v54.normalizeRole(info.Role or info.role or info.CurrentRole)
                    local username = (type(key) == "string" and key)
                        or (typeof(key) == "Instance" and key:IsA("Player") and key.Name)
                        or (type(info.Name) == "string" and info.Name)
                        or (type(info.Username) == "string" and info.Username)
                    if role and username then
                        received[username] = {
                            role = role,
                            dead = info.Dead == true or info.Killed == true
                        }
                        count += 1
                    end
                end
            end
            if count > 0 then
                roleMap = received
                roleLastUpdate = os.clock()
                roleSyncMessage = "MM2 role feed • " .. count .. " players / fast sync"
            else
                roleSyncMessage = "Role response empty; using attributes/hints"
            end
        else
            roleSyncMessage = "Role request failed; using attributes/hints"
        end
        roleFetchBusy = false
    end)
end
local function getRole(player)
    if not player then return "Unknown", "none", false end
    local char = characterOf(player)
    local rawAttribute = player:GetAttribute("Role") or player:GetAttribute("CurrentRole")
        or (char and (char:GetAttribute("Role") or char:GetAttribute("CurrentRole")))
    local attrRole = v54.normalizeRole(rawAttribute)
    if attrRole then
        -- Attributes occasionally lag a dropped-Gun pickup. Mark a temporary
        -- Hero *hint* instead of falsely showing confirmed Innocent status.
        if player == localPlayer and attrRole == "Innocent"
            and visibleWeaponHint(player) == "Gun visible" then
            return "Hero", "hint", false
        end
        return attrRole, "game", false
    end
    if os.clock() - roleLastUpdate <= 2.5 then
        local info = roleMap[player.Name]
        if info then
            if player == localPlayer and info.role == "Innocent"
                and visibleWeaponHint(player) == "Gun visible" then
                return "Hero", "hint", false
            end
            return info.role, "game", info.dead
        end
    end
    local hint = visibleWeaponHint(player)
    if hint == "Knife visible" then return "Murderer", "hint", false end
    if hint == "Gun visible" then
        return player == localPlayer and "Hero" or "Sheriff", "hint", false
    end
    return "Unknown", "none", false
end
-- Attribute and tool signals react immediately to pickups/role changes,
-- without making expensive RemoteFunction calls every render frame.
v54.lastRoleSignalFetch = -100
v54.seenRolePlayers = setmetatable({}, {__mode="k"})
v54.seenRoleCharacters = setmetatable({}, {__mode="k"})
v54.roleChangedSignal = function(player)
    if destroyed then return end
    v54.lastEspDataTick = -100
    v54.lastRoleRadarTick = -100
    if player == localPlayer and v54.updateSheriffCrosshair then
        v54.updateSheriffCrosshair()
    end
    if os.clock() - v54.lastRoleSignalFetch >= 0.55 then
        v54.lastRoleSignalFetch = os.clock()
        lastRoleFetch = os.clock()
        refreshRoles()
    end
end
v54.observeRoleCharacter = function(player, character)
    if not character or v54.seenRoleCharacters[character] then return end
    v54.seenRoleCharacters[character] = true
    for _, attribute in ipairs({"Role","CurrentRole"}) do
        watch(character:GetAttributeChangedSignal(attribute):Connect(function()
            v54.roleChangedSignal(player)
        end))
    end
    watch(character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then v54.roleChangedSignal(player) end
    end))
    watch(character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then v54.roleChangedSignal(player) end
    end))
end
v54.observeRolePlayer = function(player)
    if not player or v54.seenRolePlayers[player] then return end
    v54.seenRolePlayers[player] = true
    for _, attribute in ipairs({"Role","CurrentRole"}) do
        watch(player:GetAttributeChangedSignal(attribute):Connect(function()
            v54.roleChangedSignal(player)
        end))
    end
    watch(player.CharacterAdded:Connect(function(char)
        v54.observeRoleCharacter(player,char)
        roleMap[player.Name] = nil -- old round roles are not current ones
        v54.roleChangedSignal(player)
    end))
    v54.observeRoleCharacter(player,player.Character)
end
for _, player in ipairs(Players:GetPlayers()) do
    v54.observeRolePlayer(player)
end
watch(Players.PlayerAdded:Connect(function(player)
    v54.observeRolePlayer(player)
    v54.roleChangedSignal(player)
end))
local function getRoleColor(role, source)
    if role == "Murderer" then return Color3.fromRGB(255, 86, 104) end
    if role == "Sheriff" then return Color3.fromRGB(83, 168, 255) end
    if role == "Hero" then return Color3.fromRGB(255, 205, 83) end
    if role == "Innocent" then return Color3.fromRGB(98, 231, 159) end
    return Color3.fromRGB(165, 180, 206)
end
local function roleDisplay(role, source)
    if source == "game" then return role end
    if source == "hint" then return role .. "? [tool seen]" end
    return "Unknown"
end

local gui = Instance.new("ScreenGui")
gui.Name = "SpectraMM2Hub"
gui.DisplayOrder = 5
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
-- Keep touch controls clear of mobile cutouts and the Roblox top bar.
-- ScreenInsets support varies by client; never abort the whole menu over insets.
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui
-- Early visible startup indicator: if construction fails later, users get
-- a diagnostic instead of a blank screen.
local bootLabel = Instance.new("TextLabel")
bootLabel.Name = "SpectraStartupStatus"
bootLabel.Size = UDim2.new(0, 275, 0, 44)
bootLabel.Position = UDim2.new(0, 12, 0, 60)
bootLabel.BackgroundColor3 = Color3.fromRGB(28, 38, 62)
bootLabel.BackgroundTransparency = 0.13
bootLabel.TextColor3 = Color3.fromRGB(240, 248, 255)
bootLabel.TextWrapped = true
bootLabel.Font = Enum.Font.GothamBold
bootLabel.TextSize = 12
bootLabel.Text = "SPECTRA v9.7 • opening..."
bootLabel.ZIndex = 250
bootLabel.Parent = gui
task.delay(12, function()
    if bootLabel.Parent then
        bootLabel.Text = "SPECTRA startup incomplete. Check Roblox developer console."
        warn("[SPECTRA v9.7] Startup did not finish within 12 seconds.")
    end
end)
-- WorldToViewportPoint is NOT adjusted for the Roblox topbar. Keep ESP
-- in its own noninteractive fullscreen ScreenGui with no safe-area inset.
local boxGui = Instance.new("ScreenGui")
boxGui.Name = "SpectraESPOverlay"
boxGui.ResetOnSpawn = false
boxGui.IgnoreGuiInset = true
-- ScreenInsets can throw on some Roblox clients: never let an optional
-- ESP alignment setting block the entire window from loading.
pcall(function() boxGui.ScreenInsets = Enum.ScreenInsets.None end)
boxGui.DisplayOrder = 15
boxGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
boxGui.Parent = playerGui
v54.sheriffCrosshair = Instance.new("Frame")
v54.sheriffCrosshair.Name = "SpectraCrosshair"
v54.sheriffCrosshair.AnchorPoint = Vector2.new(0.5,0.5)
v54.sheriffCrosshair.Position = UDim2.fromScale(0.5,0.5)
v54.sheriffCrosshair.Size = UDim2.fromOffset(120,120)
v54.sheriffCrosshair.BackgroundTransparency = 1
v54.sheriffCrosshair.Visible = false
v54.sheriffCrosshair.Active = false
v54.sheriffCrosshair.Parent = boxGui
v54.crosshairParts = {}
for _, direction in ipairs({"top","bottom","left","right","dot"}) do
    local part = Instance.new("Frame")
    part.Name = direction
    part.AnchorPoint = Vector2.new(0.5,0.5)
    part.BorderSizePixel = 0
    part.BackgroundColor3 = Color3.fromRGB(104,255,245)
    part.Active = false
    part.ZIndex = 80
    part.Parent = v54.sheriffCrosshair
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(5,8,18)
    stroke.Thickness = 1.5
    stroke.Parent = part
    v54.crosshairParts[direction] = part
end

-- World-space effects must be parented in Workspace, not inside ScreenGui.
local effectsFolder = Instance.new("Folder")
effectsFolder.Name = "SpectraMM2Effects"
effectsFolder.Parent = Workspace

local function round(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 9)
    corner.Parent = parent
end
local function stroke(parent, color, transparency)
    local outline = Instance.new("UIStroke")
    outline.Color = color or Color3.fromRGB(65, 75, 100)
    outline.Transparency = transparency or 0
    outline.Parent = parent
end
local function label(parent, text, h, color, size)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.TextColor3 = color or Color3.fromRGB(225, 231, 245)
    l.TextSize = size or 14
    l.Font = Enum.Font.Gotham
    l.Text = text
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextWrapped = true
    l.TextYAlignment = Enum.TextYAlignment.Top
    -- Grow only to the text, not a giant fixed-height explanation card.
    l.Size = UDim2.new(1, -10, 0, math.min(h, 28))
    l.AutomaticSize = Enum.AutomaticSize.Y
    l.Parent = parent
    return l
end

-- SPECTRA 7.8: compact mobile/controller UI with role shortcuts.
-- Four navigation sections replace the thirteen-tab wall.
local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(760, 450)
local function windowDimensions(size)
    -- More horizontal space for legible controls on phones; leave game HUD visible.
    local w = math.clamp(size.X - 22, 300, 690)
    local h = math.clamp(size.Y - 116, 278, 456)
    return w, h
end
local width, height = windowDimensions(viewport)
local sidebarWidth = 126
local window = Instance.new("Frame")
window.Name = "Window"
window.Size = UDim2.fromOffset(width, height)
window.Position = UDim2.fromOffset(math.max(8, math.floor((viewport.X - width) / 2)), 16)
window.BackgroundColor3 = Color3.fromRGB(13, 16, 22)
window.BorderSizePixel = 0
window.Active = true
window.Parent = gui
round(window, 7)
stroke(window, Color3.fromRGB(81, 91, 112), 0.23)
local top = Instance.new("Frame")
top.Size = UDim2.new(1, 0, 0, 41)
top.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
top.BorderSizePixel = 0
top.Active = true
top.Parent = window
round(top, 6)
local title = label(top, "◈  SPECTRA  •  v9.6", 40, Color3.fromRGB(250, 251, 255), 15)
title.Position = UDim2.fromOffset(14, 1)
title.Size = UDim2.new(1, -100, 0, 40)
title.AutomaticSize = Enum.AutomaticSize.None
title.Font = Enum.Font.GothamBold
local minimize = Instance.new("TextButton")
minimize.Size = UDim2.fromOffset(34, 30)
minimize.Position = UDim2.new(1, -76, 0, 6)
minimize.Text = "−"
minimize.TextSize = 25
minimize.Font = Enum.Font.GothamBold
minimize.TextColor3 = Color3.new(1, 1, 1)
minimize.BackgroundColor3 = Color3.fromRGB(42, 50, 66)
minimize.Parent = top
round(minimize, 8)
local close = minimize:Clone()
close.Name = "MinimizeToFloatingIcon"
close.Position = UDim2.new(1, -39, 0, 6)
close.Text = "×"
close.BackgroundColor3 = Color3.fromRGB(113, 47, 63)
close.Parent = top
v54.roleStrip = Instance.new("TextLabel")
v54.roleStrip.Name = "RoleStatus"
v54.roleStrip.Position = UDim2.fromOffset(10, 46)
v54.roleStrip.Size = UDim2.new(1, -20, 0, 29)
v54.roleStrip.BackgroundColor3 = Color3.fromRGB(31, 41, 55)
v54.roleStrip.TextColor3 = Color3.fromRGB(222, 238, 251)
v54.roleStrip.TextXAlignment = Enum.TextXAlignment.Left
v54.roleStrip.Font = Enum.Font.GothamBold
v54.roleStrip.TextSize = width < 420 and 11 or 13
v54.roleStrip.Text = "  ROLE RADAR  •  checking game data..."
v54.roleStrip.TextTruncate = Enum.TextTruncate.AtEnd
v54.roleStrip.Parent = window
round(v54.roleStrip, 8)
local tabs = Instance.new("ScrollingFrame")
tabs.Name = "Sidebar"
tabs.BorderSizePixel = 0
tabs.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
tabs.Position = UDim2.fromOffset(9, 81)
tabs.Size = UDim2.new(0, sidebarWidth, 1, -117)
tabs.ScrollBarThickness = 2
tabs.ScrollBarImageColor3 = Color3.fromRGB(102, 152, 255)
tabs.AutomaticCanvasSize = Enum.AutomaticSize.Y
tabs.CanvasSize = UDim2.fromOffset(0, 0)
tabs.Parent = window
round(tabs, 10)
local tabPad = Instance.new("UIPadding")
tabPad.PaddingTop = UDim.new(0, 6)
tabPad.PaddingLeft = UDim.new(0, 5)
tabPad.PaddingRight = UDim.new(0, 5)
tabPad.PaddingBottom = UDim.new(0, 6)
tabPad.Parent = tabs
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Vertical
tabLayout.Padding = UDim.new(0, 3)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabs
local main = Instance.new("Frame")
main.Name = "Content"
main.BackgroundTransparency = 1
main.Position = UDim2.fromOffset(sidebarWidth + 16, 81)
main.Size = UDim2.new(1, -sidebarWidth - 25, 1, -117)
main.Parent = window
local status = Instance.new("TextLabel")
status.BackgroundColor3 = Color3.fromRGB(28, 34, 45)
status.Position = UDim2.new(0, 9, 1, -31)
status.Size = UDim2.new(1, -18, 0, 25)
status.TextColor3 = Color3.fromRGB(205, 222, 245)
status.TextSize = 12
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "  Ready  •  choose a section, then a tab"
status.TextTruncate = Enum.TextTruncate.AtEnd
status.Font = Enum.Font.GothamMedium
status.Parent = window
round(status, 7)
local function inform(message)
    if not destroyed then status.Text = "  " .. message end
end
local pages = {}
local tabButtons = {}
local toggleUpdaters = {}
v54.activeTab = "HOME"
v54.gamepadMenuMode = false
v54.tabOrder = { "HOME", "ESP", "MOVE", "TELEPORT", "FARM", "FUN", "MURDER", "SHERIFF", "INNOCENT", "ANIMS", "SETTINGS", "STATUS" }
-- One small section selector stays visible; only relevant tabs are shown.
v54.navGroups = {
    {title = "GENERAL", tabs = {"HOME", "ESP", "MOVE", "TELEPORT"}},
    {title = "GAMEPLAY", tabs = {"FARM", "FUN"}},
    {title = "ROLES", tabs = {"MURDER", "SHERIFF", "INNOCENT"}},
    {title = "OPTIONS", tabs = {"ANIMS", "SETTINGS", "STATUS"}},
}
v54.currentNavGroup = 1
v54.groupBar = Instance.new("Frame")
v54.groupBar.Name = "SectionPicker"
v54.groupBar.BackgroundColor3 = Color3.fromRGB(25, 32, 45)
v54.groupBar.BorderSizePixel = 0
v54.groupBar.Position = UDim2.fromOffset(9, 81)
v54.groupBar.Size = UDim2.fromOffset(sidebarWidth, 32)
v54.groupBar.Parent = window
round(v54.groupBar, 6)
v54.groupButton = function(text, widthOffset)
    local button = Instance.new("TextButton")
    button.BackgroundColor3 = Color3.fromRGB(35, 45, 65)
    button.TextColor3 = Color3.fromRGB(235, 242, 255)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 14
    button.Text = text
    button.Selectable = true
    button.BorderSizePixel = 0
    button.Size = UDim2.fromOffset(25, 26)
    button.Position = UDim2.new(widthOffset == 0 and 0 or 1, widthOffset == 0 and 3 or -28, 0, 3)
    button.Parent = v54.groupBar
    round(button, 5)
    return button
end
v54.prevGroup = v54.groupButton("‹", 0)
v54.nextGroup = v54.groupButton("›", 1)
v54.groupName = Instance.new("TextLabel")
v54.groupName.Name = "CurrentSection"
v54.groupName.BackgroundTransparency = 1
v54.groupName.Text = "GENERAL"
v54.groupName.TextColor3 = Color3.fromRGB(199, 222, 255)
v54.groupName.Font = Enum.Font.GothamBold
v54.groupName.TextSize = 11
v54.groupName.TextTruncate = Enum.TextTruncate.AtEnd
v54.groupName.Size = UDim2.new(1, -61, 1, 0)
v54.groupName.Position = UDim2.fromOffset(31, 0)
v54.groupName.Parent = v54.groupBar
v54.selectNavGroup = function(index, keepCurrentTab)
    index = ((index - 1) % #v54.navGroups) + 1
    v54.currentNavGroup = index
    local info = v54.navGroups[index]
    v54.groupName.Text = info.title .. "  " .. index .. "/" .. #v54.navGroups
    for _, name in ipairs(v54.tabOrder) do
        local tab = tabButtons[name]
        if tab then
            local isShown = table.find(info.tabs, name) ~= nil
            tab.Visible = isShown
            tab.Selectable = isShown
        end
    end
    tabs.CanvasPosition = Vector2.zero
    if not keepCurrentTab and pages[info.tabs[1]] then
        v54.activateTab(info.tabs[1])
    end
end
watch(v54.prevGroup.Activated:Connect(function()
    v54.selectNavGroup(v54.currentNavGroup - 1, false)
end))
watch(v54.nextGroup.Activated:Connect(function()
    v54.selectNavGroup(v54.currentNavGroup + 1, false)
end))
v54.activateTab = function(name)
    if not pages[name] then return end
    v54.activeTab = name
    for index, info in ipairs(v54.navGroups) do
        if table.find(info.tabs, name) and v54.currentNavGroup ~= index then
            v54.selectNavGroup(index, true)
            break
        end
    end
    for tabName, page in pairs(pages) do
        local selected = tabName == name
        page.Visible = selected
        tabButtons[tabName].BackgroundColor3 = selected
            and Color3.fromRGB(60, 87, 197) or Color3.fromRGB(28, 34, 45)
        tabButtons[tabName].TextColor3 = selected
            and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(205, 215, 230)
    end
end
local function makeTab(name)
    local b = Instance.new("TextButton")
    b.Name = "Nav_" .. name
    b.Size = UDim2.new(1, 0, 0, 37)
    local displayName = ({TELEPORT = "TRAVEL", MURDER = "MURDERER", SHERIFF = "SHERIFF", INNOCENT = "INNOCENT", SETTINGS = "SETTINGS", STATUS = "DIAGNOSTICS"})[name] or name
    b.Text = "  " .. displayName
    b.TextSize = 13
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Font = Enum.Font.GothamMedium
    b.BackgroundColor3 = Color3.fromRGB(28, 34, 45)
    b.TextColor3 = Color3.fromRGB(205, 215, 230)
    b.BorderSizePixel = 0
    b.Parent = tabs
    b.Selectable = true
    round(b, 7)
    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.BorderSizePixel = 0
    page.BackgroundTransparency = 1
    page.Size = UDim2.fromScale(1, 1)
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = Color3.fromRGB(99, 149, 255)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.fromOffset(0, 0)
    page.Visible = false
    page.Parent = main
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 5)
    pad.PaddingBottom = UDim.new(0, 15)
    pad.PaddingLeft = UDim.new(0, 3)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = page
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page
    pages[name] = page
    tabButtons[name] = b
    watch(b.Activated:Connect(function()
        v54.activateTab(name)
    end))
    return page
end
local rolesPage = makeTab("HOME")
local visualsPage = makeTab("ESP")
local movementPage = makeTab("MOVE")
local toolsPage = makeTab("TELEPORT")
local farmPage = makeTab("FARM")
-- All AIM controls now share the Sheriff page.
local funPage = makeTab("FUN")
v54.murderPage = makeTab("MURDER")
v54.sheriffPage = makeTab("SHERIFF")
local aimPage = v54.sheriffPage
v54.innocentPage = makeTab("INNOCENT")
makeTab("ANIMS")
local settingsPage = makeTab("SETTINGS")
local diagnosticsPage = makeTab("STATUS")
v54.activateTab("HOME")
v54.selectNavGroup(1, true)
-- Compact, draggable launcher that stays on screen while the full menu is hidden.
-- The position lives only for this running script session.
local launcher = Instance.new("TextButton")
launcher.Name = "FloatingSPECTRAIcon"
launcher.Size = UDim2.fromOffset(62, 62)
launcher.BackgroundColor3 = Color3.fromRGB(48, 80, 189)
launcher.TextColor3 = Color3.fromRGB(255, 255, 255)
launcher.TextSize = 29
launcher.Font = Enum.Font.GothamBold
launcher.Text = "◈"
launcher.AutoButtonColor = true
launcher.Active = true
launcher.ZIndex = 50
launcher.Visible = false
launcher.Parent = gui
round(launcher, 31)
stroke(launcher, Color3.fromRGB(145, 183, 255), 0.12)
local launcherName = Instance.new("TextLabel")
launcherName.Name = "Brand"
launcherName.BackgroundTransparency = 1
launcherName.Size = UDim2.new(1, 0, 0, 16)
launcherName.Position = UDim2.new(0, 0, 1, -18)
launcherName.Text = "SPECTRA"
launcherName.Font = Enum.Font.GothamBold
launcherName.TextColor3 = Color3.fromRGB(242, 247, 255)
launcherName.TextSize = 9
launcherName.ZIndex = 51
launcherName.Active = false
launcherName.Parent = launcher
local function usableViewport()
    local camera = Workspace.CurrentCamera
    local currentSize = camera and camera.ViewportSize or Vector2.new(390, 700)
    local topInset, bottomInset = GuiService:GetGuiInset()
    return Vector2.new(
        math.max(90, currentSize.X - topInset.X - bottomInset.X),
        math.max(110, currentSize.Y - topInset.Y - bottomInset.Y)
    )
end
local function placeLauncher(x, y)
    local safe = usableViewport()
    local maxX = math.max(8, safe.X - launcher.Size.X.Offset - 8)
    local maxY = math.max(8, safe.Y - launcher.Size.Y.Offset - 8)
    -- Keep the launcher in the upper-left zone, separate from right-side flight HUD.
    launcher.Position = UDim2.fromOffset(math.clamp(x, 8, maxX), math.clamp(y, 8, maxY))
end
local initialArea = usableViewport()
placeLauncher(12, 90)
local function heading(page, text)
    local l = label(page, "   " .. text, 28, Color3.fromRGB(195, 218, 255), 12)
    l.Name = "SectionHeader"
    l.BackgroundTransparency = 0
    l.BackgroundColor3 = Color3.fromRGB(23, 32, 49)
    l.Font = Enum.Font.GothamBold
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.AutomaticSize = Enum.AutomaticSize.None
    l.Size = UDim2.new(1, -4, 0, 28)
    round(l, 5)
    local accent = Instance.new("Frame")
    accent.BorderSizePixel = 0
    accent.BackgroundColor3 = Color3.fromRGB(100, 164, 255)
    accent.Size = UDim2.fromOffset(3, 18)
    accent.Position = UDim2.fromOffset(3, 5)
    accent.Parent = l
end
v54.menuActionButtons = {}
v54.uiDensity = "COMPACT"
v54.setUIDensity = function(density)
    v54.uiDensity = density == "TOUCH" and "TOUCH" or "COMPACT"
    for _, button in ipairs(v54.menuActionButtons) do
        if button.Parent then
            button.Size = UDim2.new(1, -4, 0, v54.uiDensity == "TOUCH" and 52 or 43)
            button.TextSize = v54.uiDensity == "TOUCH" and 14 or 13
        end
    end
    if v54.uiDensityButton and v54.uiDensityButton.Parent then
        v54.uiDensityButton.Text = "Control size: " .. v54.uiDensity .. " (tap to change)"
    end
end
local function makeButton(page, text, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -4, 0, v54.uiDensity == "TOUCH" and 52 or 43)
    b.BackgroundColor3 = Color3.fromRGB(33, 43, 59)
    b.TextColor3 = Color3.fromRGB(242, 246, 252)
    b.TextSize = v54.uiDensity == "TOUCH" and 14 or 13
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextWrapped = true
    b.Font = Enum.Font.GothamMedium
    b.Text = text
    b.AutoButtonColor = true
    b.Selectable = true
    b.BorderSizePixel = 0
    b.Parent = page
    round(b, 6)
    table.insert(v54.menuActionButtons, b)
    local inset = Instance.new("UIPadding")
    inset.PaddingLeft = UDim.new(0, 12)
    inset.PaddingRight = UDim.new(0, 13)
    inset.Parent = b
    watch(b.Activated:Connect(function()
        if not destroyed then
            local ok, err = pcall(callback)
            if not ok then inform("Error: " .. tostring(err):sub(1, 72)) end
        end
    end))
    return b
end
local function toggle(page, name, key, onChanged)
    local b
    local pill = Instance.new("TextLabel")
    pill.AnchorPoint = Vector2.new(1, 0.5)
    pill.Size = UDim2.fromOffset(49, 26)
    pill.Position = UDim2.new(1, -11, 0.5, 0)
    pill.TextSize = 12
    pill.Font = Enum.Font.GothamBold
    round(pill, 13)
    local function update()
        b.Text = name
        pill.Text = enabled[key] and "ON" or "OFF"
        pill.TextColor3 = enabled[key] and Color3.fromRGB(239, 255, 250)
            or Color3.fromRGB(216, 227, 242)
        pill.BackgroundColor3 = enabled[key] and Color3.fromRGB(32, 150, 117)
            or Color3.fromRGB(69, 76, 91)
    end
    b = makeButton(page, "", function()
        enabled[key] = not enabled[key]
        update()
        if onChanged then onChanged(enabled[key]) end
    end)
    b.TextSize = v54.uiDensity == "TOUCH" and 14 or 13
    local inset = b:FindFirstChildWhichIsA("UIPadding")
    if inset then inset.PaddingRight = UDim.new(0, 64) end
    pill.Parent = b
    update()
    table.insert(toggleUpdaters, update)
    return b
end

-- Touch/mouse value bars replace repeated +/- actions. Values continue to
-- use the existing numbers table, so saved settings and behavior stay linked.
v54.sliderRefreshers = {}
v54.sliderControllers = {}
v54.refreshSliders = function()
    for _, refresh in ipairs(v54.sliderRefreshers) do refresh() end
end
local function makeSlider(page, caption, key, minimum, maximum, step, unit, onChanged)
    local holder = Instance.new("Frame")
    holder.Name = "ValueBar_" .. key
    holder.Size = UDim2.new(1, -4, 0, 64)
    holder.BorderSizePixel = 0
    holder.BackgroundColor3 = Color3.fromRGB(31, 42, 60)
    holder.Parent = page
    round(holder, 7)

    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1
    nameLabel.Position = UDim2.fromOffset(12, 5)
    nameLabel.Size = UDim2.new(1, -118, 0, 24)
    nameLabel.Text = caption
    nameLabel.TextColor3 = Color3.fromRGB(226, 238, 255)
    nameLabel.Font = Enum.Font.GothamMedium
    nameLabel.TextSize = 12
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = holder

    local valueLabel = Instance.new("TextLabel")
    valueLabel.BackgroundTransparency = 1
    valueLabel.AnchorPoint = Vector2.new(1, 0)
    valueLabel.Position = UDim2.new(1, -12, 0, 5)
    valueLabel.Size = UDim2.fromOffset(105, 24)
    valueLabel.TextColor3 = Color3.fromRGB(136, 201, 255)
    valueLabel.TextSize = 12
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = holder

    local bar = Instance.new("TextButton")
    bar.Name = "DragValue"
    bar.Text = ""
    bar.BackgroundTransparency = 1
    bar.Size = UDim2.new(1, -26, 0, 28)
    bar.Position = UDim2.new(0, 13, 0, 30)
    bar.Selectable = true
    bar.Active = true
    bar.Parent = holder

    local track = Instance.new("Frame")
    track.BorderSizePixel = 0
    track.BackgroundColor3 = Color3.fromRGB(73, 86, 109)
    track.Position = UDim2.new(0, 0, 0.5, -4)
    track.Size = UDim2.new(1, 0, 0, 8)
    track.Parent = bar
    round(track, 4)

    local fill = Instance.new("Frame")
    fill.BorderSizePixel = 0
    fill.BackgroundColor3 = Color3.fromRGB(96, 166, 255)
    fill.Size = UDim2.fromScale(0.5, 1)
    fill.Parent = track
    round(fill, 4)

    local thumb = Instance.new("Frame")
    thumb.Name = "SliderThumb"
    thumb.BorderSizePixel = 0
    thumb.BackgroundColor3 = Color3.fromRGB(237, 247, 255)
    thumb.AnchorPoint = Vector2.new(0.5, 0.5)
    thumb.Size = UDim2.fromOffset(17, 17)
    thumb.Parent = track
    round(thumb, 9)

    local function formatValue(value)
        if unit == "%" then return tostring(math.floor(value * 100 + 0.5)) .. "%" end
        if step < 1 then return string.format("%.1f", value) .. (unit or "") end
        return tostring(math.floor(value + 0.5)) .. (unit or "")
    end
    local function refresh()
        local value = math.clamp(numbers[key] or minimum, minimum, maximum)
        local fraction = math.clamp((value - minimum) / (maximum - minimum), 0, 1)
        fill.Size = UDim2.fromScale(fraction, 1)
        thumb.Position = UDim2.fromScale(fraction, 0.5)
        valueLabel.Text = formatValue(value)
    end
    local function setByX(x)
        local fraction = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
        local snapped = minimum + math.floor(((maximum - minimum) * fraction) / step + 0.5) * step
        snapped = math.clamp(math.floor(snapped * 1000 + 0.5) / 1000, minimum, maximum)
        if numbers[key] ~= snapped then
            numbers[key] = snapped
            if onChanged then onChanged(snapped) end
        end
        refresh()
    end
    local activeInput = nil
    watch(bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            activeInput = input
            setByX(input.Position.X)
        end
    end))
    watch(UserInputService.InputChanged:Connect(function(input)
        if not activeInput then return end
        if activeInput.UserInputType == Enum.UserInputType.Touch then
            if input == activeInput then setByX(input.Position.X) end
        elseif input.UserInputType == Enum.UserInputType.MouseMovement
            and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            setByX(input.Position.X)
        end
    end))
    watch(UserInputService.InputEnded:Connect(function(input)
        if input == activeInput
            or (activeInput and activeInput.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseButton1) then
            activeInput = nil
        end
    end))
    -- When a controller selects a value bar, D-pad left/right changes
    -- the value; the usual menu-tab navigation is suspended for that bar.
    v54.sliderControllers[bar] = function(direction)
        local snapped = numbers[key] + direction * step
        snapped = math.clamp(math.floor(snapped * 1000 + 0.5) / 1000, minimum, maximum)
        if numbers[key] ~= snapped then
            numbers[key] = snapped
            if onChanged then onChanged(snapped) end
        end
        refresh()
    end
    watch(bar.Activated:Connect(function()
        if UserInputService.GamepadEnabled and GuiService.SelectedObject == bar then
            v54.sliderControllers[bar](1)
        end
    end))
    table.insert(v54.sliderRefreshers, refresh)
    refresh()
    return holder
end

-- Responsive layout: section picker and tabs remain visible in portrait.
-- Only three or four tabs appear at once, leaving room for readable controls.
local function applyResponsiveLayout()
    local narrow = width < 490
    if narrow then
        v54.groupBar.Position = UDim2.fromOffset(9, 80)
        v54.groupBar.Size = UDim2.new(1, -18, 0, 32)
        tabs.Position = UDim2.fromOffset(9, 116)
        tabs.Size = UDim2.new(1, -18, 0, 42)
        tabs.ScrollingDirection = Enum.ScrollingDirection.X
        tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
        tabLayout.FillDirection = Enum.FillDirection.Horizontal
        tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        main.Position = UDim2.fromOffset(9, 163)
        main.Size = UDim2.new(1, -18, 1, -198)
    else
        v54.groupBar.Position = UDim2.fromOffset(9, 81)
        v54.groupBar.Size = UDim2.fromOffset(sidebarWidth, 32)
        tabs.Position = UDim2.fromOffset(9, 118)
        tabs.Size = UDim2.new(0, sidebarWidth, 1, -154)
        tabs.ScrollingDirection = Enum.ScrollingDirection.Y
        tabs.AutomaticCanvasSize = Enum.AutomaticSize.Y
        tabLayout.FillDirection = Enum.FillDirection.Vertical
        main.Position = UDim2.fromOffset(sidebarWidth + 16, 81)
        main.Size = UDim2.new(1, -sidebarWidth - 25, 1, -117)
    end
    for _, button in pairs(tabButtons) do
        button.Size = narrow and UDim2.fromOffset(111, 34)
            or UDim2.new(1, 0, 0, 38)
        button.TextSize = narrow and 12 or 12
    end
end
applyResponsiveLayout()

-- Drag window with mouse or touch.
local dragging = false
local startPos, startInput, dragType
watch(top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        startPos = window.Position
        startInput = input.Position
        dragType = input.UserInputType
    end
end))
watch(UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if dragType == Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.Touch then return end
    if dragType == Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local delta = input.Position - startInput
    local screen = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
        or Vector2.new(390, 700)
    local newX = math.clamp(startPos.X.Offset + delta.X, 0, math.max(0, screen.X - width))
    local newY = math.clamp(startPos.Y.Offset + delta.Y, 0, math.max(0, screen.Y - height))
    window.Position = UDim2.fromOffset(newX, newY)
end))
watch(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == dragType then dragging = false end
end))
local minimized = false
local function setWindowOpen(open)
    if destroyed then return end
    minimized = not open
    window.Visible = open
    tabs.Visible = open
    main.Visible = open
    status.Visible = open
    launcher.Visible = not open
    if open then
        -- Don't leave a gamepad cursor pointing to a hidden launcher.
        if GuiService.SelectedObject == launcher then GuiService.SelectedObject = nil end
    elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
        GuiService.SelectedObject = nil
    end
    if not open then
        -- Position is clamped even after a phone rotation or resolution change.
        placeLauncher(launcher.Position.X.Offset, launcher.Position.Y.Offset)
    end
end

-- X and minus now BOTH minimize. Neither unloads effects or connections.
watch(minimize.Activated:Connect(function() setWindowOpen(false) end))
watch(close.Activated:Connect(function() setWindowOpen(false) end))

-- Tap to reopen; drag to reposition. Use pointer identity on touch so a
-- second finger cannot steal an ongoing drag. A drag never triggers reopen.
local launcherDragInput, launcherDragType
local launcherDragStart, launcherStartXY
local launcherMoved = false
watch(launcher.InputBegan:Connect(function(input)
    local kind = input.UserInputType
    if launcherDragInput or (kind ~= Enum.UserInputType.Touch
        and kind ~= Enum.UserInputType.MouseButton1) then return end
    launcherDragInput = input
    launcherDragType = kind
    launcherDragStart = input.Position
    launcherStartXY = Vector2.new(launcher.Position.X.Offset, launcher.Position.Y.Offset)
    launcherMoved = false
end))
watch(UserInputService.InputChanged:Connect(function(input)
    if not launcherDragInput or not minimized then return end
    if launcherDragType == Enum.UserInputType.Touch then
        if input ~= launcherDragInput then return end
    elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
        return
    end
    local delta = input.Position - launcherDragStart
    if delta.Magnitude > 9 then launcherMoved = true end
    if launcherMoved then
        placeLauncher(launcherStartXY.X + delta.X, launcherStartXY.Y + delta.Y)
    end
end))
watch(UserInputService.InputEnded:Connect(function(input)
    if not launcherDragInput then return end
    if launcherDragType == Enum.UserInputType.Touch then
        if input ~= launcherDragInput then return end
    elseif input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        return
    end
    local delta = input.Position - launcherDragStart
    local wasDrag = launcherMoved or delta.Magnitude > 9
    launcherDragInput = nil
    launcherDragType = nil
    launcherDragStart = nil
    launcherStartXY = nil
    launcherMoved = false
    if destroyed or not minimized then return end
    if wasDrag then
        -- Snap to a reachable edge after the drag ends.
        local safe = usableViewport()
        local half = safe.X / 2
        local edgeX = launcher.Position.X.Offset + launcher.Size.X.Offset / 2 < half
            and 8 or math.max(8, safe.X - launcher.Size.X.Offset - 8)
        placeLauncher(edgeX, launcher.Position.Y.Offset)
    else
        setWindowOpen(true)
    end
end))
-- Desktop shortcut, avoids interfering with phone text fields.
watch(UserInputService.InputBegan:Connect(function(input, processed)
    if processed or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        setWindowOpen(minimized)
    end
end))
-- Player visuals ------------------------------------------------------
local function destroyPlayerEffect(p)
    local e = playerEffects[p]
    if e then
        -- Never destroy e.char: it belongs to the player, not this script.
        e.highlight:Destroy()
        e.billboard:Destroy()
        playerEffects[p] = nil
    end
end
local function makePlayerEffect(p)
    local char = characterOf(p)
    local root = rootOf(p)
    local head = char and char:FindFirstChild("Head")
    if not char or not root or not head then return end
    local existing = playerEffects[p]
    if existing and existing.char == char then return end
    destroyPlayerEffect(p)
    local h = Instance.new("Highlight")
    h.Name = "LearningHubPlayerHighlight"
    h.Adornee = char
    h.FillTransparency = 0.72
    h.OutlineTransparency = 0
    h.Parent = effectsFolder

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PlayerInfo"
    billboard.Adornee = head
    billboard.Size = UDim2.fromOffset(222, 64)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = gui
    local text = Instance.new("TextLabel")
    text.Size = UDim2.fromScale(1, 1)
    text.TextScaled = false
    text.TextSize = 12
    text.TextWrapped = true
    text.Font = Enum.Font.GothamBold
    text.TextColor3 = Color3.new(1, 1, 1)
    text.TextStrokeTransparency = 0.25
    text.BackgroundTransparency = 1
    text.Parent = billboard

    playerEffects[p] = { char = char, highlight = h, billboard = billboard, text = text }
end
local function updatePlayerEffects(timeNow)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer then
            local role, source = getRole(p)
            local tracked = not enabled.ThreatsOnly or (role == "Murderer" or role == "Sheriff" or role == "Hero")
            local targetRoot = rootOf(p)
            local distance = targetRoot and distanceTo(targetRoot)
            local inRange = not enabled.RangeLimit or (distance and distance <= numbers.ESPRange)
            if enabled.PlayerESP and alive(p) and tracked and inRange then
                makePlayerEffect(p)
                local e = playerEffects[p]
                if e then
                    local hint = visibleWeaponHint(p)
                    local color = enabled.Rainbow and Color3.fromHSV((timeNow / 5) % 1, 0.85, 1)
                        or (enabled.RoleESP and getRoleColor(role, source) or colorForHint(hint))
                    e.highlight.Enabled = true
                    e.highlight.OutlineTransparency = source == "hint" and 0.35 or 0
                    e.highlight.FillColor = color
                    e.highlight.OutlineColor = color
                    e.highlight.DepthMode = enabled.XRay and Enum.HighlightDepthMode.AlwaysOnTop
                        or Enum.HighlightDepthMode.Occluded
                    e.billboard.Enabled = enabled.Names or enabled.Distances or enabled.WeaponHints or enabled.Health or enabled.ShowRoles
                    local pieces = {}
                    if enabled.Names then table.insert(pieces, "@" .. p.Name) end
                    local root = rootOf(p)
                    local distance = root and distanceTo(root)
                    if enabled.Distances and distance then
                        table.insert(pieces, ("%d studs"):format(math.floor(distance)))
                    end
                    if enabled.Health then
                        local hum = humanOf(p)
                        if hum then table.insert(pieces, ("HP %d"):format(math.ceil(hum.Health))) end
                    end
                    if enabled.ShowRoles then table.insert(pieces, roleDisplay(role, source)) end
                    if enabled.WeaponHints and hint ~= "Unknown" then table.insert(pieces, hint) end
                    e.text.Text = table.concat(pieces, "  |  ")
                    e.text.TextColor3 = color
                end
            else
                destroyPlayerEffect(p)
            end
        end
    end
    for p in pairs(playerEffects) do
        if not p.Parent then destroyPlayerEffect(p) end
    end
end

-- Box ESP projects a BODY-ONLY bounding volume: tools and accessories
-- are excluded so a holstered gun or oversized hat cannot stretch boxes.
v54.box2DObjects = {}
v54.boxBoundsCache = setmetatable({}, {__mode="k"})
v54.getBodyBounds = function(char, root, now)
    -- Cache approximate BODY-only bounds per character for 1.4s. This
    -- avoids re-scanning each avatar's 15+ parts every render update.
    local cached = v54.boxBoundsCache[char]
    if cached and now - cached.at < 1.4 then return cached.low, cached.high end
    local low, high = Vector3.new(-1.05,-2.95,-0.8), Vector3.new(1.05,2.95,0.8)
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and part ~= root then
            local localPos = root.CFrame:PointToObjectSpace(part.Position)
            local radius = part.Size * 0.5
            local a, b = localPos-radius, localPos+radius
            low = Vector3.new(math.min(low.X,a.X),math.min(low.Y,a.Y),math.min(low.Z,a.Z))
            high = Vector3.new(math.max(high.X,b.X),math.max(high.Y,b.Y),math.max(high.Z,b.Z))
        end
    end
    low = Vector3.new(math.clamp(low.X,-4,-0.4),math.clamp(low.Y,-8,-1.5),math.clamp(low.Z,-4,-0.35))
    high = Vector3.new(math.clamp(high.X,0.4,4),math.clamp(high.Y,1.5,8),math.clamp(high.Z,0.35,4))
    v54.boxBoundsCache[char] = {low=low,high=high,at=now}
    return low,high
end
v54.clear2DBox = function(player)
    local box = v54.box2DObjects[player]
    if box then
        if box.frame then box.frame:Destroy() end
        v54.box2DObjects[player] = nil
    end
end
v54.ensure2DBox = function(player)
    local box = v54.box2DObjects[player]
    if box and box.frame and box.frame.Parent then return box end
    local frame = Instance.new("Frame")
    frame.Name = "SPECTRA_ESP2D_" .. player.UserId
    frame.BorderSizePixel = 0
    frame.BackgroundTransparency = 1
    frame.ZIndex = 40
    frame.Visible = false
    frame.Parent = boxGui
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Thickness = 1.8
    stroke.Parent = frame
    box = {frame=frame, border=stroke}
    v54.box2DObjects[player] = box
    return box
end
v54.update2DBoxes = function()
    if destroyed then return end
    if not enabled.PlayerESP or not enabled.BoxESP2D then
        for _, box in pairs(v54.box2DObjects) do
            if box.frame then box.frame.Visible = false end
        end
        return
    end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local w, h = cam.ViewportSize.X, cam.ViewportSize.Y
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer then
            local box = v54.box2DObjects[player]
            local root, char = rootOf(player), characterOf(player)
            local role, source = getRole(player)
            local tracked = not enabled.ThreatsOnly
                or role == "Murderer" or role == "Sheriff" or role == "Hero"
            local distance = root and distanceTo(root)
            local eligible = root and char and alive(player) and tracked
                and (not enabled.RangeLimit or (distance and distance <= numbers.ESPRange))
            if eligible then
                local rootPoint = cam:WorldToViewportPoint(root.Position)
                if rootPoint.Z > 0.4 then
                    local low, high = v54.getBodyBounds(char,root,os.clock())
                    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
                    local seen = 0
                    for _, x in ipairs({low.X,high.X}) do
                        for _, y in ipairs({low.Y,high.Y}) do
                            for _, z in ipairs({low.Z,high.Z}) do
                                local projected = cam:WorldToViewportPoint(root.CFrame:PointToWorldSpace(Vector3.new(x,y,z)))
                                if projected.Z > 0.35 then
                                    left, top = math.min(left,projected.X), math.min(top,projected.Y)
                                    right, bottom = math.max(right,projected.X), math.max(bottom,projected.Y)
                                    seen += 1
                                end
                            end
                        end
                    end
                    if seen >= 4 and right > 0 and bottom > 0 and left < w and top < h then
                        left, top = math.clamp(left,0,w), math.clamp(top,0,h)
                        right, bottom = math.clamp(right,0,w), math.clamp(bottom,0,h)
                        if right-left > 4 and bottom-top > 8 then
                            box = box or v54.ensure2DBox(player)
                            box.frame.Position = UDim2.fromOffset(math.floor(left), math.floor(top))
                            box.frame.Size = UDim2.fromOffset(math.floor(right-left), math.floor(bottom-top))
                            box.border.Color = enabled.RoleESP and getRoleColor(role,source)
                                or colorForHint(visibleWeaponHint(player))
                            box.frame.Visible = true
                        elseif box then box.frame.Visible = false end
                    elseif box then box.frame.Visible = false end
                elseif box then box.frame.Visible = false end
            elseif box then box.frame.Visible = false end
        end
    end
    v54.clear2DBox(localPlayer)
    for player in pairs(v54.box2DObjects) do
        if player.Parent ~= Players then v54.clear2DBox(player) end
    end
end

-- Tracers follow the local root and target root via Beam Attachments.
local tracerEffects = {}
local function clearTracer(p)
    local e = tracerEffects[p]
    if not e then return end
    -- Only destroy the Beam and attachments we created.
    e.beam:Destroy()
    e.a0:Destroy()
    e.a1:Destroy()
    tracerEffects[p] = nil
end
local function updateTracers()
    local mine = rootOf(localPlayer)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer then
            local theirs = rootOf(p)
            local e = tracerEffects[p]
            local role, source = getRole(p)
            local tracked = not enabled.ThreatsOnly or (role == "Murderer" or role == "Sheriff" or role == "Hero")
            local inRange = not enabled.RangeLimit or (theirs and distanceTo(theirs) and distanceTo(theirs) <= numbers.ESPRange)
            if not enabled.PlayerESP or not enabled.Tracers or not tracked or not inRange or not mine or not theirs or not alive(p) then
                clearTracer(p)
            else
                if e and (e.mine ~= mine or e.theirs ~= theirs) then
                    clearTracer(p)
                    e = nil
                end
                if not e then
                    local a0 = Instance.new("Attachment")
                    a0.Name = "LearningHubTracerOrigin"
                    a0.Parent = mine
                    local a1 = Instance.new("Attachment")
                    a1.Name = "LearningHubTracerTarget"
                    a1.Parent = theirs
                    local beam = Instance.new("Beam")
                    beam.Attachment0 = a0
                    beam.Attachment1 = a1
                    beam.Width0 = 0.07
                    beam.Width1 = 0.07
                    beam.FaceCamera = true
                    beam.LightEmission = 0.9
                    beam.Transparency = NumberSequence.new(0.16)
                    beam.Parent = effectsFolder
                    e = { mine = mine, theirs = theirs, a0 = a0, a1 = a1, beam = beam }
                    tracerEffects[p] = e
                end
                e.beam.Color = ColorSequence.new(enabled.RoleESP
                    and getRoleColor(role, source) or colorForHint(visibleWeaponHint(p)))
            end
        end
    end
    for p in pairs(tracerEffects) do
        if not p.Parent then clearTracer(p) end
    end
end

-- Name-based map markers, not MM2 privileged server data.
local function objectType(obj)
    if not obj:IsA("BasePart") and not obj:IsA("Model") then return nil end
    local name = obj.Name:lower()
    if (name == "gundrop" or name == "droppedgun" or name == "dropped_gun"
        or name == "pistoldrop" or name == "droppedpistol"
        or name == "gunpickup" or name == "gun_drop") then
        return "Gun"
    elseif name == "knifedrop" or name == "droppedknife" or name == "dropped_knife" then
        return "Knife"
    elseif name == "coin" or name == "coinpart" or name == "coin_server"
        or name == "coinpickup" or name == "token" or name == "tokenpart"
        or name == "goldtoken" or name == "tokenpickup"
        or (obj:IsA("BasePart") and obj:FindFirstChild("CoinVisual")) then
        return "Coin"
    elseif name == "candy" or name == "shell" or name == "gem"
        or name == "snowflake" or name == "eventtoken" or name == "pumpkinpickup" then
        return "Event"
    end
    return nil
end
local function clearObject(obj)
    local e = objectEffects[obj]
    if not e then return end
    e.highlight:Destroy()
    e.billboard:Destroy()
    objectEffects[obj] = nil
end
local function ensureObject(obj)
    if objectEffects[obj] then return end
    if not obj:IsDescendantOf(Workspace) then return end
    local kind = objectType(obj)
    if not kind then return end
    local anchor = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
    if not anchor then return end
    if kind == "Gun" and not enabled.GunESP then return end
    if kind == "Coin" and not enabled.CoinESP then return end
    if kind == "Knife" and not enabled.KnifeESP then return end
    if kind == "Event" and not enabled.EventESP then return end
    if (function()
        local count = 0
        for _ in pairs(objectEffects) do count = count + 1 end
        return count
    end)() >= 90 then return end
    local color = kind == "Gun" and Color3.fromRGB(255, 209, 64)
        or kind == "Knife" and Color3.fromRGB(255, 95, 112)
        or kind == "Event" and Color3.fromRGB(190, 144, 255)
        or Color3.fromRGB(125, 255, 129)
    local h = Instance.new("Highlight")
    h.Name = "LearningHubObjectHighlight"
    h.Adornee = obj
    h.FillColor = color
    h.OutlineColor = color
    h.FillTransparency = 0.58
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent = effectsFolder
    local bb = Instance.new("BillboardGui")
    bb.Adornee = anchor
    bb.Size = UDim2.fromOffset(130, 34)
    bb.AlwaysOnTop = true
    bb.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
    bb.Parent = gui
    local t = Instance.new("TextLabel")
    t.Size = UDim2.fromScale(1, 1)
    t.TextColor3 = color
    t.TextStrokeTransparency = 0.15
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.GothamBold
    t.TextSize = 13
    t.Parent = bb
    objectEffects[obj] = { highlight = h, billboard = bb, text = t, kind = kind, anchor = anchor }
end
local function scanObjects()
    if not enabled.GunESP and not enabled.CoinESP and not enabled.KnifeESP and not enabled.EventESP then
        for obj in pairs(objectEffects) do clearObject(obj) end
        return
    end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if objectType(obj) then ensureObject(obj) end
    end
end
local function updateObjects()
    for obj, e in pairs(objectEffects) do
        if not obj:IsDescendantOf(Workspace)
            or (e.kind == "Gun" and not enabled.GunESP)
            or (e.kind == "Coin" and not enabled.CoinESP)
            or (e.kind == "Knife" and not enabled.KnifeESP)
            or (e.kind == "Event" and not enabled.EventESP) then
            clearObject(obj)
        else
            local d = e.anchor.Parent and distanceTo(e.anchor)
            e.text.Text = e.kind .. (d and (" • %d studs"):format(d) or "")
        end
    end
end
watch(Workspace.DescendantAdded:Connect(function(obj)
    local kind = objectType(obj)
    if kind then
        if kind == "Gun" and enabled.GunAlerts and os.clock() - enabled.GunAlertTime > 4 then
            enabled.GunAlertTime = os.clock()
            enabled.GunAlertMessage = "Possible dropped Gun detected (object name)"
            inform(enabled.GunAlertMessage)
        end
        task.defer(function()
            if not destroyed and obj.Parent then ensureObject(obj) end
        end)
    end
end))
watch(Workspace.DescendantRemoving:Connect(function(obj)
    if objectEffects[obj] then clearObject(obj) end
end))

-- ROUND RESULT CLEANUP: PlayerGui only. Does not touch the hub, Roblox CoreGui,
-- normal round HUD, inventory, player list, chat, or unrelated ScreenGuis.
v54.roundResultNames = {
    roundresult=true, roundresults=true, roundresultscreen=true,
    roundend=true, roundendgui=true, roundendscreen=true, endround=true,
    endroundscreen=true, endgame=true, endgamegui=true, endgamescreen=true,
    victory=true, victorygui=true, victoryscreen=true, victoryframe=true,
    defeat=true, defeatgui=true, defeatscreen=true,
    resultframe=true, resultsframe=true, resultui=true, resultsgui=true,
    resultsscreen=true, results=true, winners=true, winner=true,
    winscreen=true, winscreengui=true, winframe=true,
    winnergui=true, winnerscreen=true, winnersframe=true,
    murdererwin=true, murdererwins=true, murdererwon=true,
    murdererwinframe=true, murdererwinsgui=true,
    innocentswin=true, innocentwin=true, innocentswins=true,
    innocentswinframe=true, innocentswinsgui=true,
    sheriffwin=true, sheriffwins=true, sheriffvictory=true,
    herowin=true, herowins=true, gameover=true,
    gameovergui=true, gameoverscreen=true, roundsummary=true,
}
v54.isRoundResultName = function(name)
    if type(name) ~= "string" then return false end
    local compact = string.lower(name):gsub("[^%w]", "")
    return v54.roundResultNames[compact] == true
        or compact:match("^roundresults?[%w]*$") ~= nil
        or compact:match("^roundends?[%w]*$") ~= nil
        or compact:match("^endgame[%w]*$") ~= nil
        or compact:match("^victory[%w]*$") ~= nil
        or compact:match("^murdererwins?[%w]*$") ~= nil
        or compact:match("^innocents?wins?[%w]*$") ~= nil
        or compact:match("^winnerscreen[%w]*$") ~= nil
        or compact:match("^gameover[%w]*$") ~= nil
end
v54.isRoundResultText = function(value)
    if type(value) ~= "string" then return false end
    -- RichText often wraps win text in formatting tags.
    local t = string.lower(value:gsub("<[^>]+>", "")):gsub("[^%w]", "")
    if #t < 3 or #t > 85 then return false end
    return t == "victory" or t == "defeat" or t == "youwin" or t == "youwon"
        or t == "roundover" or t == "roundresults" or t == "gameover"
        or t:match("^the?innocents?wins?$") ~= nil
        or t:match("^innocents?wins?$") ~= nil
        or t:match("^the?murdererwins?$") ~= nil
        or t:match("^murdererwins?$") ~= nil
        or t:match("^sheriffwins?$") ~= nil
        or t:match("^herowins?$") ~= nil
        or t:find("innocentshavewon", 1, true) ~= nil
        or t:find("murdererhaswon", 1, true) ~= nil
        or t:find("sheriffhassavedtheday", 1, true) ~= nil
        or t:find("herohassavedtheday", 1, true) ~= nil
        or t:find("murderervictory", 1, true) ~= nil
        or t:find("innocentvictory", 1, true) ~= nil
end
-- MM2 also shows a long dark XP/reward progress overlay like "+3,000".
-- It need not contain the words "win" or "victory", so the old cleaner missed it.
-- Only consider reasonably large, mid-screen, wide panels containing a clear
-- positive reward label; never hide an entire HUD or root ScreenGui by heuristic.
v54.isRoundRewardText = function(value)
    if type(value) ~= "string" then return false end
    local stripped = value:gsub("<[^>]+>", ""):gsub("%s+", "")
    local amount = stripped:match("^%+([%d,]+)$")
    if not amount then return false end
    local digits = (amount:gsub(",", ""))
    local numerical = tonumber(digits)
    return numerical ~= nil and numerical >= 50
end
v54.rewardPanelFor = function(item)
    local cam = Workspace.CurrentCamera
    local screen = cam and cam.ViewportSize or Vector2.new(1280,720)
    local best = nil
    local node = item.Parent
    local depth = 0
    while node and node ~= playerGui and depth < 8 do
        if node:IsA("ScreenGui") then break end
        if node:IsA("GuiObject") and node.Visible then
            local sz = node.AbsoluteSize
            local pos = node.AbsolutePosition
            local centerY = pos.Y + sz.Y/2
            -- Restrict to a reward/progress bar across the center area.
            local eligible = sz.X >= screen.X * 0.34 and sz.X <= screen.X * 0.96
                and sz.Y >= 30 and sz.Y <= math.min(screen.Y*0.34, 260)
                and centerY >= screen.Y * 0.20 and centerY <= screen.Y * 0.81
            if eligible then best = node end
        end
        node = node.Parent
        depth += 1
    end
    return best
end
-- Hide the surrounding result panel when a result label is nested in
-- a generic-named frame. Never hide the broad game HUD by name alone.
v54.resultContainerFor = function(item, manual)
    local camera = Workspace.CurrentCamera
    local view = camera and camera.ViewportSize or Vector2.new(800, 500)
    local candidate, node, hops = nil, item.Parent, 0
    while node and node ~= playerGui and hops < 6 do
        if node:IsA("ScreenGui") then
            if v54.isRoundResultName(node.Name) then return node end
            break
        end
        if node:IsA("GuiObject") and node.Visible then
            if v54.isRoundResultName(node.Name) then return node end
            local nm = node.Name:lower()
            local sz = node.AbsoluteSize
            local centreX = node.AbsolutePosition.X + sz.X/2
            local centreY = node.AbsolutePosition.Y + sz.Y/2
            local centered = math.abs(centreX - view.X/2) <= view.X * 0.38
                and math.abs(centreY - view.Y/2) <= view.Y * 0.39
            local notRoot = nm ~= "main" and nm ~= "hud" and nm ~= "maingui"
                and nm ~= "gamegui" and nm ~= "container"
            if centered and notRoot and sz.X >= 115 and sz.Y >= 50
                and (manual or (sz.X <= view.X * 0.92
                    and sz.Y <= view.Y * 0.90)) then
                candidate = candidate or node
            end
        end
        node = node.Parent
        hops += 1
    end
    return candidate or item
end
v54.clearRoundResults = function(manual)
    if destroyed or not playerGui or not playerGui.Parent then return 0 end
    local hidden = 0
    local claimed = {}
    for _, item in ipairs(playerGui:GetDescendants()) do
        if item ~= gui and item ~= boxGui
            and not item:IsDescendantOf(gui) and not item:IsDescendantOf(boxGui) then
            local recognized = v54.isRoundResultName(item.Name)
            local isText = item:IsA("TextLabel") or item:IsA("TextButton")
            local textMatch = isText and v54.isRoundResultText(item.Text)
            local rewardPanel = isText and v54.isRoundRewardText(item.Text)
                and v54.rewardPanelFor(item) or nil
            if recognized or textMatch or rewardPanel then
                local selected = rewardPanel or
                    (recognized and item or v54.resultContainerFor(item, manual))
                if selected:IsA("ScreenGui") then
                    if selected.Enabled and not claimed[selected] then
                        selected.Enabled = false
                        claimed[selected] = true
                        hidden += 1
                    end
                elseif selected:IsA("GuiObject") and selected.Visible and not claimed[selected] then
                    selected.Visible = false
                    claimed[selected] = true
                    hidden += 1
                end
            end
        end
    end
    v54.roundResultHiddenTotal += hidden
    if hidden > 0 then
        v54.roundResultNotice = string.format("Cleared %d winner panel(s) • session %d",
            hidden, v54.roundResultHiddenTotal)
        if manual then inform(v54.roundResultNotice) end
    elseif manual then
        local visible = {}
        for _, candidate in ipairs(playerGui:GetChildren()) do
            if candidate:IsA("ScreenGui") and candidate ~= gui and candidate ~= boxGui
                and candidate.Enabled and #visible < 6 then
                table.insert(visible, candidate.Name)
            end
        end
        v54.roundResultNotice = "No recognized result. Game UI names: "
            .. (#visible > 0 and table.concat(visible, ", ") or "none")
        inform(v54.roundResultNotice)
    end
    if v54.roundResultStatusLabel and v54.roundResultStatusLabel.Parent then
        v54.roundResultStatusLabel.Text = v54.roundResultNotice
    end
    return hidden
end
v54.manualClearRoundResults = function()
    -- Results can get recreated by delayed animations; briefly rescan.
    v54.roundResultManualUntil = os.clock() + 18
    return v54.clearRoundResults(true)
end

-- Movement and local utilities ----------------------------------------
local function restoreNoclip()
    for part, value in pairs(originalCollisions) do
        if part.Parent then pcall(function() part.CanCollide = value end) end
    end
    table.clear(originalCollisions)
end
-- Apply BEFORE the physics simulation as well as after it. This avoids a
-- collision frame between Roblox resetting avatar parts and Heartbeat.
v54.applyNoclip = function()
    if destroyed or not enabled.Noclip then return end
    local char = characterOf(localPlayer)
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if originalCollisions[part] == nil then
                originalCollisions[part] = part.CanCollide
            end
            if part.CanCollide then part.CanCollide = false end
        end
    end
end
local function stopFly()
    if flyVelocity then flyVelocity:Destroy() end
    if flyAttachment then flyAttachment:Destroy() end
    flyVelocity, flyAttachment, flyRoot = nil, nil, nil
    local humanoid = humanOf(localPlayer)
    if humanoid then pcall(function()
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end) end
end
local function setupFly()
    local root = rootOf(localPlayer)
    if not root then return end
    if flyRoot == root and flyVelocity and flyVelocity.Parent then return end
    stopFly()
    local a = Instance.new("Attachment")
    a.Name = "LearningHubFlyAttachment"
    a.Parent = root
    local velocity = Instance.new("LinearVelocity")
    velocity.Name = "LearningHubFlyVelocity"
    velocity.Attachment0 = a
    velocity.RelativeTo = Enum.ActuatorRelativeTo.World
    velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    velocity.MaxForce = math.max(100000, root.AssemblyMass * 4500)
    velocity.VectorVelocity = Vector3.zero
    velocity.Parent = root
    flyAttachment, flyVelocity, flyRoot = a, velocity, root
end
do
-- Independent mobile flight controller: remains accessible with the main menu minimized.
-- Standard Roblox joystick supplies horizontal movement; large separate buttons supply altitude.
local flightHud = Instance.new("Frame")
flightHud.Name = "SPECTRA_FlightHud"
flightHud.AnchorPoint = Vector2.new(1, 1)
flightHud.Position = UDim2.new(1, -12, 1, -12)
flightHud.Size = UDim2.fromOffset(112, 232)
flightHud.BackgroundColor3 = Color3.fromRGB(19, 26, 39)
flightHud.BackgroundTransparency = 0.1
flightHud.BorderSizePixel = 0
flightHud.ZIndex = 85
flightHud.Active = true
flightHud.Parent = gui
flightHud.Visible = false -- v7.5: hidden permanently; D-pad belongs to role actions
round(flightHud, 13)
stroke(flightHud, Color3.fromRGB(115, 153, 233), 0.2)
local function flightButton(name, y, height, textValue, color)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Position = UDim2.fromOffset(8, y)
    b.Size = UDim2.new(1, -16, 0, height)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Text = textValue
    b.TextSize = 16
    b.Font = Enum.Font.GothamBold
    b.ZIndex = 86
    b.Parent = flightHud
    round(b, 9)
    return b
end
local flyToggleHud = flightButton("ToggleFlight", 8, 40, "FLY: OFF", Color3.fromRGB(75, 79, 96))
local flyUpHud = flightButton("Ascend", 56, 52, "▲  UP", Color3.fromRGB(46, 115, 193))
local flyDownHud = flightButton("Descend", 115, 52, "▼  DOWN", Color3.fromRGB(46, 115, 193))
local flySpeedHud = flightButton("FlightSpeed", 175, 40, "SPEED 45", Color3.fromRGB(48, 57, 77))
v54.updateFlyHUD = function()
    if destroyed then return end
    -- An inactive HUD should not cover the game or floating SPECTRA icon.
    flightHud.Visible = false -- no on-screen fly UI
    flightHud.Size = enabled.Fly and UDim2.fromOffset(112, 232)
        or UDim2.fromOffset(112, 56)
    flyUpHud.Visible = enabled.Fly
    flyDownHud.Visible = enabled.Fly
    flySpeedHud.Visible = enabled.Fly
    -- If the launcher was dragged into the flight HUD, move it to a free corner.
    if minimized then
        local a, b = launcher.AbsolutePosition, flightHud.AbsolutePosition
        local az, bz = launcher.AbsoluteSize, flightHud.AbsoluteSize
        local overlapping = a.X < b.X + bz.X and a.X + az.X > b.X
            and a.Y < b.Y + bz.Y and a.Y + az.Y > b.Y
        if overlapping then placeLauncher(12, 90) end
    end
    flyToggleHud.Text = enabled.Fly and "FLY: ON" or "FLY: OFF"
    flyToggleHud.BackgroundColor3 = enabled.Fly
        and Color3.fromRGB(40, 139, 113) or Color3.fromRGB(75, 79, 96)
    flySpeedHud.Text = "SPEED " .. tostring(numbers.FlySpeed) .. " +"
    flyUpHud.BackgroundColor3 = (flyUp or v54.gamepadFlyUp) and Color3.fromRGB(32, 161, 109) or Color3.fromRGB(46, 115, 193)
    flyDownHud.BackgroundColor3 = (flyDown or v54.gamepadFlyDown) and Color3.fromRGB(32, 161, 109) or Color3.fromRGB(46, 115, 193)
end
v54.setFlight = function(on)
    enabled.Fly = on and true or false
    if enabled.Fly then
        -- The farm and manual flight must not both set character position.
        enabled.AutoCoinFarm = false
        v54.farmTravelToken += 1
        setupFly()
        inform("Background flight enabled; manual flight HUD hidden in v7.5")
    else
        flyUp, flyDown = false, false
        v54.gamepadFlyUp, v54.gamepadFlyDown = false, false
        stopFly()
        inform("Flight stopped")
    end
    v54.updateFlyHUD()
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end
watch(flyToggleHud.Activated:Connect(function() v54.setFlight(not enabled.Fly) end))
watch(flySpeedHud.Activated:Connect(function()
    numbers.FlySpeed = numbers.FlySpeed >= 105 and 25 or numbers.FlySpeed + 20
    v54.updateFlyHUD()
end))
local heldUpInput, heldDownInput = nil, nil
local function attachHold(button, goesUp)
    watch(button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if goesUp then
                heldUpInput = input
                flyUp = true
            else
                heldDownInput = input
                flyDown = true
            end
            v54.updateFlyHUD()
        end
    end))
    watch(button.InputEnded:Connect(function(input)
        if goesUp and input == heldUpInput then
            heldUpInput, flyUp = nil, false
        elseif not goesUp and input == heldDownInput then
            heldDownInput, flyDown = nil, false
        end
        v54.updateFlyHUD()
    end))
end
attachHold(flyUpHud, true)
attachHold(flyDownHud, false)
watch(UserInputService.InputEnded:Connect(function(input)
    if input == heldUpInput then heldUpInput, flyUp = nil, false end
    if input == heldDownInput then heldDownInput, flyDown = nil, false end
    if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Space then flyUp = false end
    if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.LeftControl then flyDown = false end
    v54.updateFlyHUD()
end))
watch(UserInputService.InputBegan:Connect(function(input, processed)
    if processed or not enabled.Fly then return end
    if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Space then flyUp = true end
    if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.LeftControl then flyDown = true end
    v54.updateFlyHUD()
end))
v54.updateFlyHUD()
end -- scope temporary flight HUD widget locals

local function applyCharacterSettings()
    local humanoid = humanOf(localPlayer)
    if humanoid then
        if not baseHumanoidSettings[humanoid] then
            baseHumanoidSettings[humanoid] = {
                speed = humanoid.WalkSpeed,
                jump = humanoid.JumpPower,
                useJumpPower = humanoid.UseJumpPower,
            }
        end
        local base = baseHumanoidSettings[humanoid]
        -- User observed "Invalid Location" with requested speed above 40.
        humanoid.WalkSpeed = enabled.Sprint and math.min(numbers.Speed, 36) or base.speed
        if enabled.CustomJump then
            humanoid.UseJumpPower = true
            humanoid.JumpPower = numbers.Jump
        else
            humanoid.UseJumpPower = base.useJumpPower
            humanoid.JumpPower = base.jump
        end
    end
end
watch(localPlayer.CharacterAdded:Connect(function(newCharacter)
    -- Request fresh round role data promptly after respawning.
    lastRoleFetch = -100
    task.delay(0.2, function()
        if not destroyed then refreshRoles() end
    end)
    -- Include accessories and avatar parts added after initial character spawn.
    watch(newCharacter.DescendantAdded:Connect(function(part)
        if not destroyed and enabled.Noclip and part:IsA("BasePart") then
            task.defer(v54.applyNoclip)
        end
    end))
    if v54.stopAnimationPreview then v54.stopAnimationPreview() end
    restoreNoclip()
    stopFly()
    flyUp, flyDown = false, false
    v54.updateFlyHUD()
    -- Original local transparency is stored weakly and restored on unload.
    task.delay(0.65, function()
        if not destroyed and localPlayer.Character == newCharacter then
            applyCharacterSettings()
            -- Re-test the active movement pack on respawn; saved prefs never auto-apply.
            if v54.refreshAnimationRigButtons then v54.refreshAnimationRigButtons() end
            if v54.applyAnimationPack and v54.selectedAnimationPack ~= "Default" then
                local selected = v54.animationPacks[v54.selectedAnimationPack]
                if selected and selected.Rig == v54.animationRigName() then
                    v54.applyAnimationPack(v54.selectedAnimationPack, true)
                else
                    v54.selectedAnimationPack = "Default"
                end
            end
        end
    end)
end))
watch(UserInputService.JumpRequest:Connect(function()
    if enabled.InfiniteJump then
        local humanoid = humanOf(localPlayer)
        if humanoid and humanoid.Health > 0 then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end))

local function setLocalGhost(on)
    if on then
        local char = characterOf(localPlayer)
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if originalLocalTransparency[part] == nil then
                    originalLocalTransparency[part] = part.LocalTransparencyModifier
                end
                part.LocalTransparencyModifier = 0.85
            end
        end
    else
        for part, original in pairs(originalLocalTransparency) do
            if part.Parent then part.LocalTransparencyModifier = original end
            originalLocalTransparency[part] = nil
        end
    end
end

v54.setFullbright = function(on)
    if on then
        Lighting.Brightness = 3
        Lighting.ClockTime = 14
        Lighting.Ambient = Color3.fromRGB(180, 180, 180)
        Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 100000
    else
        for property, value in pairs(lightOriginal) do
            Lighting[property] = value
        end
    end
end
v54.setLowFX = function(on)
    if on then
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("PostEffect") then
                if originalFX[child] == nil then originalFX[child] = child.Enabled end
                child.Enabled = false
            end
        end
    else
        for effect, original in pairs(originalFX) do
            if effect.Parent then effect.Enabled = original end
        end
        table.clear(originalFX)
    end
end

v54.setNoFog = function(on)
    if on then
        Lighting.FogStart = 0
        Lighting.FogEnd = 100000
        for _, effect in ipairs(Lighting:GetChildren()) do
            if effect:IsA("Atmosphere") then
                if not fogOriginal[effect] then
                    fogOriginal[effect] = {Density = effect.Density, Haze = effect.Haze}
                end
                effect.Density = 0
                effect.Haze = 0
            end
        end
    else
        Lighting.FogStart = lightOriginal.FogStart
        Lighting.FogEnd = lightOriginal.FogEnd
        for atmosphere, original in pairs(fogOriginal) do
            if atmosphere.Parent then
                atmosphere.Density = original.Density
                atmosphere.Haze = original.Haze
            end
        end
        table.clear(fogOriginal)
    end
end
v54.setHideOwnName = function(on)
    local hum = humanOf(localPlayer)
    if not hum then return end
    if on then
        if ownNameOriginal[hum] == nil then
            ownNameOriginal[hum] = hum.DisplayDistanceType
        end
        hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    elseif ownNameOriginal[hum] then
        hum.DisplayDistanceType = ownNameOriginal[hum]
        ownNameOriginal[hum] = nil
    end
end

local function otherPlayers()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer then table.insert(list, p) end
    end
    table.sort(list, function(a, b) return a.Name:lower() < b.Name:lower() end)
    return list
end
local function chooseNextPlayer()
    local list = otherPlayers()
    if #list == 0 then
        selectedPlayer = nil
        inform("No other players to select")
        return
    end
    local current = 0
    for i, p in ipairs(list) do
        if p == selectedPlayer then current = i break end
    end
    selectedPlayer = list[(current % #list) + 1]
    refreshPlayerDropdown()
    inform("Selected: " .. selectedPlayer.DisplayName .. " (@" .. selectedPlayer.Name .. ")")
end
local function restoreCamera()
    spectateTarget = nil
    enabled.CameraLock = false
    local camera = Workspace.CurrentCamera
    local humanoid = humanOf(localPlayer)
    if camera and humanoid then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = humanoid
    end
end
local function spectate()
    if not selectedPlayer or not humanOf(selectedPlayer) then
        inform("Select a live player first")
        return
    end
    spectateTarget = selectedPlayer
    enabled.CameraLock = false
    local camera = Workspace.CurrentCamera
    if camera then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = humanOf(selectedPlayer)
        inform("Spectating " .. selectedPlayer.DisplayName)
    end
end
local function moveNear(p)
    local root = rootOf(p)
    local own = rootOf(localPlayer)
    if not root or not own then inform("Target isn't spawned") return end
    own.CFrame = root.CFrame * CFrame.new(3, 0, 0)
    inform("Local teleport attempted • server may correct it")
end
local function findHint(kind)
    for _, p in ipairs(otherPlayers()) do
        if alive(p) and visibleWeaponHint(p) == kind then return p end
    end
    return nil
end
local function findRoleTarget(roleWanted)
    local fallback
    for _, p in ipairs(otherPlayers()) do
        if alive(p) then
            local role, source = getRole(p)
            if role == roleWanted then
                if source == "game" then return p, "game" end
                fallback = fallback or p
            end
        end
    end
    return fallback, fallback and "hint" or "none"
end
local function selectRole(role)
    local p, source = findRoleTarget(role)
    if not p then
        inform("No " .. role .. " identified yet")
        return nil
    end
    selectedPlayer = p
    refreshPlayerDropdown()
    inform(role .. (source == "hint" and " (unconfirmed tool)" or " (game data)") .. ": " .. p.Name)
    return p
end
local function findNearestObject(kind)
    local own = rootOf(localPlayer)
    if not own then return nil end
    local closest, bestDistance = nil, math.huge
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if objectType(obj) == kind then
            local anchor = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
            if anchor then
                local d = (anchor.Position - own.Position).Magnitude
                if d < bestDistance then closest, bestDistance = anchor, d end
            end
        end
    end
    return closest
end
local function tpNearObject(kind)
    local target = findNearestObject(kind)
    local root = rootOf(localPlayer)
    if not root or not target then
        inform("No " .. kind .. " object found")
        return
    end
    root.CFrame = target.CFrame * CFrame.new(0, 3, 0)
    inform("Local teleport attempted • " .. kind)
end
local function tpCrosshair()
    local camera = Workspace.CurrentCamera
    local root = rootOf(localPlayer)
    if not camera or not root then return inform("Character/camera not ready") end
    local size = camera.ViewportSize
    local ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {characterOf(localPlayer)}
    local hit = Workspace:Raycast(ray.Origin, ray.Direction * 450, params)
    if not hit then return inform("No surface at center of screen") end
    root.CFrame = CFrame.new(hit.Position + Vector3.new(0, 4, 0))
    inform("Crosshair teleport attempted")
end
local function createDemoPart(name, color)
    local root = rootOf(localPlayer)
    if not root then inform("Spawn your character first") return end
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.Size = Vector3.new(2, 2, 2)
    part.Shape = Enum.PartType.Ball
    part.Material = Enum.Material.Neon
    part.Color = color
    part.CFrame = root.CFrame * CFrame.new(0, 2, -12)
    part.Parent = Workspace
    table.insert(demoParts, part)
    ensureObject(part)
    inform("Spawned local-only " .. name .. " demo")
end


-- MM2 convenience actions. Everything below uses player-side movement/physics.
-- Coin pickup, role info, and player collisions are game/server dependent.
local function isCollectible(obj)
    if not obj:IsA("BasePart") then return false end
    local kind = objectType(obj)
    if kind == "Coin" then return true end
    if enabled.FarmEvents and kind == "Event" then return true end
    if obj.Name == "CoinVisual" and obj.Parent and obj.Parent:IsA("BasePart") then
        return false -- Visual children are not independently collectible.
    end
    return false
end
local function scanFarmTargets()
    if os.clock() - farmLastScan < 1.1 then return end
    farmLastScan = os.clock()
    table.clear(farmCache)
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if isCollectible(obj) and #farmCache < 600 then
            table.insert(farmCache, obj)
        end
    end
end
local function getNearestFarmCoin()
    local own = rootOf(localPlayer)
    if not own then return nil end
    scanFarmTargets()
    local nearest, best = nil, numbers.FarmRadius
    for _, obj in ipairs(farmCache) do
        if obj.Parent and isCollectible(obj) then
            local visual = obj:FindFirstChild("CoinVisual")
            local collected = visual and visual:GetAttribute("Collected") == true
            local prior = farmVisited[obj]
            if not collected and (not prior or os.clock() - prior > 12) then
                local dist = (obj.Position - own.Position).Magnitude
                if dist < best then nearest, best = obj, dist end
            end
        end
    end
    return nearest, best
end
local function resetFarmTracking()
    table.clear(farmVisited)
    table.clear(farmCache)
    farmFocus, farmFocusStart, farmProgressDistance = nil, 0, math.huge
    farmAttempts, farmSkipped, farmLastScan = 0, 0, 0
    farmNotice = "Tracking cleared"
    v54.postFarmFinished = false
    v54.postFarmIdleSince = nil
    v54.postFarmStatus = "Ready"
end

local function getNearestGun()
    local root = rootOf(localPlayer)
    if not root then return nil end
    return findNearestObject("Gun")
end

-- A named GunDrop may be present locally without server-authorized pickup.
-- Always return to the precise saved position, even when pickup fails.
v54.hasGunInInventory = function()
    local char = characterOf(localPlayer)
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    local tool = char and char:FindFirstChild("Gun")
    if tool and tool:IsA("Tool") then return true end
    tool = backpack and backpack:FindFirstChild("Gun")
    return tool ~= nil and tool:IsA("Tool")
end
v54.attemptGunPickup = function(automatic)
    if destroyed or v54.gunPickupBusy then return end
    if flingBusy or enabled.FlingActive or v54.frontActionBusy then
        if not automatic then inform("Stop fling/front action before gun pickup") end
        return
    end
    if v54.hasGunInInventory() then
        v54.gunPickupStatus = "Gun already equipped or in backpack"
        if not automatic then inform(v54.gunPickupStatus) end
        return
    end
    local target = getNearestGun()
    local ownRoot, hum = rootOf(localPlayer), humanOf(localPlayer)
    if not target or not ownRoot or not hum or hum.Health <= 0 then
        if not automatic then inform("No GunDrop or living character available") end
        return
    end
    local now = os.clock()
    if automatic and (now - v54.gunPickupLastAt < 1.25
        or (v54.gunPickupTried[target] and now - v54.gunPickupTried[target] < 3.5)) then
        return
    end
    v54.gunPickupLastAt, v54.gunPickupTried[target] = now, now
    v54.gunPickupBusy = true
    v54.farmTravelToken += 1 -- stop competing coin flight movement
    local savedRootCF = ownRoot.CFrame
    local savedFly, savedNoclip = enabled.Fly, enabled.Noclip
    v54.gunReturnCF = savedRootCF
    v54.gunPickupStatus = "Pickup: fast touch, then return to exact saved position"
    task.spawn(function()
        local success, failure = pcall(function()
            if savedFly then
                enabled.Fly = false
                stopFly()
            end
            if savedNoclip then
                enabled.Noclip = false
                restoreNoclip()
            end
            -- Four short touch opportunities, rather than six long 0.13s waits.
            -- Touch detection and pickup still depend on the game server.
            for attempt = 1, 4 do
                if destroyed or rootOf(localPlayer) ~= ownRoot or hum.Health <= 0
                    or not target.Parent or v54.hasGunInInventory() then break end
                ownRoot.CFrame = CFrame.new(target.Position + Vector3.new(0, attempt % 2 == 0 and 0.15 or 0.55, 0))
                ownRoot.AssemblyLinearVelocity = Vector3.zero
                task.wait(0.055)
            end
        end)
        -- ALWAYS execute the return step (even if the target disappears).
        local restored = false
        local function returnHome()
            if destroyed or rootOf(localPlayer) ~= ownRoot or hum.Health <= 0 then return false end
            local ok = pcall(function()
                ownRoot.AssemblyLinearVelocity = Vector3.zero
                ownRoot.AssemblyAngularVelocity = Vector3.zero
                ownRoot.CFrame = savedRootCF
                hum:MoveTo(savedRootCF.Position)
            end)
            if not ok then return false end
            return (ownRoot.Position - savedRootCF.Position).Magnitude < 3
        end
        restored = returnHome()
        task.wait(0.055)
        restored = returnHome() or restored
        -- One delayed position check catches immediate post-touch corrections.
        task.wait(0.12)
        if not destroyed and rootOf(localPlayer) == ownRoot
            and (ownRoot.Position - savedRootCF.Position).Magnitude > 6 then
            restored = returnHome() or restored
        end
        enabled.Noclip = savedNoclip
        if savedFly and not destroyed then
            enabled.Fly = true
            setupFly()
        end
        if not destroyed then
            v54.gunPickupStatus = (v54.hasGunInInventory()
                and "Gun tool confirmed" or "Touch attempted; server pickup not confirmed")
                .. (restored and " • returned to saved position locally"
                    or " • return unverified / character changed")
            if not success then
                v54.gunPickupStatus = "Pickup error: " .. tostring(failure):sub(1, 65)
                    .. (restored and " • returned" or " • return unverified")
            end
            inform(v54.gunPickupStatus)
        end
        v54.gunPickupBusy = false
        v54.gunReturnCF = nil
    end)
end

local function setFarmEnabled(on)
    if on then
        v54.lastCoinTeleportAt = -100
        enabled.CoinESP = true
        enabled.AutoGunApproach = false
        if enabled.Fly then
            enabled.Fly = false
            stopFly()
            v54.updateFlyHUD()
        end
        farmFocus, farmFocusStart, farmProgressDistance = nil, 0, math.huge
        v54.postFarmFinished = false
        v54.postFarmIdleSince = nil
        v54.postActionToken += 1
        v54.postFarmStatus = "Farm running • waiting for eligible coins"
        inform("Farm started • visits are not confirmed pickups")
    else
        v54.farmTravelToken += 1
        local humanoid = humanOf(localPlayer)
        local root = rootOf(localPlayer)
        if humanoid and root then humanoid:MoveTo(root.Position) end
        inform("Coin farm stopped")
    end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end

-- Through-wall flight, using normal local CFrame updates and temporarily
-- noncolliding parts. Server validation may reverse motion or deny pickups.
local function beginCoinFlight(target)
    if v54.farmFlightBusy then return end
    local root = rootOf(localPlayer)
    local char = characterOf(localPlayer)
    if not root or not char or not target or not target.Parent then return end
    v54.farmFlightBusy = true
    v54.farmTravelToken += 1
    local token = v54.farmTravelToken
    task.spawn(function()
        local replacedCollisions = {}
        local startTime = os.clock()
        local reached = false
        local success, failure = pcall(function()
            while not destroyed and enabled.AutoCoinFarm and enabled.CoinFlight
                and v54.farmTravelToken == token and root.Parent and target.Parent
                and os.clock() - startTime < 8 do
                -- Prevent local collisions while traversing the map.
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if replacedCollisions[part] == nil then
                            replacedCollisions[part] = part.CanCollide
                        end
                        part.CanCollide = false
                    end
                end
                local destination = target.Position + Vector3.new(0, 0.6, 0)
                local remaining = destination - root.Position
                if remaining.Magnitude < 2.4 then
                    reached = true
                    break
                end
                local dt = RunService.Heartbeat:Wait()
                if not enabled.AutoCoinFarm then break end
                local step = math.min(remaining.Magnitude,
                    math.min(numbers.FarmFlySpeed, 30) * math.min(dt, 0.1))
                root.CFrame = CFrame.new(root.Position + remaining.Unit * step)
                    * (root.CFrame - root.CFrame.Position)
                v54.farmTravelDetail = string.format("Flying through map • %d studs", math.floor(remaining.Magnitude))
            end
        end)
        -- Hold briefly in the contact region before selecting another target.
        if reached and not destroyed and enabled.AutoCoinFarm and target.Parent then
            local waitStart = os.clock()
            while os.clock() - waitStart < 0.3 and enabled.AutoCoinFarm and not destroyed do
                RunService.Heartbeat:Wait()
            end
        end
        for part, oldCollide in pairs(replacedCollisions) do
            if part.Parent and not enabled.Noclip then part.CanCollide = oldCollide end
        end
        if not destroyed and v54.farmTravelToken == token then
            farmVisited[target] = os.clock()
            if reached then
                farmAttempts += 1
                farmNotice = "Flight reached coin position • pickup unconfirmed"
            else
                farmSkipped += 1
                farmNotice = success and "Flight timed out/canceled" or "Flight error: " .. tostring(failure):sub(1, 55)
            end
            farmFocus = nil
        end
        v54.farmFlightBusy = false
        v54.farmTravelDetail = "Idle"
    end)
end

-- Local contact experiment. Physics ownership/collision rules can prevent any target fling.
-- A displacement on this client is not proof that other clients saw the same movement.
-- Client-visible collision information; this does not grant authority over targets.
local function contactReport(player)
    local me = characterOf(localPlayer)
    local other = characterOf(player)
    if not me or not other then return false, "Characters not spawned" end
    local ownRoot = rootOf(localPlayer)
    local hasOwn = 0
    local hasTarget = 0
    local compatible = 0
    local possible = {}
    for _, part in ipairs(me:GetDescendants()) do
        if part:IsA("BasePart") and (part.CanCollide or part == ownRoot) then
            hasOwn += 1
            table.insert(possible, part)
        end
    end
    for _, part in ipairs(other:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            hasTarget += 1
            for _, mine in ipairs(possible) do
                local ok, can = pcall(function()
                    return Workspace:CollisionGroupsAreCollidable(mine.CollisionGroup, part.CollisionGroup)
                end)
                if ok and can then
                    compatible += 1
                    break
                end
            end
        end
    end
    local message = string.format(
        "Collision check • own=%d target=%d group-compatible=%d (local)",
        hasOwn, hasTarget, compatible)
    return compatible > 0, message
end

-- Read-only physics analysis. GetNetworkOwner can be unavailable in some
-- execution contexts, so treat every owner reading as a clue, not proof.
v54.physicsDiagnostic = function(player)
    if not player or player == localPlayer or player.Parent ~= Players then
        return "Choose an active target first"
    end
    local mine, theirs = rootOf(localPlayer), rootOf(player)
    if not mine or not theirs then return "Target or local character not spawned" end
    local compatibility, contact = contactReport(player)
    local distance = (mine.Position - theirs.Position).Magnitude
    local ownerText = "unavailable on this client"
    local ok, owner = pcall(function() return theirs:GetNetworkOwner() end)
    if ok then
        ownerText = owner and ("@" .. owner.Name) or "server/nil"
    end
    local ownOwnerText = "unavailable"
    local okOwn, ownOwner = pcall(function() return mine:GetNetworkOwner() end)
    if okOwn then ownOwnerText = ownOwner and ("@" .. ownOwner.Name) or "server/nil" end
    local collisionText = compatibility and "collision groups overlap"
        or "no compatible collidable body parts"
    local reason = not compatibility and
        "Physics push unlikely: target has no compatible collidable parts."
        or ok and owner ~= localPlayer and
        "Target assembly is not reported as locally owned. Server/another client may override any launch."
        or "Local contact is possible; replication to other players still UNVERIFIED."
    local report = string.format(
        "@%s • gap %.1f studs • target owner %s • own owner %s • mass %.1f • anchored %s • %s. %s",
        player.Name, distance, ownerText, ownOwnerText,
        theirs.AssemblyMass, tostring(theirs.Anchored), collisionText, reason)
    return report .. " [" .. contact .. "]"
end

-- Contact is a local physics experiment; outside-map launches are never guaranteed.
-- SPECTRA 7.8: independently adapted from the *readable method* on the
-- user-supplied Scribd fling.lua page. The page redacts many properties as
-- [Link], so exact original source cannot be faithfully reproduced.
-- Main details: target HRP/head/accessory, alternating vertical offsets,
-- local CFrame adjustments, 9e7 linear / 9e8 angular pulses, BodyVelocity
-- with 9e9 max force, ~2 second contact, and cleanup/return.
-- Restored from SPECTRA v6.9: last user-reported intermittently working frame-contact fling.
-- Conservative 2,500 studs/s test, 1.12s contact, 10s delayed monitoring.
local function flingSelected(targetOverride, onFinished)
    if flingBusy then
        inform("Fling already active; press STOP first")
        return false
    end
    local target = targetOverride or selectedPlayer
    local own, humanoid = rootOf(localPlayer), humanOf(localPlayer)
    local theirRoot = target and rootOf(target)
    if not target or target == localPlayer or not alive(target)
        or not own or not theirRoot or not humanoid then
        inform("Fling couldn't start: choose a living target with a spawned character in FUN")
        return false
    end
    local canContact, collisionReport = contactReport(target)
    if not canContact then
        -- A higher spin speed cannot create a contact impulse when the
        -- target has no collidable surfaces. Keep this warning explicit.
        flingNotice = "Collision blocker: " .. collisionReport
            .. " • fling likely not effective in this round."
        if v54.flingFunLine and v54.flingFunLine.Parent then
            v54.flingFunLine.Text = flingNotice
        end
        inform(flingNotice)
    end
    flingBusy = true
    flingToken += 1
    local token = flingToken
    local origin = own.CFrame
    local startingTarget = theirRoot.Position
    local initialGap = (own.Position - theirRoot.Position).Magnitude
    -- No fixed distance limit: the selected target must still be replicated.
    -- MM2 can correct attempts to move our avatar across the map.
    if not theirRoot:IsDescendantOf(Workspace) then
        flingBusy = false
        inform("Target character is not currently available in Workspace")
        return false
    end
    local oldPlatformStand, oldRootCollision = humanoid.PlatformStand, own.CanCollide
    local saved = {
        Fly = enabled.Fly, Noclip = enabled.Noclip,
        AutoCoinFarm = enabled.AutoCoinFarm, AntiFling = enabled.AntiFling,
        SpinMode = enabled.SpinMode, AntiSlip = enabled.AntiSlip,
        AntiVoid = enabled.AntiVoid,
    }
    for key in pairs(saved) do enabled[key] = false end
    stopFly()
    restoreNoclip()
    enabled.FlingActive = true
    local activeFlingMode = v54.flingMode
    local contactDuration = activeFlingMode == "spin"
        and math.clamp(numbers.SpinFlingDuration, 0.8, 3.0)
        or activeFlingMode == "launch" and math.clamp(numbers.LaunchDuration, 0.8, 2.5)
        or activeFlingMode == "touch" and math.clamp(numbers.TouchDuration, 0.6, 2.3)
        or 1.12
    flingNotice = string.format("%s • @%s (%.0f studs) • local contact test (server unverified)%s",
        activeFlingMode, target.Name, initialGap,
        canContact and "" or " • COLLISION WARNING")
    if v54.flingFunLine and v54.flingFunLine.Parent then v54.flingFunLine.Text = flingNotice end
    inform(flingNotice)
    task.spawn(function()
        local overlaps, contactFrames, pulses, placements, approachFails = 0, 0, 0, 0, 0
        local peakOwn, peakSpin, peakTarget, targetTravel = 0, 0, 0, 0
        local elapsed, closest, maxDrift, firstLaunchTime = 0, math.huge, 0, nil
        local followTravel, followSpeed, followSamples = 0, 0, 0
        local lowestTargetY = startingTarget.Y
        local reason = "contact window elapsed"
        local spinAttachment, spinConstraint
        local touchMotor, touchPhysicsOriginal, touchMasslessOriginal
        local success, failure = pcall(function()
            own.CanCollide = true
            humanoid.PlatformStand = true
            humanoid:ChangeState(Enum.HumanoidStateType.Physics)
            if activeFlingMode == "touch" then
                -- Adapted from Infinite Yield's public fling command:
                -- a temporary BodyAngularVelocity on the local root.
                -- Use bounded values and always restore physical properties.
                touchPhysicsOriginal = own.CustomPhysicalProperties
                touchMasslessOriginal = own.Massless
                own.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5)
                own.Massless = false
                touchMotor = Instance.new("BodyAngularVelocity")
                touchMotor.Name = "SPECTRA_TouchSpinTemporary"
                touchMotor.MaxTorque = Vector3.new(0, 1e9, 0)
                touchMotor.P = 1e9
                touchMotor.AngularVelocity = Vector3.new(0,
                    math.clamp(numbers.TouchSpinSpeed, 1500, 30000), 0)
                touchMotor.Parent = own
            end
            if activeFlingMode == "spin" then
                spinAttachment = Instance.new("Attachment")
                spinAttachment.Name = "SPECTRA_TemporarySpin"
                spinAttachment.Parent = own
                spinConstraint = Instance.new("AngularVelocity")
                spinConstraint.Name = "SPECTRA_TemporarySpinDrive"
                spinConstraint.Attachment0 = spinAttachment
                spinConstraint.RelativeTo = Enum.ActuatorRelativeTo.World
                spinConstraint.AngularVelocity = Vector3.new(0,
                    math.clamp(numbers.SpinFlingSpeed, 700, 3500), 0)
                spinConstraint.MaxTorque = math.clamp(numbers.SpinFlingSpeed * 175000, 1e8, 6e8)
                spinConstraint.Parent = own
            end
            local overlapParams = OverlapParams.new()
            overlapParams.FilterType = Enum.RaycastFilterType.Include
            overlapParams.FilterDescendantsInstances = {target.Character}
            overlapParams.MaxParts = 12
            local started, lastUpdate, consecutiveOutOfRange = os.clock(), -1, 0
            local lastSpinPlacement = -100
            local spinCorrections = 0
            local lastCollisionProbe = -100
            local launchCorrections, lastLaunchPlacement = 0, -100
            local touchCorrections, lastTouchPlacement = 0, -100
            local launchAxis = Vector3.new(startingTarget.X-origin.Position.X,0,
                startingTarget.Z-origin.Position.Z)
            if launchAxis.Magnitude < 0.5 then
                launchAxis = Vector3.new(own.CFrame.LookVector.X,0,own.CFrame.LookVector.Z)
            end
            if launchAxis.Magnitude < 0.5 then launchAxis = Vector3.new(0,0,-1) end
            launchAxis = launchAxis.Unit
            -- Position and apply impulses EVERY frame, not every 0.17 seconds.
            -- When the client accepts these local CFrame changes, the gap
            -- should read ~1.5 studs, as it did in the reference monitor.
            while not destroyed and enabled.FlingActive and flingToken == token
                and os.clock() - started < contactDuration do
                local r, t = rootOf(localPlayer), rootOf(target)
                if r ~= own or not t or not alive(target) then
                    reason = "own character or target disappeared"
                    break
                end
                elapsed = os.clock() - started
                local phase = elapsed * 35
                local beforeGap = (own.Position - t.Position).Magnitude
                maxDrift = math.max(maxDrift, beforeGap)
                if elapsed > 0.1 and beforeGap > 10 then
                    consecutiveOutOfRange += 1
                else
                    consecutiveOutOfRange = 0
                end
                if consecutiveOutOfRange >= (activeFlingMode ~= "classic" and 14 or 10) then
                    reason = "server or movement system repeatedly moved us away (>10 studs)"
                    break
                end
                local height = math.floor(elapsed / 0.20) % 2 == 0 and 1.45 or -1.45
                local offset = Vector3.new(0.28 * math.sin(phase), height, 0.28 * math.cos(phase))
                local intended = activeFlingMode == "launch"
                    and t.Position - launchAxis * 1.5 + Vector3.new(0,-0.45,0)
                    or activeFlingMode == "touch"
                        and t.Position + Vector3.new(0,0.2,0)
                    or (t.Position + offset)
                -- Classic retains its original per-frame positioning.
                -- In Spin mode, do NOT teleport every physics frame: that
                -- prevents AngularVelocity from resolving contact naturally.
                -- Correct position only briefly if contact drifts away.
                if activeFlingMode == "classic"
                    or activeFlingMode == "spin" and elapsed - lastSpinPlacement >= 0.18
                        and (own.Position - intended).Magnitude > 2.1
                    or activeFlingMode == "launch" and launchCorrections < 4
                        and elapsed - lastLaunchPlacement >= 0.24
                        and (own.Position - intended).Magnitude > 2.2
                    or activeFlingMode == "touch" and touchCorrections < 8
                        and elapsed - lastTouchPlacement >= 0.21
                        and (own.Position - intended).Magnitude > 2.0 then
                    own.CFrame = activeFlingMode == "launch"
                        and CFrame.lookAt(intended, intended + launchAxis)
                        or CFrame.new(intended) * CFrame.Angles(0, phase * 1.8, 0)
                    placements += 1
                    if activeFlingMode == "spin" then
                        lastSpinPlacement = elapsed
                        spinCorrections += 1
                    elseif activeFlingMode == "launch" then
                        lastLaunchPlacement = elapsed
                        launchCorrections += 1
                    elseif activeFlingMode == "touch" then
                        lastTouchPlacement = elapsed
                        touchCorrections += 1
                    end
                end
                local actualGap = (own.Position - t.Position).Magnitude
                closest = math.min(closest, actualGap)
                if actualGap > 5 then approachFails += 1 end

                -- One bounded impulse per physics frame; the next frame
                -- reestablishes contact instead of allowing prolonged drift.
                local direction = activeFlingMode == "launch"
                    and (launchAxis + Vector3.new(0, 0.30, 0))
                    or Vector3.new(math.sin(phase * 1.13),
                        0.55 * math.cos(phase * 0.73), math.cos(phase * 1.37))
                if direction.Magnitude > 0 and activeFlingMode ~= "touch" then
                    own.AssemblyLinearVelocity = direction.Unit *
                        (activeFlingMode == "launch"
                            and math.clamp(numbers.LaunchSpeed, 150, 800)
                            or activeFlingMode == "spin"
                                and math.clamp(numbers.SpinFlingSpeed * 0.6, 850, 2200)
                            or 2500)
                    pulses += 1
                end
                if activeFlingMode == "classic" then
                    own.AssemblyAngularVelocity = Vector3.new(
                        900 * math.sin(phase), 2200 * math.cos(phase * 0.75),
                        900 * math.cos(phase))
                elseif activeFlingMode == "touch" and touchMotor then
                    -- Infinite Yield alternates rotation and rest. Keep
                    -- each pulse time-limited to let physics resolve contact.
                    local engaged = (elapsed % 0.3) < 0.2
                    touchMotor.AngularVelocity = Vector3.new(0,
                        engaged and math.clamp(numbers.TouchSpinSpeed, 1500, 30000) or 0, 0)
                elseif activeFlingMode == "launch" then
                    -- A forward-moving physical contact attempt, rather than
                    -- setting the selected player's character position.
                    own.AssemblyAngularVelocity = Vector3.zero
                end
                lowestTargetY = math.min(lowestTargetY, t.Position.Y)
                -- Spatial queries are expensive on mobile. Sample overlap
                -- at 10Hz instead of on every physics/render frame.
                if elapsed - lastCollisionProbe >= 0.1 then
                    lastCollisionProbe = elapsed
                    local success, touching = pcall(function()
                        return Workspace:GetPartBoundsInBox(own.CFrame, own.Size, overlapParams)
                    end)
                    if success and #touching > 0 then overlaps += 1 end
                    contactFrames += 1
                end
                peakOwn = math.max(peakOwn, own.AssemblyLinearVelocity.Magnitude)
                peakSpin = math.max(peakSpin, own.AssemblyAngularVelocity.Magnitude)
                peakTarget = math.max(peakTarget, t.AssemblyLinearVelocity.Magnitude)
                targetTravel = math.max(targetTravel, (t.Position - startingTarget).Magnitude)
                if elapsed - lastUpdate > 0.38 then
                    lastUpdate = elapsed
                    flingNotice = string.format(
                        "Contacting %s: %.1fs, gap %.1f, %d/%d overlap, %d placements • LOCAL",
                        target.DisplayName, elapsed, actualGap, overlaps, contactFrames, placements)
                    if v54.flingFunLine and v54.flingFunLine.Parent then
                        v54.flingFunLine.Text = flingNotice
                    end
                end
                if own.Position.Y < -120 or humanoid.Health <= 0 then
                    reason = "own character fell or died"
                    break
                end
                if activeFlingMode == "spin" or activeFlingMode == "launch"
                    or activeFlingMode == "touch" then
                    -- PreSimulation runs before the physics solver; allow
                    -- rotational contact to be processed without a CFrame
                    -- reset after each rendered frame.
                    local ok, presim = pcall(function() return RunService.PreSimulation end)
                    if ok and presim then presim:Wait()
                    else RunService.Heartbeat:Wait() end
                else
                    RunService.Heartbeat:Wait()
                end
            end
        end)
        -- Remove the experimental constraint whether the attempt succeeds,
        -- is stopped, or throws. Classic never creates one.
        pcall(function()
            if spinConstraint then spinConstraint:Destroy() end
            if spinAttachment then spinAttachment:Destroy() end
            if touchMotor then touchMotor:Destroy() end
            if activeFlingMode == "touch" and own.Parent then
                own.CustomPhysicalProperties = touchPhysicsOriginal
                own.Massless = touchMasslessOriginal
            end
        end)
        -- Always stop local physics and restore position before observing the target.
        pcall(function()
            if own.Parent then
                own.AssemblyAngularVelocity = Vector3.zero
                own.AssemblyLinearVelocity = Vector3.zero
                own.CanCollide = oldRootCollision
                if not destroyed and rootOf(localPlayer) == own and humanoid.Health > 0 then
                    own.CFrame = origin * CFrame.new(0, 3, 0)
                end
            end
            if humanoid.Parent then
                humanoid.PlatformStand = oldPlatformStand
                if not oldPlatformStand and humanoid.Health > 0 then
                    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end
        end)
        if not destroyed then
            for key, value in pairs(saved) do enabled[key] = value end
        end
        enabled.FlingActive = false
        if not destroyed then
            for _, refresh in ipairs(toggleUpdaters) do refresh() end
        end
        if success and not destroyed and flingToken == token then
            local beginningFollow = os.clock()
            local followBaseline, lastTextAt = targetTravel, -1
            while not destroyed and flingToken == token and os.clock() - beginningFollow < 10 do
                local t = rootOf(target)
                if not t or not alive(target) then
                    reason = reason .. " • target despawned during follow-up"
                    break
                end
                local since = os.clock() - beginningFollow
                local distance = (t.Position - startingTarget).Magnitude
                local speed = t.AssemblyLinearVelocity.Magnitude
                followTravel = math.max(followTravel, distance)
                followSpeed = math.max(followSpeed, speed)
                lowestTargetY = math.min(lowestTargetY, t.Position.Y)
                followSamples += 1
                if not firstLaunchTime and distance > math.max(100, followBaseline + 60) then
                    firstLaunchTime = since
                end
                if since - lastTextAt >= 1 then
                    lastTextAt = since
                    flingNotice = string.format(
                        "Contact ended; tracking %s %.1f/10s: displacement %.0f, peak %.0f/s LOCAL",
                        target.DisplayName, since, distance, followSpeed)
                    if v54.flingFunLine and v54.flingFunLine.Parent then
                        v54.flingFunLine.Text = flingNotice
                    end
                end
                task.wait(since < 1.0 and 0.07 or 0.16)
            end
        end
        flingBusy = false
        if not destroyed then
            local motion = math.max(targetTravel, followTravel)
            local observedDrop = startingTarget.Y-lowestTargetY
            local launchText = (observedDrop >= 50
                and string.format("observed target %.0f studs below start LOCALLY", observedDrop))
                or (firstLaunchTime
                    and string.format("possible delayed launch at +%.2fs", firstLaunchTime))
                or "no significant target launch observed"
            local contactText = canContact and "collision groups compatible" or "local collision test inconclusive"
            flingNotice = success and string.format(
                "%s: %.2fs, %d placements (%d spin corrections), %d/%d overlap, %d gap>5, nearest %.1f, drift %.0f; own %.0f/s spin %.0f; target %.0f studs peak %.0f/s; lowest target Y %.1f; %s; %s; %s. LOCAL OBSERVATION ONLY.",
                activeFlingMode:upper(), elapsed, placements, spinCorrections, overlaps, contactFrames, approachFails,
                closest == math.huge and -1 or closest, maxDrift, peakOwn, peakSpin,
                motion, math.max(peakTarget, followSpeed), lowestTargetY,
                launchText, contactText, reason)
                or "Fling error: " .. tostring(failure):sub(1, 90)
            if v54.flingFunLine and v54.flingFunLine.Parent then
                v54.flingFunLine.Text = flingNotice
            end
            inform(flingNotice)
        end
        if type(onFinished) == "function" then
            pcall(onFinished, success, math.max(targetTravel, followTravel), target.DisplayName)
        end
    end)
    return true
end

-- Every target in Fling All runs the very same flingSelected function.
v54.flingAll = function()
    if v54.flingAllActive or flingBusy then
        return inform("Finish or stop the current fling first")
    end
    local roster = {}
    for _, player in ipairs(otherPlayers()) do
        if alive(player) and rootOf(player) then table.insert(roster, player) end
    end
    if #roster == 0 then return inform("No living players to try") end
    v54.flingAllToken += 1
    local batchToken = v54.flingAllToken
    v54.flingAllActive = true
    v54.flingAllProgress = "Fling All: queued " .. #roster .. " players • SAME frame-contact / delayed observation"
    inform(v54.flingAllProgress)
    task.spawn(function()
        local attempted, skipped, possibleLaunches = 0, 0, 0
        for index, player in ipairs(roster) do
            if destroyed or v54.flingAllToken ~= batchToken then break end
            if not alive(player) or not rootOf(player) then
                skipped += 1
            else
                local finished = false
                v54.flingAllProgress = string.format("Fling All %d/%d: %s", index, #roster, player.DisplayName)
                if v54.flingFunLine and v54.flingFunLine.Parent then
                    v54.flingFunLine.Text = v54.flingAllProgress
                end
                if flingSelected(player, function(ok, distance)
                    if ok and distance > 100 then possibleLaunches += 1 end
                    finished = true
                end) then
                    attempted += 1
                    while not finished and not destroyed and v54.flingAllToken == batchToken do
                        task.wait(0.06)
                    end
                else
                    skipped += 1
                end
                if destroyed or v54.flingAllToken ~= batchToken then break end
                task.wait(0.35)
            end
        end
        v54.flingAllProgress = v54.flingAllToken == batchToken
            and string.format("Fling All: %d attempted, %d skipped, %d moved 100+ studs LOCAL (server UNVERIFIED)", attempted, skipped, possibleLaunches)
            or string.format("Fling All stopped: %d attempted, %d skipped", attempted, skipped)
        v54.flingAllActive = false
        if not destroyed then
            flingNotice = v54.flingAllProgress
            if v54.flingFunLine and v54.flingFunLine.Parent then v54.flingFunLine.Text = flingNotice end
            inform(flingNotice)
        end
    end)
end

-- Read-only Moondiety fling monitor. Never changes forces or character state.
-- Observable client data cannot reveal the other script's source or server truth.
v54.monitorToken = 0
v54.monitorRunning = false
v54.monitorLog = nil
v54.monitorSummary = "Not recorded"
v54.startMonitor = function()
    if v54.monitorRunning then return inform("Monitor already recording") end
    if flingBusy or v54.flingAllActive or enabled.FlingActive then
        return inform("Stop SPECTRA fling before monitoring Moondiety")
    end
    local target = selectedPlayer
    local own = rootOf(localPlayer)
    local other = target and rootOf(target)
    if not own or not other or not target or not alive(target) then
        return inform("Choose a living target from FUN to monitor")
    end
    v54.monitorToken += 1
    local token = v54.monitorToken
    v54.monitorRunning = true
    v54.monitorStopRequested = false
    local started, firstOwn, firstTarget = os.clock(), own.Position, other.Position
    local maxOwnSpeed, maxOwnSpin, maxTargetSpeed = 0, 0, 0
    local maxOwnTravel, maxTargetTravel, minGap, overlapping = 0, 0, math.huge, 0
    local readings = 0
    local rows = {"seconds,self_speed,self_spin,target_speed,self_travel,target_travel,root_gap,overlap"}
    v54.monitorSummary = "Recording " .. target.DisplayName .. " for up to 25 seconds; trigger Moondiety fling now"
    if v54.monitorLabel then v54.monitorLabel.Text = v54.monitorSummary end
    inform("Fling monitor started • minimize SPECTRA, use Moondiety on the selected player")
    task.spawn(function()
        local nextSample = started
        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Include
        overlapParams.FilterDescendantsInstances = {target.Character}
        overlapParams.MaxParts = 12
        while not destroyed and v54.monitorToken == token and not v54.monitorStopRequested and os.clock() - started < 25 do
            local r, t = rootOf(localPlayer), rootOf(target)
            if not r or not t or r ~= own or not alive(target) then break end
            if os.clock() >= nextSample then
                nextSample = os.clock() + 0.15
                local elapsed = os.clock() - started
                local selfSpeed = r.AssemblyLinearVelocity.Magnitude
                local selfSpin = r.AssemblyAngularVelocity.Magnitude
                local targetSpeed = t.AssemblyLinearVelocity.Magnitude
                local ownTravel = (r.Position - firstOwn).Magnitude
                local targetTravel = (t.Position - firstTarget).Magnitude
                local gap = (r.Position - t.Position).Magnitude
                local overlap = #Workspace:GetPartBoundsInBox(r.CFrame, r.Size, overlapParams) > 0
                maxOwnSpeed = math.max(maxOwnSpeed, selfSpeed)
                maxOwnSpin = math.max(maxOwnSpin, selfSpin)
                maxTargetSpeed = math.max(maxTargetSpeed, targetSpeed)
                maxOwnTravel = math.max(maxOwnTravel, ownTravel)
                maxTargetTravel = math.max(maxTargetTravel, targetTravel)
                minGap = math.min(minGap, gap)
                if overlap then overlapping += 1 end
                readings += 1
                rows[#rows + 1] = string.format("%.2f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%d",
                    elapsed, selfSpeed, selfSpin, targetSpeed, ownTravel, targetTravel, gap, overlap and 1 or 0)
                if v54.monitorLabel and v54.monitorLabel.Parent then
                    v54.monitorLabel.Text = string.format(
                        "RECORDING %.1fs • own %.0f/s, spin %.0f rad/s; target %.0f/s; distance %.1f",
                        elapsed, selfSpeed, selfSpin, targetSpeed, gap)
                end
            end
            RunService.Heartbeat:Wait()
        end
        if destroyed or v54.monitorToken ~= token then return end
        v54.monitorRunning = false
        v54.monitorLog = table.concat(rows, "\n")
        v54.monitorSummary = string.format(
            "Moondiety monitor • %d samples; own peak %.0f/s, spin peak %.0f rad/s, own travel %.0f; target peak %.0f/s, target travel %.1f; closest %.1f; overlap samples %d. LOCAL ONLY.",
            readings, maxOwnSpeed, maxOwnSpin, maxOwnTravel,
            maxTargetSpeed, maxTargetTravel, minGap == math.huge and -1 or minGap, overlapping)
        if v54.monitorLabel and v54.monitorLabel.Parent then
            v54.monitorLabel.Text = v54.monitorSummary
        end
        inform("Moondiety monitor finished • use COPY/SAVE LOG to share results")
    end)
end
v54.stopMonitor = function()
    if not v54.monitorRunning then return inform("Monitor is not running") end
    -- End normally on the next Heartbeat, keeping results and samples.
    v54.monitorStopRequested = true
end

local function hasWallClearance(camera, part)
    -- Always enforce real camera line of sight, even if an older saved
    -- setting disabled AimWallCheck. Camera aim never tracks through walls.
    local vector = part.Position - camera.CFrame.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ownChar = characterOf(localPlayer)
    params.FilterDescendantsInstances = ownChar and { ownChar } or {}
    local hit = Workspace:Raycast(camera.CFrame.Position, vector, params)
    return not hit or hit.Instance:IsDescendantOf(part.Parent)
end
-- Prefer reliable MM2 role data. A controller may also visually track an
-- equipped Knife when the role remote hasn't replied; this is not confirmation.
local function findConfirmedMurderer(allowVisibleKnifeFallback)
    local ownRoot = rootOf(localPlayer)
    local candidate, bestDistance = nil, math.huge
    local observedKnife, observedDistance = nil, math.huge
    for _, player in ipairs(otherPlayers()) do
        local role, source, isDead = getRole(player)
        local part = rootOf(player)
        if role == "Murderer" and not isDead and part and alive(player) then
            local distance = ownRoot and (part.Position - ownRoot.Position).Magnitude or 0
            if source == "game" and distance < bestDistance then
                candidate, bestDistance = player, distance
            elseif allowVisibleKnifeFallback and source == "hint"
                and v54.isMurdererKnifeVisible(player) and distance < observedDistance then
                observedKnife, observedDistance = player, distance
            end
        end
    end
    if candidate then return candidate, "game" end
    if allowVisibleKnifeFallback and observedKnife then return observedKnife, "visible Knife" end
    return nil, "no confirmed Murderer or visible Knife"
end

v54.withinScreenAimRadius = function(part)
    local camera = Workspace.CurrentCamera
    if not camera or not part then return false end
    local point, onScreen = camera:WorldToViewportPoint(part.Position)
    if not onScreen or point.Z <= 0 then return false end
    return (Vector2.new(point.X, point.Y) - camera.ViewportSize / 2).Magnitude <= numbers.AimRadius
end

-- Only treat the Murderer as armed when a physically visible Knife TOOL is
-- equipped in their Character, not merely stored in their Backpack.
-- This is local observation, not a server-backed weapon state.
v54.isMurdererKnifeVisible = function(player)
    local char = player and characterOf(player)
    if not char then return false end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") and child.Name:lower():find("knife", 1, true) then
            for _, part in ipairs(child:GetDescendants()) do
                if part:IsA("BasePart") and part.Transparency < 0.96
                    and part.LocalTransparencyModifier < 0.96 then
                    return true
                end
            end
        end
    end
    return false
end

local function findAimPart()
    local camera = Workspace.CurrentCamera
    if not camera then return nil end
    -- A real Gun in the character/backpack provides a fallback while
    -- MM2's role remote is late. Known non-Sheriff roles are still blocked.
    if not v54.canUseSheriffControls or not v54.canUseSheriffControls() then
        return nil
    end
    if v54.sheriffFrontShotActive then
        local murderer = findConfirmedMurderer(true)
        local char = murderer and characterOf(murderer)
        local head = char and char:FindFirstChild("Head")
        -- Ignore knife visibility and radius, but NOT solid-wall obstruction.
        if murderer and alive(murderer) and head and head:IsA("BasePart")
            and hasWallClearance(camera, head) then
            return head
        end
        return nil
    end
    local l2 = enabled.ControllerHoldAim and v54.gamepadAimHeld
    if enabled.AutoAimMurderer or l2 then
        -- Holding L2 deliberately bypasses knife-visibility and FOV gating.
        -- It moves the camera only; real shots still obey server rules.
        local murderer = findConfirmedMurderer(l2)
        if not murderer then return nil end
        if not l2 and enabled.SheriffRequireVisibleKnife
            and not v54.isMurdererKnifeVisible(murderer) then return nil end
        local char = characterOf(murderer)
        local part = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
        if l2 and part and alive(murderer) and hasWallClearance(camera, part) then
            return part
        end
        if part and hasWallClearance(camera, part)
            and (not enabled.AutoShootRadiusGate or v54.withinScreenAimRadius(part)) then
            return part
        end
        return nil
    end
    local center = camera.ViewportSize / 2
    local best, chosen = numbers.AimRadius, nil
    for _, player in ipairs(otherPlayers()) do
        local role = getRole(player)
        if alive(player) and role == "Murderer"
            and (not enabled.SheriffRequireVisibleKnife or v54.isMurdererKnifeVisible(player)) then
            local char = characterOf(player)
            local part = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
            if part then
                local projected, onScreen = camera:WorldToViewportPoint(part.Position)
                local dist = (Vector2.new(projected.X, projected.Y) - center).Magnitude
                if onScreen and projected.Z > 0 and dist < best and hasWallClearance(camera, part) then
                    best, chosen = dist, part
                end
            end
        end
    end
    return chosen
end

-- This is a real, cooldown-gated gun request, NOT a claim that a hit registered.
-- Known MM2 gun variants expose KnifeServer.ShootGun or a CreateBeam RemoteFunction.
local function findGun()
    local char = characterOf(localPlayer)
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    for _, container in ipairs({char, backpack}) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    local name = tool.Name:lower()
                    if name == "gun" or name:find("revolver",1,true)
                        or name:find("pistol",1,true)
                        or name:find("handgun",1,true) then
                        return tool, tool.Parent == char
                    end
                end
            end
        end
    end
    return nil, false
end

-- The role feed can lag after a new round. If no verified role is available,
-- a real Gun tool grants controller fallback; it does not prove Sheriff role.
v54.canUseSheriffControls = function()
    if not alive(localPlayer) then return false, "Your character is not alive" end
    local role, source = getRole(localPlayer)
    local gun = findGun()
    -- Tool possession is a better current-round signal than a lagging
    -- role snapshot. It remains unverified: dropped-gun Heroes can hold a Gun.
    if gun then
        return true, role == "Sheriff" and source == "game"
            and "game-confirmed Sheriff with Gun"
            or "Gun tool present (Sheriff role unverified)"
    end
    -- Sometimes role data arrives before the Gun has been inserted.
    if source == "game" and role == "Sheriff" then
        return true, "Sheriff confirmed, Gun not yet spawned"
    end
    return false, "No Gun tool or confirmed Sheriff (feed: " .. tostring(role) .. ")"
end
v54.updateSheriffCrosshair = function()
    if destroyed or not v54.sheriffCrosshair then return end
    local tool, equipped = findGun()
    -- Hero: an Innocent who picks up the dropped Gun is allowed to aim.
    -- The equipped Tool is the immediate source of truth; the role remote
    -- might still say Innocent for the first second after pickup.
    v54.sheriffCrosshair.Visible = enabled.ShowSheriffCrosshair
        and tool ~= nil and equipped and alive(localPlayer) or false
    if not v54.sheriffCrosshair.Visible then return end
    local length = math.clamp(numbers.CrosshairSize,8,36)
    local gap = math.max(5,math.floor(length*0.44))
    local offset = gap + length/2
    local opacity = math.clamp(numbers.CrosshairOpacity,0.35,1)
    for direction, part in pairs(v54.crosshairParts) do
        part.BackgroundTransparency = 1-opacity
        if direction == "dot" then
            part.Size = UDim2.fromOffset(4,4)
            part.Position = UDim2.fromOffset(60,60)
        elseif direction == "top" or direction == "bottom" then
            part.Size = UDim2.fromOffset(3,length)
            part.Position = UDim2.fromOffset(60,60+(direction=="top" and -offset or offset))
        else
            part.Size = UDim2.fromOffset(length,3)
            part.Position = UDim2.fromOffset(60+(direction=="left" and -offset or offset),60)
        end
    end
end
v54.equipSheriffGun = function()
    if not v54.canUseSheriffControls() then return false end
    local gun, equipped = findGun()
    if not gun then return false end
    if equipped then return true end
    local humanoid = humanOf(localPlayer)
    if not humanoid then return false end
    pcall(function() humanoid:EquipTool(gun) end)
    return gun.Parent == characterOf(localPlayer)
end

local function gunShootRemote(gun)
    local knifeServer = gun:FindFirstChild("KnifeServer")
    local primary = knifeServer and knifeServer:FindFirstChild("ShootGun")
    if primary and primary:IsA("RemoteFunction") then return primary, "AH" end
    local knifeLocal = gun:FindFirstChild("KnifeLocal")
    local createBeam = knifeLocal and knifeLocal:FindFirstChild("CreateBeam")
    local fallback = createBeam and createBeam:FindFirstChild("RemoteFunction")
    if fallback and fallback:IsA("RemoteFunction") then return fallback, "AH2" end
    return nil, nil
end

-- Check the actual third-person firing origin. The gun Handle and character
-- Head can have different lines of sight in shoulder/third-person view.
-- This is still only a client-side precheck, not a server hit confirmation.
local function shootLineOfSight(target, destination, gun)
    local char = characterOf(localPlayer)
    local targetChar = characterOf(target)
    local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
    if not head or not targetChar then return false, "Character missing" end
    local origin = head.Position
    if gun and gun.Parent == char then
        local handle = gun:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") then
            origin = handle.Position
            for _, marker in ipairs(handle:GetDescendants()) do
                if marker:IsA("Attachment") and
                    (marker.Name:lower():find("muzzle", 1, true)
                    or marker.Name:lower():find("barrel", 1, true)) then
                    origin = marker.WorldPosition
                    break
                end
            end
        end
    end
    local direction = destination - origin
    if direction.Magnitude > 400 or direction.Magnitude < 0.1 then
        return false, "Gun shot outside valid distance"
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    local result = Workspace:Raycast(origin, direction, params)
    if not result or result.Instance:IsDescendantOf(targetChar) then return true end
    return false, "Gun muzzle is obstructed"
end

-- The server may enforce its own reload timer independently of these
-- client-side request intervals. Never present sent requests as confirmed hits.
v54.sheriffShotCooldown = function()
    local role, source = getRole(localPlayer)
    local gun = findGun()
    if enabled.SheriffRapidFire and gun
        and (role == "Sheriff" or role == "Hero") then
        return math.clamp(numbers.SheriffRapidInterval, 0.65, 2.5)
    end
    return 2.5
end
local function attemptMurdererShot(manual, headPriority)
    if destroyed or shotInFlight then return end
    local now = os.clock()
    if now - lastShotAttempt < v54.sheriffShotCooldown() then
        if manual then inform("Gun cooldown • wait before shooting again") end
        return
    end
    -- Honor the same Sheriff/Gun-tool fallback as the controller. This
    -- only issues the normal gun request; it never asserts server-side hits.
    local allowed, permissionStatus = v54.canUseSheriffControls()
    if not allowed then
        shotNotice = "Gun unavailable: " .. permissionStatus
        if manual then inform(shotNotice) end
        return
    end
    local murderer = findConfirmedMurderer(v54.sheriffFrontShotActive
        or enabled.SilentAim or enabled.AutoSilentShot)
    -- The optional Knife-visible gate applies to ordinary Sheriff aim/shoot.
    -- Front-stack invoked by D-pad Down (or its matching UI button) ignores it.
    if enabled.SheriffRequireVisibleKnife and not v54.sheriffFrontShotActive
        and not enabled.SilentAim and not enabled.AutoSilentShot
        and not v54.isMurdererKnifeVisible(murderer) then
        shotNotice = "Waiting: confirmed Murderer must have a visibly equipped Knife"
        if manual then inform(shotNotice) end
        return
    end
    local murdererChar = murderer and characterOf(murderer)
    local head = murdererChar and murdererChar:FindFirstChild("Head")
    -- Auto mode must target the Head too: v7.5 used HRP in automatic
    -- shots while the camera tracked the Head (especially inaccurate in TPS).
    local targetPart = (head and head:IsA("BasePart") and head)
        or (not headPriority and murderer and rootOf(murderer))
    if not targetPart then
        shotNotice = "Waiting for a living, game-confirmed Murderer"
        if manual then inform(shotNotice) end
        return
    end
    -- When front-stack is active, screen-center radius is irrelevant: the
    -- target is being placed in the player's front space, not the reticle.
    -- Keep world-position and unobstructed-shot checks; front mode bypasses Knife visibility.
    if not manual and enabled.AutoShootRadiusGate and not v54.sheriffFrontShotActive
        and not enabled.SilentAim and not enabled.AutoSilentShot
        and not v54.withinScreenAimRadius(targetPart) then
        shotNotice = "Auto shoot waiting: Murderer outside visible aim circle"
        return
    end
    local gun, equipped = findGun()
    if not gun then
        shotNotice = "Gun not found in character or backpack"
        if manual then inform(shotNotice) end
        return
    end
    if not equipped then
        local humanoid = humanOf(localPlayer)
        if humanoid then humanoid:EquipTool(gun) end
        shotNotice = "Automatically equipping Gun before headshot"
        if manual then inform(shotNotice) end
        return
    end
    -- Front mode has a stable, exact Head target; do not lead it.
    -- Third-person camera parallax must not alter the world-space shot point.
    local camera = Workspace.CurrentCamera
    local myChar = characterOf(localPlayer)
    local myHead = myChar and myChar:FindFirstChild("Head")
    local firstPerson = camera and myHead
        and (camera.CFrame.Position - myHead.Position).Magnitude < 2.1
    local lead = (v54.sheriffFrontShotActive or enabled.SilentAim
        or enabled.AutoSilentShot) and 0
        or (firstPerson and 0.02 or 0.008)
    local position = targetPart.Position + targetPart.AssemblyLinearVelocity * lead
    if v54.sheriffFrontShotActive and not enabled.SilentAim
        and not enabled.AutoSilentShot and camera then
        -- Avoid firing while the third-person camera is still catching up
        -- from a reposition, or while the weapon is being equipped.
        local toHead = position - camera.CFrame.Position
        if toHead.Magnitude > 0.1 and camera.CFrame.LookVector:Dot(toHead.Unit) < 0.985 then
            shotNotice = "Aligning 3P camera with Murderer Head before gun request"
            return
        end
    end
    if camera and not hasWallClearance(camera, targetPart) then
        shotNotice = "Target behind wall; no gun request sent"
        return
    end
    local clear, reason = shootLineOfSight(murderer, position, gun)
    if not clear then
        shotNotice = reason or "Murderer is obscured / out of range"
        if manual then inform(shotNotice) end
        return
    end
    local remote, shotTag = gunShootRemote(gun)
    if not remote then
        shotNotice = "No supported Gun ShootGun/CreateBeam remote found"
        if manual then inform(shotNotice) end
        return
    end
    shotInFlight = true
    lastShotAttempt = now
    shotAttemptCount += 1
    local request = shotAttemptCount
    -- A RemoteFunction may never return on a disconnected/unsupported server.
    -- Release the local pending flag after a bounded wait so the mode recovers.
    task.delay(4, function()
        if destroyed or not shotInFlight or shotAttemptCount ~= request then return end
        shotInFlight = false
        shotNotice = "Gun request #" .. request .. " timed out; server did not reply"
        if enabled.AutoSilentShot then v54.silentAimReport = shotNotice end
    end)
    if enabled.AutoSilentShot then
        v54.silentAimReport = "Auto head shot #" .. request .. " pending • hit not confirmed"
    end
    shotNotice = (headPriority and "Headshot" or "Gun") .. " request #" .. request
        .. " pending; hit not confirmed"
    task.spawn(function()
        local ok, err = pcall(function() remote:InvokeServer(1, position, shotTag) end)
        if destroyed or shotAttemptCount ~= request then return end
        shotInFlight = false
        shotNotice = ok and ("Sent gun request #" .. request .. "; hit unconfirmed")
            or ("Gun remote error: " .. tostring(err):sub(1, 65))
        if enabled.AutoSilentShot then
            v54.silentAimReport = ok
                and ("Auto Silent Shot #" .. request .. " requested; server hit UNVERIFIED")
                or ("Auto Silent Shot failed: " .. tostring(err):sub(1, 70))
        end
        if manual or not ok then inform(shotNotice) end
    end)
end
-- Optional Sheriff Silent Aim: when the equipped Gun fires normally,
-- make one additional head-position request using the existing gun method.
-- The native shot is not intercepted; server hit validation still applies.
v54.silentAimBindGun = function()
    local gun, equipped = findGun()
    if not gun or not equipped or v54.silentAimSeenGun[gun] then return end
    v54.silentAimSeenGun[gun] = true
    watch(gun.Activated:Connect(function()
        if destroyed or not enabled.SilentAim or enabled.AutoSilentShot
            or gun.Parent ~= characterOf(localPlayer) then return end
        local role, source = getRole(localPlayer)
        if role ~= "Sheriff" or source ~= "game" then
            v54.silentAimReport = "Waiting for confirmed Sheriff role"
            return
        end
        if os.clock() - v54.silentAimLast < 0.15 then return end
        v54.silentAimLast = os.clock()
        local before = shotAttemptCount
        attemptMurdererShot(true, true)
        v54.silentAimReport = shotAttemptCount > before
            and "Head-target shot requested • hit not confirmed"
            or ("No shot request • " .. shotNotice)
    end))
end
-- Role actions: request the experience's ordinary equipped Tool behavior.
-- These controls are local client attempts, NOT server-confirmed eliminations.
v54.roleActionStatus = "Role actions idle"
v54.roleActionLabel = nil
v54.murderSequenceToken = 0
v54.murderSequenceBusy = false
v54.murderAuraLast = 0
v54.murderAttackLast = 0
v54.murderTargetLabel = nil
v54.roleActionMessage = function(message)
    v54.roleActionStatus = message
    if v54.roleActionLabel and v54.roleActionLabel.Parent then
        v54.roleActionLabel.Text = message
    end
    inform(message)
end
v54.confirmRole = function(required)
    local role, source, dead = getRole(localPlayer)
    if not alive(localPlayer) then return false, role, source end
    -- Role feed's Dead flag can be stale after the character has respawned.
    -- Always trust living Humanoid and current role/tool evidence over stale
    -- dead flags when deciding to run the local aura test.
    if role == required and source == "game" then return true, role, source end
    if required == "Murderer" then
        -- Tool evidence is weaker than the MM2 role feed, but avoids a fully
        -- nonresponsive D-pad when the remote is unavailable or stale.
        local char = characterOf(localPlayer)
        local pack = localPlayer:FindFirstChildOfClass("Backpack")
        for _, container in ipairs({char,pack}) do
            if container then
                for _, t in ipairs(container:GetChildren()) do
                    if t:IsA("Tool") and t.Name:lower():find("knife", 1, true) then
                        return true, "Murderer", "Knife tool (unverified)"
                    end
                end
            end
        end
    end
    return false, role, source
end
v54.findKnife = function()
    local char = characterOf(localPlayer)
    local pack = localPlayer:FindFirstChildOfClass("Backpack")
    for _, folder in ipairs({char, pack}) do
        if folder then
            for _, tool in ipairs(folder:GetChildren()) do
                if tool:IsA("Tool") and tool.Name:lower():find("knife", 1, true) then
                    return tool, tool.Parent == char
                end
            end
        end
    end
    return nil, false
end
v54.attackWithKnife = function(opponent, relocate)
    if destroyed or not opponent or opponent == localPlayer or not alive(opponent) then
        return false, "Target is not alive"
    end
    if not v54.confirmRole("Murderer") then
        enabled.MurderAura = false
        return false, "Murderer role and Knife tool both unavailable"
    end
    if os.clock() - v54.murderAttackLast < 0.42 then
        return false, "Knife attempt cooling down"
    end
    local root, targetRoot = rootOf(localPlayer), rootOf(opponent)
    local hum = humanOf(localPlayer)
    local knife, equipped = v54.findKnife()
    if not root or not targetRoot or not hum or not knife then
        return false, "Knife/tool/character missing"
    end
    if not equipped then
        pcall(function() hum:EquipTool(knife) end)
        if knife.Parent ~= characterOf(localPlayer) then
            return false, "Could not equip Knife"
        end
    end
    local gap = (root.Position - targetRoot.Position).Magnitude
    if gap > numbers.KnifeAuraRadius and not relocate then
        return false, "Out of aura range"
    end
    v54.murderAttackLast = os.clock()
    local previousCF = root.CFrame
    local moved = false
    if relocate and gap > 5 then
        -- A single visible approach request; MM2 may reject movement/pickup.
        local ok = pcall(function()
            root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 1.8)
        end)
        moved = ok
    end
    local ok, err = pcall(function() knife:Activate() end)
    if moved then
        task.delay(0.24, function()
            if not destroyed and root.Parent and rootOf(localPlayer) == root and hum.Health > 0 then
                pcall(function() root.CFrame = previousCF end)
            end
        end)
    end
    return ok, ok and "Knife activated (elimination unverified)" or tostring(err):sub(1, 65)
end
v54.killSelected = function()
    if v54.murderSequenceBusy then return v54.roleActionMessage("Stop Kill All before selecting") end
    if not selectedPlayer or selectedPlayer == localPlayer then
        return v54.roleActionMessage("Choose a living target; use the target selector")
    end
    local ok, message = v54.attackWithKnife(selectedPlayer, true)
    v54.roleActionMessage("Kill Selected " .. selectedPlayer.DisplayName .. ": " .. message)
end
v54.killAll = function()
    if v54.murderSequenceBusy then return v54.roleActionMessage("Kill All already running") end
    if not v54.confirmRole("Murderer") then
        return v54.roleActionMessage("Kill All requires confirmed Murderer role")
    end
    v54.murderSequenceToken += 1
    local token = v54.murderSequenceToken
    v54.murderSequenceBusy = true
    enabled.MurderAura = false
    local roster = {}
    for _, p in ipairs(otherPlayers()) do
        if alive(p) then table.insert(roster, p) end
    end
    v54.roleActionMessage("Kill All sequence started: " .. #roster .. " targets")
    task.spawn(function()
        local requests, denied = 0, 0
        for i, p in ipairs(roster) do
            if destroyed or v54.murderSequenceToken ~= token or not v54.confirmRole("Murderer") then break end
            if alive(p) then
                local ok, status = v54.attackWithKnife(p, true)
                if ok then requests += 1 else denied += 1 end
                v54.roleActionMessage(string.format("Kill All %d/%d: %s • %s", i, #roster, p.DisplayName, status))
                task.wait(0.65)
            end
        end
        if v54.murderSequenceToken == token then
            v54.roleActionMessage(string.format("Kill All finished: %d knife requests, %d skipped; eliminations UNVERIFIED", requests, denied))
        end
        v54.murderSequenceBusy = false
    end)
end
-- Experimental local front positioning. Changing a remote player's CFrame on
-- this client does not confer network ownership, server authority, or actual
-- eliminations. No hidden remotes, anchored targets, or persistent loops.
v54.frontActionToken = 0
v54.frontActionBusy = false
v54.frontActionStatus = "Front actions idle"
v54.frontActionLabel = nil
v54.frontActionMessage = function(message)
    v54.frontActionStatus = message
    if v54.frontActionLabel and v54.frontActionLabel.Parent then
        v54.frontActionLabel.Text = message
    end
    inform(message)
end
v54.stopFrontAction = function(quiet)
    v54.sheriffFrontArmed = false
    v54.sheriffFrontShotActive = false
    v54.frontActionToken += 1
    v54.frontActionBusy = false
    if not quiet then v54.frontActionMessage("Front positioning canceled") end
end
v54.frontStackAction = function(mode)
    if destroyed then return end
    if v54.frontActionBusy then
        return v54.frontActionMessage("Front action already running; press STOP")
    end
    if flingBusy or v54.flingAllActive or enabled.FlingActive then
        return v54.frontActionMessage("Stop SPECTRA fling before front positioning")
    end
    local isMurder = mode == "murder"
    local role, source = getRole(localPlayer)
    local allowedSheriff, controllerEvidence = v54.canUseSheriffControls()
    local allowedMurder, _, murderEvidence = v54.confirmRole("Murderer")
    if not alive(localPlayer) or (isMurder and not allowedMurder)
        or (not isMurder and not allowedSheriff) then
        return v54.frontActionMessage(isMurder
            and "D-pad Up blocked: no live Murderer role or Knife tool"
            or ("Sheriff front action blocked: " .. controllerEvidence))
    end
    local own = rootOf(localPlayer)
    local humanoid = humanOf(localPlayer)
    if not own or not humanoid then
        return v54.frontActionMessage("Your character is unavailable")
    end
    local targets = {}
    if isMurder then
        for _, player in ipairs(otherPlayers()) do
            if alive(player) and rootOf(player) then
                table.insert(targets, player)
            end
        end
    else
        local murderer, evidence = findConfirmedMurderer(true)
        if murderer and alive(murderer) and rootOf(murderer) then
            table.insert(targets, murderer)
        end
    end
    if #targets == 0 then
        return v54.frontActionMessage("No living, eligible target with a spawned character")
    end
    local weapon, equipped
    if isMurder then weapon, equipped = v54.findKnife()
    else weapon, equipped = findGun() end
    if not weapon then
        return v54.frontActionMessage(isMurder and "Knife missing" or "Gun missing")
    end
    if not equipped then
        pcall(function() humanoid:EquipTool(weapon) end)
        if weapon.Parent ~= characterOf(localPlayer) then
            return v54.frontActionMessage("Could not equip required weapon")
        end
    end
    -- Front Stack is deliberately opt-in. No saved toggle starts it at login.
    -- The server will usually overwrite changes to characters you do not own.
    v54.frontActionToken += 1
    local token = v54.frontActionToken
    v54.frontActionBusy = true
    -- Sheriff mirrors the Murderer front-stack placement algorithm, but
    -- only queues ONE Murderer target and uses Gun head-position shots.
    v54.sheriffFrontShotActive = not isMurder
    local count = #targets
    local moveSelf = not isMurder and enabled.SheriffFrontMoveSelf
    local frontName = isMurder and "Front Stack + Knife"
        or (moveSelf and "Sheriff approach + Gun" or "Legacy visual front + Gun")
    v54.frontActionMessage(frontName .. ": " .. tostring(count)
        .. " target(s) • " .. (isMurder and tostring(murderEvidence) or controllerEvidence)
        .. " • hits NOT confirmed")
    task.spawn(function()
        local duration = isMurder and 2.2 or 5.5
        local start, lastAttack = os.clock(), -10
        local shooterMovedAt = -10
        local frames, stayedFrames, attackRequests = 0, 0, 0
        local failures = 0
        local lastStatus = -1
        while not destroyed and v54.frontActionToken == token and os.clock() - start < duration do
            local currentRoot = rootOf(localPlayer)
            if currentRoot ~= own or not own.Parent or not alive(localPlayer) then break end
            -- Front headshot mode stays active even when the Murderer holsters their Knife.
            local activeTargets = 0
            for index, player in ipairs(targets) do
                local root = rootOf(player)
                if root and root.Parent and alive(player) then
                    local distance = isMurder and 2.7 or numbers.SheriffFrontDistance
                    local ok = pcall(function()
                        if moveSelf then
                            -- The target stays at their real character location.
                            -- Move our own character into range and face them.
                            -- Our avatar has a better chance of replicating
                            -- than a client-only write to another player's root.
                            local ownPos, targetPos = own.Position, root.Position
                            local horizontal = Vector3.new(
                                ownPos.X - targetPos.X, 0, ownPos.Z - targetPos.Z)
                            if horizontal.Magnitude < 0.2 then
                                local back = -root.CFrame.LookVector
                                horizontal = Vector3.new(back.X, 0, back.Z)
                            end
                            if horizontal.Magnitude < 0.2 then
                                horizontal = Vector3.new(0, 0, 1)
                            end
                            local desiredPos = targetPos + horizontal.Unit * distance
                            local lookPoint = Vector3.new(
                                targetPos.X, desiredPos.Y, targetPos.Z)
                            -- Avoid unnecessary repeated teleports and camera jitter.
                            if (own.Position - desiredPos).Magnitude > 1.8 then
                                own.CFrame = CFrame.lookAt(desiredPos, lookPoint)
                                shooterMovedAt = os.clock()
                                v54.sheriffFrontRelocations += 1
                            else
                                own.CFrame = CFrame.lookAt(own.Position, lookPoint)
                            end
                            v54.sheriffFrontMoveNotice = "Approaching real target, distance "
                                .. math.floor((own.Position - targetPos).Magnitude + 0.5)
                                .. " studs (server unverified)"
                        else
                            -- Classic Murder front-stack and opt-in old Sheriff visual
                            -- positioning behave as before.
                            local desired = own.CFrame * CFrame.new(
                                ((index-1)%3-1)*0.22, 0,
                                -distance - math.floor((index-1)/3)*0.1)
                            root.CFrame = desired
                        end
                    end)
                    if ok then activeTargets += 1 else failures += 1 end
                end
            end
            frames += 1
            if os.clock() - lastAttack >= (isMurder and 0.36 or 0.65) then
                lastAttack = os.clock()
                if isMurder then
                    local ok = pcall(function() weapon:Activate() end)
                    if ok then attackRequests += 1 end
                else
                    -- Wait for own-character movement to settle before firing.
                    -- Never fire into a fake local target position by default.
                    if not moveSelf or os.clock() - shooterMovedAt >= 0.28 then
                        local prior = shotAttemptCount
                        attemptMurdererShot(false, true)
                        if shotAttemptCount > prior then attackRequests += 1 end
                    else
                        shotNotice = "Settling Sheriff position before firing"
                    end
                end
            end
            RunService.Heartbeat:Wait()
            local retained = 0
            for _, player in ipairs(targets) do
                local root = rootOf(player)
                if root and alive(player) then
                    local localRelative = own.CFrame:PointToObjectSpace(root.Position)
                    local minDistance = isMurder and 1 or (numbers.SheriffFrontDistance - 2)
                    local maxDistance = isMurder and 6 or (numbers.SheriffFrontDistance + 2)
                    if localRelative.Z < -minDistance and localRelative.Z > -maxDistance
                        and math.abs(localRelative.X) < 2.2 then
                        retained += 1
                    end
                end
            end
            if retained > 0 then stayedFrames += 1 end
            if os.clock() - lastStatus > 0.9 and v54.frontActionToken == token then
                lastStatus = os.clock()
                if v54.frontActionLabel then
                    v54.frontActionLabel.Text = string.format(
                        "%s: %d/%d seen in front, %d requests, %.1fs • LOCAL ONLY",
                        frontName, retained, count, attackRequests, os.clock()-start)
                end
            end
        end
        if v54.frontActionToken == token then
            v54.sheriffFrontShotActive = false
            v54.frontActionBusy = false
            v54.frontActionMessage(string.format(
                "%s finished: %d target(s), %d gun/knife requests, %d/%d frames near target, %d movement errors. Kills/replication UNVERIFIED.",
                frontName, count, attackRequests, stayedFrames, frames, failures))
        end
    end)
end

v54.stopRoleActions = function()
    v54.stopFrontAction(true)
    v54.murderSequenceToken += 1
    v54.murderSequenceBusy = false
    enabled.MurderAura = false
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    v54.roleActionMessage("Murderer actions stopped")
end
v54.checkNearestThreat = function()
    local murderer = findConfirmedMurderer()
    local root, threatRoot = rootOf(localPlayer), rootOf(murderer)
    if not root or not threatRoot then
        return v54.roleActionMessage("No game-confirmed Murderer position available")
    end
    local gap = (root.Position - threatRoot.Position).Magnitude
    v54.roleActionMessage(string.format("Murderer: %s • %.1f studs away (client-observed)", murderer.DisplayName, gap))
end
v54.retreatFromThreat = function()
    local myRole, source = getRole(localPlayer)
    if source ~= "game" or myRole ~= "Innocent" then
        return v54.roleActionMessage("Retreat is available to game-confirmed Innocents")
    end
    local threat = findConfirmedMurderer()
    local root, threatRoot, hum = rootOf(localPlayer), rootOf(threat), humanOf(localPlayer)
    if not root or not threatRoot or not hum then
        return v54.roleActionMessage("No confirmed threat or live character")
    end
    local away = root.Position - threatRoot.Position
    if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
    local destination = root.Position + away.Unit * 20
    hum:MoveTo(destination)
    v54.roleActionMessage("Moving away from Murderer • 20-stud waypoint (path not guaranteed)")
end
-- Aura checks are periodic and use one standard Knife activation at a time.
task.spawn(function()
    while not destroyed do
        task.wait(0.22)
        if enabled.MurderAura and not v54.murderSequenceBusy then
            if not v54.confirmRole("Murderer") then
                enabled.MurderAura = false
                v54.roleActionMessage("Aura paused: no living Murderer/Knife evidence")
                for _, update in ipairs(toggleUpdaters) do update() end
            elseif os.clock() - v54.murderAuraLast >= 0.5 then
                v54.murderAuraLast = os.clock()
                local own = rootOf(localPlayer)
                local candidate, gap = nil, numbers.KnifeAuraRadius
                if own then
                    for _, p in ipairs(otherPlayers()) do
                        local r = rootOf(p)
                        if r and alive(p) then
                            local d = (own.Position - r.Position).Magnitude
                            if d <= gap then candidate, gap = p, d end
                        end
                    end
                end
                if candidate then
                    local actualReach = math.min(5.3, numbers.KnifeAuraRadius)
                    local moveCloser = enabled.MurderAuraApproach
                        and gap > actualReach and gap <= 14
                    if gap <= actualReach or moveCloser then
                        local ok, detail = v54.attackWithKnife(candidate, moveCloser)
                        v54.roleActionStatus = "Aura " .. candidate.DisplayName
                            .. string.format(" (%.1f studs): ", gap) .. detail
                    else
                        -- A detection radius larger than knife reach does
                        -- not imply an actual hit; don't spam impossible shots.
                        v54.roleActionStatus = "Aura sees " .. candidate.DisplayName
                            .. string.format(" at %.1f studs; contact needs %.1f", gap, actualReach)
                    end
                    if v54.roleActionLabel then v54.roleActionLabel.Text = v54.roleActionStatus end
                else
                    v54.roleActionStatus = "Aura scanning • no living players inside "
                        .. tostring(numbers.KnifeAuraRadius) .. " studs"
                    if v54.roleActionLabel then v54.roleActionLabel.Text = v54.roleActionStatus end
                end
            end
        end
    end
end)

-- FARM FINISH ACTIONS: optional and grounded in actual game-reported roles.
-- A lack of collectible targets is not a guarantee that a bag has filled.
v54.finishFarm = function(reason)
    if destroyed or v54.postFarmFinished then return end
    v54.postFarmFinished = true
    enabled.AutoCoinFarm = false
    v54.farmTravelToken += 1
    local message = "Farm paused: " .. reason .. " (" .. farmAttempts .. " visits, rewards unverified)"
    farmNotice = message
    v54.postFarmStatus = message
    for _, update in ipairs(toggleUpdaters) do update() end
    local explicitReset = v54.resetAt40Enabled and reason == "40 visited positions"
    if v54.postFarmMode ~= "role" and not explicitReset then inform(message); return end
    local role, source = getRole(localPlayer)
    if source ~= "game" then
        v54.postFarmStatus = "No confirmed role: no post-farm action taken"
        inform(v54.postFarmStatus)
        return
    end
    if explicitReset and role ~= "Innocent" then
        v54.postFarmStatus = "40 visits reached, but confirmed role is " .. tostring(role)
            .. "; Innocent-only reset skipped"
        inform(v54.postFarmStatus)
        return
    end
    if role == "Sheriff" or role == "Hero" then
        enabled.AutoAimMurderer = true
        enabled.AimAssist = false
        attemptMurdererShot(true) -- one request, not a confirmed hit
        v54.postFarmStatus = "Sheriff/Hero: aim ON; one gun shot attempted (unconfirmed)"
        inform(v54.postFarmStatus)
    elseif role == "Innocent" then
        local humanoid = humanOf(localPlayer)
        local originalChar = characterOf(localPlayer)
        if humanoid and humanoid.Health > 0 then
            local requestedAt = os.clock()
            pcall(function()
                humanoid.Health = 0
                humanoid:ChangeState(Enum.HumanoidStateType.Dead)
            end)
            v54.postFarmStatus = "Innocent: reset requested, waiting for death/respawn"
            inform(v54.postFarmStatus)
            task.delay(2, function()
                if destroyed then return end
                local died = localPlayer.Character ~= originalChar
                    or not humanoid.Parent or humanoid.Health <= 0
                v54.postFarmStatus = died
                    and string.format("Innocent reset observed after %.1fs (server respawn still unverified)", os.clock()-requestedAt)
                    or "Innocent reset NOT observed; server/game may have rejected the request"
                inform(v54.postFarmStatus)
            end)
        else
            v54.postFarmStatus = "Innocent: no live Humanoid to reset"
            inform(v54.postFarmStatus)
        end
    elseif role == "Murderer" then
        v54.postActionToken += 1
        local token = v54.postActionToken
        v54.postFarmStatus = "Murderer: starting knife-activation sweep (hits unverified)"
        inform(v54.postFarmStatus)
        task.spawn(function()
            local attempts = 0
            for _, opponent in ipairs(otherPlayers()) do
                if destroyed or v54.postActionToken ~= token or not alive(localPlayer) then break end
                if alive(opponent) then
                    local char = characterOf(localPlayer)
                    local ownRoot = rootOf(localPlayer)
                    local targetRoot = rootOf(opponent)
                    local humanoid = humanOf(localPlayer)
                    local pack = localPlayer:FindFirstChildOfClass("Backpack")
                    local knife = char and char:FindFirstChild("Knife") or pack and pack:FindFirstChild("Knife")
                    if ownRoot and targetRoot and knife and knife:IsA("Tool") then
                        if humanoid and knife.Parent ~= char then humanoid:EquipTool(knife) end
                        -- No fabricated kill remote; this is a normal Tool activation attempt.
                        pcall(function()
                            ownRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 2)
                            knife:Activate()
                        end)
                        attempts += 1
                        task.wait(0.7)
                    end
                end
            end
            if destroyed or v54.postActionToken ~= token then return end
            v54.postFarmStatus = "Murderer: " .. attempts .. " knife attempts, no confirmed eliminations"
            inform(v54.postFarmStatus)
        end)
    else
        v54.postFarmStatus = "Role " .. tostring(role) .. ": no post-farm action"
        inform(v54.postFarmStatus)
    end
end
-- GAMEPAD SUPPORT -------------------------------------------------------
-- Only observe L2/LT for hold-to-aim while MM2 reports a living Sheriff.
-- L1/LB and R1/RB are NOT handled by this hub, so the game's normal
-- weapon equip/unequip controls are not overridden or consumed.
v54.controllerStatusLabel = nil
v54.updateControllerStatus = function()
    if destroyed or not v54.controllerStatusLabel or not v54.controllerStatusLabel.Parent then return end
    local online = UserInputService.GamepadEnabled
    local sheriff, sheriffEvidence = v54.canUseSheriffControls()
    local target, targetEvidence = findConfirmedMurderer(true)
    local held = enabled.ControllerHoldAim and v54.gamepadAimHeld and sheriff
    v54.controllerStatusLabel.Text = (online and "GAMEPAD CONNECTED" or "NO GAMEPAD DETECTED")
        .. " | D-pad ↑ " .. v54.gamepadInputCount.up
        .. " ↓ " .. v54.gamepadInputCount.down
        .. " L2 " .. v54.gamepadInputCount.l2
        .. "  |  hold L2/LT: "
        .. (not enabled.ControllerHoldAim and "disabled"
            or not sheriff and "SHERIFF ONLY"
            or held and "AIMING" or "ready") .. " [" .. sheriffEvidence .. "]"
        .. "\nTarget: " .. (target and target.DisplayName or targetEvidence)
        .. "\nD-pad ↑ Murder: Kill All  •  ↓ Sheriff: "
        .. (enabled.SheriffDpadFrontLock
            and (v54.sheriffFrontArmed and "front ARMED" or "front lock")
            or "auto aim/headshot")
        .. "  |  L1/LB + R1/RB: game weapon controls"
        .. "\nY/Triangle menu • D-pad ←/→ tabs or selected value bar • A select • B back"
        .. "\n" .. v54.lastGamepadInput
        .. "\nInput route: " .. (v54.contextActionStatus or "starting")
end
-- Single controller dispatcher shared by ContextActionService + UserInputService.
-- De-dupe events because some gamepad drivers fire on both routes.
v54.dispatchController = function(key, source)
    if destroyed then return end
    local id = key == Enum.KeyCode.DPadUp and "up"
        or key == Enum.KeyCode.DPadDown and "down"
        or key == Enum.KeyCode.ButtonL2 and "l2" or nil
    if not id then return end
    local now = os.clock()
    if now - (v54.gamepadLastDispatch[id] or -100) < 0.17 then return end
    v54.gamepadLastDispatch[id] = now
    v54.gamepadInputCount[id] += 1
    if id == "l2" then
        v54.gamepadAimHeld = true
        local ok, reason = v54.canUseSheriffControls()
        local target, targetReason = findConfirmedMurderer(true)
        v54.lastGamepadInput = "L2 " .. source .. ": "
            .. (not ok and reason or not target and ("no target: " .. targetReason) or "tracking Murderer")
    elseif id == "up" then
        if v54.frontActionBusy then
            v54.stopFrontAction()
            v54.lastGamepadInput = "D-pad ↑: stopped front action"
        else
            v54.frontStackAction("murder")
            v54.lastGamepadInput = "D-pad ↑ " .. source .. ": " .. v54.frontActionStatus
        end
    elseif id == "down" then
        local allowed, reason = v54.canUseSheriffControls()
        if not allowed then
            v54.lastGamepadInput = "D-pad ↓ blocked: " .. reason
            inform(v54.lastGamepadInput)
        elseif enabled.SheriffDpadFrontLock then
            if v54.sheriffFrontArmed then
                v54.stopFrontAction()
                enabled.AutoAimMurderer = false
                v54.lastGamepadInput = "D-pad ↓: front action disarmed"
            else
                v54.sheriffFrontArmed = true
                enabled.AutoAimMurderer = false
                enabled.AutoShootMurderer = false
                enabled.CombatRadius = true
                enabled.AimFOVRing = true
                v54.sheriffFrontLastTry = os.clock()
                v54.equipSheriffGun()
                v54.frontStackAction("sheriff")
                v54.lastGamepadInput = "D-pad ↓ " .. source .. ": " .. v54.frontActionStatus
            end
        else
            enabled.AutoShootMurderer = not enabled.AutoShootMurderer
            enabled.AutoAimMurderer = enabled.AutoShootMurderer
            enabled.CombatRadius = true
            enabled.AimFOVRing = true
            v54.equipSheriffGun()
            v54.lastGamepadInput = enabled.AutoShootMurderer
                and "D-pad ↓: regular Sheriff auto-aim/shoot ON"
                or "D-pad ↓: regular Sheriff auto-aim/shoot OFF"
        end
        for _, refresh in ipairs(toggleUpdaters) do refresh() end
    end
    v54.updateControllerStatus()
    v54.updateFlyHUD()
end
watch(UserInputService.InputBegan:Connect(function(input, processed)
    if destroyed or not v54.isGamepadInput(input) then return end
    local key = input.KeyCode
    if key == Enum.KeyCode.ButtonL2 or key == Enum.KeyCode.DPadUp
        or key == Enum.KeyCode.DPadDown then
        -- Observe buttons even if the Roblox menu has already processed them.
        local ok, err = pcall(v54.dispatchController, key, "UIS")
        if not ok then
            v54.lastGamepadInput = "Controller input error: " .. tostring(err):sub(1, 90)
            warn("[SPECTRA] " .. v54.lastGamepadInput)
        end
    end
end))
-- ContextActionService is an additional input path (never sinks controls).
-- It also works on clients which don't pass some button presses to UIS.
v54.controllerActionName = "SPECTRA_V83_Inputs_" .. tostring(localPlayer.UserId)
local actionOK, actionError = pcall(function()
    ContextActionService:BindActionAtPriority(v54.controllerActionName,
        function(_, state, input)
            if destroyed then return Enum.ContextActionResult.Pass end
            if state == Enum.UserInputState.Begin then
                local ok, err = pcall(v54.dispatchController, input.KeyCode, "CAS")
                if not ok then
                    v54.lastGamepadInput = "Controller action error: " .. tostring(err):sub(1, 90)
                    warn("[SPECTRA] " .. v54.lastGamepadInput)
                end
            elseif input.KeyCode == Enum.KeyCode.ButtonL2
                and state == Enum.UserInputState.End then
                v54.gamepadAimHeld = false
            end
            return Enum.ContextActionResult.Pass
        end, false, Enum.ContextActionPriority.High.Value + 10,
        Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.ButtonL2)
end)
v54.contextActionStatus = actionOK and "CAS active + UIS fallback"
    or ("UIS fallback only: " .. tostring(actionError):sub(1,60))
-- Some Xbox/PlayStation triggers report analog InputChanged rather than
-- a reliable InputBegan. Use threshold + release for continuous L2 tracking.
watch(UserInputService.InputChanged:Connect(function(input)
    if destroyed or not v54.isGamepadInput(input) then return end
    if input.KeyCode == Enum.KeyCode.ButtonL2 then
        local pressure = input.Position.Z
        if pressure > 0.12 then
            v54.gamepadAimHeld = true
        elseif pressure < 0.06 then
            v54.gamepadAimHeld = false
        end
    end
end))
watch(UserInputService.InputEnded:Connect(function(input)
    if destroyed or not v54.isGamepadInput(input) then return end
    if input.KeyCode == Enum.KeyCode.ButtonL2 then
        v54.gamepadAimHeld = false
        v54.lastGamepadInput = "L2/LT released"
    -- D-pad ↑/↓ actions trigger on press; nothing is held on release.
    end
    v54.updateControllerStatus()
    v54.updateFlyHUD()
end))
watch(UserInputService.GamepadDisconnected:Connect(function(_)
    v54.gamepadAimHeld, v54.gamepadFlyUp, v54.gamepadFlyDown = false, false, false
    v54.lastGamepadInput = "Controller disconnected"
    v54.updateControllerStatus()
end))
watch(UserInputService.GamepadConnected:Connect(function(_)
    v54.lastGamepadInput = "Controller connected: hold L2/LT to aim as Sheriff"
    v54.updateControllerStatus()
end))
v54.aimRing = Instance.new("Frame")
v54.aimRing.Name = "AimRadiusPreview"
v54.aimRing.AnchorPoint = Vector2.new(0.5, 0.5)
v54.aimRing.BackgroundTransparency = 1
v54.aimRing.BorderSizePixel = 0
v54.aimRing.Visible = false
v54.aimRing.Parent = gui
round(v54.aimRing, 999)
v54.ringStroke = Instance.new("UIStroke")
v54.ringStroke.Thickness = 2
v54.ringStroke.Color = Color3.fromRGB(87, 174, 255)
v54.ringStroke.Transparency = 0.32
v54.ringStroke.Parent = v54.aimRing
v54.sheriffRingText = Instance.new("TextLabel")
v54.sheriffRingText.Name = "SheriffAimStatus"
v54.sheriffRingText.BackgroundTransparency = 0.25
v54.sheriffRingText.BackgroundColor3 = Color3.fromRGB(16,24,35)
v54.sheriffRingText.TextColor3 = Color3.new(1,1,1)
v54.sheriffRingText.TextSize = 12
v54.sheriffRingText.Font = Enum.Font.GothamBold
v54.sheriffRingText.Size = UDim2.fromOffset(245,29)
v54.sheriffRingText.AnchorPoint = Vector2.new(0.5,1)
v54.sheriffRingText.Position = UDim2.new(0.5,0,0,-8)
v54.sheriffRingText.Parent = v54.aimRing
round(v54.sheriffRingText,6)
v54.combatRing = Instance.new("Frame")
v54.combatRing.Name = "KnifeAuraRadiusPreview"
v54.combatRing.AnchorPoint = Vector2.new(0.5, 0.5)
v54.combatRing.BackgroundTransparency = 1
v54.combatRing.Visible = false
v54.combatRing.Parent = boxGui
round(v54.combatRing, 999)
v54.combatStroke = Instance.new("UIStroke")
v54.combatStroke.Thickness = 2
v54.combatStroke.Color = Color3.fromRGB(255, 130, 111)
v54.combatStroke.Transparency = 0.15
v54.combatStroke.Parent = v54.combatRing
v54.combatText = Instance.new("TextLabel")
v54.combatText.BackgroundTransparency = 0.45
v54.combatText.BackgroundColor3 = Color3.fromRGB(16, 24, 35)
v54.combatText.TextColor3 = Color3.new(1,1,1)
v54.combatText.TextSize = 12
v54.combatText.Font = Enum.Font.GothamBold
v54.combatText.Size = UDim2.fromOffset(210, 26)
v54.combatText.AnchorPoint = Vector2.new(0.5, 0)
v54.combatText.Position = UDim2.new(0.5, 0, 1, 8)
v54.combatText.Parent = v54.combatRing
round(v54.combatText, 6)
v54.updateCombatRadius = function()
    local cam = Workspace.CurrentCamera
    local own = rootOf(localPlayer)
    local auraRole = v54.confirmRole("Murderer")
    local show = enabled.CombatRadius and enabled.MurderAura
        and auraRole and own and cam
    v54.combatRing.Visible = not not show
    if not show then return end
    local view = cam.ViewportSize
    local a, onScreen = cam:WorldToViewportPoint(own.Position)
    local b = cam:WorldToViewportPoint(own.Position
        + cam.CFrame.RightVector * numbers.KnifeAuraRadius)
    -- For first-person or camera-over-shoulder views, the root may be behind
    -- the near plane. Show a clearly labeled fallback scan indicator anyway.
    local centered = not onScreen or a.Z <= 0 or b.Z <= 0
    local radius = centered and math.clamp(numbers.KnifeAuraRadius * 5, 55, 220)
        or math.clamp(math.abs(b.X-a.X), 45, 320)
    local x = centered and view.X/2 or math.clamp(a.X, 0, view.X)
    local y = centered and view.Y/2 or math.clamp(a.Y, 0, view.Y)
    v54.combatRing.Position = UDim2.fromOffset(x,y)
    v54.combatRing.Size = UDim2.fromOffset(radius*2,radius*2)
    local nearby = 0
    for _, player in ipairs(otherPlayers()) do
        local root = rootOf(player)
        if root and alive(player) and (root.Position-own.Position).Magnitude <= numbers.KnifeAuraRadius then
            nearby += 1
        end
    end
    v54.combatStroke.Color = nearby > 0 and Color3.fromRGB(72,240,144) or Color3.fromRGB(255,130,111)
    v54.combatText.Text = string.format("AURA SCAN %d studs • %d nearby%s",
        numbers.KnifeAuraRadius, nearby, centered and " • 2D" or "")
end
v54.updateAimRing = function()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local view = camera.ViewportSize
    v54.aimRing.Position = UDim2.fromOffset(view.X / 2, view.Y / 2)
    v54.aimRing.Size = UDim2.fromOffset(numbers.AimRadius * 2, numbers.AimRadius * 2)
    local showSheriff = enabled.AimFOVRing or enabled.CombatRadius
    local active = enabled.AutoShootMurderer or enabled.AutoAimMurderer
        or v54.sheriffFrontArmed or enabled.AimAssist
        or (enabled.ControllerHoldAim and v54.gamepadAimHeld)
    -- Never show Sheriff's aim reticle as Innocent/Murderer without a Gun:
    -- it was misleadingly visible even when the camera was blocked.
    v54.aimRing.Visible = showSheriff and active and v54.canUseSheriffControls()
    if v54.aimRing.Visible then
        local frontMode = v54.sheriffFrontArmed or v54.sheriffFrontShotActive
        local murderer = findConfirmedMurderer()
        local target = murderer and (characterOf(murderer) and (characterOf(murderer):FindFirstChild("Head") or rootOf(murderer)))
        local inside = target and v54.withinScreenAimRadius(target)
        local knifeOK = not enabled.SheriffRequireVisibleKnife or v54.isMurdererKnifeVisible(murderer)
        v54.ringStroke.Color = ((frontMode and murderer ~= nil) or (inside and knifeOK))
            and Color3.fromRGB(72,240,144) or Color3.fromRGB(255,100,118)
        v54.sheriffRingText.Text = frontMode and "SHERIFF: FRONT HEADSHOT • KNIFE NOT REQUIRED"
            or ((not knifeOK and "SHERIFF: KNIFE HIDDEN • PAUSED")
                or (inside and "SHERIFF: IN RADIUS" or "SHERIFF: OUT OF RADIUS"))
                .. (enabled.AutoShootMurderer and " • AUTO SHOOT" or " • AIM")
    end
end
-- Role radar ----------------------------------------------------------
heading(rolesPage, "QUICK ACCESS")
label(rolesPage, "Pick a section with ‹ / › above, or jump straight to a common tool:",
    45, Color3.fromRGB(194, 215, 239), 12)
makeButton(rolesPage, "COIN FARM  →", function() v54.activateTab("FARM") end)
makeButton(rolesPage, "PLAYER SELECTION / FUN  →", function() v54.activateTab("FUN") end)
makeButton(rolesPage, "SHERIFF AIM & CONTROLLER  →", function() v54.activateTab("SHERIFF") end)
makeButton(rolesPage, "SAVED SETTINGS  →", function() v54.activateTab("SETTINGS") end)
makeButton(rolesPage, "CLEAR STUCK ROUND RESULT SCREEN", function() v54.manualClearRoundResults() end)
heading(rolesPage, "ROLE RADAR  /  LIVE")
label(rolesPage,
    "Red: Murderer  •  Blue: Sheriff  •  Gold: Hero  •  Green: Innocent. " ..
    "A question mark means a visible weapon hint, not a confirmed role.",
    58, Color3.fromRGB(184, 207, 228), 12)
makeButton(rolesPage, "Refresh MM2 role feed", function()
    lastRoleFetch = -100
    refreshRoles()
    inform("Requested MM2 role refresh")
end)
toggle(rolesPage, "Notify when game roles change", "RoleAlerts")
v54.roleDataLine = label(rolesPage, "Checking MM2 game role data...", 36, Color3.fromRGB(160, 205, 232), 12)
v54.yourRoleLiveLabel = label(rolesPage, "YOU: checking live role...", 52,
    Color3.fromRGB(200,235,252), 15)
v54.roleDataLine.TextWrapped = true
do
heading(rolesPage, "SELECT PLAYER  /  AUTO-REFRESH")
v54.chosenPlayerLabel = label(rolesPage, "Selected: nobody", 35,
    Color3.fromRGB(211, 232, 255), 14)
v54.chosenPlayerLabel.Font = Enum.Font.GothamBold
v54.dropdownButton = makeButton(rolesPage, "  CHOOSE PLAYER  ▼", function()
    dropdownOpen = not dropdownOpen
    refreshPlayerDropdown()
end)
v54.dropdownButton.BackgroundColor3 = Color3.fromRGB(44, 72, 125)
v54.dropdownButton.TextSize = 16
v54.dropdownList = Instance.new("ScrollingFrame")
v54.dropdownList.Name = "LivePlayerDropdown"
v54.dropdownList.Size = UDim2.new(1, -4, 0, 210)
v54.dropdownList.BackgroundColor3 = Color3.fromRGB(20, 28, 44)
v54.dropdownList.ScrollBarThickness = 5
v54.dropdownList.ScrollBarImageColor3 = Color3.fromRGB(101, 166, 255)
v54.dropdownList.AutomaticCanvasSize = Enum.AutomaticSize.Y
v54.dropdownList.CanvasSize = UDim2.fromOffset(0, 0)
v54.dropdownList.Visible = false
v54.dropdownList.Parent = rolesPage
round(v54.dropdownList, 9)
v54.dropdownPadding = Instance.new("UIPadding")
v54.dropdownPadding.PaddingTop = UDim.new(0, 6)
v54.dropdownPadding.PaddingBottom = UDim.new(0, 6)
v54.dropdownPadding.PaddingLeft = UDim.new(0, 7)
v54.dropdownPadding.PaddingRight = UDim.new(0, 7)
v54.dropdownPadding.Parent = v54.dropdownList
v54.dropdownLayout = Instance.new("UIListLayout")
v54.dropdownLayout.Padding = UDim.new(0, 5)
v54.dropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
v54.dropdownLayout.Parent = v54.dropdownList
v54.dropdownRows = {}
refreshPlayerDropdown = function()
    if destroyed or not v54.dropdownList.Parent then return end
    local list = otherPlayers()
    local inServer = {}
    if selectedPlayer and selectedPlayer.Parent ~= Players then
        selectedPlayer = nil
    end
    v54.chosenPlayerLabel.Text = selectedPlayer
        and ("Selected: " .. selectedPlayer.DisplayName .. "  (@" .. selectedPlayer.Name .. ")")
        or "Selected: nobody  •  tap CHOOSE PLAYER"
    v54.dropdownButton.Text = "  " .. (selectedPlayer and selectedPlayer.DisplayName or "CHOOSE PLAYER")
        .. "  (" .. tostring(#list) .. ") " .. (dropdownOpen and "▲" or "▼")
    v54.dropdownList.Visible = dropdownOpen
    for i, p in ipairs(list) do
        inServer[p] = true
        local row = v54.dropdownRows[p]
        if not row then
            row = Instance.new("TextButton")
            row.Name = "Pick_" .. tostring(p.UserId)
            row.Size = UDim2.new(1, -3, 0, 49)
            row.BackgroundColor3 = Color3.fromRGB(32, 43, 65)
            row.TextColor3 = Color3.fromRGB(240, 245, 255)
            row.Font = Enum.Font.GothamMedium
            row.TextSize = 14
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.TextTruncate = Enum.TextTruncate.AtEnd
            row.AutoButtonColor = true
            row.Parent = v54.dropdownList
            round(row, 7)
            watch(row.Activated:Connect(function()
                if p.Parent ~= Players then return end
                selectedPlayer = p
                dropdownOpen = false
                lastPlayerChange = "Selected " .. p.DisplayName
                refreshPlayerDropdown()
                inform(lastPlayerChange .. " (@" .. p.Name .. ")")
            end))
            v54.dropdownRows[p] = row
        end
        row.LayoutOrder = i
        local role, origin = getRole(p)
        row.Text = "  " .. (selectedPlayer == p and "✓  " or "") .. p.DisplayName
            .. "  (@" .. p.Name .. ")  • " .. roleDisplay(role, origin)
        row.BackgroundColor3 = selectedPlayer == p and Color3.fromRGB(55, 92, 146)
            or Color3.fromRGB(32, 43, 65)
        row.TextColor3 = getRoleColor(role, origin)
    end
    for p, row in pairs(v54.dropdownRows) do
        if not inServer[p] then
            row:Destroy()
            v54.dropdownRows[p] = nil
        end
    end
    v54.refreshFunPicker()
end
label(rolesPage, "Live player names, roles and selected target update automatically. " ..
    "Role labels show ? when based only on a visible weapon.",
    61, Color3.fromRGB(165, 195, 228), 12)
end
heading(rolesPage, "QUICK ROLE TARGETS")
makeButton(rolesPage, "Select murderer (game data or tool hint)", function() selectRole("Murderer") end)
makeButton(rolesPage, "Select sheriff (game data or tool hint)", function() selectRole("Sheriff") end)
makeButton(rolesPage, "Spectate selected player", spectate)
makeButton(rolesPage, "Return to my character", restoreCamera)
local function updateRoleRadar()
    local yourRole, yourSource = getRole(localPlayer)
    if v54.yourRoleLiveLabel and v54.yourRoleLiveLabel.Parent then
        local _, armed = findGun()
        v54.yourRoleLiveLabel.Text = "YOUR ROLE: " .. roleDisplay(yourRole,yourSource)
            .. (armed and "  •  GUN EQUIPPED" or "")
        v54.yourRoleLiveLabel.TextColor3 = getRoleColor(yourRole,yourSource)
    end
    local murderer, sheriff, hero = "?", "?", "?"
    local known = 0
    for _, p in ipairs(Players:GetPlayers()) do
        local role, source = getRole(p)
        if source == "game" then
            known += 1
            if role == "Murderer" then murderer = p.DisplayName end
            if role == "Sheriff" then sheriff = p.DisplayName end
            if role == "Hero" then hero = p.DisplayName end
        end
    end
    local signature = murderer .. "/" .. sheriff .. "/" .. hero
    if enabled.RoleAlerts and known > 0 and signature ~= roleChangeSignature then
        if roleChangeSignature ~= "" then
            inform("Role update • Murderer: " .. murderer .. " • Sheriff: " .. sheriff)
        end
        roleChangeSignature = signature
    end
    if known == 0 then
        for _, p in ipairs(Players:GetPlayers()) do
            local role, source = getRole(p)
            if source == "hint" then
                if role == "Murderer" then murderer = p.DisplayName .. "?" end
                if role == "Sheriff" then sheriff = p.DisplayName .. "?" end
            end
        end
    end
    local prefix = known > 0 and "GAME DATA" or "TOOL HINTS"
    v54.roleStrip.Text = " " .. prefix .. "  •  M: " .. murderer .. "   S: " .. sheriff
    local age = roleLastUpdate > 0 and (os.clock() - roleLastUpdate) or nil
    v54.roleDataLine.Text = roleSyncMessage .. (age and ("  •  " .. math.floor(age) .. "s ago") or "")
    refreshPlayerDropdown()
end

-- Roster changes update the dropdown immediately; the periodic role feed remains throttled.
watch(Players.PlayerAdded:Connect(function(player)
    lastPlayerChange = player.DisplayName .. " joined"
    task.defer(function()
        if destroyed then return end
        lastRoleFetch = -100
        refreshRoles()
        updateRoleRadar()
    end)
end))
watch(Players.PlayerRemoving:Connect(function(player)
    lastPlayerChange = player.DisplayName .. " left"
    if selectedPlayer == player then
        selectedPlayer = nil
        inform("Selected player left • choose another")
    end
    if spectateTarget == player then restoreCamera() end
    task.delay(0.15, function()
        if not destroyed then updateRoleRadar() end
    end)
end))

-- Visuals page --------------------------------------------------------
-- V4 notes: No claim of confirmed inventory or hidden roles without game data.
heading(visualsPage, "PLAYER HIGHLIGHTS")
toggle(visualsPage, "Color ESP by roles", "RoleESP")
toggle(visualsPage, "Show role labels", "ShowRoles")
toggle(visualsPage, "Only Sheriff / Murderer / Hero", "ThreatsOnly")
toggle(visualsPage, "Limit ESP distance", "RangeLimit")
makeSlider(visualsPage, "ESP RANGE", "ESPRange", 50, 1500, 10, " studs")
toggle(visualsPage, "Player ESP", "PlayerESP")
toggle(visualsPage, "2D BOX ESP • body-only (no self)", "BoxESP2D")
toggle(visualsPage, "Show names", "Names")
toggle(visualsPage, "Show distance", "Distances")
toggle(visualsPage, "Health labels", "Health")
toggle(visualsPage, "Visible weapon hints", "WeaponHints")
toggle(visualsPage, "Through-wall outlines", "XRay")
toggle(visualsPage, "Tracer beams", "Tracers")
toggle(visualsPage, "Rainbow outlines", "Rainbow")
heading(visualsPage, "MAP OBJECT MARKERS")
toggle(visualsPage, "Dropped gun markers", "GunESP", function() scanObjects() end)
toggle(visualsPage, "Alert on new named dropped guns", "GunAlerts")
toggle(visualsPage, "Dropped knife markers", "KnifeESP", function() scanObjects() end)
toggle(visualsPage, "Coin markers", "CoinESP", function() scanObjects() end)
toggle(visualsPage, "Seasonal item markers (name-based)", "EventESP", function() scanObjects() end)
label(visualsPage, "Game roles update every six seconds when the MM2 role feed is accessible. " ..
    "Otherwise tool colors and question marks are observations only.", 55,
    Color3.fromRGB(160, 173, 194), 12)

-- Movement page -------------------------------------------------------
heading(movementPage, "Character controls")
toggle(movementPage, "Custom walkspeed", "Sprint", applyCharacterSettings)
makeSlider(movementPage, "WALK SPEED (CAP 36)", "Speed", 8, 36, 1, "", applyCharacterSettings)
label(movementPage, "High WalkSpeed can trigger Invalid Location in MM2. The applied speed is capped at 36, but MM2 can enforce a lower server limit.", 80,
    Color3.fromRGB(215,197,168), 12)
toggle(movementPage, "Custom jump power", "CustomJump", applyCharacterSettings)
makeSlider(movementPage, "JUMP POWER", "Jump", 30, 150, 5, "", applyCharacterSettings)
toggle(movementPage, "Infinite jump", "InfiniteJump")
toggle(movementPage, "Anti-fling velocity cap", "AntiFling")
toggle(movementPage, "Noclip (pre-physics + heartbeat)", "Noclip", function(on)
    if on then v54.applyNoclip() else restoreNoclip() end
end)
label(movementPage, "Noclip now disables collisions before physics and after movement. Some game-controlled barriers or server correction can still block movement.",
    72, Color3.fromRGB(188, 224, 250), 12)
label(movementPage, "Flight controls are hidden. Farm Flight remains accessible under FARM, but D-pad Up/Down now control role actions instead of flight.",
    70, Color3.fromRGB(188, 224, 250), 13)
makeSlider(movementPage, "CAMERA FOV", "FOV", 40, 110, 1, "°", function(value)
    if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = value end
end)
makeButton(movementPage, "Reset movement values", function()
    enabled.Sprint = false
    enabled.CustomJump = false
    enabled.Noclip = false
    enabled.Fly = false
    restoreNoclip()
    stopFly()
    v54.updateFlyHUD()
    applyCharacterSettings()
    numbers.FOV = previousFOV
    if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = previousFOV end
    v54.refreshSliders()
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    inform("Movement reset")
end)

-- Tools page ----------------------------------------------------------
heading(toolsPage, "Players and camera")
makeButton(toolsPage, "Select next player", chooseNextPlayer)
makeButton(toolsPage, "Spectate selected", spectate)
makeButton(toolsPage, "Return to my camera", restoreCamera)
makeButton(toolsPage, "Look at selected (ON/OFF)", function()
    if not selectedPlayer or not rootOf(selectedPlayer) then
        inform("Select a spawned player first") return
    end
    restoreCamera()
    enabled.CameraLock = true
    inform("Camera tracking selected • tap Return to stop")
end)
heading(toolsPage, "Quick waypoint and gun")
makeButton(toolsPage, "Save current position", function()
    local root = rootOf(localPlayer)
    if root then v54.savedWaypoint = root.CFrame; inform("Waypoint saved for this session") end
end)
makeButton(toolsPage, "Return to saved position", function()
    local root = rootOf(localPlayer)
    if root and v54.savedWaypoint then root.CFrame = v54.savedWaypoint; inform("Waypoint return attempted")
    else inform("Save a position first") end
end)
makeButton(toolsPage, "Grab dropped gun + return (manual)", function()
    v54.attemptGunPickup(false)
end)
heading(toolsPage, "Teleports (may be server-corrected)")
makeButton(toolsPage, "Teleport near identified Murderer", function()
    local p = selectRole("Murderer")
    if p then moveNear(p) end
end)
makeButton(toolsPage, "Teleport near identified Sheriff", function()
    local p = selectRole("Sheriff")
    if p then moveNear(p) end
end)
makeButton(toolsPage, "Teleport near selected", function()
    if selectedPlayer then moveNear(selectedPlayer) else inform("Select a player") end
end)
makeButton(toolsPage, "Teleport near visible Knife", function()
    local p = findHint("Knife visible")
    if p then moveNear(p) else inform("No equipped Knife detected") end
end)
makeButton(toolsPage, "Teleport near visible Gun", function()
    local p = findHint("Gun visible")
    if p then moveNear(p) else inform("No equipped Gun detected") end
end)
makeButton(toolsPage, "Teleport to nearest named GunDrop", function()
    local closest, bestDist = nil, math.huge
    local own = rootOf(localPlayer)
    if not own then inform("Character not spawned") return end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if objectType(obj) == "Gun" then
            local anchor = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
            if anchor then
                local d = (anchor.Position - own.Position).Magnitude
                if d < bestDist then closest, bestDist = anchor, d end
            end
        end
    end
    if closest then
        own.CFrame = closest.CFrame * CFrame.new(0, 3, 0)
        inform("GunDrop proximity teleport attempted")
    else
        inform("No named GunDrop object found")
    end
end)
makeButton(toolsPage, "Teleport to closest Coin", function() tpNearObject("Coin") end)
makeButton(toolsPage, "Teleport to dropped Knife", function() tpNearObject("Knife") end)
makeButton(toolsPage, "Teleport to crosshair target", tpCrosshair)
makeButton(toolsPage, "Teleport near random player", function()
    local list = otherPlayers()
    if #list == 0 then inform("No other players") return end
    moveNear(list[math.random(1, #list)])
end)
makeButton(toolsPage, "Find and teleport to Lobby", function()
    local place = Workspace:FindFirstChild("Lobby", true)
    if not place then inform("No object named Lobby found") return end
    local destination
    if place:IsA("BasePart") then destination = place.CFrame
    elseif place:IsA("Model") then destination = place:GetPivot() end
    local root = rootOf(localPlayer)
    if destination and root then
        root.CFrame = destination * CFrame.new(0, 5, 0)
        inform("Lobby teleport attempted")
    else
        inform("Lobby object wasn't a Part or Model")
    end
end)
heading(toolsPage, "Client-only test objects")
makeButton(toolsPage, "Spawn demo GunDrop", function()
    createDemoPart("GunDrop", Color3.fromRGB(255, 213, 70))
end)
makeButton(toolsPage, "Spawn demo Coin", function()
    createDemoPart("Coin", Color3.fromRGB(107, 255, 122))
end)


-- FARM / AIM / FUN -----------------------------------------------------
heading(farmPage, "COIN COLLECTION")
label(farmPage, "Default: WALK to coins, reducing sudden movement that can trigger Invalid Location. TELEPORT and FLY are experimental options that MM2 may reject; visits are NOT verified coins.",
    112, Color3.fromRGB(207, 218, 237), 13)
toggle(farmPage, "AUTO FARM COINS", "AutoCoinFarm", setFarmEnabled)
toggle(farmPage, "Mode: TELEPORT to each coin (UNSAFE)", "CoinTeleport", function(on)
    if on then
        enabled.CoinFlight = false
        inform("Teleport mode may cause Invalid Location. WALK is the safer default.")
    end
    v54.farmTravelToken += 1
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end)
toggle(farmPage, "Mode: FLY THROUGH WALLS (UNSAFE)", "CoinFlight", function(on)
    if on then
        enabled.CoinTeleport = false
        inform("Farm fly may cause Invalid Location. WALK is the safer default.")
    end
    v54.farmTravelToken += 1
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end)
label(farmPage, "WALK mode is the conservative default. Both TELEPORT and FLY can still result in Invalid Location or movement correction.",
    67, Color3.fromRGB(205, 219, 240), 12)
makeSlider(farmPage, "FARM FLIGHT SPEED (CAP 30)", "FarmFlySpeed", 10, 30, 1, " studs/s")
makeSlider(farmPage, "TELEPORT INTERVAL", "FarmTeleportDelay", 1, 8, 0.5, " sec")
toggle(farmPage, "Include seasonal items by name", "FarmEvents", function()
    farmLastScan = 0
end)
toggle(farmPage, "STOP FARM at visit target (default 40)", "FarmVisitLimit")
v54.resetAt40Button = makeButton(farmPage, "Innocent reset at 40 VISITS: OFF", function()
    v54.resetAt40Enabled = not v54.resetAt40Enabled
    v54.resetAt40Button.Text = v54.resetAt40Enabled
        and "Innocent reset at 40 VISITS: ON" or "Innocent reset at 40 VISITS: OFF"
    inform("40-visit reset " .. (v54.resetAt40Enabled and "armed (Innocent role only)" or "disabled")
        .. " • visits are not earned coins")
end)
label(farmPage, "Set the number of positions visited below. It is NOT the MM2 coin-bag counter. Enable ROLE ACTIONS separately for reset/shot attempts.",
    76, Color3.fromRGB(217, 215, 187), 12)
makeSlider(farmPage, "VISIT LIMIT", "FarmVisitCap", 10, 100, 1, " visits")
toggle(farmPage, "Show coin markers", "CoinESP", function() scanObjects() end)
makeSlider(farmPage, "COLLECTION RANGE", "FarmRadius", 100, 1800, 25, " studs")
makeButton(farmPage, "Reset farm counters / stuck-target list", function()
    resetFarmTracking()
    inform("Farm counters reset")
end)
v54.farmStats = label(farmPage, "Ready • 0 targets visited", 70, Color3.fromRGB(189, 221, 255), 14)
heading(farmPage, "WHEN FARMING FINISHES")
label(farmPage, "Completion means 10 seconds without eligible coin targets, or the configured visit limit. It does NOT prove your bag is full.",
    64, Color3.fromRGB(206, 224, 250), 12)
v54.postFarmModeButton = makeButton(farmPage, "After farm: NOTIFY ONLY (default)", function()
    v54.postFarmMode = v54.postFarmMode == "notify" and "role" or "notify"
    v54.postFarmModeButton.Text = v54.postFarmMode == "notify"
        and "After farm: NOTIFY ONLY" or "After farm: ROLE ACTIONS (unverified)"
    inform("After farm: " .. (v54.postFarmMode == "notify" and "notify only" or "role-dependent attempt"))
end)
label(farmPage, "Opt-in ROLE ACTIONS: Innocent requests local reset; Sheriff/Hero aims and tries one shot; Murderer attempts knife activations. The server may reject all these; no instant-win claim.",
    102, Color3.fromRGB(234, 197, 151), 12)
v54.postFarmInfo = label(farmPage, "Post-farm: not triggered", 56, Color3.fromRGB(164, 219, 242), 12)
heading(farmPage, "DROPPED GUN")
label(farmPage, "Drops a marker at workspace.GunDrop. Manual or Auto attempts a short teleport, checks for a Gun tool, then returns to your previous location. Pickups can be denied by the server.", 95, Color3.fromRGB(204, 222, 241), 12)
makeButton(farmPage, "GRAB GUN + RETURN • manual", function()
    v54.attemptGunPickup(false)
end)
toggle(farmPage, "AUTO grab GunDrop + return", "AutoGunPickup", function(on)
    if on then
        enabled.GunESP = true
        enabled.GunAlerts = true
        scanObjects()
        inform("Auto gun pickup is ON: checking for GunDrop")
    else
        inform("Auto gun pickup is OFF")
    end
end)
v54.gunPickupStatusLabel = label(farmPage, "Gun pickup: ready", 75, Color3.fromRGB(179, 225, 251), 12)
makeButton(farmPage, "Stop automation", function()
    enabled.AutoCoinFarm = false
    enabled.AutoGunApproach = false
    enabled.AutoGunPickup = false
    v54.farmTravelToken += 1
    v54.postActionToken += 1
    local humanoid, root = humanOf(localPlayer), rootOf(localPlayer)
    if humanoid and root then humanoid:MoveTo(root.Position) end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    inform("Auto movement stopped")
end)
heading(aimPage, "CAMERA AIM ASSIST")
label(aimPage, "Aim and auto shots use the shown radius when radius gating is on. Only game-confirmed Murderers are targeted. Server hits are not guaranteed.",
    78, Color3.fromRGB(207, 218, 237), 13)
toggle(aimPage, "Aim camera at Murderer (FOV-limited)", "AimAssist", function(on)
    if on then enabled.CameraLock = false; enabled.AutoAimMurderer = false end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end)
toggle(aimPage, "AUTO AIM • confirmed Murderer (visible radius)", "AutoAimMurderer", function(on)
    if on then enabled.AimAssist = false; enabled.CameraLock = false end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end)
toggle(aimPage, "AUTO SHOOT • confirmed Murderer (Gun only)", "AutoShootMurderer", function(on)
    if on then enabled.AutoSilentShot = false end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end)
toggle(aimPage, "AUTO SILENT SHOT • visible Murderer Head", "AutoSilentShot", function(on)
    enabled.SilentAim = on
    if on then
        enabled.AutoShootMurderer = false
        enabled.AutoAimMurderer = false
        enabled.AimAssist = false
        v54.silentAimReport = "Auto Silent Shot ON • no L2, waits for a visible Murderer"
    else
        v54.silentAimReport = "Silent Aim OFF"
    end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    inform(v54.silentAimReport)
end)
heading(aimPage, "SILENT AIM • SHERIFF ONLY")
label(aimPage, "SILENT AIM requests head shots when you fire normally. AUTO SILENT SHOT also attempts a cooldown-limited shot automatically when the Sheriff has a clear line of sight to the Murderer. No camera turn. Server may reject hits.", 100,
    Color3.fromRGB(194, 219, 247), 12)
toggle(aimPage, "SILENT AIM • AUTOMATIC (no L2 required)", "SilentAim", function(on)
    enabled.AutoSilentShot = on
    if on then
        enabled.AutoAimMurderer = false
        enabled.AimAssist = false
        enabled.AutoShootMurderer = false
        v54.silentAimReport = "AUTO Silent Aim armed • watching for visible Murderer"
    else
        v54.silentAimReport = "OFF"
    end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    inform(v54.silentAimReport)
end)
v54.silentAimLabel = label(aimPage, "Silent Aim: OFF", 50,
    Color3.fromRGB(177, 222, 193), 12)
makeButton(aimPage, "SHOOT confirmed Murderer NOW (one attempt)", function()
    attemptMurdererShot(true)
end)
v54.shotInfoLabel = label(aimPage, "Gun status: waiting", 72, Color3.fromRGB(189, 221, 255), 13)

toggle(aimPage, "Require clear line of sight", "AimWallCheck")
label(aimPage, "Camera aim is for Sheriff. If the role feed is late, a real Gun tool provides a fallback; the hub labels that state as unverified. Confirmed Innocent/Murderer/Hero roles remain blocked.", 65,
    Color3.fromRGB(180, 211, 247), 12)
toggle(aimPage, "Show aim area on screen", "AimFOVRing")
toggle(aimPage, "Show live Murder/Sheriff combat radius", "CombatRadius")
toggle(aimPage, "Auto shoot/aim only inside shown circle", "AutoShootRadiusGate")
label(aimPage, "Sheriff: green ring = confirmed Murderer inside screen radius; red = outside. Murderer: projected knife aura circle turns green when a living target is within its world-space stud radius.", 88, Color3.fromRGB(182, 216, 242), 12)
makeSlider(aimPage, "AIM RESPONSE", "AimSmooth", 0.1, 1, 0.01, "%")
makeSlider(aimPage, "AIM CIRCLE RADIUS", "AimRadius", 70, 500, 5, " px")
v54.aimRateLabel = label(aimPage, "Camera aim response: 54% per frame", 32,
    Color3.fromRGB(150, 218, 248), 13)
makeButton(aimPage, "Aim speed: SMOOTH", function()
    numbers.AimSmooth = 0.34
    inform("Aim speed: smooth (34% per frame)")
end)
makeButton(aimPage, "Aim speed: FAST", function()
    numbers.AimSmooth = 0.72
    inform("Aim speed: fast (72% per frame)")
end)
makeButton(aimPage, "Aim speed: INSTANT", function()
    numbers.AimSmooth = 1
    inform("Aim speed: immediate camera alignment")
end)
heading(aimPage, "CONTROLLER • XBOX / PLAYSTATION")
label(aimPage,
    "SHERIFF: hold LT (Xbox) / L2 (PlayStation) for camera aim. L2 ignores the Knife-visible and aim-radius gates. L1/LB and R1/RB stay free for normal weapon controls. If the role feed is late, a real Gun tool allows an unverified fallback.",
    120, Color3.fromRGB(195, 222, 247), 13)
toggle(aimPage, "SHERIFF: HOLD L2/LT to aim at Murderer", "ControllerHoldAim", function(on)
    if not on then v54.gamepadAimHeld = false end
    v54.updateControllerStatus()
end)
v54.controllerStatusLabel = label(aimPage, "Controller status: waiting", 90,
    Color3.fromRGB(157, 213, 255), 13)
v54.updateControllerStatus()
-- Role-specific controls: local attempts only; not server-confirmed kills.
heading(v54.murderPage, "MURDERER • KNIFE ACTIONS")
label(v54.murderPage, "Requires MM2-confirmed Murderer role and a real Knife tool. Actions activate the equipped knife; the game may reject hits. Kill All is sequential, not an instant-win remote.",
    112, Color3.fromRGB(211, 225, 246), 12)
v54.murderTargetLabel = label(v54.murderPage, "Selected: none • choose with NEXT TARGET", 54,
    Color3.fromRGB(194, 218, 248), 12)
makeButton(v54.murderPage, "NEXT TARGET • cycle current living players", function()
    local roster = {}
    for _, p in ipairs(otherPlayers()) do if alive(p) then table.insert(roster,p) end end
    if #roster == 0 then return inform("No living opponents") end
    local oldIndex = table.find(roster, selectedPlayer) or 0
    selectedPlayer = roster[(oldIndex % #roster) + 1]
    refreshPlayerDropdown()
    v54.murderTargetLabel.Text = "Selected: " .. selectedPlayer.DisplayName .. " (@" .. selectedPlayer.Name .. ")"
    inform("Murderer target: " .. selectedPlayer.DisplayName)
end)
makeButton(v54.murderPage, "KILL SELECTED • knife activation + return", function()
    v54.killSelected()
end)
makeButton(v54.murderPage, "KILL ALL • FRONT STACK + KNIFE (EXPERIMENT)", function()
    v54.frontStackAction("murder")
end)
makeButton(v54.murderPage, "LEGACY KILL ALL • sequential knife attempts", function()
    v54.killAll()
end)
heading(v54.murderPage, "EXPERIMENTAL • FRONT STACK")
label(v54.murderPage, "Try holding living targets 2.7 studs in front of you for 2.2s while activating Knife. Target positioning is CLIENT-ONLY unless MM2 server accepts it. Simultaneous kills are NOT guaranteed.",
    96, Color3.fromRGB(240, 204, 161), 12)
toggle(v54.murderPage, "KILL AURA • scan radius + real knife contact", "MurderAura", function(on)
    if on and not v54.confirmRole("Murderer") then
        enabled.MurderAura = false
        for _, refresh in ipairs(toggleUpdaters) do refresh() end
        inform("Aura requires living Murderer role or actual Knife tool")
    else
        inform(on and "Aura scanning • knife attempts only near contact range" or "Aura disabled")
    end
end)
toggle(v54.murderPage, "SHOW LIVE KNIFE AURA CIRCLE", "CombatRadius")
makeSlider(v54.murderPage, "KNIFE AURA SCAN RANGE", "KnifeAuraRadius", 5, 35, 1, " studs")
toggle(v54.murderPage, "AURA SHORT APPROACH (EXPERIMENTAL/UNSAFE)", "MurderAuraApproach")
label(v54.murderPage, "Aura circle shows scan range. A normal Knife only attempts a hit within ~5 studs. Optional short approach up to 14 studs can cause Invalid Location; OFF by default.", 92,
    Color3.fromRGB(213,197,168), 12)
v54.roleActionLabel = label(v54.murderPage, "Role actions idle", 100, Color3.fromRGB(242, 214, 167), 12)
v54.frontActionLabel = label(v54.murderPage, "Front actions idle", 95, Color3.fromRGB(242, 214, 167), 12)
makeButton(v54.murderPage, "STOP ALL MURDER / FRONT ACTIONS", function() v54.stopRoleActions() end)
heading(v54.sheriffPage, "SHERIFF / HERO • GUN")
label(v54.sheriffPage, "Game-confirmed Sheriff/Hero only. Normal auto-aim/shoot can require a visible Knife (setting below). The separate front-lock mode ignores Knife visibility and uses world-space Head coordinates. Shots remain unverified.",
    90, Color3.fromRGB(208, 223, 248), 12)
makeButton(v54.sheriffPage, "SHOOT CONFIRMED MURDERER NOW", function() attemptMurdererShot(true) end)
heading(v54.sheriffPage, "SHERIFF REQUEST TIMING")
toggle(v54.sheriffPage, "RAPID FIRE • Sheriff only (experimental)", "SheriffRapidFire", function(on)
    if on then
        enabled.SilentAim = true
        enabled.AutoSilentShot = true
        enabled.AutoShootMurderer = false
        inform("Rapid Fire armed. MM2 server cooldown still applies.")
    else
        inform("Rapid Fire disabled")
    end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end)
makeSlider(v54.sheriffPage, "RAPID REQUEST INTERVAL", "SheriffRapidInterval", 0.65, 2.5, 0.05, " s")
label(v54.sheriffPage, "Sets the local request interval, not the actual server weapon reload. This option cannot guarantee more registered hits.", 64,
    Color3.fromRGB(200,220,245), 12)
heading(v54.sheriffPage, "EXPERIMENTAL • FRONT HEADSHOT")
label(v54.sheriffPage, "D-PAD DOWN / FRONT HEADSHOT: recommended mode positions YOUR Sheriff near the Murderer's actual location at configured gun range for 5.5s, locks the camera to their Head, and requests gun shots. The old visual-only target-moving mode remains optional. Server may reject movement or shots.",
    92, Color3.fromRGB(240, 204, 161), 12)
makeSlider(v54.sheriffPage, "FRONT SHOT DISTANCE", "SheriffFrontDistance", 8, 30, 1, " studs")
toggle(v54.sheriffPage, "FRONT: move ME near real Murderer (recommended)", "SheriffFrontMoveSelf")
label(v54.sheriffPage, "Recommended ON: moves your Sheriff within range of the actual Murderer, facing their Head. OFF: old local-only target relocation (can show ghost hits). Server shots remain unverified.", 92,
    Color3.fromRGB(190, 215, 244), 12)
makeButton(v54.sheriffPage, "ONE MURDERER IN FRONT + AUTO GUN HEADSHOT", function()
    v54.frontStackAction("sheriff")
end)
makeButton(v54.sheriffPage, "SHOOT MURDERER HEAD • one request", function()
    attemptMurdererShot(true, true)
end)
toggle(v54.sheriffPage, "AUTO SHOOT • head target (1P/3P)", "AutoShootMurderer", function(on)
    if on then
        enabled.AutoAimMurderer = true
        v54.equipSheriffGun()
    end
end)
toggle(v54.sheriffPage, "REQUIRE VISIBLE KNIFE (normal auto aim/shoot only)", "SheriffRequireVisibleKnife")
toggle(v54.sheriffPage, "SHOW AIM/SHOT RADIUS RING", "CombatRadius")
toggle(v54.sheriffPage, "D-PAD ↓: MURDERER IN FRONT (OFF = auto aim)", "SheriffDpadFrontLock")
toggle(v54.sheriffPage, "AIM LOCK • confirmed Murderer (uses Knife setting)", "AutoAimMurderer")
makeButton(v54.sheriffPage, "EQUIP GUN FROM BACKPACK", function()
    local role, source = getRole(localPlayer)
    if source ~= "game" or (role ~= "Sheriff" and role ~= "Hero") then
        return inform("Equip requires a confirmed Sheriff/Hero")
    end
    local gun, equipped = findGun()
    local hum = humanOf(localPlayer)
    if not gun or not hum then return inform("No usable Gun in Backpack or character") end
    if not equipped then pcall(function() hum:EquipTool(gun) end) end
    inform(gun.Parent == characterOf(localPlayer) and "Gun equipped" or "Equip attempted; not confirmed")
end)
makeButton(v54.sheriffPage, "STOP FRONT LOCK / AUTO HEADSHOT", function()
    v54.stopFrontAction(false)
end)
makeButton(v54.sheriffPage, "SHOW CONFIRMED MURDERER DISTANCE", function() v54.checkNearestThreat() end)
heading(v54.innocentPage, "INNOCENT • SURVIVAL TOOLS")
label(v54.innocentPage, "Defensive tools: threat distance, ordinary MoveTo retreat, dropped-gun pickup, and alerts. Does not grant Sheriff or Murderer abilities.",
    96, Color3.fromRGB(208, 223, 248), 12)
makeButton(v54.innocentPage, "SHOW MURDERER DISTANCE", function() v54.checkNearestThreat() end)
makeButton(v54.innocentPage, "RETREAT 20 STUDS FROM CONFIRMED MURDERER", function() v54.retreatFromThreat() end)
makeButton(v54.innocentPage, "GRAB DROPPED GUN + RETURN (manual)", function()
    v54.attemptGunPickup(false)
end)
toggle(v54.innocentPage, "AUTO PICK UP DROPPED GUN", "AutoGunPickup")
toggle(v54.innocentPage, "MURDERER / SHERIFF ROLE ALERTS", "RoleAlerts")
makeButton(v54.innocentPage, "HIGHLIGHT THREATS + DROPPED GUN", function()
    enabled.PlayerESP, enabled.RoleESP, enabled.GunESP = true, true, true
    scanObjects()
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    inform("Threat and gun highlights enabled")
end)

heading(funPage, "FUN MOVEMENT")
label(funPage, "Fling is experimental: the client cannot guarantee another player's server-owned movement. FUN shows contact and up to 10 seconds of observed displacement.",
    68, Color3.fromRGB(207, 218, 237), 13)
toggle(funPage, "Spin mode (my character)", "SpinMode", function(on)
    if not on then
        local root = rootOf(localPlayer)
        if root then root.AssemblyAngularVelocity = Vector3.zero end
    end
end)
-- FUN now owns a dropdown: choosing a name never leaves the FUN tab.
do
v54.funPickerOpen = false
v54.funPickerButton = makeButton(funPage, "  SELECT FLING TARGET  ▼", function()
    v54.funPickerOpen = not v54.funPickerOpen
    v54.refreshFunPicker()
end)
v54.funPickerButton.BackgroundColor3 = Color3.fromRGB(44, 72, 125)
v54.funPickerList = Instance.new("ScrollingFrame")
v54.funPickerList.Name = "FunLiveTargetPicker"
v54.funPickerList.Size = UDim2.new(1, -4, 0, 190)
v54.funPickerList.BackgroundColor3 = Color3.fromRGB(20, 28, 44)
v54.funPickerList.ScrollBarThickness = 5
v54.funPickerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
v54.funPickerList.CanvasSize = UDim2.fromOffset(0, 0)
v54.funPickerList.Visible = false
v54.funPickerList.Parent = funPage
round(v54.funPickerList, 9)
v54.pickerLayout = Instance.new("UIListLayout")
v54.pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder
v54.pickerLayout.Padding = UDim.new(0, 5)
v54.pickerLayout.Parent = v54.funPickerList
v54.funRows = {}
v54.refreshFunPicker = function()
    if destroyed or not v54.funPickerList.Parent then return end
    local roster = otherPlayers()
    local present = {}
    v54.funPickerButton.Text = "  TARGET: " .. (selectedPlayer and selectedPlayer.DisplayName or "CHOOSE PLAYER")
        .. "  (" .. #roster .. ") " .. (v54.funPickerOpen and "▲" or "▼")
    v54.funPickerList.Visible = v54.funPickerOpen
    for i, player in ipairs(roster) do
        present[player] = true
        local button = v54.funRows[player]
        if not button then
            button = Instance.new("TextButton")
            button.Name = "FunPick_" .. player.UserId
            button.Size = UDim2.new(1, 0, 0, 49)
            button.TextXAlignment = Enum.TextXAlignment.Left
            button.TextSize = 14
            button.Font = Enum.Font.GothamMedium
            button.Selectable = true
            button.Parent = v54.funPickerList
            round(button, 7)
            watch(button.Activated:Connect(function()
                if player.Parent ~= Players then return end
                selectedPlayer = player
                v54.funPickerOpen = false
                lastPlayerChange = "Selected " .. player.DisplayName
                refreshPlayerDropdown() -- also refreshes the FUN picker
                inform("Fling target: " .. player.DisplayName .. " (@" .. player.Name .. ")")
            end))
            v54.funRows[player] = button
        end
        local role, origin = getRole(player)
        button.LayoutOrder = i
        button.TextColor3 = getRoleColor(role, origin)
        button.BackgroundColor3 = player == selectedPlayer
            and Color3.fromRGB(55, 92, 146) or Color3.fromRGB(32, 43, 65)
        button.Text = "  " .. (player == selectedPlayer and "✓  " or "")
            .. player.DisplayName .. " (@" .. player.Name .. ") • " .. roleDisplay(role, origin)
    end
    for player, button in pairs(v54.funRows) do
        if not present[player] then
            button:Destroy()
            v54.funRows[player] = nil
        end
    end
end
v54.refreshFunPicker()
end
heading(funPage, "PHYSICS LIMITS & NETWORK OWNERSHIP")
label(funPage, "Network ownership belongs to the server/assigned client. Your character's velocity cannot reliably force an opponent to move if their assembly is owned elsewhere or MM2 corrects the collision. Check the target diagnostics before testing another mode.", 116,
    Color3.fromRGB(208,213,242), 12)
heading(funPage, "PLAYER FLING • EXPERIMENTAL")
label(funPage, "Choose a target above, without leaving FUN. This is a client-side physics test, not a guaranteed fling: if the server rejects the collision, other players will not move. STATUS shows locally observed motion.",
    94, Color3.fromRGB(207, 218, 237), 13)
v54.flingFunLine = label(funPage, "Fling test: not started. Choose a player, then use Diagnose.",
    100, Color3.fromRGB(248, 207, 161), 13)
makeButton(funPage, "DIAGNOSE PHYSICS OWNER / COLLISIONS", function()
    if not selectedPlayer then return inform("Choose a player in FUN first") end
    local report = v54.physicsDiagnostic(selectedPlayer)
    flingNotice = report
    v54.flingFunLine.Text = report
    inform(report)
    print("[SPECTRA PHYSICS] " .. report)
end)
label(funPage, "RESTORED v6.9 FLING • ~1.12 second per-frame 1.5 stud approach with 2,500 studs/s pulses. Fling Selected and Fling All use the exact same routine. 10 second delayed-launch monitor; LOCAL ONLY.",
    95, Color3.fromRGB(255, 207, 172), 12)
label(funPage, "Spin now allows ~0.18s of physics contact between position corrections instead of teleporting every frame. Classic still uses its old method. Other players may remain server-owned and unaffected.", 72,
    Color3.fromRGB(194, 220, 241), 12)
makeSlider(funPage, "SPIN ROTATION SPEED", "SpinFlingSpeed", 700, 3500, 100, " rad/s")
makeSlider(funPage, "SPIN CONTACT DURATION", "SpinFlingDuration", 0.8, 3.0, 0.1, " s")
heading(funPage, "PHYSICAL CONTACT LAUNCH • NEW TEST")
label(funPage, "LAUNCH tries pushing a selected player by moving your own character into contact and applying forward/upward velocity. It never directly writes the other player's CFrame. The server may ignore/correct the motion.", 105,
    Color3.fromRGB(188,220,248), 12)
makeSlider(funPage, "LAUNCH MOVEMENT SPEED", "LaunchSpeed", 150, 800, 25, " studs/s")
makeSlider(funPage, "LAUNCH CONTACT TIME", "LaunchDuration", 0.8, 2.5, 0.1, " s")
heading(funPage, "IY-INSPIRED TOUCH FLING")
label(funPage, "Experimental touch-spin adapted from Infinite Yield's documented fling mechanism. Uses temporary local root angular force with short rotation pulses. Can attempt a selected target at any starting distance by repositioning your own avatar. Long moves may trigger Invalid Location or server correction.", 95,
    Color3.fromRGB(193,222,245), 12)
makeSlider(funPage, "TOUCH SPIN SPEED", "TouchSpinSpeed", 1500, 30000, 500, " rad/s")
makeSlider(funPage, "TOUCH TEST DURATION", "TouchDuration", 0.6, 2.3, 0.1, " s")
v54.refreshFlingModeText = function()
    if not v54.flingModeToggle then return end
    v54.flingModeToggle.Text = v54.flingMode == "classic"
        and "MODE: CLASSIC • tap for SPIN"
        or v54.flingMode == "spin" and "MODE: SPIN • tap for LAUNCH"
        or v54.flingMode == "launch" and "MODE: LAUNCH • tap for TOUCH"
        or "MODE: IY TOUCH • tap for CLASSIC"
end
v54.flingModeToggle = makeButton(funPage, "MODE: CLASSIC • tap for SPIN", function()
    if flingBusy or v54.flingAllActive then
        return inform("Stop current fling before switching modes")
    end
    v54.flingMode = v54.flingMode == "classic" and "spin"
        or v54.flingMode == "spin" and "launch"
        or v54.flingMode == "launch" and "touch" or "classic"
    v54.refreshFlingModeText()
    inform("Contact mode: " .. v54.flingMode:upper()
        .. " • local movement is not proof of server displacement")
end)
v54.refreshFlingModeText()
makeButton(funPage, "TOUCH FLING SELECTED • NEW TEST", function()
    if flingBusy or v54.flingAllActive then
        return inform("Stop the previous contact test before starting another")
    end
    v54.flingMode = "touch"
    v54.refreshFlingModeText()
    flingSelected()
end)
makeButton(funPage, "LAUNCH SELECTED • PHYSICS CONTACT TEST", function()
    if flingBusy or v54.flingAllActive then return inform("Finish the current contact test") end
    v54.flingMode = "launch"
    v54.refreshFlingModeText()
    flingSelected()
end)
makeButton(funPage, "FLING SELECTED • CHOSEN MODE", function()
    flingSelected()
end)
makeButton(funPage, "FLING ALL • CHOSEN MODE", function()
    v54.flingAll()
end)
label(funPage, "CLASSIC: earlier velocity method. SPIN: AngularVelocity constraint. LAUNCH: forward momentum. IY TOUCH: alternating BodyAngularVelocity pulses with original mass settings restored afterward. Reports observed motion for 10 seconds; no guaranteed server fling.",
    96, Color3.fromRGB(186,225,209), 12)

heading(funPage, "READ-ONLY MOONDIETY MONITOR")
label(funPage, "Select the same target, tap START, minimize SPECTRA and fling only with Moondiety. Recording runs up to 25 seconds. Do not run both fling engines simultaneously.",
    100, Color3.fromRGB(195, 225, 247), 12)
v54.monitorLabel = label(funPage, "Monitor: idle. No samples recorded.", 106, Color3.fromRGB(198, 234, 204), 12)
makeButton(funPage, "START 25s MONITOR • read-only", function()
    v54.startMonitor()
end)
makeButton(funPage, "STOP MONITOR / finalize readings", function()
    v54.stopMonitor()
end)
makeButton(funPage, "COPY / SAVE LAST MONITOR LOG", function()
    if not v54.monitorLog then return inform("No completed monitor log yet") end
    local copied, saved = false, false
    if type(setclipboard) == "function" then
        copied = pcall(setclipboard, v54.monitorSummary .. "\n" .. v54.monitorLog)
    end
    if type(writefile) == "function" then
        saved = pcall(writefile, "SPECTRA_FlingMonitor.csv", v54.monitorLog)
    end
    if not copied and not saved then
        print("SPECTRA FLING MONITOR\n" .. v54.monitorSummary .. "\n" .. v54.monitorLog)
    end
    inform((copied and "Copied log • " or "") .. (saved and "Saved SPECTRA_FlingMonitor.csv" or "")
        .. (not copied and not saved and "Wrote log to executor console" or ""))
end)
makeButton(funPage, "Stop fling / observation / ALL", function()
    v54.flingAllToken += 1
    v54.flingAllActive = false
    flingToken += 1
    enabled.FlingActive = false
    enabled.SpinMode = false
    local root = rootOf(localPlayer)
    if root then
        root.AssemblyAngularVelocity = Vector3.zero
        root.AssemblyLinearVelocity = Vector3.zero
    end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    v54.flingAllProgress = "Fling All stopped by user"
    inform("Fling, observation and Fling All stopped")
end)
makeButton(funPage, "Sit", function()
    local humanoid = humanOf(localPlayer)
    if humanoid then humanoid.Sit = true end
end)
makeButton(funPage, "Stand up", function()
    local humanoid = humanOf(localPlayer)
    if humanoid then humanoid.Sit = false end
end)
-- Animation and emote previews: require equipped emotes / accessible assets.
-- This does not unlock ownership or alter the account's permanent inventory.
do
-- R15 movement animation pack presets. These are local previews only; no bundle ownership is granted.
-- We edit the character's existing Animate Animation instances, rather than play seven
-- movement tracks simultaneously. Missing/custom Animate hierarchies are skipped safely.
v54.animationPacks = {
    ["R6 Free"] = {
        Rig="R6", Idle={180435571,180435792}, Walk=180426354, Run=180426354,
        Jump=125750702, Fall=180436148, Climb=180436334, Sit=178130996,
        ToolHold=182393478, ToolSlash=129967390, ToolLunge=129967478,
        Wave=128777973, Point=128853357, Dance1={182435998,182491037,182491065},
        Dance2={182436842,182491248,182491277},
        Dance3={182436935,182491368,182491423}, Laugh=129423131, Cheer=129423030
    },
    ["R15 Classic"] = {
        Rig="R15", Idle={507766666,507766951,507766388},
        Walk=507777826, Run=507767714, Jump=507765000, Fall=507767968,
        Swim=507784897, SwimIdle=507785072, Climb=507765644, Sit=507768133,
        ToolHold=507768375, ToolSlash=522635514, ToolLunge=522638767,
        Wave=507770239, Point=507770453,
        Dance1={507771019,507771955,507772104},
        Dance2={507776043,507776720,507776879},
        Dance3={507777268,507777451,507777623},
        Laugh=507770818, Cheer=507770677
    },
    ["R6 Style on R15"] = {
        Rig="R15", Idle={12521158637,12521162526}, Walk=12518152696,
        Run=12518152696, Jump=12520880485, Fall=12520972571,
        Climb=12520982150, Sit=12520993168,
        ToolHold=12520996634, ToolSlash=12520999032, ToolLunge=12521002003,
        Wave=12521004586, Point=12521007694,
        Dance1={12521009666,12521151637,12521015053},
        Dance2={12521169800,12521173533,12521027874},
        Dance3={12521178362,12521181508,12521184133},
        Laugh=12521018724, Cheer=12521021991,
        IdleOnce={13842624027,13842624352}, WalkOnce=13842624225,
        FallOnce=13842624498, ClimbOnce=13842624634, ToolOnce=13842624036,
        NinjaDash=13978512316, NinjaSlash=13978507503, DualSlash=13978510688,
        SwordPump=13978511071, SwordSwingJump=13978511543,
        SwordThrust=13978511983, TwoHandSword=13978504790
    },
    ["Rthro"] = {
        Rig="R15", Idle={2510197257,2510196951,3711062489},
        Walk=2510202577, Run=2510198475, Jump=2510197830, Fall=2510195892,
        Swim=2510199791, SwimIdle=2510201162, Climb=2510192778
    },
    ["Astronaut"] = {
        Rig="R15", Idle={891621366,891633237,1047759695},
        Walk=891636393, Run=891636393, Jump=891627522, Fall=891617961,
        Swim=891639666, SwimIdle=891663592, Climb=891609353
    },
    ["Bubbly"] = {
        Rig="R15", Idle={910004836,910009958,1018536639},
        Walk=910034870, Run=910025107, Jump=910016857, Fall=910001910,
        Swim=910028158, SwimIdle=910030921, Climb=909997997
    },
    ["Cartoony"] = {
        Rig="R15", Idle={742637544,742638445,885477856},
        Walk=742640026, Run=742638842, Jump=742637942, Fall=742637151,
        Swim=742639220, SwimIdle=742639812, Climb=742636889
    },
    ["Elder"] = {
        Rig="R15", Idle={845397899,845400520,901160519},
        Walk=845403856, Run=845386501, Jump=845398858, Fall=845396048,
        Swim=845401742, SwimIdle=845403127, Climb=845392038
    },
    ["Knight"] = {
        Rig="R15", Idle={657595757,657568135,885499184},
        Walk=657552124, Run=657564596, Jump=658409194, Fall=657600338,
        Swim=657560551, SwimIdle=657557095, Climb=658360781
    },
    ["Levitation"] = {
        Rig="R15", Idle={616006778,616008087,886862142},
        Walk=616013216, Run=616010382, Jump=616008936, Fall=616005863,
        Swim=616011509, SwimIdle=616012453, Climb=616003713
    },
    ["Mage"] = {
        Rig="R15", Idle={707742142,707855907,885508740},
        Walk=707897309, Run=707861613, Jump=707853694, Fall=707829716,
        Swim=707876443, SwimIdle=707894699, Climb=707826056
    },
    ["Ninja"] = {
        Rig="R15", Idle={656117400,656118341,886742569},
        Walk=656121766, Run=656118852, Jump=656117878, Fall=656115606,
        Swim=656119721, SwimIdle=656121397, Climb=656114359
    },
    ["Pirate"] = {
        Rig="R15", Idle={750781874,750782770,885515365},
        Walk=750785693, Run=750783738, Jump=750782230, Fall=750780242,
        Swim=750784579, SwimIdle=750785176, Climb=750779899
    },
    ["Robot"] = {
        Rig="R15", Idle={616088211,616089559,885531463},
        Walk=616095330, Run=616091570, Jump=616090535, Fall=616087089,
        Swim=616092998, SwimIdle=616094091, Climb=616086039
    },
    ["Stylish"] = {
        Rig="R15", Idle={616136790,616138447,886888594},
        Walk=616146177, Run=616140816, Jump=616139451, Fall=616134815,
        Swim=616143378, SwimIdle=616144772, Climb=616133594
    },
    ["Superhero"] = {
        Rig="R15", Idle={616111295,616113536,885535855},
        Walk=616122287, Run=616117076, Jump=616115533, Fall=616108001,
        Swim=616119360, SwimIdle=616120861, Climb=616104706
    },
    ["Toy"] = {
        Rig="R15", Idle={782841498,782845736,980952228},
        Walk=782843345, Run=782842708, Jump=782847020, Fall=782846423,
        Swim=782844582, SwimIdle=782845186, Climb=782843869
    },
    ["Vampire"] = {
        Rig="R15", Idle={1083445855,1083450166,1088037547},
        Walk=1083473930, Run=1083462077, Jump=1083455352, Fall=1083443587,
        Swim=1083464683, SwimIdle=1083467779, Climb=1083439238
    },
    ["Werewolf"] = {
        Rig="R15", Idle={1083195517,1083214717,1099492820},
        Walk=1083178339, Run=1083216690, Jump=1083218792, Fall=1083189019,
        Swim=1083222527, SwimIdle=1083225406, Climb=1083182000
    },
    ["Zombie"] = {
        Rig="R15", Idle={616158929,616160636,885545458},
        Walk=616168032, Run=616163682, Jump=616161997, Fall=616157476,
        Swim=616165109, SwimIdle=616166655, Climb=616156119
    },
}

v54.selectedAnimationPack = "Default"
v54.lastSavedPack = "Default"
v54.animationPackOriginals = setmetatable({}, {__mode = "k"})
v54.animationPackStatus = "Original character movement animations"
v54.animationPackStatusLabel = nil
v54.animationPackSequence = 0
v54.packReferences = {
    Idle = {{"idle","Animation1"}, {"idle","Animation2"}, {"idle","Animation3"}},
    Walk = {{"walk","WalkAnim"}}, Run = {{"run","RunAnim"}},
    Jump = {{"jump","JumpAnim"}}, Fall = {{"fall","FallAnim"}},
    Swim = {{"swim","Swim"}}, SwimIdle = {{"swimidle","SwimIdle"}},
    Climb = {{"climb","ClimbAnim"}}, Sit = {{"sit","SitAnim"}},
    ToolHold = {{"toolnone","ToolNoneAnim"}},
    ToolSlash = {{"toolslash","ToolSlashAnim"}},
    ToolLunge = {{"toollunge","ToolLungeAnim"}},
    Wave = {{"wave","WaveAnim"}}, Point = {{"point","PointAnim"}},
    Dance1 = {{"dance","Animation1"},{"dance","Animation2"},{"dance","Animation3"}},
    Dance2 = {{"dance2","Animation1"},{"dance2","Animation2"},{"dance2","Animation3"}},
    Dance3 = {{"dance3","Animation1"},{"dance3","Animation2"},{"dance3","Animation3"}},
    Laugh = {{"laugh","LaughAnim"}}, Cheer = {{"cheer","CheerAnim"}}
}
v54.animationRigName = function()
    local hum = humanOf(localPlayer)
    if not hum then return "Loading" end
    return hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"
end
v54.packAssetId = function(ids, index)
    local id = type(ids) == "table" and ids[math.min(index or 1, #ids)] or ids
    if type(id) ~= "number" and type(id) ~= "string" then return nil end
    if tostring(id):match("^%d+$") then return "rbxassetid://" .. tostring(id) end
    return id
end

v54.updatePackStatus = function(message)
    v54.animationPackStatus = message
    if v54.animationPackStatusLabel and v54.animationPackStatusLabel.Parent then
        v54.animationPackStatusLabel.Text = message
    end
end
-- Changing AnimationId alone can leave Animate playing a cached track. Restart
-- the existing controller after successful edits or restoration, but never destroy it.
v54.restartAnimate = function(character)
    task.defer(function()
        if destroyed or localPlayer.Character ~= character then return end
        local animate = character:FindFirstChild("Animate")
        if not animate or not (animate:IsA("LocalScript") or animate:IsA("Script")) then return end
        pcall(function()
            animate.Disabled = true
            task.wait(0.08)
            if not destroyed and animate.Parent then animate.Disabled = false end
        end)
    end)
end
v54.restoreAnimationPack = function(quiet)
    v54.animationPackSequence += 1
    local count = 0
    for character, savedIds in pairs(v54.animationPackOriginals) do
        for animation, oldId in pairs(savedIds) do
            if animation.Parent and animation:IsDescendantOf(character) then
                local ok = pcall(function() animation.AnimationId = oldId end)
                if ok then count += 1 end
            end
        end
        v54.animationPackOriginals[character] = nil
        if count > 0 then v54.restartAnimate(character) end
    end
    v54.selectedAnimationPack = "Default"
    local message = "Original animations restored (" .. count .. " clips)"
    v54.updatePackStatus(message)
    if not quiet then inform(message) end
end
-- Apply Animate IDs immediately. A previous 7-second batch of
-- Animator:LoadAnimation probes often timed out and rejected the entire pack
-- on mobile before any IDs could be installed.
v54.applyAnimationPack = function(name, quiet)
    local pack = v54.animationPacks[name]
    if not pack then
        if not quiet then inform("Unknown animation pack: " .. tostring(name)) end
        return false
    end
    v54.animationPackSequence += 1
    local sequence = v54.animationPackSequence
    local character = localPlayer.Character
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    local animate = character and character:FindFirstChild("Animate")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not character or not hum or not animate or not animator then
        v54.updatePackStatus("Cannot apply pack: missing live Humanoid, Animator or Animate")
        return false
    end
    local rig = v54.animationRigName()
    if rig ~= pack.Rig then
        v54.updatePackStatus("Wrong rig: " .. name .. " needs " .. pack.Rig
            .. "; you're using " .. rig)
        return false
    end
    v54.stopAnimationPreview()
    local original = v54.animationPackOriginals[character]
    if not original then
        original = {}
        v54.animationPackOriginals[character] = original
    end
    local updated, same, missing, errors = 0, 0, 0, 0
    local oldLocomotion = {}
    for action, references in pairs(v54.packReferences) do
        for index, pair in ipairs(references) do
            local folder = animate:FindFirstChild(pair[1])
            local clip = folder and folder:FindFirstChild(pair[2])
            if clip and clip:IsA("Animation") then
                local desired = v54.packAssetId(pack[action], index)
                if desired then
                    if original[clip] == nil then original[clip] = clip.AnimationId end
                    if clip.AnimationId == desired then
                        same += 1
                    else
                        if action == "Walk" or action == "Run" or action == "Idle"
                            or action == "Jump" or action == "Fall" then
                            oldLocomotion[clip.AnimationId] = true
                        end
                        local ok = pcall(function() clip.AnimationId = desired end)
                        if ok then updated += 1 else errors += 1 end
                    end
                end
            else
                missing += 1
            end
        end
    end
    if updated + same == 0 then
        v54.updatePackStatus(name .. ": no compatible Animate clip slots found")
        return false
    end
    v54.selectedAnimationPack = name
    -- Prevent currently playing old locomotion tracks from masking new
    -- animation IDs. Do not stop tool attacks or unrelated emotes.
    pcall(function()
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            local id = track.Animation and track.Animation.AnimationId
            if (id and oldLocomotion[id])
                or track.Priority == Enum.AnimationPriority.Core
                or track.Priority == Enum.AnimationPriority.Idle
                or track.Priority == Enum.AnimationPriority.Movement then
                track:Stop(0.1)
            end
        end
    end)
    v54.restartAnimate(character)
    local message = name .. " / " .. rig .. ": " .. updated
        .. " new clip IDs set; " .. same .. " already selected; "
        .. errors .. " errors. Game may override animations."
    v54.updatePackStatus(message)
    if not quiet then inform(message) end
    task.delay(1.5, function()
        if destroyed or sequence ~= v54.animationPackSequence
            or localPlayer.Character ~= character then return end
        local changedBack, stillSet = 0, 0
        for action, references in pairs(v54.packReferences) do
            for index, pair in ipairs(references) do
                local folder = animate:FindFirstChild(pair[1])
                local clip = folder and folder:FindFirstChild(pair[2])
                local desired = v54.packAssetId(pack[action], index)
                if clip and clip:IsA("Animation") and desired then
                    if clip.AnimationId == desired then
                        stillSet += 1
                    else
                        changedBack += 1
                    end
                end
            end
        end
        if changedBack > 0 then
            v54.updatePackStatus(name .. ": " .. changedBack
                .. " clip(s) changed by MM2's Animate system. "
                .. "Local override may be unsupported in this round.")
        else
            v54.updatePackStatus(name .. ": " .. stillSet
                .. " IDs remain installed. Use CHECK PLAYING CLIPS to see "
                .. "which animations actually run.")
        end
    end)
    return true
end
v54.reportPlayingAnimations = function()
    local hum = humanOf(localPlayer)
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then return inform("No Animator on the current character") end
    local output = {}
    local tracks = animator:GetPlayingAnimationTracks()
    for _, track in ipairs(tracks) do
        local id = track.Animation and track.Animation.AnimationId or "unknown"
        table.insert(output, tostring(id) .. " (" .. track.Priority.Name
            .. ", " .. (track.IsPlaying and "playing" or "stopped") .. ")")
        if #output >= 6 then break end
    end
    local message = #output > 0 and table.concat(output, " | ")
        or "No animation tracks currently playing"
    v54.updatePackStatus("Live tracks: " .. message)
    inform("Live animation IDs printed to executor console")
    print("[SPECTRA ANIMS] " .. message)
end
-- Emergency fallback if an older hub already replaced movement IDs without saving
-- originals. Use the avatar's own description, never unknown copied bundle IDs.
v54.recoverAvatarAnimations = function()
    local character = localPlayer.Character
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    local animate = character and character:FindFirstChild("Animate")
    if not hum or not animate then
        return inform("Cannot recover: missing character/Humanoid/Animate")
    end
    local ok, desc = pcall(function() return hum:GetAppliedDescription() end)
    if not ok or not desc then
        return inform("Avatar animation description unavailable; try respawning")
    end
    local recovered = 0
    for action, references in pairs(v54.packReferences) do
        local valid, id = pcall(function() return desc[action .. "Animation"] end)
        if valid and type(id) == "number" and id > 0 then
            for _, pair in ipairs(references) do
                local folder = animate:FindFirstChild(pair[1])
                local clip = folder and folder:FindFirstChild(pair[2])
                if clip and clip:IsA("Animation") then
                    if pcall(function() clip.AnimationId = "rbxassetid://" .. tostring(id) end) then
                        recovered += 1
                    end
                end
            end
        end
    end
    if recovered > 0 then
        v54.animationPackOriginals[character] = nil
        v54.selectedAnimationPack = "Default"
        v54.animationPackSequence += 1
        v54.restartAnimate(character)
    end
    local message = recovered > 0
        and ("Restored " .. recovered .. " avatar-description clips; some games override these")
        or "No avatar animation IDs available; try character reset/respawn"
    v54.updatePackStatus(message)
    inform(message)
end
heading(pages["ANIMS"], "MOVEMENT PACKS • RIG MATCH ONLY")
v54.animationRigLabel = label(pages["ANIMS"], "Detecting character rig...", 80,
    Color3.fromRGB(184,209,245), 12)
v54.animationPackButtons = {}
v54.refreshAnimationRigButtons = function()
    local rig = v54.animationRigName()
    if v54.animationRigLabel and v54.animationRigLabel.Parent then
        v54.animationRigLabel.Text = "Detected body: " .. rig
            .. ". Only matching packs are shown. Use CHECK PLAYING to verify."
    end
    for name, button in pairs(v54.animationPackButtons) do
        local pack = v54.animationPacks[name]
        if button and button.Parent then button.Visible = pack and pack.Rig == rig end
    end
    for _, entry in ipairs(v54.catalogPreviewButtons or {}) do
        if entry.button and entry.button.Parent then
            entry.button.Visible = entry.rig == rig
        end
    end
end
for _, packName in ipairs({
    "R6 Free", "R15 Classic", "R6 Style on R15", "Rthro",
    "Astronaut","Bubbly","Cartoony","Elder","Knight","Levitation",
    "Mage","Ninja","Pirate","Robot","Stylish","Superhero",
    "Toy","Vampire","Werewolf","Zombie"
}) do
    local name = packName
    v54.animationPackButtons[name] = makeButton(pages["ANIMS"],
        "APPLY " .. name:upper() .. " PACK", function()
            if v54.animationRigName() ~= v54.animationPacks[name].Rig then
                return inform("Wrong rig: " .. name .. " requires "
                    .. v54.animationPacks[name].Rig)
            end
            v54.stopAnimationPreview()
            v54.applyAnimationPack(name, false)
        end)
end
v54.refreshAnimationRigButtons()
makeButton(pages["ANIMS"], "CHECK PLAYING ANIMATIONS (actual IDs)", function()
    v54.reportPlayingAnimations()
end)
label(pages["ANIMS"], "Pack IDs are applied immediately; the game may override them and some assets may require permission. An animation changes appearance, not the character's physical movement speed.", 95,
    Color3.fromRGB(196,216,245), 12)
makeButton(pages["ANIMS"], "EMERGENCY RESTORE original animations", function()
    v54.restoreAnimationPack(false)
end)
makeButton(pages["ANIMS"], "RECOVER animations from avatar", function()
    v54.recoverAvatarAnimations()
end)
v54.animationPackStatusLabel = label(pages["ANIMS"], v54.animationPackStatus, 65,
    Color3.fromRGB(163, 225, 255), 12)

heading(pages["ANIMS"], "EMOTES & ANIMATION PREVIEW")
label(pages["ANIMS"], "Play an emote equipped by your avatar or preview a permitted animation ID. Unsupported/unowned assets will fail without changing your inventory.",
    94, Color3.fromRGB(190, 216, 246), 13)
v54.stopAnimationPreview = function()
    if v54.animationTrack then
        pcall(function() v54.animationTrack:Stop(0.12); v54.animationTrack:Destroy() end)
        v54.animationTrack = nil
    end
    if v54.animationAsset then
        pcall(function() v54.animationAsset:Destroy() end)
        v54.animationAsset = nil
    end
end
v54.playEmote = function(name)
    local humanoid = humanOf(localPlayer)
    if not humanoid then return inform("Character not loaded") end
    v54.stopAnimationPreview()
    task.spawn(function()
        local ok, played = pcall(function() return humanoid:PlayEmoteAsync(name) end)
        v54.animationStatus = ok and played and ("Emote playing: " .. name)
            or ("Emote " .. name .. " not available on this avatar")
        if not destroyed then inform(v54.animationStatus) end
    end)
end
for _, emote in ipairs({"wave", "cheer", "dance", "dance2", "dance3", "laugh", "point"}) do
    local name = emote
    makeButton(pages["ANIMS"], "Emote: " .. name:upper(), function()
        v54.playEmote(name)
    end)
end
heading(pages["ANIMS"], "CUSTOM ASSET ID")
v54.assetBox = Instance.new("TextBox")
v54.assetBox.Name = "AnimationIdInput"
v54.assetBox.Size = UDim2.new(1, -4, 0, 46)
v54.assetBox.BackgroundColor3 = Color3.fromRGB(34, 41, 55)
v54.assetBox.TextColor3 = Color3.fromRGB(244, 250, 255)
v54.assetBox.PlaceholderColor3 = Color3.fromRGB(163, 183, 211)
v54.assetBox.PlaceholderText = "Animation ID (digits only)"
v54.assetBox.Text = ""
v54.assetBox.ClearTextOnFocus = false
v54.assetBox.Font = Enum.Font.Gotham
v54.assetBox.TextSize = 15
v54.assetBox.Parent = pages["ANIMS"]
round(v54.assetBox, 8)
v54.previewButton = nil
v54.previewButton = makeButton(pages["ANIMS"], "PREVIEW animation ID", function()
    local digits = v54.assetBox.Text:match("^%s*(%d+)%s*$")
    if not digits or #digits > 20 then return inform("Enter a numeric animation asset ID") end
    local humanoid = humanOf(localPlayer)
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator then return inform("Character Animator is not available") end
    v54.stopAnimationPreview()
    local asset = Instance.new("Animation")
    asset.AnimationId = "rbxassetid://" .. digits
    local ok, track = pcall(function() return animator:LoadAnimation(asset) end)
    if not ok or not track then
        asset:Destroy()
        return inform("Animation could not load: asset may not be accessible")
    end
    v54.animationAsset = asset
    v54.animationTrack = track
    track.Priority = Enum.AnimationPriority.Action
    track.Looped = false
    local played, err = pcall(function() track:Play(0.12, 1, v54.animationSpeed) end)
    v54.animationStatus = played and ("Preview request for " .. digits .. " at " .. v54.animationSpeed .. "x")
        or ("Preview error: " .. tostring(err):sub(1, 72))
    inform(v54.animationStatus)
    task.delay(1.6, function()
        if destroyed or v54.animationTrack ~= track then return end
        if track.Length <= 0 then
            v54.animationStatus = "Preview " .. digits
                .. " did NOT load. Asset may be private, unavailable, or wrong rig."
        else
            v54.animationStatus = "Preview " .. digits .. " loaded ("
                .. string.format("%.2f",track.Length) .. "s); movements are visual only."
        end
        if v54.animationStatusLabel and v54.animationStatusLabel.Parent then
            v54.animationStatusLabel.Text = v54.animationStatus
        end
    end)
end)
-- Catalog previews use the supplied IDs, but do NOT claim asset ownership.
-- They are only visible on the rig these clips were authored for.
v54.catalogPreviewButtons = {}
v54.catalogPreviewEntries = {
    {"R6", "R6 WAVE", 128777973},
    {"R6", "R6 POINT", 128853357},
    {"R6", "R6 DANCE 1", 182435998},
    {"R6", "R6 DANCE 2", 182436842},
    {"R6", "R6 DANCE 3", 182436935},
    {"R6", "R6 LAUGH", 129423131},
    {"R6", "R6 CHEER", 129423030},
    -- Additional built-in R6 transition clips (separate from looping tracks).
    {"R6", "R6 IDLE 1 TRANSITION", 125750544},
    {"R6", "R6 IDLE 2 TRANSITION", 125750618},
    {"R6", "R6 WALK TRANSITION", 125749145},
    {"R6", "R6 FALL TRANSITION", 125750759},
    {"R6", "R6 CLIMB TRANSITION", 125750800},
    {"R6", "R6 TOOL TRANSITION", 125750867},
    {"R15", "CLASSIC WAVE", 507770239},
    {"R15", "CLASSIC POINT", 507770453},
    {"R15", "CLASSIC DANCE 1", 507771019},
    {"R15", "CLASSIC DANCE 2", 507776043},
    {"R15", "CLASSIC DANCE 3", 507777268},
    {"R15", "CATALOG HELLO", 3576686446},
    {"R15", "CATALOG SHRUG", 3576968026},
    {"R15", "CATALOG POINT 2", 3576823880},
    {"R15", "CATALOG STADIUM", 3360686498},
    {"R15", "CATALOG SALUTE", 3360689775},
    {"R15", "CATALOG TILT", 3360692915},
    {"R15", "CATALOG APPLAUD", 5915779043},
    {"R15", "R6 STYLE NINJA DASH", 13978512316},
    {"R15", "R6 STYLE NINJA SLASH", 13978507503},
    {"R15", "R6 STYLE DUAL SLASH", 13978510688},
    {"R15", "R6 STYLE SWORD PUMP", 13978511071},
    {"R15", "R6 STYLE SWORD JUMP", 13978511543},
    {"R15", "R6 STYLE SWORD THRUST", 13978511983},
    {"R15", "R6 STYLE TWO HAND SWORD", 13978504790}
}
heading(pages["ANIMS"], "RIG-COMPATIBLE PREVIEW IDS")
label(pages["ANIMS"], "Includes standard Roblox animations, catalog emotes, and extra R6 transitions. Only IDs matching your current rig appear; other creators' assets may still need permission.", 100,
    Color3.fromRGB(185,207,237), 12)
for _, item in ipairs(v54.catalogPreviewEntries) do
    local rig, title, id = item[1], item[2], item[3]
    local control = makeButton(pages["ANIMS"], "SELECT " .. title, function()
        if v54.animationRigName() ~= rig then
            return inform("Preview only supports the " .. rig .. " avatar rig")
        end
        v54.assetBox.Text = tostring(id)
        inform(title .. " selected • tap PREVIEW animation ID")
    end)
    table.insert(v54.catalogPreviewButtons, {rig=rig, button=control})
end
v54.refreshAnimationRigButtons()
heading(pages["ANIMS"], "QUICK PREVIEW IDS (R15)")
label(pages["ANIMS"], "These select standard Roblox R15 animation asset IDs. Tap PREVIEW above to play; assets may still be blocked by the experience.",
    78, Color3.fromRGB(184, 205, 240), 12)
-- The formerly unfiltered R15 quick previews are provided in the
-- rig-compatible list above. R6 users do not see incompatible choices.
makeButton(pages["ANIMS"], "Cycle preview speed: 1x / 1.5x / 0.75x", function()
    if v54.animationSpeed == 1 then v54.animationSpeed = 1.5
    elseif v54.animationSpeed == 1.5 then v54.animationSpeed = 0.75
    else v54.animationSpeed = 1 end
    if v54.animationTrack then
        pcall(function() v54.animationTrack:AdjustSpeed(v54.animationSpeed) end)
    end
    inform("Animation preview speed: " .. v54.animationSpeed .. "x")
end)
makeButton(pages["ANIMS"], "STOP animation preview", function()
    v54.stopAnimationPreview()
    inform("Custom preview stopped")
end)
v54.animationStatusLabel = label(pages["ANIMS"], "Status: ready", 74,
    Color3.fromRGB(180, 214, 250), 12)
label(pages["ANIMS"], "Extra free avatar emotes are available if your avatar has them equipped. Animation previews cannot grant ownership or change inventory.",
    74, Color3.fromRGB(180, 210, 245), 12)
end
-- Controller menu navigation: Y/Triangle toggles the menu; B/Circle minimizes.
-- D-pad left/right changes categories, up/down moves between visible controls,
-- and A/Cross activates the selected button via Roblox GuiButton.Activated.
do
v54.focusMenuControl = function(direction)
    if minimized or destroyed then return end
    local page = pages[v54.activeTab]
    if not page then return end
    local controls = {}
    for _, element in ipairs(page:GetDescendants()) do
        if element:IsA("GuiButton") and element.Selectable then
            local shown = true
            local parent = element
            while parent and parent ~= page do
                if parent:IsA("GuiObject") and not parent.Visible then
                    shown = false
                    break
                end
                parent = parent.Parent
            end
            if shown then table.insert(controls, element) end
        end
    end
    table.sort(controls, function(a, b)
        if a.AbsolutePosition.Y == b.AbsolutePosition.Y then
            return a.AbsolutePosition.X < b.AbsolutePosition.X
        end
        return a.AbsolutePosition.Y < b.AbsolutePosition.Y
    end)
    if #controls == 0 then
        GuiService.SelectedObject = tabButtons[v54.activeTab]
        return
    end
    local index = 0
    for i, obj in ipairs(controls) do
        if GuiService.SelectedObject == obj then index = i; break end
    end
    if index == 0 then index = direction < 0 and #controls + 1 or 0 end
    local nextIndex = math.clamp(index + direction, 1, #controls)
    local focused = controls[nextIndex]
    GuiService.SelectedObject = focused
    local offsetY = focused.AbsolutePosition.Y - page.AbsolutePosition.Y + page.CanvasPosition.Y
    local maxScroll = math.max(0, page.AbsoluteCanvasSize.Y - page.AbsoluteSize.Y)
    page.CanvasPosition = Vector2.new(page.CanvasPosition.X,
        math.clamp(offsetY - 14, 0, maxScroll))
end
v54.cycleMenuTab = function(direction)
    local index = table.find(v54.tabOrder, v54.activeTab) or 1
    local nextIndex = ((index - 1 + direction) % #v54.tabOrder) + 1
    v54.activateTab(v54.tabOrder[nextIndex])
    v54.focusMenuControl(1)
end
watch(UserInputService.InputBegan:Connect(function(input, processed)
    if destroyed or not v54.isGamepadInput(input) then return end
    local key = input.KeyCode
    if key == Enum.KeyCode.ButtonY then
        v54.gamepadMenuMode = true
        setWindowOpen(minimized)
        if not minimized then v54.focusMenuControl(1) end
        return
    end
    if minimized then return end
    local selected = GuiService.SelectedObject
    local adjustSlider = selected and v54.sliderControllers[selected]
    if adjustSlider and (key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.DPadRight) then
        adjustSlider(key == Enum.KeyCode.DPadRight and 1 or -1)
        v54.lastGamepadInput = "Value bar adjusted using D-pad"
        return
    end
    if key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.DPadRight then
        v54.gamepadMenuMode = true
    end
    if not v54.gamepadMenuMode then return end
    if key == Enum.KeyCode.ButtonB then
        setWindowOpen(false)
        v54.gamepadMenuMode = false
    elseif key == Enum.KeyCode.DPadLeft then
        v54.cycleMenuTab(-1)
    elseif key == Enum.KeyCode.DPadRight then
        v54.cycleMenuTab(1)
    end
    -- Let Roblox handle ButtonA GuiButton.Activated for the focused button.
end))
end
-- Settings page -------------------------------------------------------
heading(settingsPage, "INTERFACE & ACCESSIBILITY")
label(settingsPage, "Compact mode fits more controls; Touch mode increases tap targets. Use the section arrows above to switch tab groups.",
    56, Color3.fromRGB(190, 217, 247), 12)
v54.uiDensityButton = makeButton(settingsPage, "Control size: COMPACT (tap to change)", function()
    v54.setUIDensity(v54.uiDensity == "COMPACT" and "TOUCH" or "COMPACT")
    inform("Control size: " .. v54.uiDensity)
end)
makeButton(settingsPage, "Jump to HOME dashboard", function() v54.activateTab("HOME") end)
heading(settingsPage, "VISUAL SETTINGS")
toggle(settingsPage, "Ghosted avatar (only on MY screen)", "LocalGhost", setLocalGhost)
toggle(settingsPage, "Fullbright", "Fullbright", v54.setFullbright)
toggle(settingsPage, "Remove fog and atmosphere haze", "NoFog", v54.setNoFog)
toggle(settingsPage, "Hide my overhead name (local)", "HideOwnName", v54.setHideOwnName)
toggle(settingsPage, "Reduce sliding on ice (local)", "AntiSlip")
toggle(settingsPage, "Disable post-processing FX", "LowFX", v54.setLowFX)
toggle(settingsPage, "Anti-void (experimental)", "AntiVoid")
heading(settingsPage, "ROUND RESULTS")
label(settingsPage, "Auto-hide is ON by default and also recognizes the large +XP progress-bar overlay shown after a round. It avoids Roblox CoreGui and the regular game HUD. Turn OFF if a legitimate reward panel should remain.",
    67, Color3.fromRGB(192, 217, 242), 12)
toggle(settingsPage, "AUTO-HIDE round results", "AutoHideRoundResults", function(on)
    if on then v54.clearRoundResults(false)
    else v54.roundResultManualUntil = 0 end
    inform("Auto-hide round results: " .. (on and "ON" or "OFF"))
end)
makeButton(settingsPage, "CLEAR STUCK RESULT SCREEN NOW", function()
    v54.manualClearRoundResults()
end)
v54.roundResultStatusLabel = label(settingsPage, v54.roundResultNotice, 45,
    Color3.fromRGB(168, 216, 242), 12)
makeButton(settingsPage, "Reset gravity", function()
    Workspace.Gravity = previousGravity
    numbers.Gravity = previousGravity
    v54.refreshSliders()
    inform("Gravity restored")
end)
makeSlider(settingsPage, "LOCAL GRAVITY", "Gravity", 30, 300, 1, "", function(value)
    Workspace.Gravity = value
end)
heading(settingsPage, "SAVED SETTINGS")
label(settingsPage, "Save preferences for next session. Uses executor readfile/writefile when supported; otherwise only this executor session is remembered. Active farming, shooting, fling and flight are NEVER auto-enabled on load.",
    112, Color3.fromRGB(191, 213, 245), 12)
v54.settingsFile = "SPECTRA_MM2_settings_v5_9.json"
v54.safeActive = {
    AutoCoinFarm = true, AutoGunPickup = true, AutoGunApproach = true,
    AutoShootMurderer = true, SilentAim = true, AutoSilentShot = true, SheriffRapidFire = true,
    CoinTeleport = true, CoinFlight = true, MurderAura = true, MurderAuraApproach = true, FlingActive = true, Fly = true, SpinMode = true,
    CameraLock = true, Sprint = true, Noclip = true, AutoAimMurderer = true,
}
v54.settingsSnapshot = function()
    local toggles, sliders = {}, {}
    for key, default in pairs(v54.defaultEnabled) do
        if type(default) == "boolean" and not v54.safeActive[key] then
            toggles[key] = enabled[key]
        end
    end
    for key, default in pairs(v54.defaultNumbers) do
        if type(default) == "number" then sliders[key] = numbers[key] end
    end
    return {version = 4, toggles = toggles, numbers = sliders,
        postFarmMode = v54.postFarmMode,
        resetAt40Enabled = v54.resetAt40Enabled,
        animationPack = v54.selectedAnimationPack,
        uiDensity = v54.uiDensity}
end
v54.saveSettings = function()
    local snapshot = v54.settingsSnapshot()
    environment.SpectraSessionPreferences = snapshot
    local persisted = false
    local message = "Saved for this executor session"
    if type(writefile) == "function" then
        local ok, err = pcall(function()
            writefile(v54.settingsFile, game:GetService("HttpService"):JSONEncode(snapshot))
        end)
        if ok then persisted = true; message = "Saved to " .. v54.settingsFile
        else message = "Session only; file write: " .. tostring(err):sub(1, 50) end
    end
    v54.settingsStatus = message
    if v54.settingsStatusLabel then v54.settingsStatusLabel.Text = message end
    inform(message)
    return persisted
end
v54.loadSettings = function(quiet)
    local snapshot = nil
    local source = "session"
    if type(readfile) == "function" then
        local ok, result = pcall(function()
            return game:GetService("HttpService"):JSONDecode(readfile(v54.settingsFile))
        end)
        if ok and type(result) == "table" then snapshot = result; source = "file" end
    end
    if not snapshot and type(environment.SpectraSessionPreferences) == "table" then
        snapshot = environment.SpectraSessionPreferences
    end
    if not snapshot or type(snapshot.toggles) ~= "table" or type(snapshot.numbers) ~= "table" then
        v54.settingsStatus = "No saved configuration found"
        if v54.settingsStatusLabel then v54.settingsStatusLabel.Text = v54.settingsStatus end
        if not quiet then inform(v54.settingsStatus) end
        return false
    end
    for key, value in pairs(snapshot.toggles) do
        if type(v54.defaultEnabled[key]) == "boolean" and not v54.safeActive[key]
            and type(value) == "boolean" then enabled[key] = value end
    end
    -- Older saved settings inherited auto-hide OFF from v9.0 defaults.
    -- Migrate ON once for the new XP-overlay fix. v9.1 user opt-outs
    -- stay OFF after they save the new version-4 preferences.
    if not snapshot.version or snapshot.version < 4 then
        enabled.AutoHideRoundResults = true
    end
    for key, value in pairs(snapshot.numbers) do
        if type(v54.defaultNumbers[key]) == "number" and type(value) == "number"
            and value == value and math.abs(value) < 10000 then
            numbers[key] = value
        end
    end
    v54.setUIDensity(snapshot.uiDensity)
    numbers.FarmVisitCap = math.clamp(math.floor(numbers.FarmVisitCap), 10, 100)
    if snapshot.postFarmMode == "notify" or snapshot.postFarmMode == "role" then
        v54.postFarmMode = snapshot.postFarmMode
    end
    v54.resetAt40Enabled = snapshot.resetAt40Enabled == true
    if v54.resetAt40Button then
        v54.resetAt40Button.Text = v54.resetAt40Enabled
            and "Innocent reset at 40 VISITS: ON" or "Innocent reset at 40 VISITS: OFF"
    end
    -- v5.9 stored an obsolete 20-visit default. New users start at 40.
    if (not snapshot.version or snapshot.version < 3)
        and numbers.FarmVisitCap == 20 then
        numbers.FarmVisitCap = 40
    end
    if v54.postFarmModeButton then
        v54.postFarmModeButton.Text = v54.postFarmMode == "role"
            and "After farm: ROLE ACTIONS (experimental)" or "After farm: NOTIFY ONLY"
    end
    numbers.FarmFlySpeed = math.clamp(numbers.FarmFlySpeed, 10, 100)
    numbers.FarmTeleportDelay = math.clamp(numbers.FarmTeleportDelay, 1, 8)
    numbers.AimSmooth = math.clamp(numbers.AimSmooth, 0.1, 1)
    numbers.KnifeAuraRadius = math.clamp(numbers.KnifeAuraRadius, 5, 35)
    numbers.Speed = math.clamp(numbers.Speed, 8, 36)
    numbers.FarmFlySpeed = math.clamp(numbers.FarmFlySpeed, 10, 30)
    numbers.FarmRadius = math.clamp(numbers.FarmRadius, 100, 1800)
    numbers.SheriffFrontDistance = math.clamp(numbers.SheriffFrontDistance, 8, 30)
    numbers.Gravity = math.clamp(numbers.Gravity, 30, 300)
    Workspace.Gravity = numbers.Gravity
    -- Never restore automation as active after reload.
    for key in pairs(v54.safeActive) do
        if type(enabled[key]) == "boolean" then enabled[key] = false end
    end
    enabled.CoinFlight = enabled.CoinFlight or false
    if enabled.CoinFlight then enabled.CoinTeleport = false end
    -- Asset permissions can change. Do not silently alter movement clips on load.
    -- Remember the preference, but require a deliberate pack test after launch.
    if type(snapshot.animationPack) == "string" and v54.animationPacks[snapshot.animationPack] then
        v54.lastSavedPack = snapshot.animationPack
        v54.updatePackStatus("Saved pack: " .. snapshot.animationPack ..
            " (not auto-applied; tap APPLY to validate safely)")
    elseif snapshot.animationPack == "Default" then
        v54.lastSavedPack = "Default"
    end
    applyCharacterSettings()
    v54.setFullbright(enabled.Fullbright)
    v54.setNoFog(enabled.NoFog)
    v54.setLowFX(enabled.LowFX)
    v54.setHideOwnName(enabled.HideOwnName)
    setLocalGhost(enabled.LocalGhost)
    if v54.updateFlyHUD then v54.updateFlyHUD() end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    v54.refreshSliders()
    v54.settingsStatus = "Settings loaded (" .. source .. ")"
    if v54.settingsStatusLabel then v54.settingsStatusLabel.Text = v54.settingsStatus end
    if not quiet then inform(v54.settingsStatus) end
    return true
end
v54.resetSavedDefaults = function()
    v54.farmTravelToken += 1
    v54.postActionToken += 1
    stopFly()
    restoreNoclip()
    for key, value in pairs(v54.defaultEnabled) do enabled[key] = value end
    for key, value in pairs(v54.defaultNumbers) do numbers[key] = value end
    if v54.restoreAnimationPack then v54.restoreAnimationPack(true) end
    v54.postFarmMode = "notify"
    v54.setUIDensity("COMPACT")
    v54.resetAt40Enabled = false
    if v54.resetAt40Button then v54.resetAt40Button.Text = "Innocent reset at 40 VISITS: OFF" end
    if v54.postFarmModeButton then
        v54.postFarmModeButton.Text = "After farm: NOTIFY ONLY"
    end
    if v54.updateFlyHUD then v54.updateFlyHUD() end
    -- Defaults do not launch any action.
    enabled.AutoCoinFarm, enabled.Fly, enabled.FlingActive = false, false, false
    v54.setFullbright(false)
    v54.setNoFog(false)
    v54.setLowFX(false)
    v54.setHideOwnName(false)
    setLocalGhost(false)
    applyCharacterSettings()
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    v54.settingsStatus = "Factory defaults loaded; tap SAVE to persist"
    if v54.settingsStatusLabel then v54.settingsStatusLabel.Text = v54.settingsStatus end
    inform(v54.settingsStatus)
end
makeButton(settingsPage, "SAVE SETTINGS to device / session", function() v54.saveSettings() end)
makeButton(settingsPage, "LOAD saved settings now", function() v54.loadSettings(false) end)
makeButton(settingsPage, "RESTORE DEFAULTS (doesn't erase file)", function() v54.resetSavedDefaults() end)
v54.settingsStatusLabel = label(settingsPage, v54.settingsStatus, 60, Color3.fromRGB(165, 220, 248), 13)
heading(settingsPage, "Session")
label(settingsPage, "Tap the X or − to minimize into the floating SPECTRA icon. Drag that icon anywhere and tap it to reopen. Everything stays active until you fully unload.", 91, Color3.fromRGB(193, 218, 250), 14)
makeButton(settingsPage, "Minimize to floating icon", function()
    setWindowOpen(false)
end)
-- Full cleanup is intentionally separate and requires two taps.
v54.performFullUnload = function() inform("Unload is not ready") end
v54.unloadConfirmDeadline = 0
v54.unloadControl = nil
v54.unloadControl = makeButton(settingsPage, "FULLY UNLOAD SPECTRA (tap twice)", function()
    if os.clock() < v54.unloadConfirmDeadline then
        v54.performFullUnload()
        return
    end
    v54.unloadConfirmDeadline = os.clock() + 5
    v54.unloadControl.Text = "CONFIRM UNLOAD • tap again within 5 sec"
    inform("Tap again to remove ESP, GUI and local effects")
    task.delay(5, function()
        if not destroyed and v54.unloadControl and v54.unloadControl.Parent
            and os.clock() >= v54.unloadConfirmDeadline then
            v54.unloadControl.Text = "FULLY UNLOAD SPECTRA (tap twice)"
        end
    end)
end)
v54.unloadControl.BackgroundColor3 = Color3.fromRGB(98, 37, 52)
makeButton(settingsPage, "Show player count", function()
    inform("Players in server: " .. #Players:GetPlayers())
end)
makeButton(settingsPage, "Rejoin this place", function()
    if RunService:IsStudio() then inform("Rejoin isn't available in Studio playtest") return end
    local ok, err = pcall(function() TeleportService:Teleport(game.PlaceId, localPlayer) end)
    if not ok then inform("Rejoin failed: " .. tostring(err):sub(1, 60)) end
end)
label(settingsPage, "Role radar reads game-reported data only when MM2 exposes it. " ..
    "Features here run on your client; teleports and movement may be server-corrected. " ..
    "No remote kill-all, forced wins, or trade manipulation.",
    85, Color3.fromRGB(180, 193, 213), 12)


-- Diagnostics: these are capability/observation checks, not server guarantees.
heading(diagnosticsPage, "LIVE STATUS & DIAGNOSTICS")
label(diagnosticsPage, "Shows what is observable on this client. A green script status does not verify MM2 rewards, remote attacks, or trading.", 78, Color3.fromRGB(215, 224, 242), 14)
do
v54.diagRole = label(diagnosticsPage, "Role data: checking...", 55, Color3.fromRGB(190, 214, 245), 14)
v54.diagFarm = label(diagnosticsPage, "Farm: waiting", 66, Color3.fromRGB(190, 214, 245), 14)
v54.diagWorld = label(diagnosticsPage, "Players/markers: waiting", 90, Color3.fromRGB(190, 214, 245), 14)
v54.diagMisc = label(diagnosticsPage, "Controls: waiting", 112, Color3.fromRGB(190, 214, 245), 14)
refreshDiagnostics = function()
    if destroyed then return end
    local reported = os.clock() - roleLastUpdate < 12
    v54.diagRole.Text = "Role feed: " .. (reported and "game data recently received" or "unavailable/stale")
        .. "\n" .. roleSyncMessage
    v54.diagFarm.Text = "Farm: " .. (enabled.AutoCoinFarm and "ON" or "OFF")
        .. "  |  mode: " .. (enabled.CoinFlight and "fly" or enabled.CoinTeleport and "teleport" or "walk")
        .. "  |  fly: " .. numbers.FarmFlySpeed .. "  tp delay: " .. numbers.FarmTeleportDelay .. "s"
        .. "  |  attempts: " .. farmAttempts .. "  |  skipped: " .. farmSkipped
        .. "\nThese are NOT confirmed currency pickups"
    local playerCount = #Players:GetPlayers() - 1
    local markers = 0
    for _ in pairs(objectEffects) do markers += 1 end
    local selected = selectedPlayer and selectedPlayer.Name or "none"
    local playerDistance = selectedPlayer and rootOf(selectedPlayer) and distanceTo(rootOf(selectedPlayer))
    v54.diagWorld.Text = "Other players: " .. math.max(playerCount, 0)
        .. "  |  marked objects: " .. markers
        .. "\nSelected: " .. selected .. (playerDistance and ("  •  " .. math.floor(playerDistance) .. " studs") or "")
        .. "\nGun alerts: " .. (enabled.GunAlerts and enabled.GunAlertMessage or "OFF")
        .. "\nGun pickup: " .. v54.gunPickupStatus
    v54.diagMisc.Text = "Fly HUD: " .. (enabled.Fly and "ON" or "OFF") .. " (joystick + ▲/▼)"
        .. "  |  speed: " .. numbers.FlySpeed .. "\n"
        .. "Aim: " .. ((enabled.AimAssist or enabled.AutoAimMurderer) and "ON" or "OFF")
        .. "  |  auto shoot: " .. (enabled.AutoShootMurderer and "ON" or "OFF")
        .. "  |  shot requests: " .. shotAttemptCount
        .. "\n" .. shotNotice .. "\n" .. flingNotice
end
makeButton(diagnosticsPage, "Refresh role feed", function()
    lastRoleFetch = os.clock()
    refreshRoles()
    inform("Role refresh requested")
end)
makeButton(diagnosticsPage, "Rescan nearby markers", function()
    scanObjects()
    farmLastScan = 0
    scanFarmTargets()
    inform("Marker rescan complete")
end)
makeButton(diagnosticsPage, "STOP all automation and camera assist", function()
    enabled.AutoCoinFarm = false
    enabled.AutoGunApproach = false
    enabled.AutoGunPickup = false
    v54.postActionToken += 1
    v54.stopRoleActions()
    enabled.AimAssist = false
    enabled.AutoAimMurderer = false
    enabled.AutoShootMurderer = false
    v54.sheriffFrontArmed = false
    enabled.CameraLock = false
    enabled.SpinMode = false
    enabled.FlingActive = false
    flingToken += 1
    v54.flingAllToken += 1
    v54.flingAllActive = false
    local hum, root = humanOf(localPlayer), rootOf(localPlayer)
    if hum and root then hum:MoveTo(root.Position) end
    if root then root.AssemblyAngularVelocity = Vector3.zero end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
    inform("Automation stopped")
end)
label(diagnosticsPage, "Not implemented or verified: guaranteed knife eliminations, silent hit redirection, god mode, forced wins, auto trades/buys/crafting, bag resets, Discord webhooks, multi-account sync, server hopping or FPS unlock. Role actions only activate equipped tools; MM2 may reject them.", 210, Color3.fromRGB(255, 206, 178), 13)
end

-- Controlled farm scheduler; each attempt can be canceled immediately.
-- Visits and teleports are NOT server-confirmed currency earnings.
task.spawn(function()
    while not destroyed do
        task.wait(0.35)
        if destroyed then break end
        local own, hum = rootOf(localPlayer), humanOf(localPlayer)
        if not v54.gunPickupBusy and own and hum and hum.Health > 0 and (enabled.AutoCoinFarm or enabled.AutoGunApproach) then
            if enabled.AutoCoinFarm then
                if v54.farmFlightBusy then
                    farmNotice = v54.farmTravelDetail
                elseif v54.resetAt40Enabled and farmAttempts >= 40 then
                    hum:MoveTo(own.Position)
                    v54.finishFarm("40 visited positions")
                elseif enabled.FarmVisitLimit and farmAttempts >= numbers.FarmVisitCap then
                    hum:MoveTo(own.Position)
                    v54.finishFarm("visit limit reached")
                else
                    local target, dist = getNearestFarmCoin()
                    if target and target.Parent then
                        v54.postFarmIdleSince = nil
                        if target ~= farmFocus then
                            farmFocus, farmFocusStart, farmProgressDistance = target, os.clock(), dist
                        end
                        if dist < farmProgressDistance - 1.5 then
                            farmProgressDistance = dist
                            farmFocusStart = os.clock()
                        end
                        if dist < 2.6 then
                            farmVisited[target] = os.clock()
                            farmAttempts += 1
                            farmFocus = nil
                            farmNotice = "Reached target • pickup not verified"
                        elseif os.clock() - farmFocusStart > 6 then
                            farmVisited[target] = os.clock()
                            farmSkipped += 1
                            farmFocus = nil
                            farmNotice = "Skipped stuck or unreachable target"
                        elseif enabled.CoinFlight then
                            beginCoinFlight(target)
                            farmNotice = "Starting through-wall flight to coin"
                        elseif enabled.CoinTeleport then
                            local secondsLeft = numbers.FarmTeleportDelay - (os.clock() - v54.lastCoinTeleportAt)
                            if secondsLeft > 0 then
                                farmNotice = string.format("Teleport cooldown %.1fs (server position still unverified)", secondsLeft)
                            else
                                v54.lastCoinTeleportAt = os.clock()
                                local ok = pcall(function()
                                    own.CFrame = CFrame.new(target.Position + Vector3.new(0, 0.6, 0))
                                    own.AssemblyLinearVelocity = Vector3.zero
                                end)
                                farmNotice = ok and "Teleport visited coin position • verifying proximity" or "Teleport request failed"
                            end
                        else
                            hum:MoveTo(target.Position)
                            farmNotice = "Walking to target • " .. math.floor(dist) .. " studs"
                        end
                    else
                        farmNotice = "No matching collectibles in range"
                        if farmAttempts > 0 then
                            v54.postFarmIdleSince = v54.postFarmIdleSince or os.clock()
                            if os.clock() - v54.postFarmIdleSince > 10 then
                                v54.finishFarm("no eligible coins for 10 seconds")
                            end
                        end
                    end
                end
            elseif enabled.AutoGunApproach then
                local gun = getNearestGun()
                if gun then
                    hum:MoveTo(gun.Position)
                    farmNotice = "Walking toward dropped gun"
                else
                    farmNotice = "No dropped gun found"
                end
            end
        elseif enabled.AutoCoinFarm or enabled.AutoGunApproach then
            farmNotice = "Waiting for live character"
        end
        if v54.farmStats and v54.farmStats.Parent then
            v54.farmStats.Text = farmNotice .. "  |  mode: "
                .. (enabled.CoinFlight and "fly/noclip" or enabled.CoinTeleport and "teleport" or "walk")
                .. "  |  visits: " .. farmAttempts .. "/" .. numbers.FarmVisitCap
                .. "  skipped: " .. farmSkipped .. " (NOT confirmed pickups)"
        end
    end
end)
-- Auto gun picker is independent from the coin farm. It pauses farm movement
-- during pickup and never claims success without seeing the Gun Tool.
task.spawn(function()
    while not destroyed do
        task.wait(0.22)
        if enabled.AutoGunPickup and not v54.gunPickupBusy and not destroyed then
            v54.attemptGunPickup(true)
        end
    end
end)
-- Controller front mode is opt-in and cancellable. Remains armed until
-- D-pad Down is pressed again; no Knife-visible requirement in front mode.
task.spawn(function()
    while not destroyed do
        task.wait(0.20)
        if v54.sheriffFrontArmed then
            local allowed, reason = v54.canUseSheriffControls()
            if not allowed then
                v54.lastGamepadInput = "D-pad front canceled: " .. reason
                v54.stopFrontAction(true)
                enabled.AutoAimMurderer = false
            elseif not v54.frontActionBusy and not flingBusy and not v54.flingAllActive
                and os.clock() - v54.sheriffFrontLastTry > 5 then
                local murderer = findConfirmedMurderer(true)
                if murderer and alive(murderer) and rootOf(murderer) then
                    v54.sheriffFrontLastTry = os.clock()
                    v54.equipSheriffGun()
                    v54.frontStackAction("sheriff")
                end
            end
        end
    end
end)
-- Server calls can yield; keep them out of the RenderStep and heartbeat.
task.spawn(function()
    while not destroyed do
        task.wait(0.42)
        if enabled.AutoShootMurderer and not enabled.AutoSilentShot then
            attemptMurdererShot(false, true)
        end
        if enabled.AutoSilentShot then
            -- Completely independent of L2 and camera-lock controls.
            local role, source = getRole(localPlayer)
            local gun, equipped = findGun()
            -- MM2 Heroes collect the dropped Sheriff Gun. A stale Innocent
            -- feed must not block automatic aiming while it is equipped.
            local roleAllowed = gun ~= nil and alive(localPlayer)
                and (role == "Sheriff" or role == "Hero"
                    or role == "Innocent" or source ~= "game")
            if not alive(localPlayer) or not roleAllowed then
                v54.silentAimReport = "Auto waiting: living Sheriff/Hero with equipped Gun"
            elseif not gun then
                v54.silentAimReport = "Auto waiting: Gun tool not found"
            else
                if not equipped then
                    v54.equipSheriffGun()
                    v54.silentAimReport = "Auto waiting: equipping Sheriff Gun"
                else
                    local murderer = findConfirmedMurderer(true)
                    local char = murderer and characterOf(murderer)
                    local head = char and char:FindFirstChild("Head")
                    local camera = Workspace.CurrentCamera
                    if not murderer then
                        v54.silentAimReport = "Auto waiting: no Murderer role / visible Knife"
                    elseif not head then
                        v54.silentAimReport = "Auto waiting: Murderer Head missing"
                    elseif not camera or not hasWallClearance(camera, head) then
                        v54.silentAimReport = "Auto waiting: Murderer behind a solid wall"
                    else
                        local clear, reason = shootLineOfSight(murderer, head.Position, gun)
                        if not clear then
                            v54.silentAimReport = "Auto waiting: " .. tostring(reason)
                        elseif shotInFlight then
                            v54.silentAimReport = "Auto waiting: previous gun request"
                        elseif os.clock() - lastShotAttempt < v54.sheriffShotCooldown() then
                            v54.silentAimReport = string.format(
                                "Auto waiting: reload %.1fs", v54.sheriffShotCooldown() - (os.clock()-lastShotAttempt))
                        else
                            -- Shot still requires acceptance by the game's server.
                            local prior = shotAttemptCount
                            attemptMurdererShot(false, true)
                            if shotAttemptCount == prior then
                                v54.silentAimReport = "Auto request blocked: " .. shotNotice
                            end
                        end
                    end
                end
            end
        end
    end
end)
-- Apply noclip before Roblox simulates collisions. Fallback for clients
-- lacking the newer PreSimulation signal is Stepped.
do
    local ok, presim = pcall(function() return RunService.PreSimulation end)
    if ok and presim then
        watch(presim:Connect(v54.applyNoclip))
    else
        watch(RunService.Stepped:Connect(v54.applyNoclip))
    end
end
-- A single heartbeat for periodic state updates.
watch(RunService.Heartbeat:Connect(function(delta)
    if destroyed then return end
    local now = os.clock()
    local cameraNow = Workspace.CurrentCamera
    if cameraNow then
        local updatedView = cameraNow.ViewportSize
        if math.abs(updatedView.X - viewport.X) > 8 or math.abs(updatedView.Y - viewport.Y) > 8 then
            viewport = updatedView
            width, height = windowDimensions(viewport)
            window.Size = UDim2.fromOffset(width, height)
            applyResponsiveLayout()
            placeLauncher(launcher.Position.X.Offset, launcher.Position.Y.Offset)
            title.TextSize = width < 420 and 13 or 15
            v54.roleStrip.TextSize = width < 420 and 11 or 13
            window.Position = UDim2.fromOffset(
                math.clamp(window.Position.X.Offset, 0, math.max(0, viewport.X - width)),
                math.clamp(window.Position.Y.Offset, 0, math.max(0, viewport.Y - height)))
        end
    end
    local ownRoot = rootOf(localPlayer)
    if enabled.Noclip then v54.applyNoclip() end
    if (enabled.AutoHideRoundResults or now < v54.roundResultManualUntil)
        and now - v54.roundResultLastScan >= 0.85 then
        v54.roundResultLastScan = now
        local ok, err = pcall(v54.clearRoundResults, false)
        if not ok then
            v54.roundResultNotice = "Round-result scan error: " .. tostring(err):sub(1, 75)
            warn(v54.roundResultNotice)
        end
    end
    if enabled.Fly then
        setupFly()
        local humanoid = humanOf(localPlayer)
        if humanoid and flyVelocity and flyRoot then
            local v = humanoid.MoveDirection * numbers.FlySpeed
            local y = ((flyUp or v54.gamepadFlyUp) and 1 or 0) - ((flyDown or v54.gamepadFlyDown) and 1 or 0)
            flyVelocity.VectorVelocity = v + Vector3.new(0, y * numbers.FlySpeed, 0)
        end
    end
    if spectateTarget and (not spectateTarget.Parent or not alive(spectateTarget)) then
        restoreCamera()
    end
    if enabled.SpinMode and ownRoot and not flingBusy then
        ownRoot.AssemblyAngularVelocity = Vector3.new(0, 15, 0)
    end
    if enabled.AntiFling and ownRoot and not enabled.FlingActive
        and ownRoot.AssemblyLinearVelocity.Magnitude > 160 then
        ownRoot.AssemblyLinearVelocity = Vector3.zero
        inform("Excessive local velocity damped")
    end
    if enabled.AntiSlip and ownRoot then
        local hum = humanOf(localPlayer)
        if hum and hum.FloorMaterial == Enum.Material.Ice then
            local v = ownRoot.AssemblyLinearVelocity
            local dir = hum.MoveDirection
            local targetSpeed = hum.WalkSpeed
            ownRoot.AssemblyLinearVelocity = Vector3.new(dir.X * targetSpeed, v.Y, dir.Z * targetSpeed)
        end
    end
    if enabled.AntiVoid and ownRoot then
        local humanoid = humanOf(localPlayer)
        if ownRoot.Position.Y > -10 and humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
            lastSafeCFrame = ownRoot.CFrame
        elseif ownRoot.Position.Y < -45 and lastSafeCFrame then
            ownRoot.CFrame = lastSafeCFrame * CFrame.new(0, 5, 0)
            inform("Anti-void recovery attempted")
        end
    end
    -- New drops arrive through DescendantAdded. Keep markers responsive
    -- without rescanning all Workspace descendants every frame.
    if now - v54.lastObjectMarkerTick >= 0.25 then
        v54.lastObjectMarkerTick = now
        if enabled.GunESP or enabled.CoinESP or enabled.KnifeESP or enabled.EventESP then
            updateObjects()
        end
    end
    -- Role feed / ESP refresh independently of the heavier settings UI.
    if now - lastRoleFetch >= v54.roleRefreshSeconds then
        lastRoleFetch = now
        refreshRoles() -- asynchronous RemoteFunction call, never blocks heartbeat
    end
    if now - v54.lastRoleRadarTick >= 0.3 then
        v54.lastRoleRadarTick = now
        updateRoleRadar()
    end
    if now - v54.lastEspDataTick >= 0.32 then
        v54.lastEspDataTick = now
        updatePlayerEffects(now)
        if enabled.Tracers then updateTracers() end
    end
    if now - lastVisualTick >= 0.72 then
        lastVisualTick = now
        v54.refreshSliders()
        v54.updateAimRing()
        v54.updateControllerStatus()
        if not enabled.Tracers then updateTracers() end
        -- Marker distances refresh independently at 4Hz, below.
        -- Update already-enabled settings in case of respawn/map changes.
        if enabled.Fullbright then v54.setFullbright(true) end
        if enabled.LowFX then v54.setLowFX(true) end
        if enabled.NoFog then v54.setNoFog(true) end
        if enabled.HideOwnName then v54.setHideOwnName(true) end
        if enabled.LocalGhost then setLocalGhost(true) end
        refreshDiagnostics()
        if v54.flingFunLine and v54.flingFunLine.Parent then
            v54.flingFunLine.Text = "Fling: " .. flingNotice
                .. "\nOverlaps only mean spatial intersection; target motion may be natural and is not server-confirmed."
        end
        if v54.gunPickupStatusLabel and v54.gunPickupStatusLabel.Parent then
            v54.gunPickupStatusLabel.Text = "Gun: " .. v54.gunPickupStatus
        end
        if v54.animationStatusLabel and v54.animationStatusLabel.Parent then
            v54.animationStatusLabel.Text = "Animation: " .. v54.animationStatus
        end
        if v54.aimRateLabel and v54.aimRateLabel.Parent then
            v54.aimRateLabel.Text = string.format("Aim response: %d%% per frame (100%% = instant)",
                math.floor(numbers.AimSmooth * 100 + 0.5))
        end
        if v54.postFarmInfo and v54.postFarmInfo.Parent then
            v54.postFarmInfo.Text = "Finish action: " .. v54.postFarmStatus
        end
        if v54.shotInfoLabel and v54.shotInfoLabel.Parent then v54.shotInfoLabel.Text = shotNotice end
        if enabled.SilentAim then v54.silentAimBindGun() end
        if v54.silentAimLabel and v54.silentAimLabel.Parent then
            v54.silentAimLabel.Text = "Silent Aim: " .. v54.silentAimReport
        end
    end
end))
-- Priority after the default camera script, for explicit camera tracking.
RunService:BindToRenderStep("LearningHub_Camera_" .. tostring(localPlayer.UserId),
    Enum.RenderPriority.Camera.Value + 1, function()
        if destroyed or not enabled.CameraLock then return end
        local camera = Workspace.CurrentCamera
        local root = rootOf(selectedPlayer)
        if camera and root then
            camera.CFrame = CFrame.lookAt(camera.CFrame.Position, root.Position + Vector3.new(0, 2, 0))
        end
    end)
-- Run after Roblox's default camera and the hub's camera lock.
v54.aimStepName = "Spectra_Aim_" .. tostring(localPlayer.UserId)
RunService:BindToRenderStep(v54.aimStepName, Enum.RenderPriority.Camera.Value + 3, function()
    if destroyed or not (enabled.AimAssist or enabled.AutoAimMurderer or v54.sheriffFrontShotActive
        or (enabled.ControllerHoldAim and v54.gamepadAimHeld)) or enabled.CameraLock or spectateTarget then return end
    -- The same permission gate is used for camera, D-pad Down and status.
    -- Don't erase the physical held-trigger state when role data is late.
    if not v54.canUseSheriffControls() then return end
    local camera = Workspace.CurrentCamera
    local target = findAimPart()
    if camera and target then
        local wanted = CFrame.lookAt(camera.CFrame.Position, target.Position)
        -- Immediate, exact head alignment in front mode; otherwise use the
        -- user's smoothing slider. This reduces 3P camera lag when shooting.
        camera.CFrame = v54.sheriffFrontShotActive
            and wanted or camera.CFrame:Lerp(wanted, numbers.AimSmooth)
    end
end)
v54.espStepName = "SPECTRA_BoxesCombat_" .. tostring(localPlayer.UserId)
v54.lastBoxFrame = -100
v54.lastEspDataTick = -100
v54.lastRoleRadarTick = -100
RunService:BindToRenderStep(v54.espStepName, Enum.RenderPriority.Camera.Value + 5, function()
    if destroyed then return end
    if os.clock() - v54.lastBoxFrame >= 0.105 then
        v54.lastBoxFrame = os.clock()
        v54.update2DBoxes()
        v54.updateSheriffCrosshair()
    end
    v54.updateAimRing()
    v54.updateCombatRadius()
end)
v54.cameraStepName = "LearningHub_Camera_" .. tostring(localPlayer.UserId)

local function unload()
    if destroyed then return end
    destroyed = true
    for _, c in ipairs(connections) do c:Disconnect() end
    RunService:UnbindFromRenderStep(v54.cameraStepName)
    RunService:UnbindFromRenderStep(v54.aimStepName)
    RunService:UnbindFromRenderStep(v54.espStepName)
    enabled.AutoCoinFarm = false
    enabled.AutoGunApproach = false
    enabled.AutoGunPickup = false
    v54.farmTravelToken += 1
    v54.postActionToken += 1
    v54.murderSequenceToken += 1
    v54.murderSequenceBusy = false
    v54.stopFrontAction(true)
    enabled.MurderAura = false
    v54.stopAnimationPreview()
    if v54.restoreAnimationPack then v54.restoreAnimationPack(true) end
    enabled.AutoShootMurderer = false
    enabled.AutoAimMurderer = false
    enabled.SilentAim = false
    enabled.AutoSilentShot = false
    enabled.SheriffRapidFire = false
    v54.targetTeleportToken += 1
    v54.gamepadAimHeld, v54.gamepadFlyUp, v54.gamepadFlyDown = false, false, false
    enabled.SpinMode = false
    v54.flingAllToken += 1
    v54.flingAllActive = false
    flingToken += 1
    enabled.FlingActive = false
    local r = rootOf(localPlayer)
    if r then r.AssemblyAngularVelocity = Vector3.zero end
    restoreNoclip()
    stopFly()
    setLocalGhost(false)
    restoreCamera()
    for p in pairs(playerEffects) do destroyPlayerEffect(p) end
    for p in pairs(v54.box2DObjects) do v54.clear2DBox(p) end
    for p in pairs(tracerEffects) do clearTracer(p) end
    for obj in pairs(objectEffects) do clearObject(obj) end
    for _, part in ipairs(demoParts) do if part.Parent then part:Destroy() end end
    effectsFolder:Destroy()
    v54.setLowFX(false)
    v54.setFullbright(false)
    v54.setNoFog(false)
    for hum, prior in pairs(ownNameOriginal) do
        if hum.Parent then hum.DisplayDistanceType = prior end
    end
    Workspace.Gravity = previousGravity
    local camera = Workspace.CurrentCamera
    if camera then camera.FieldOfView = previousFOV end
    local humanoid = humanOf(localPlayer)
    if humanoid then
        local base = baseHumanoidSettings[humanoid]
        if base then
            humanoid.WalkSpeed = base.speed
            humanoid.UseJumpPower = base.useJumpPower
            humanoid.JumpPower = base.jump
        end
    end
    pcall(function() ContextActionService:UnbindAction(v54.controllerActionName) end)
    gui:Destroy()
    boxGui:Destroy()
    if environment.MM2LearningHubUnload == unload then
        environment.MM2LearningHubUnload = nil
    end
end
environment.MM2LearningHubUnload = unload
v54.performFullUnload = unload

-- Startup steps may fail in a particular MM2 version. The UI should
-- remain visible and report the failure instead of silently disappearing.
local startupOK, startupError = pcall(function()
    v54.loadSettings(true)
    applyCharacterSettings()
    refreshRoles()
    refreshPlayerDropdown()
    updateRoleRadar()
end)
if startupOK then
    if bootLabel.Parent then bootLabel:Destroy() end
    enabled.ControllerHoldAim = true -- migrate older saved opt-out so L2 works by default
    inform("SPECTRA v9.7 loaded • rig packs / aura / fling fixes")
    print("SPECTRA MM2 Hub v9.7 loaded.")
else
    if bootLabel.Parent then
        bootLabel.Text = "SPECTRA warning: " .. tostring(startupError):sub(1,90)
    end
    warn("SPECTRA v9.7 startup: " .. tostring(startupError))
    inform("Startup warning: " .. tostring(startupError):sub(1,110))
end
