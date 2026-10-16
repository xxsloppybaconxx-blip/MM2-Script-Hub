--[[
  MM2 SPECTRA HUB 8.3 - GAMEPAD INPUT REPAIR / ROUND UI CLEANUP
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
    AutoHideRoundResults = false, -- opt-in; default keeps legitimate win screens
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
    CoinTeleport = true,
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
    SheriffDpadFrontLock = true, -- Down runs front-lock test; toggle OFF for ordinary auto aim
    SheriffRequireVisibleKnife = true, -- Normal sheriff auto aim/shoot only; NEVER gate front-stack
    MurderAura = false,
    ControllerHoldAim = true,
    LocalGhost = false,
}
local numbers = { Speed = 24, Jump = 65, FlySpeed = 45, FOV = 70, ESPRange = 250, FarmRadius = 1000, FarmFlySpeed = 25, FarmTeleportDelay = 2.5, AimRadius = 210, AimSmooth = 0.54, FarmVisitCap = 40, KnifeAuraRadius = 12, SheriffFrontDistance = 14, Gravity = Workspace.Gravity }
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
    roundResultNotice = "Ready • auto-hide OFF",
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
v54.gamepadLastDispatch = {}
v54.sheriffFrontArmed = false
v54.sheriffFrontLastTry = -100
v54.sheriffFrontShotActive = false -- front-stack shots bypass regular FOV gate

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

-- Game-reported roles are refreshed at most once every six seconds.
-- Many MM2 script examples refer to this RemoteFunction. Never infer that
-- an unknown player is innocent, and do not claim an equipped tool confirms a role.
local validRole = { Murderer = true, Sheriff = true, Innocent = true, Hero = true }
local function refreshRoles()
    if roleFetchBusy or destroyed then return end
    roleFetchBusy = true
    roleRequestId += 1
    local thisRequest = roleRequestId
    -- InvokeServer has no built-in timeout. Release the busy state if it never returns.
    task.delay(9, function()
        if destroyed or roleRequestId ~= thisRequest or not roleFetchBusy then return end
        roleRequestId += 1 -- Late responses from the old request are ignored.
        roleFetchBusy = false
        roleSyncMessage = "Role feed timed out • retrying later"
    end)
    task.spawn(function()
        local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
        if not remote or not remote:IsA("RemoteFunction") then
            roleMap = {}
            roleSyncMessage = "Role feed unavailable • using observed tools"
            roleFetchBusy = false
            return
        end
        local ok, data = pcall(function() return remote:InvokeServer() end)
        if destroyed or thisRequest ~= roleRequestId then return end
        if ok and type(data) == "table" then
            local received, count = {}, 0
            for username, info in pairs(data) do
                if type(info) == "table" and validRole[info.Role] then
                    local key = type(username) == "string" and username
                        or type(info.Name) == "string" and info.Name or nil
                    if key then
                        received[key] = { role = info.Role, dead = info.Dead == true or info.Killed == true }
                        count += 1
                    end
                end
            end
            if count > 0 then
                roleMap = received
                roleLastUpdate = os.clock()
                roleSyncMessage = "MM2 role feed • " .. count .. " players"
            else
                roleMap = {}
                roleSyncMessage = "No readable roles returned • using tool hints"
            end
        else
            roleMap = {}
            roleSyncMessage = "Role request unavailable • using tool hints"
        end
        roleFetchBusy = false
    end)
end

local function getRole(player)
    if player and os.clock() - roleLastUpdate < 12 then
        local data = roleMap[player.Name]
        if data then return data.role, "game", data.dead end
    end
    local hint = player and visibleWeaponHint(player) or "Unknown"
    if hint == "Knife visible" then return "Murderer", "hint", false end
    if hint == "Gun visible" then return "Sheriff", "hint", false end
    return "Unknown", "none", false
end
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
bootLabel.Text = "SPECTRA v8.3 • opening..."
bootLabel.ZIndex = 250
bootLabel.Parent = gui
task.delay(12, function()
    if bootLabel.Parent then
        bootLabel.Text = "SPECTRA startup incomplete. Check Roblox developer console."
        warn("[SPECTRA v8.3] Startup did not finish within 12 seconds.")
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
boxGui.DisplayOrder = 4
boxGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
boxGui.Parent = playerGui

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
local title = label(top, "◈  SPECTRA  •  v8.3", 40, Color3.fromRGB(250, 251, 255), 15)
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
local roleStrip = Instance.new("TextLabel")
roleStrip.Name = "RoleStatus"
roleStrip.Position = UDim2.fromOffset(10, 46)
roleStrip.Size = UDim2.new(1, -20, 0, 29)
roleStrip.BackgroundColor3 = Color3.fromRGB(31, 41, 55)
roleStrip.TextColor3 = Color3.fromRGB(222, 238, 251)
roleStrip.TextXAlignment = Enum.TextXAlignment.Left
roleStrip.Font = Enum.Font.GothamBold
roleStrip.TextSize = width < 420 and 11 or 13
roleStrip.Text = "  ROLE RADAR  •  checking game data..."
roleStrip.TextTruncate = Enum.TextTruncate.AtEnd
roleStrip.Parent = window
round(roleStrip, 8)
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
v54.tabOrder = { "HOME", "ESP", "MOVE", "TELEPORT", "FARM", "AIM", "FUN", "MURDER", "SHERIFF", "INNOCENT", "ANIMS", "SETTINGS", "STATUS" }
-- One small section selector stays visible; only relevant tabs are shown.
v54.navGroups = {
    {title = "GENERAL", tabs = {"HOME", "ESP", "MOVE", "TELEPORT"}},
    {title = "GAMEPLAY", tabs = {"FARM", "AIM", "FUN"}},
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
local aimPage = makeTab("AIM")
local funPage = makeTab("FUN")
v54.murderPage = makeTab("MURDER")
v54.sheriffPage = makeTab("SHERIFF")
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
                    if enabled.Names then table.insert(pieces, p.DisplayName) end
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

-- On-screen 2D ESP boxes: ordinary Gui Frames, rebuilt on respawn and cleaned on unload.
-- Project all eight oriented bounding-box corners to avoid R6/R15 assumptions.
v54.box2DObjects = {}
v54.clear2DBox = function(player)
    local box = v54.box2DObjects[player]
    if box then
        box.frame:Destroy()
        v54.box2DObjects[player] = nil
    end
end
v54.ensure2DBox = function(player)
    if v54.box2DObjects[player] then return v54.box2DObjects[player] end
    local frame = Instance.new("Frame")
    frame.Name = "SPECTRA_ESP2D_" .. player.UserId
    frame.BorderSizePixel = 0
    frame.BackgroundTransparency = 1
    frame.Visible = false
    frame.ZIndex = 40
    frame.Parent = boxGui
    local border = Instance.new("UIStroke")
    border.Thickness = 1.8
    border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    border.Parent = frame
    v54.box2DObjects[player] = {frame = frame, border = border}
    return v54.box2DObjects[player]
end
v54.update2DBoxes = function()
    local camera = Workspace.CurrentCamera
    if not camera or destroyed then return end
    local vw, vh = camera.ViewportSize.X, camera.ViewportSize.Y
    for _, player in ipairs(Players:GetPlayers()) do
        -- Always remove the local player's box, including any stale frame.
        if player == localPlayer then
            v54.clear2DBox(player)
        else
            local role, source = getRole(player)
            local tracked = not enabled.ThreatsOnly or role == "Murderer"
                or role == "Sheriff" or role == "Hero"
            local root = rootOf(player)
            local gap = root and distanceTo(root)
            local visible = enabled.BoxESP2D and enabled.PlayerESP and alive(player)
                and tracked and (not enabled.RangeLimit or (gap and gap <= numbers.ESPRange))
            local box = v54.box2DObjects[player]
            if visible and root then
                local char = characterOf(player)
                local ok, cf, size = pcall(function() return char:GetBoundingBox() end)
                local rootPoint = camera:WorldToViewportPoint(root.Position)
                if ok and size and rootPoint.Z > 0.35 then
                    local half = size * 0.5
                    local minX, minY = math.huge, math.huge
                    local maxX, maxY = -math.huge, -math.huge
                    local seen = 0
                    for _, x in ipairs({-1, 1}) do
                        for _, y in ipairs({-1, 1}) do
                            for _, z in ipairs({-1, 1}) do
                                local pos = (cf * CFrame.new(half.X*x, half.Y*y, half.Z*z)).Position
                                local p = camera:WorldToViewportPoint(pos)
                                -- A close or partially clipped avatar still gets a box;
                                -- don't require every one of eight corners on-screen.
                                if p.Z > 0.35 then
                                    minX, minY = math.min(minX, p.X), math.min(minY, p.Y)
                                    maxX, maxY = math.max(maxX, p.X), math.max(maxY, p.Y)
                                    seen += 1
                                end
                            end
                        end
                    end
                    if seen >= 2 and maxX > 0 and maxY > 0
                        and minX < vw and minY < vh then
                        box = box or v54.ensure2DBox(player)
                        minX, minY = math.clamp(minX, 0, vw), math.clamp(minY, 0, vh)
                        maxX, maxY = math.clamp(maxX, 0, vw), math.clamp(maxY, 0, vh)
                        if maxX - minX > 2 and maxY - minY > 2 then
                            box.frame.Position = UDim2.fromOffset(minX, minY)
                            box.frame.Size = UDim2.fromOffset(maxX-minX, maxY-minY)
                            box.border.Color = enabled.RoleESP and getRoleColor(role, source)
                                or colorForHint(visibleWeaponHint(player))
                            box.frame.Visible = true
                        else
                            box.frame.Visible = false
                        end
                    elseif box then
                        box.frame.Visible = false
                    end
                elseif box then
                    box.frame.Visible = false
                end
            elseif box then
                box.frame.Visible = false
            end
        end
    end
    for player in pairs(v54.box2DObjects) do
        if not player.Parent or player == localPlayer then
            v54.clear2DBox(player)
        end
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
    if (name == "gundrop" or name == "droppedgun" or name == "dropped_gun") then
        return "Gun"
    elseif name == "knifedrop" or name == "droppedknife" or name == "dropped_knife" then
        return "Knife"
    elseif name == "coin" or name == "coinpart" or name == "coin_server"
        or name == "coinpickup" or name == "token"
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
    roundend=true, roundendscreen=true, endround=true, endroundscreen=true,
    victory=true, victoryscreen=true, victoryframe=true,
    resultframe=true, resultui=true, resultsgui=true, resultsscreen=true,
    results=true, winscreen=true, winnergui=true, winnerscreen=true,
    murdererwin=true, murdererwins=true, innocentswin=true,
    innocentswins=true, sheriffwin=true, sheriffwins=true,
    herowin=true, herowins=true, defeat=true, defeatscreen=true,
    gameover=true, gameoverscreen=true, roundsummary=true,
}
v54.isRoundResultName = function(name)
    if type(name) ~= "string" then return false end
    local compact = string.lower(name):gsub("[^%w]", "")
    return v54.roundResultNames[compact] == true
        or compact:match("^roundresult[%w]*$") ~= nil
        or compact:match("^victory[%w]*screen$") ~= nil
end
v54.isRoundResultText = function(value)
    if type(value) ~= "string" then return false end
    local t = string.lower(value):gsub("[^%w]", "")
    return t == "victory" or t == "youwin" or t == "youwon"
        or t == "innocentswin" or t == "innocentswins"
        or t == "murdererwin" or t == "murdererwins"
        or t == "sheriffwin" or t == "sheriffwins"
        or t == "roundover" or t == "roundresults"
end
v54.clearRoundResults = function(manual)
    if destroyed or not playerGui or not playerGui.Parent then return 0 end
    local hidden = 0
    local claimed = {}
    for _, item in ipairs(playerGui:GetDescendants()) do
        if item ~= gui and not item:IsDescendantOf(gui) then
            if item:IsA("ScreenGui") and item.Enabled and v54.isRoundResultName(item.Name) then
                item.Enabled = false
                claimed[item] = true
                hidden += 1
            elseif item:IsA("GuiObject") and item.Visible then
                if v54.isRoundResultName(item.Name) then
                    item.Visible = false
                    claimed[item] = true
                    hidden += 1
                elseif item:IsA("TextLabel") and v54.isRoundResultText(item.Text) then
                    -- Some MM2 builds name only the win TextLabel, not its container.
                    -- Never disable a generic parent ScreenGui or broad HUD frame.
                    local parent = item.Parent
                    if parent and parent:IsA("Frame") and parent.Visible
                        and parent.Size.X.Scale <= 0.95 and parent.Size.Y.Scale <= 0.95
                        and not claimed[parent] and parent.Name ~= "Main" then
                        parent.Visible = false
                        claimed[parent] = true
                    else
                        item.Visible = false
                        claimed[item] = true
                    end
                    hidden += 1
                end
            end
        end
    end
    v54.roundResultHiddenTotal += hidden
    if hidden > 0 then
        v54.roundResultNotice = string.format("Cleared %d result element(s) • session %d", hidden, v54.roundResultHiddenTotal)
        if manual then inform(v54.roundResultNotice) end
    elseif manual then
        v54.roundResultNotice = "No visible known round-result UI found"
        inform(v54.roundResultNotice)
    end
    if v54.roundResultStatusLabel and v54.roundResultStatusLabel.Parent then
        v54.roundResultStatusLabel.Text = v54.roundResultNotice
    end
    return hidden
end
v54.manualClearRoundResults = function()
    -- Keep watching briefly in case a stuck animation makes the overlay reappear.
    v54.roundResultManualUntil = os.clock() + 12
    v54.clearRoundResults(true)
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
        humanoid.WalkSpeed = enabled.Sprint and numbers.Speed or base.speed
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
            if v54.applyAnimationPack and v54.selectedAnimationPack ~= "Default" then
                v54.applyAnimationPack(v54.selectedAnimationPack, true)
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

local function setFullbright(on)
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
local function setLowFX(on)
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

local function setNoFog(on)
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
local function setHideOwnName(on)
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
                local step = math.min(remaining.Magnitude, numbers.FarmFlySpeed * math.min(dt, 0.1))
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
    -- Some games temporarily set CanCollide=false while players can still
    -- overlap. Don't silently refuse to approach because of this local probe.
    flingBusy = true
    flingToken += 1
    local token = flingToken
    local origin = own.CFrame
    local startingTarget = theirRoot.Position
    local initialGap = (own.Position - theirRoot.Position).Magnitude
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
    flingNotice = string.format("Approaching %s (%.1f studs away) • ~1.1s close contact; %s",
        target.DisplayName, initialGap, canContact and "collisions compatible" or "collision check inconclusive")
    if v54.flingFunLine and v54.flingFunLine.Parent then v54.flingFunLine.Text = flingNotice end
    inform(flingNotice)
    task.spawn(function()
        local overlaps, contactFrames, pulses, placements, approachFails = 0, 0, 0, 0, 0
        local peakOwn, peakSpin, peakTarget, targetTravel = 0, 0, 0, 0
        local elapsed, closest, maxDrift, firstLaunchTime = 0, math.huge, 0, nil
        local followTravel, followSpeed, followSamples = 0, 0, 0
        local reason = "contact window elapsed"
        local success, failure = pcall(function()
            own.CanCollide = true
            humanoid.PlatformStand = true
            humanoid:ChangeState(Enum.HumanoidStateType.Physics)
            local overlapParams = OverlapParams.new()
            overlapParams.FilterType = Enum.RaycastFilterType.Include
            overlapParams.FilterDescendantsInstances = {target.Character}
            overlapParams.MaxParts = 12
            local started, lastUpdate, consecutiveOutOfRange = os.clock(), -1, 0
            -- Position and apply impulses EVERY frame, not every 0.17 seconds.
            -- When the client accepts these local CFrame changes, the gap
            -- should read ~1.5 studs, as it did in the reference monitor.
            while not destroyed and enabled.FlingActive and flingToken == token
                and os.clock() - started < 1.12 do
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
                if consecutiveOutOfRange >= 10 then
                    reason = "server or movement system repeatedly moved us away (>10 studs)"
                    break
                end
                local height = math.floor(elapsed / 0.20) % 2 == 0 and 1.45 or -1.45
                local offset = Vector3.new(0.28 * math.sin(phase), height, 0.28 * math.cos(phase))
                local intended = t.Position + offset
                -- First placement occurs immediately: no 0.17s delay.
                own.CFrame = CFrame.new(intended) * CFrame.Angles(0, phase * 1.8, 0)
                placements += 1
                local actualGap = (own.Position - t.Position).Magnitude
                closest = math.min(closest, actualGap)
                if actualGap > 5 then approachFails += 1 end

                -- One bounded impulse per physics frame; the next frame
                -- reestablishes contact instead of allowing prolonged drift.
                local direction = Vector3.new(math.sin(phase * 1.13),
                    0.55 * math.cos(phase * 0.73), math.cos(phase * 1.37))
                if direction.Magnitude > 0 then
                    own.AssemblyLinearVelocity = direction.Unit * 2500
                    pulses += 1
                end
                own.AssemblyAngularVelocity = Vector3.new(
                    900 * math.sin(phase), 2200 * math.cos(phase * 0.75),
                    900 * math.cos(phase))
                if #Workspace:GetPartBoundsInBox(own.CFrame, own.Size, overlapParams) > 0 then
                    overlaps += 1
                end
                contactFrames += 1
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
                RunService.Heartbeat:Wait()
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
            local launchText = firstLaunchTime
                and string.format("possible delayed launch at +%.2fs", firstLaunchTime)
                or "no delayed launch observed"
            local contactText = canContact and "collision groups compatible" or "local collision test inconclusive"
            flingNotice = success and string.format(
                "2500: %.2fs, %d placements, %d/%d overlap, %d gap>5, nearest %.1f, max drift %.0f; own %.0f/s spin %.0f; target %.0f studs peak %.0f/s; %s; %s; %s. LOCAL ONLY.",
                elapsed, placements, overlaps, contactFrames, approachFails,
                closest == math.huge and -1 or closest, maxDrift, peakOwn, peakSpin,
                motion, math.max(peakTarget, followSpeed), launchText, contactText, reason)
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
    if not enabled.AimWallCheck then return true end
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
        -- Front mode deliberately ignores the regular knife and FOV gates.
        if murderer and alive(murderer) and head and head:IsA("BasePart") then
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
        if l2 and part and alive(murderer) then return part end
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

local function shootLineOfSight(target, destination)
    local char = characterOf(localPlayer)
    local targetChar = characterOf(target)
    local originPart = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
    if not originPart or not targetChar then return false end
    local direction = destination - originPart.Position
    if direction.Magnitude > 400 or direction.Magnitude < 0.1 then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    local result = Workspace:Raycast(originPart.Position, direction, params)
    return result == nil or result.Instance:IsDescendantOf(targetChar)
end

local function attemptMurdererShot(manual, headPriority)
    if destroyed or shotInFlight then return end
    local now = os.clock()
    if now - lastShotAttempt < 2.5 then
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
    local murderer = findConfirmedMurderer(v54.sheriffFrontShotActive)
    -- The optional Knife-visible gate applies to ordinary Sheriff aim/shoot.
    -- Front-stack invoked by D-pad Down (or its matching UI button) ignores it.
    if enabled.SheriffRequireVisibleKnife and not v54.sheriffFrontShotActive
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
    -- The gun's remote expects a WORLD-space target. Derive it from
    -- the same Head in BOTH camera modes (not from the screen mouse ray).
    -- Small optional lead avoids v7.5's over-leading of fast targets.
    local camera = Workspace.CurrentCamera
    local myChar = characterOf(localPlayer)
    local myHead = myChar and myChar:FindFirstChild("Head")
    local firstPerson = camera and myHead
        and (camera.CFrame.Position - myHead.Position).Magnitude < 2.1
    local lead = firstPerson and 0.02 or 0.035
    local position = targetPart.Position + targetPart.AssemblyLinearVelocity * lead
    if targetPart == head then
        position -= Vector3.new(0, math.min(0.08, head.Size.Y * 0.08), 0)
    end
    if not shootLineOfSight(murderer, position) then
        shotNotice = "Murderer is obscured / out of range"
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
    shotNotice = (headPriority and "Headshot" or "Gun") .. " request #" .. shotAttemptCount
        .. " pending; hit not confirmed"
    task.spawn(function()
        local ok, err = pcall(function() remote:InvokeServer(1, position, shotTag) end)
        shotInFlight = false
        if destroyed then return end
        shotNotice = ok and ("Sent gun request #" .. shotAttemptCount .. "; hit unconfirmed")
            or ("Gun remote error: " .. tostring(err):sub(1, 65))
        if manual or not ok then inform(shotNotice) end
    end)
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
    if dead or not alive(localPlayer) then return false, role, source end
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
    local frontName = isMurder and "Front Stack + Knife" or "Murderer Front Stack + Gun"
    v54.frontActionMessage(frontName .. ": " .. tostring(count)
        .. " target(s) • " .. (isMurder and tostring(murderEvidence) or controllerEvidence)
        .. " • hits NOT confirmed")
    task.spawn(function()
        local duration = isMurder and 2.2 or 4.3
        local start, lastAttack = os.clock(), -10
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
                    local desired = own.CFrame * CFrame.new(((index-1)%3-1)*0.22, 0,
                        -distance - math.floor((index-1)/3)*0.1)
                    -- This is a local request ONLY; it may be overwritten or
                    -- rejected by MM2's network ownership and server physics.
                    local ok = pcall(function()
                        root.CFrame = desired
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
                    -- Aim at the tracked Head's world coordinates in both
                    -- 1st and 3rd person. The normal screen-radius gate is
                    -- deliberately bypassed ONLY in this front-stack mode.
                    local prior = shotAttemptCount
                    attemptMurdererShot(false, true)
                    if shotAttemptCount > prior then attackRequests += 1 end
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
                "%s finished: %d target(s), %d weapon requests, %d/%d frames with observed front contact, %d local write errors. Kills/replication UNVERIFIED.",
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
                v54.roleActionMessage("Aura disabled: role no longer confirmed")
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
                    local ok, detail = v54.attackWithKnife(candidate, false)
                    v54.roleActionStatus = "Aura: " .. candidate.DisplayName .. " • " .. detail
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
local controllerActionName = "SPECTRA_V83_Inputs_" .. tostring(localPlayer.UserId)
local actionOK, actionError = pcall(function()
    ContextActionService:BindActionAtPriority(controllerActionName,
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
local aimRing = Instance.new("Frame")
aimRing.Name = "AimRadiusPreview"
aimRing.AnchorPoint = Vector2.new(0.5, 0.5)
aimRing.BackgroundTransparency = 1
aimRing.BorderSizePixel = 0
aimRing.Visible = false
aimRing.Parent = gui
round(aimRing, 999)
local ringStroke = Instance.new("UIStroke")
ringStroke.Thickness = 2
ringStroke.Color = Color3.fromRGB(87, 174, 255)
ringStroke.Transparency = 0.32
ringStroke.Parent = aimRing
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
v54.sheriffRingText.Parent = aimRing
round(v54.sheriffRingText,6)
v54.combatRing = Instance.new("Frame")
v54.combatRing.Name = "KnifeAuraRadiusPreview"
v54.combatRing.AnchorPoint = Vector2.new(0.5, 0.5)
v54.combatRing.BackgroundTransparency = 1
v54.combatRing.Visible = false
v54.combatRing.Parent = gui
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
    local role, source = getRole(localPlayer)
    local show = enabled.CombatRadius and source == "game" and role == "Murderer"
        and enabled.MurderAura and own and cam
    v54.combatRing.Visible = show and true or false
    if not show then return end
    local a, onScreen = cam:WorldToViewportPoint(own.Position)
    local b = cam:WorldToViewportPoint(own.Position + cam.CFrame.RightVector * numbers.KnifeAuraRadius)
    if not onScreen or a.Z <= 0 or b.Z <= 0 then
        v54.combatRing.Visible = false
        return
    end
    local radius = math.clamp(math.abs(b.X-a.X), 18, 700)
    v54.combatRing.Position = UDim2.fromOffset(a.X,a.Y)
    v54.combatRing.Size = UDim2.fromOffset(radius*2,radius*2)
    local nearby = 0
    for _, player in ipairs(otherPlayers()) do
        local root = rootOf(player)
        if root and alive(player) and (root.Position-own.Position).Magnitude <= numbers.KnifeAuraRadius then
            nearby += 1
        end
    end
    v54.combatStroke.Color = nearby > 0 and Color3.fromRGB(72,240,144) or Color3.fromRGB(255,130,111)
    v54.combatText.Text = string.format("KNIFE AURA  %d studs • %d inside", numbers.KnifeAuraRadius, nearby)
end
local function updateAimRing()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local view = camera.ViewportSize
    aimRing.Position = UDim2.fromOffset(view.X / 2, view.Y / 2)
    aimRing.Size = UDim2.fromOffset(numbers.AimRadius * 2, numbers.AimRadius * 2)
    local showSheriff = enabled.AimFOVRing or enabled.CombatRadius
    local active = enabled.AutoShootMurderer or enabled.AutoAimMurderer
        or v54.sheriffFrontArmed or enabled.AimAssist
        or (enabled.ControllerHoldAim and v54.gamepadAimHeld)
    -- Never show Sheriff's aim reticle as Innocent/Murderer without a Gun:
    -- it was misleadingly visible even when the camera was blocked.
    aimRing.Visible = showSheriff and active and v54.canUseSheriffControls()
    if aimRing.Visible then
        local frontMode = v54.sheriffFrontArmed or v54.sheriffFrontShotActive
        local murderer = findConfirmedMurderer()
        local target = murderer and (characterOf(murderer) and (characterOf(murderer):FindFirstChild("Head") or rootOf(murderer)))
        local inside = target and v54.withinScreenAimRadius(target)
        local knifeOK = not enabled.SheriffRequireVisibleKnife or v54.isMurdererKnifeVisible(murderer)
        ringStroke.Color = ((frontMode and murderer ~= nil) or (inside and knifeOK))
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
makeButton(rolesPage, "AIM & CONTROLLER  →", function() v54.activateTab("AIM") end)
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
local roleDataLine = label(rolesPage, "Checking MM2 game role data...", 36, Color3.fromRGB(160, 205, 232), 12)
roleDataLine.TextWrapped = true
do
heading(rolesPage, "SELECT PLAYER  /  AUTO-REFRESH")
local chosenPlayerLabel = label(rolesPage, "Selected: nobody", 35,
    Color3.fromRGB(211, 232, 255), 14)
chosenPlayerLabel.Font = Enum.Font.GothamBold
local dropdownButton = makeButton(rolesPage, "  CHOOSE PLAYER  ▼", function()
    dropdownOpen = not dropdownOpen
    refreshPlayerDropdown()
end)
dropdownButton.BackgroundColor3 = Color3.fromRGB(44, 72, 125)
dropdownButton.TextSize = 16
local dropdownList = Instance.new("ScrollingFrame")
dropdownList.Name = "LivePlayerDropdown"
dropdownList.Size = UDim2.new(1, -4, 0, 210)
dropdownList.BackgroundColor3 = Color3.fromRGB(20, 28, 44)
dropdownList.ScrollBarThickness = 5
dropdownList.ScrollBarImageColor3 = Color3.fromRGB(101, 166, 255)
dropdownList.AutomaticCanvasSize = Enum.AutomaticSize.Y
dropdownList.CanvasSize = UDim2.fromOffset(0, 0)
dropdownList.Visible = false
dropdownList.Parent = rolesPage
round(dropdownList, 9)
local dropdownPadding = Instance.new("UIPadding")
dropdownPadding.PaddingTop = UDim.new(0, 6)
dropdownPadding.PaddingBottom = UDim.new(0, 6)
dropdownPadding.PaddingLeft = UDim.new(0, 7)
dropdownPadding.PaddingRight = UDim.new(0, 7)
dropdownPadding.Parent = dropdownList
local dropdownLayout = Instance.new("UIListLayout")
dropdownLayout.Padding = UDim.new(0, 5)
dropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
dropdownLayout.Parent = dropdownList
local dropdownRows = {}
refreshPlayerDropdown = function()
    if destroyed or not dropdownList.Parent then return end
    local list = otherPlayers()
    local inServer = {}
    if selectedPlayer and selectedPlayer.Parent ~= Players then
        selectedPlayer = nil
    end
    chosenPlayerLabel.Text = selectedPlayer
        and ("Selected: " .. selectedPlayer.DisplayName .. "  (@" .. selectedPlayer.Name .. ")")
        or "Selected: nobody  •  tap CHOOSE PLAYER"
    dropdownButton.Text = "  " .. (selectedPlayer and selectedPlayer.DisplayName or "CHOOSE PLAYER")
        .. "  (" .. tostring(#list) .. ") " .. (dropdownOpen and "▲" or "▼")
    dropdownList.Visible = dropdownOpen
    for i, p in ipairs(list) do
        inServer[p] = true
        local row = dropdownRows[p]
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
            row.Parent = dropdownList
            round(row, 7)
            watch(row.Activated:Connect(function()
                if p.Parent ~= Players then return end
                selectedPlayer = p
                dropdownOpen = false
                lastPlayerChange = "Selected " .. p.DisplayName
                refreshPlayerDropdown()
                inform(lastPlayerChange .. " (@" .. p.Name .. ")")
            end))
            dropdownRows[p] = row
        end
        row.LayoutOrder = i
        local role, origin = getRole(p)
        row.Text = "  " .. (selectedPlayer == p and "✓  " or "") .. p.DisplayName
            .. "  (@" .. p.Name .. ")  • " .. roleDisplay(role, origin)
        row.BackgroundColor3 = selectedPlayer == p and Color3.fromRGB(55, 92, 146)
            or Color3.fromRGB(32, 43, 65)
        row.TextColor3 = getRoleColor(role, origin)
    end
    for p, row in pairs(dropdownRows) do
        if not inServer[p] then
            row:Destroy()
            dropdownRows[p] = nil
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
    roleStrip.Text = " " .. prefix .. "  •  M: " .. murderer .. "   S: " .. sheriff
    local age = roleLastUpdate > 0 and (os.clock() - roleLastUpdate) or nil
    roleDataLine.Text = roleSyncMessage .. (age and ("  •  " .. math.floor(age) .. "s ago") or "")
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
toggle(visualsPage, "2D BOX ESP • outlines around players", "BoxESP2D")
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
makeSlider(movementPage, "WALK SPEED", "Speed", 8, 75, 1, "", applyCharacterSettings)
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
label(farmPage, "Pick one travel mode: TELEPORT visits each coin directly, or FLY THROUGH WALLS travels between coins without local collisions. Collection depends on MM2's server; visits are not earned coins.",
    112, Color3.fromRGB(207, 218, 237), 13)
toggle(farmPage, "AUTO FARM COINS", "AutoCoinFarm", setFarmEnabled)
toggle(farmPage, "Mode: TELEPORT to each coin", "CoinTeleport", function(on)
    if on then enabled.CoinFlight = false end
    v54.farmTravelToken += 1
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end)
toggle(farmPage, "Mode: FLY THROUGH WALLS", "CoinFlight", function(on)
    if on then enabled.CoinTeleport = false end
    v54.farmTravelToken += 1
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end)
label(farmPage, "Flight defaults to 25 studs/s. Teleport waits 2.5 seconds between jumps. The game can still reject invalid positions.",
    67, Color3.fromRGB(205, 219, 240), 12)
makeSlider(farmPage, "FARM FLIGHT SPEED", "FarmFlySpeed", 10, 100, 1, " studs/s")
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
local farmStats = label(farmPage, "Ready • 0 targets visited", 70, Color3.fromRGB(189, 221, 255), 14)
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
toggle(aimPage, "AUTO SHOOT • confirmed Murderer (Gun only)", "AutoShootMurderer")
makeButton(aimPage, "SHOOT confirmed Murderer NOW (one attempt)", function()
    attemptMurdererShot(true)
end)
local shotInfoLabel = label(aimPage, "Gun status: waiting", 72, Color3.fromRGB(189, 221, 255), 13)

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
toggle(v54.murderPage, "KILL AURA • nearby knife activations", "MurderAura", function(on)
    if on and not v54.confirmRole("Murderer") then
        enabled.MurderAura = false
        for _, refresh in ipairs(toggleUpdaters) do refresh() end
        inform("Aura requires game-confirmed Murderer role")
    else
        inform(on and "Aura enabled; no teleports; nearby targets only" or "Aura disabled")
    end
end)
toggle(v54.murderPage, "SHOW LIVE KNIFE AURA CIRCLE", "CombatRadius")
makeSlider(v54.murderPage, "KNIFE AURA RANGE", "KnifeAuraRadius", 5, 35, 1, " studs")
v54.roleActionLabel = label(v54.murderPage, "Role actions idle", 100, Color3.fromRGB(242, 214, 167), 12)
v54.frontActionLabel = label(v54.murderPage, "Front actions idle", 95, Color3.fromRGB(242, 214, 167), 12)
makeButton(v54.murderPage, "STOP ALL MURDER / FRONT ACTIONS", function() v54.stopRoleActions() end)
heading(v54.sheriffPage, "SHERIFF / HERO • GUN")
label(v54.sheriffPage, "Game-confirmed Sheriff/Hero only. Normal auto-aim/shoot can require a visible Knife (setting below). The separate front-lock mode ignores Knife visibility and uses world-space Head coordinates. Shots remain unverified.",
    90, Color3.fromRGB(208, 223, 248), 12)
makeButton(v54.sheriffPage, "SHOOT CONFIRMED MURDERER NOW", function() attemptMurdererShot(true) end)
heading(v54.sheriffPage, "EXPERIMENTAL • FRONT HEADSHOT")
label(v54.sheriffPage, "D-PAD DOWN / FRONT HEADSHOT: attempts to hold ONLY the game-confirmed Murderer at your configured gun range for 4.3s, points the camera at their Head, equips Gun, and requests Head shots. Knife can be hidden or holstered. Normal knife-visible setting does NOT apply. Server may reject repositioning and shots.",
    92, Color3.fromRGB(240, 204, 161), 12)
makeSlider(v54.sheriffPage, "FRONT SHOT DISTANCE", "SheriffFrontDistance", 8, 30, 1, " studs")
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
local funPickerOpen = false
local funPickerButton = makeButton(funPage, "  SELECT FLING TARGET  ▼", function()
    funPickerOpen = not funPickerOpen
    v54.refreshFunPicker()
end)
funPickerButton.BackgroundColor3 = Color3.fromRGB(44, 72, 125)
local funPickerList = Instance.new("ScrollingFrame")
funPickerList.Name = "FunLiveTargetPicker"
funPickerList.Size = UDim2.new(1, -4, 0, 190)
funPickerList.BackgroundColor3 = Color3.fromRGB(20, 28, 44)
funPickerList.ScrollBarThickness = 5
funPickerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
funPickerList.CanvasSize = UDim2.fromOffset(0, 0)
funPickerList.Visible = false
funPickerList.Parent = funPage
round(funPickerList, 9)
local pickerLayout = Instance.new("UIListLayout")
pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder
pickerLayout.Padding = UDim.new(0, 5)
pickerLayout.Parent = funPickerList
local funRows = {}
v54.refreshFunPicker = function()
    if destroyed or not funPickerList.Parent then return end
    local roster = otherPlayers()
    local present = {}
    funPickerButton.Text = "  TARGET: " .. (selectedPlayer and selectedPlayer.DisplayName or "CHOOSE PLAYER")
        .. "  (" .. #roster .. ") " .. (funPickerOpen and "▲" or "▼")
    funPickerList.Visible = funPickerOpen
    for i, player in ipairs(roster) do
        present[player] = true
        local button = funRows[player]
        if not button then
            button = Instance.new("TextButton")
            button.Name = "FunPick_" .. player.UserId
            button.Size = UDim2.new(1, 0, 0, 49)
            button.TextXAlignment = Enum.TextXAlignment.Left
            button.TextSize = 14
            button.Font = Enum.Font.GothamMedium
            button.Selectable = true
            button.Parent = funPickerList
            round(button, 7)
            watch(button.Activated:Connect(function()
                if player.Parent ~= Players then return end
                selectedPlayer = player
                funPickerOpen = false
                lastPlayerChange = "Selected " .. player.DisplayName
                refreshPlayerDropdown() -- also refreshes the FUN picker
                inform("Fling target: " .. player.DisplayName .. " (@" .. player.Name .. ")")
            end))
            funRows[player] = button
        end
        local role, origin = getRole(player)
        button.LayoutOrder = i
        button.TextColor3 = getRoleColor(role, origin)
        button.BackgroundColor3 = player == selectedPlayer
            and Color3.fromRGB(55, 92, 146) or Color3.fromRGB(32, 43, 65)
        button.Text = "  " .. (player == selectedPlayer and "✓  " or "")
            .. player.DisplayName .. " (@" .. player.Name .. ") • " .. roleDisplay(role, origin)
    end
    for player, button in pairs(funRows) do
        if not present[player] then
            button:Destroy()
            funRows[player] = nil
        end
    end
end
v54.refreshFunPicker()
end
heading(funPage, "PLAYER FLING • EXPERIMENTAL")
label(funPage, "Choose a target above, without leaving FUN. This is a client-side physics test, not a guaranteed fling: if the server rejects the collision, other players will not move. STATUS shows locally observed motion.",
    94, Color3.fromRGB(207, 218, 237), 13)
v54.flingFunLine = label(funPage, "Fling test: not started. Choose a player, then use Diagnose.",
    100, Color3.fromRGB(248, 207, 161), 13)
makeButton(funPage, "Diagnose selected player's collisions", function()
    if not selectedPlayer then return inform("Choose a player in FUN first") end
    local canContact, report = contactReport(selectedPlayer)
    flingNotice = report .. (canContact and " • possible contact" or " • no contact possible")
    v54.flingFunLine.Text = flingNotice
    inform(flingNotice)
end)
label(funPage, "RESTORED v6.9 FLING • ~1.12 second per-frame 1.5 stud approach with 2,500 studs/s pulses. Fling Selected and Fling All use the exact same routine. 10 second delayed-launch monitor; LOCAL ONLY.",
    95, Color3.fromRGB(255, 207, 172), 12)
makeButton(funPage, "FLING SELECTED • v6.9 CLASSIC + TRACK", function()
    flingSelected()
end)
makeButton(funPage, "FLING ALL • SAME v6.9 CLASSIC", function()
    v54.flingAll()
end)
label(funPage, "v6.9 FLING RESTORED • 2,500 studs/s, ~1.12s frame-by-frame contact, then delayed observation. No unverified extreme-speed button.",
    78, Color3.fromRGB(186, 225, 209), 12)

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
    Ninja = {
        Idle = "rbxassetid://658832408",
        Walk = "rbxassetid://658831143",
        Run = "rbxassetid://658830056",
        Jump = "rbxassetid://658832070",
        Fall = "rbxassetid://658831500",
        Swim = "rbxassetid://658832807",
        Climb = "rbxassetid://658833139",
    },
    Cartoony = {
        Idle = "rbxassetid://837011741",
        Walk = "rbxassetid://837010234",
        Run = "rbxassetid://837009922",
        Jump = "rbxassetid://837011171",
        Fall = "rbxassetid://837010685",
        Swim = "rbxassetid://837012509",
        Climb = "rbxassetid://837013990",
    },
    Levitation = {
        Idle = "rbxassetid://619542203",
        Walk = "rbxassetid://619544080",
        Run = "rbxassetid://619543231",
        Jump = "rbxassetid://619542888",
        Fall = "rbxassetid://619541867",
        Swim = "rbxassetid://619543721",
        Climb = "rbxassetid://619541458",
    },
    Stylish = {
        Idle = "rbxassetid://619511648",
        Walk = "rbxassetid://619512767",
        Run = "rbxassetid://619512153",
        Jump = "rbxassetid://619511974",
        Fall = "rbxassetid://619511417",
        Swim = "rbxassetid://619512450",
        Climb = "rbxassetid://619509955",
    },
    Popstar = {
        Idle = "rbxassetid://1212900985",
        Walk = "rbxassetid://1212980338",
        Run = "rbxassetid://1212980348",
        Jump = "rbxassetid://1212954642",
        Fall = "rbxassetid://1212900995",
        Swim = "rbxassetid://1212852603",
        Climb = "rbxassetid://1213044953",
    },
    Patrol = {
        Idle = "rbxassetid://1149612882",
        Walk = "rbxassetid://1151231493",
        Run = "rbxassetid://1150967949",
        Jump = "rbxassetid://1150944216",
        Fall = "rbxassetid://1148863382",
        Swim = "rbxassetid://1151204998",
        Climb = "rbxassetid://1148811837",
    },
    Sneaky = {
        Idle = "rbxassetid://1132473842",
        Walk = "rbxassetid://1132510133",
        Run = "rbxassetid://1132494274",
        Jump = "rbxassetid://1132489853",
        Fall = "rbxassetid://1132469004",
        Swim = "rbxassetid://1132500520",
        Climb = "rbxassetid://1132461372",
    },
    Princess = {
        Idle = "rbxassetid://941003647",
        Walk = "rbxassetid://941028902",
        Run = "rbxassetid://941015281",
        Jump = "rbxassetid://941008832",
        Fall = "rbxassetid://941000007",
        Swim = "rbxassetid://941018893",
        Climb = "rbxassetid://940996062",
    },
    Zombie = {
        Idle = "rbxassetid://616158929",
        Walk = "rbxassetid://616168032",
        Run = "rbxassetid://616163682",
        Jump = "rbxassetid://616161997",
        Fall = "rbxassetid://616156119",
        Swim = "rbxassetid://616157476",
        Climb = "rbxassetid://616160636",
    },
}
v54.selectedAnimationPack = "Default"
v54.lastSavedPack = "Default"
v54.animationPackOriginals = setmetatable({}, {__mode = "k"})
v54.animationPackStatus = "Original character movement animations"
v54.animationPackStatusLabel = nil
v54.animationPackSequence = 0
v54.packReferences = {
    Idle = {{"idle", "Animation1"}, {"idle", "Animation2"}},
    Walk = {{"walk", "WalkAnim"}},
    Run = {{"run", "RunAnim"}},
    Jump = {{"jump", "JumpAnim"}},
    Fall = {{"fall", "FallAnim"}},
    Swim = {{"swim", "Swim"}, {"swimidle", "SwimIdle"}},
    Climb = {{"climb", "ClimbAnim"}},
}
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
v54.applyAnimationPack = function(name, quiet)
    local pack = v54.animationPacks[name]
    if not pack then
        if not quiet then inform("Animation pack not recognized: " .. tostring(name)) end
        return
    end
    v54.animationPackSequence += 1
    local requestSequence = v54.animationPackSequence
    v54.updatePackStatus("Checking " .. name .. " animations before editing your character...")
    task.spawn(function()
        local character = localPlayer.Character
        if not character then
            v54.updatePackStatus("No character to apply " .. name)
            return
        end
        local hum = character:FindFirstChildOfClass("Humanoid")
        local animate = character:FindFirstChild("Animate") or character:WaitForChild("Animate", 5)
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if not animate or not animator or hum.RigType ~= Enum.HumanoidRigType.R15 then
            v54.updatePackStatus("Pack not applied: requires R15, Animator and Animate")
            return
        end
        -- Verify clips can really load before replacing active Animate references.
        -- Roblox may return a track but leave Length=0 for unavailable assets.
        local ready, approved, problems = 0, {}, {}
        local total = 0
        for action, id in pairs(pack) do
            total += 1
            task.spawn(function()
                local probe = Instance.new("Animation")
                probe.AnimationId = id
                local ok, track = pcall(function() return animator:LoadAnimation(probe) end)
                if ok and track then
                    local deadline = os.clock() + 3.2
                    while track.Length <= 0 and os.clock() < deadline
                        and requestSequence == v54.animationPackSequence
                        and not destroyed do
                        task.wait(0.10)
                    end
                    approved[action] = track.Length > 0
                    pcall(function() track:Destroy() end)
                else
                    approved[action] = false
                end
                probe:Destroy()
                ready += 1
            end)
        end
        local deadline = os.clock() + 4
        while ready < total and os.clock() < deadline
            and requestSequence == v54.animationPackSequence and not destroyed do
            task.wait(0.1)
        end
        if requestSequence ~= v54.animationPackSequence or destroyed then return end
        for _, action in ipairs({"Idle", "Walk", "Run"}) do
            if not approved[action] then
                table.insert(problems, action)
            end
        end
        if #problems > 0 then
            local message = name .. " NOT applied: unavailable " .. table.concat(problems, ", ")
                .. ". Existing animations preserved."
            v54.updatePackStatus(message)
            if not quiet then inform(message) end
            return
        end
        local original = v54.animationPackOriginals[character]
        if not original then
            original = {}
            v54.animationPackOriginals[character] = original
        end
        local updated, skipped = 0, 0
        for action, references in pairs(v54.packReferences) do
            for _, pair in ipairs(references) do
                local group = animate:FindFirstChild(pair[1])
                local clip = group and group:FindFirstChild(pair[2])
                if clip and clip:IsA("Animation") then
                    if original[clip] == nil then original[clip] = clip.AnimationId end
                    -- Keep the original clip for any unavailable action.
                    local chosenId = approved[action] and pack[action] or original[clip]
                    if not approved[action] then skipped += 1 end
                    local ok = pcall(function() clip.AnimationId = chosenId end)
                    if ok then updated += 1 end
                end
            end
        end
        if requestSequence ~= v54.animationPackSequence or destroyed then return end
        if updated > 0 then
            v54.selectedAnimationPack = name
            v54.restartAnimate(character)
            local message = name .. ": " .. updated .. " clips set; " .. skipped
                .. " unsupported clips kept original."
            v54.updatePackStatus(message)
            if not quiet then inform(message) end
        else
            v54.updatePackStatus(name .. ": no matching Animate clips found")
        end
    end)
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
heading(pages["ANIMS"], "MOVEMENT ANIMATION PACKS (R15)")
label(pages["ANIMS"], "Checks whether movement clips actually load before changing your avatar. Unavailable clips stay original; saved packs do NOT auto-apply at startup.",
    90, Color3.fromRGB(184, 209, 245), 12)
for _, name in ipairs({"Ninja", "Cartoony", "Levitation", "Stylish", "Popstar", "Patrol", "Sneaky", "Princess", "Zombie"}) do
    local nameForButton = name
    makeButton(pages["ANIMS"], "APPLY " .. nameForButton:upper() .. " PACK", function()
        v54.stopAnimationPreview()
        v54.applyAnimationPack(nameForButton, false)
    end)
end
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
local assetBox = Instance.new("TextBox")
assetBox.Name = "AnimationIdInput"
assetBox.Size = UDim2.new(1, -4, 0, 46)
assetBox.BackgroundColor3 = Color3.fromRGB(34, 41, 55)
assetBox.TextColor3 = Color3.fromRGB(244, 250, 255)
assetBox.PlaceholderColor3 = Color3.fromRGB(163, 183, 211)
assetBox.PlaceholderText = "Animation ID (digits only)"
assetBox.Text = ""
assetBox.ClearTextOnFocus = false
assetBox.Font = Enum.Font.Gotham
assetBox.TextSize = 15
assetBox.Parent = pages["ANIMS"]
round(assetBox, 8)
local previewButton
previewButton = makeButton(pages["ANIMS"], "PREVIEW animation ID", function()
    local digits = assetBox.Text:match("^%s*(%d+)%s*$")
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
    v54.animationStatus = played and ("Previewing " .. digits .. " at " .. v54.animationSpeed .. "x")
        or ("Preview error: " .. tostring(err):sub(1, 72))
    inform(v54.animationStatus)
end)
heading(pages["ANIMS"], "QUICK PREVIEW IDS (R15)")
label(pages["ANIMS"], "These select standard Roblox R15 animation asset IDs. Tap PREVIEW above to play; assets may still be blocked by the experience.",
    78, Color3.fromRGB(184, 205, 240), 12)
for _, item in ipairs({
    {"Wave", "507770239"}, {"Cheer", "507770677"},
    {"Laugh", "507770818"}, {"Point", "507770453"},
    {"Dance 1", "507771019"}, {"Dance 2", "507776043"},
    {"Dance 3", "507777268"},
}) do
    local title, id = item[1], item[2]
    makeButton(pages["ANIMS"], "Select animation: " .. title, function()
        assetBox.Text = id
        inform(title .. " selected; tap PREVIEW animation ID")
    end)
end
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
local function focusMenuControl(direction)
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
local function cycleMenuTab(direction)
    local index = table.find(v54.tabOrder, v54.activeTab) or 1
    local nextIndex = ((index - 1 + direction) % #v54.tabOrder) + 1
    v54.activateTab(v54.tabOrder[nextIndex])
    focusMenuControl(1)
end
watch(UserInputService.InputBegan:Connect(function(input, processed)
    if destroyed or not v54.isGamepadInput(input) then return end
    local key = input.KeyCode
    if key == Enum.KeyCode.ButtonY then
        v54.gamepadMenuMode = true
        setWindowOpen(minimized)
        if not minimized then focusMenuControl(1) end
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
        cycleMenuTab(-1)
    elseif key == Enum.KeyCode.DPadRight then
        cycleMenuTab(1)
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
toggle(settingsPage, "Fullbright", "Fullbright", setFullbright)
toggle(settingsPage, "Remove fog and atmosphere haze", "NoFog", setNoFog)
toggle(settingsPage, "Hide my overhead name (local)", "HideOwnName", setHideOwnName)
toggle(settingsPage, "Reduce sliding on ice (local)", "AntiSlip")
toggle(settingsPage, "Disable post-processing FX", "LowFX", setLowFX)
toggle(settingsPage, "Anti-void (experimental)", "AntiVoid")
heading(settingsPage, "ROUND RESULTS")
label(settingsPage, "Auto-hide is OFF by default. It only searches for recognizable round-end panels in PlayerGui, not the full game HUD.",
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
    AutoShootMurderer = true, MurderAura = true, FlingActive = true, Fly = true, SpinMode = true,
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
    return {version = 3, toggles = toggles, numbers = sliders,
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
    setFullbright(enabled.Fullbright)
    setNoFog(enabled.NoFog)
    setLowFX(enabled.LowFX)
    setHideOwnName(enabled.HideOwnName)
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
    setFullbright(false)
    setNoFog(false)
    setLowFX(false)
    setHideOwnName(false)
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
local performFullUnload = function() inform("Unload is not ready") end
local unloadConfirmDeadline = 0
local unloadControl
unloadControl = makeButton(settingsPage, "FULLY UNLOAD SPECTRA (tap twice)", function()
    if os.clock() < unloadConfirmDeadline then
        performFullUnload()
        return
    end
    unloadConfirmDeadline = os.clock() + 5
    unloadControl.Text = "CONFIRM UNLOAD • tap again within 5 sec"
    inform("Tap again to remove ESP, GUI and local effects")
    task.delay(5, function()
        if not destroyed and unloadControl and unloadControl.Parent
            and os.clock() >= unloadConfirmDeadline then
            unloadControl.Text = "FULLY UNLOAD SPECTRA (tap twice)"
        end
    end)
end)
unloadControl.BackgroundColor3 = Color3.fromRGB(98, 37, 52)
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
local diagRole = label(diagnosticsPage, "Role data: checking...", 55, Color3.fromRGB(190, 214, 245), 14)
local diagFarm = label(diagnosticsPage, "Farm: waiting", 66, Color3.fromRGB(190, 214, 245), 14)
local diagWorld = label(diagnosticsPage, "Players/markers: waiting", 90, Color3.fromRGB(190, 214, 245), 14)
local diagMisc = label(diagnosticsPage, "Controls: waiting", 112, Color3.fromRGB(190, 214, 245), 14)
refreshDiagnostics = function()
    if destroyed then return end
    local reported = os.clock() - roleLastUpdate < 12
    diagRole.Text = "Role feed: " .. (reported and "game data recently received" or "unavailable/stale")
        .. "\n" .. roleSyncMessage
    diagFarm.Text = "Farm: " .. (enabled.AutoCoinFarm and "ON" or "OFF")
        .. "  |  mode: " .. (enabled.CoinFlight and "fly" or enabled.CoinTeleport and "teleport" or "walk")
        .. "  |  fly: " .. numbers.FarmFlySpeed .. "  tp delay: " .. numbers.FarmTeleportDelay .. "s"
        .. "  |  attempts: " .. farmAttempts .. "  |  skipped: " .. farmSkipped
        .. "\nThese are NOT confirmed currency pickups"
    local playerCount = #Players:GetPlayers() - 1
    local markers = 0
    for _ in pairs(objectEffects) do markers += 1 end
    local selected = selectedPlayer and selectedPlayer.Name or "none"
    local playerDistance = selectedPlayer and rootOf(selectedPlayer) and distanceTo(rootOf(selectedPlayer))
    diagWorld.Text = "Other players: " .. math.max(playerCount, 0)
        .. "  |  marked objects: " .. markers
        .. "\nSelected: " .. selected .. (playerDistance and ("  •  " .. math.floor(playerDistance) .. " studs") or "")
        .. "\nGun alerts: " .. (enabled.GunAlerts and enabled.GunAlertMessage or "OFF")
        .. "\nGun pickup: " .. v54.gunPickupStatus
    diagMisc.Text = "Fly HUD: " .. (enabled.Fly and "ON" or "OFF") .. " (joystick + ▲/▼)"
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
        if farmStats and farmStats.Parent then
            farmStats.Text = farmNotice .. "  |  mode: "
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
        task.wait(0.28)
        if enabled.AutoShootMurderer then attemptMurdererShot(false, true) end
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
            roleStrip.TextSize = width < 420 and 11 or 13
            window.Position = UDim2.fromOffset(
                math.clamp(window.Position.X.Offset, 0, math.max(0, viewport.X - width)),
                math.clamp(window.Position.Y.Offset, 0, math.max(0, viewport.Y - height)))
        end
    end
    local ownRoot = rootOf(localPlayer)
    if enabled.Noclip then v54.applyNoclip() end
    if (enabled.AutoHideRoundResults or now < v54.roundResultManualUntil)
        and now - v54.roundResultLastScan >= 0.4 then
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
    if now - lastVisualTick >= 0.5 then
        lastVisualTick = now
        v54.refreshSliders()
        if now - lastRoleFetch >= 6 then
            lastRoleFetch = now
            refreshRoles()
        end
        if now - lastRoleUI >= 0.55 then
            lastRoleUI = now
            updateRoleRadar()
        end
        updateAimRing()
        v54.updateControllerStatus()
        updatePlayerEffects(now)
        updateTracers()
        updateObjects()
        -- Update already-enabled settings in case of respawn/map changes.
        if enabled.Fullbright then setFullbright(true) end
        if enabled.LowFX then setLowFX(true) end
        if enabled.NoFog then setNoFog(true) end
        if enabled.HideOwnName then setHideOwnName(true) end
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
        if shotInfoLabel and shotInfoLabel.Parent then shotInfoLabel.Text = shotNotice end
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
local aimStepName = "Spectra_Aim_" .. tostring(localPlayer.UserId)
RunService:BindToRenderStep(aimStepName, Enum.RenderPriority.Camera.Value + 3, function()
    if destroyed or not (enabled.AimAssist or enabled.AutoAimMurderer or v54.sheriffFrontShotActive
        or (enabled.ControllerHoldAim and v54.gamepadAimHeld)) or enabled.CameraLock or spectateTarget then return end
    -- The same permission gate is used for camera, D-pad Down and status.
    -- Don't erase the physical held-trigger state when role data is late.
    if not v54.canUseSheriffControls() then return end
    local camera = Workspace.CurrentCamera
    local target = findAimPart()
    if camera and target then
        local wanted = CFrame.lookAt(camera.CFrame.Position, target.Position)
        camera.CFrame = camera.CFrame:Lerp(wanted, numbers.AimSmooth)
    end
end)
v54.espStepName = "SPECTRA_BoxesCombat_" .. tostring(localPlayer.UserId)
v54.lastBoxFrame = -100
RunService:BindToRenderStep(v54.espStepName, Enum.RenderPriority.Camera.Value + 5, function()
    if destroyed then return end
    if os.clock() - v54.lastBoxFrame >= 0.055 then
        v54.lastBoxFrame = os.clock()
        v54.update2DBoxes()
    end
    updateAimRing()
    v54.updateCombatRadius()
end)
local cameraStepName = "LearningHub_Camera_" .. tostring(localPlayer.UserId)

local function unload()
    if destroyed then return end
    destroyed = true
    for _, c in ipairs(connections) do c:Disconnect() end
    RunService:UnbindFromRenderStep(cameraStepName)
    RunService:UnbindFromRenderStep(aimStepName)
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
    setLowFX(false)
    setFullbright(false)
    setNoFog(false)
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
    pcall(function() ContextActionService:UnbindAction(controllerActionName) end)
    gui:Destroy()
    boxGui:Destroy()
    if environment.MM2LearningHubUnload == unload then
        environment.MM2LearningHubUnload = nil
    end
end
environment.MM2LearningHubUnload = unload
performFullUnload = unload

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
    inform("SPECTRA v8.3 loaded • D-pad/L2 input & round UI fixes")
    print("SPECTRA MM2 Hub v8.3 loaded.")
else
    if bootLabel.Parent then
        bootLabel.Text = "SPECTRA warning: " .. tostring(startupError):sub(1,90)
    end
    warn("SPECTRA v8.3 startup: " .. tostring(startupError))
    inform("Startup warning: " .. tostring(startupError):sub(1,110))
end
