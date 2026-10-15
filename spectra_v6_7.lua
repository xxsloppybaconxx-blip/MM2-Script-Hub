--[[
  MM2 SPECTRA HUB 6.7 - SINGLE 2500 FLING AND PHYSICS MONITOR
  Original, readable, client-side Luau example.
  Best tested in a Roblox Studio LocalScript in StarterPlayerScripts.
  Also uses ordinary Roblox client APIs for executor compatibility,
  but has NOT been tested in Delta or the live MM2 experience.

  Features: MM2 game-reported roles (if available), live role radar,
  player ESP, nametags, distance, visible-weapon hints,
  through-wall outlines, player tracers, rainbow ESP, dropped-gun
  and coin markers (name-based), spectate, camera tracking, selected
  player cycling, movement options, optional fly, teleport attempts,
  fullbright, post-effect reduction, player count, anti-void,
  local demo target, mobile-friendly draggable UI and cleanup.

  Role information is only definitive when MM2 provides readable role data.
  Visible weapon hints are explicitly marked unconfirmed. No auto-kill or insta-win. Flings and farming may be corrected by the game server.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
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
    AimRequireSheriff = false,
    AutoAimMurderer = false,
    AutoShootMurderer = false,
    ControllerHoldAim = true,
    ControllerR1Shoot = false,
    LocalGhost = false,
}
local numbers = { Speed = 24, Jump = 65, FlySpeed = 45, FOV = 70, ESPRange = 250, FarmRadius = 1000, FarmFlySpeed = 25, FarmTeleportDelay = 2.5, AimRadius = 210, AimSmooth = 0.54, FarmVisitCap = 40 }
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
}
-- Controller buttons operate alongside touch/keyboard without consuming Roblox inputs.
-- Hold L1/LB for role-confirmed aiming, D-pad up/down for flight altitude.
v54.defaultEnabled = table.clone(enabled)
v54.defaultNumbers = table.clone(numbers)
v54.gamepadAimHeld = false
v54.gamepadFlyUp, v54.gamepadFlyDown = false, false
v54.lastGamepadInput = "No controller input"

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
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
-- Keep touch controls clear of mobile cutouts and the Roblox top bar.
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

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

-- SPECTRA 3: Mobile landscape-first layout inspired by the user's demo video.
-- Larger text, fewer labels crammed into each button, vertical navigation.
local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(760, 450)
local function windowDimensions(size)
    -- Compact ImGui-inspired dimensions: avoid inventory and topbar overlays.
    local w = math.clamp(size.X - 80, 290, 650)
    local h = math.clamp(size.Y - 105, 260, 454)
    return w, h
end
local width, height = windowDimensions(viewport)
local sidebarWidth = 116
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
local title = label(top, "◈  SPECTRA  MM2  •  v5.8", 40, Color3.fromRGB(250, 251, 255), 15)
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
status.Text = "  Ready  •  tap a category on the left"
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
v54.tabOrder = { "HOME", "ESP", "MOVE", "TELEPORT", "FARM", "AIM", "FUN", "ANIMS", "SETTINGS", "STATUS" }
v54.activateTab = function(name)
    if not pages[name] then return end
    v54.activeTab = name
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
    b.Text = "  " .. name
    b.TextSize = 13
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Font = Enum.Font.GothamBold
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
makeTab("ANIMS")
local settingsPage = makeTab("SETTINGS")
local diagnosticsPage = makeTab("STATUS")
v54.activateTab("HOME")
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
    local l = label(page, text, 26, Color3.fromRGB(200, 217, 255), 14)
    l.Font = Enum.Font.GothamBold
    l.Size = UDim2.new(1, -4, 0, 26)
end
local function makeButton(page, text, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -4, 0, 45)
    b.BackgroundColor3 = Color3.fromRGB(32, 38, 50)
    b.TextColor3 = Color3.fromRGB(242, 246, 252)
    b.TextSize = 14
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextWrapped = true
    b.Font = Enum.Font.GothamMedium
    b.Text = text
    b.AutoButtonColor = true
    b.Selectable = true
    b.BorderSizePixel = 0
    b.Parent = page
    round(b, 9)
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
    b.TextSize = 13
    local inset = b:FindFirstChildWhichIsA("UIPadding")
    if inset then inset.PaddingRight = UDim.new(0, 64) end
    pill.Parent = b
    update()
    table.insert(toggleUpdaters, update)
    return b
end

-- Use horizontal scrolling navigation on portrait phones so buttons have room
-- for legible labels. Landscape keeps the sidebar from the reference video.
local function applyResponsiveLayout()
    local narrow = width < 470
    if narrow then
        tabs.Position = UDim2.fromOffset(9, 81)
        tabs.Size = UDim2.new(1, -20, 0, 42)
        tabs.ScrollingDirection = Enum.ScrollingDirection.X
        tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
        tabLayout.FillDirection = Enum.FillDirection.Horizontal
        tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        main.Position = UDim2.fromOffset(10, 130)
        main.Size = UDim2.new(1, -20, 1, -164)
    else
        tabs.Position = UDim2.fromOffset(9, 81)
        tabs.Size = UDim2.new(0, sidebarWidth, 1, -117)
        tabs.ScrollingDirection = Enum.ScrollingDirection.Y
        tabs.AutomaticCanvasSize = Enum.AutomaticSize.Y
        tabLayout.FillDirection = Enum.FillDirection.Vertical
        main.Position = UDim2.fromOffset(sidebarWidth + 16, 81)
        main.Size = UDim2.new(1, -sidebarWidth - 25, 1, -117)
    end
    for _, button in pairs(tabButtons) do
        button.Size = narrow and UDim2.fromOffset(92, 34)
            or UDim2.new(1, 0, 0, 37)
        button.TextSize = narrow and 12 or 13
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

-- Movement and local utilities ----------------------------------------
local function restoreNoclip()
    for part, value in pairs(originalCollisions) do
        if part.Parent then part.CanCollide = value end
    end
    table.clear(originalCollisions)
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
        inform("FLY: joystick to move • HUD UP/DOWN • E/Q on keyboard")
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
    if flingBusy or enabled.FlingActive then
        if not automatic then inform("Stop the fling test before gun pickup") end
        return
    end
    if v54.hasGunInInventory() then
        v54.gunPickupStatus = "Gun already in inventory; no teleport needed"
        if not automatic then inform(v54.gunPickupStatus) end
        return
    end
    local target = getNearestGun()
    local root, hum = rootOf(localPlayer), humanOf(localPlayer)
    if not target or not root or not hum or hum.Health <= 0 then
        if not automatic then
            v54.gunPickupStatus = "No GunDrop or living character available"
            inform(v54.gunPickupStatus)
        end
        return
    end
    local now = os.clock()
    if automatic and (now - v54.gunPickupLastAt < 4 or
        (v54.gunPickupTried[target] and now - v54.gunPickupTried[target] < 12)) then
        return
    end
    v54.gunPickupLastAt = now
    v54.gunPickupTried[target] = now
    v54.gunPickupBusy = true
    -- Cancel any in-progress flying coin route before moving to GunDrop.
    if v54.farmFlightBusy then v54.farmTravelToken += 1 end
    v54.gunPickupStatus = "Pickup: teleporting to dropped gun…"
    inform(v54.gunPickupStatus)
    local savedCF = root.CFrame
    local savedFly = enabled.Fly
    local savedNoclip = enabled.Noclip
    task.spawn(function()
        local ok, err = pcall(function()
            if savedFly then
                enabled.Fly = false
                stopFly()
                v54.updateFlyHUD()
            end
            if savedNoclip then
                enabled.Noclip = false
                restoreNoclip()
            end
            -- Small temporary positional adjustments allow ordinary touch pickup.
            -- We do not invoke hidden remotes, spoof server ownership, or grant tools.
            for i = 1, 6 do
                if destroyed or rootOf(localPlayer) ~= root or hum.Health <= 0
                    or not target:IsDescendantOf(Workspace) then break end
                root.CFrame = CFrame.new(target.Position + Vector3.new(0, 0.35 + (i % 2) * 0.35, 0))
                root.AssemblyLinearVelocity = Vector3.zero
                task.wait(0.13)
                if v54.hasGunInInventory() then break end
            end
            task.wait(0.16)
        end)
        -- Always try to restore the original location and flight preference.
        local restored = pcall(function()
            if not destroyed and rootOf(localPlayer) == root and hum.Health > 0 then
                root.CFrame = savedCF
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
            enabled.Noclip = savedNoclip
            if savedFly and not destroyed then
                enabled.Fly = true
                v54.setFlight(true)
            end
        end)
        local confirmed = v54.hasGunInInventory()
        if destroyed then return end
        v54.gunPickupStatus = (confirmed and "Gun in backpack/character: pickup confirmed"
                or (ok and "Returned; server pickup NOT confirmed"
                    or "Pickup error: " .. tostring(err):sub(1, 70)))
            .. (restored and " • return attempted" or " • return failed")
        v54.gunPickupBusy = false
        if not destroyed then inform(v54.gunPickupStatus) end
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

-- Single fling mode. Both ONE and ALL use exactly the same short, bounded
-- 2,500-stud/s contact routine. Server-side displacement is NOT guaranteed.
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
        inform("Choose a living target in FUN")
        return false
    end
    local contact, collisionReport = contactReport(target)
    if not contact then
        flingNotice = collisionReport .. " • locally incompatible collisions"
        inform(flingNotice)
        return false
    end
    flingBusy = true
    flingToken += 1
    local token = flingToken
    local origin = own.CFrame
    local startingTarget = theirRoot.Position
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
    flingNotice = "2,500 studs/s fling running against " .. target.DisplayName .. " • 0.85s max"
    if v54.flingFunLine then v54.flingFunLine.Text = flingNotice end
    task.spawn(function()
        local proxy, ownAttachment, goalAttachment, align
        local overlaps, pulses, peakOwn, peakTarget, targetTravel = 0, 0, 0, 0, 0
        local elapsed = 0
        local success, failure = pcall(function()
            proxy = Instance.new("Part")
            proxy.Name = "SPECTRA_Fling2500Goal"
            proxy.Size = Vector3.new(0.2, 0.2, 0.2)
            proxy.Anchored, proxy.CanCollide, proxy.CanTouch = true, false, false
            proxy.Transparency = 1
            proxy.CFrame = own.CFrame
            proxy.Parent = Workspace
            ownAttachment = Instance.new("Attachment")
            ownAttachment.Parent = own
            goalAttachment = Instance.new("Attachment")
            goalAttachment.Parent = proxy
            align = Instance.new("AlignPosition")
            align.Mode = Enum.PositionAlignmentMode.TwoAttachment
            align.Attachment0, align.Attachment1 = ownAttachment, goalAttachment
            align.RigidityEnabled = false
            align.MaxForce = math.max(2000000, own.AssemblyMass * 18000)
            align.MaxVelocity, align.Responsiveness = 230, 180
            align.ApplyAtCenterOfMass = true
            align.Parent = own
            own.CanCollide = true
            humanoid.PlatformStand = true
            humanoid:ChangeState(Enum.HumanoidStateType.Physics)
            local overlapParams = OverlapParams.new()
            overlapParams.FilterType = Enum.RaycastFilterType.Include
            overlapParams.FilterDescendantsInstances = {target.Character}
            overlapParams.MaxParts = 12
            local started, previousPulse = os.clock(), -1
            while not destroyed and enabled.FlingActive and flingToken == token
                and os.clock() - started < 0.85 do
                local r, t = rootOf(localPlayer), rootOf(target)
                if r ~= own or not t or not alive(target) then break end
                elapsed = os.clock() - started
                local phase = elapsed * 33
                local vertical = math.floor(elapsed / 0.12) % 2 == 0 and 0.85 or -0.95
                local offset = Vector3.new(0.22 * math.sin(phase), vertical, 0.22 * math.cos(phase))
                proxy.CFrame = CFrame.new(t.Position + offset)
                if elapsed - previousPulse >= 0.13 then
                    previousPulse = elapsed
                    pulses += 1
                    local direction = Vector3.new(math.sin(phase * 1.19),
                        math.cos(phase * 0.67) * 0.6, math.cos(phase * 1.41))
                    if direction.Magnitude > 0 then
                        own.AssemblyLinearVelocity = direction.Unit * 2500
                    end
                    own.AssemblyAngularVelocity = Vector3.new(
                        550 * math.sin(phase), 1400 * math.cos(phase * 0.75),
                        550 * math.cos(phase))
                end
                local gap = (own.Position - t.Position).Magnitude
                peakOwn = math.max(peakOwn, own.AssemblyLinearVelocity.Magnitude)
                peakTarget = math.max(peakTarget, t.AssemblyLinearVelocity.Magnitude)
                targetTravel = math.max(targetTravel, (t.Position - startingTarget).Magnitude)
                if #Workspace:GetPartBoundsInBox(own.CFrame, own.Size, overlapParams) > 0 then
                    overlaps += 1
                end
                if gap > 65 or own.Position.Y < -120 then break end
                RunService.Heartbeat:Wait()
            end
        end)
        for _, obj in ipairs({align, ownAttachment, goalAttachment, proxy}) do
            if obj then pcall(function() obj:Destroy() end) end
        end
        pcall(function()
            if own.Parent then
                own.AssemblyAngularVelocity = Vector3.zero
                own.AssemblyLinearVelocity = Vector3.zero
                own.CanCollide = oldRootCollision
                if not destroyed and rootOf(localPlayer) == own then
                    own.CFrame = origin * CFrame.new(0, 3, 0)
                end
            end
            if humanoid.Parent then
                humanoid.PlatformStand = oldPlatformStand
                if not oldPlatformStand then
                    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end
        end)
        if not destroyed then
            for key, value in pairs(saved) do enabled[key] = value end
        end
        enabled.FlingActive, flingBusy = false, false
        if not destroyed then
            for _, refresh in ipairs(toggleUpdaters) do refresh() end
            flingNotice = success and string.format(
                "2500 fling: %.2fs, %d pulses, %d overlaps; own peak %.0f, target peak %.0f studs/s; local target movement %.1f studs. Server UNVERIFIED.",
                elapsed, pulses, overlaps, peakOwn, peakTarget, targetTravel)
                or "2500 fling error: " .. tostring(failure):sub(1, 90)
            if v54.flingFunLine and v54.flingFunLine.Parent then
                v54.flingFunLine.Text = flingNotice
            end
            inform(flingNotice)
        end
        if type(onFinished) == "function" then
            pcall(onFinished, success, targetTravel, target.DisplayName)
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
    v54.flingAllProgress = "Fling All: queued " .. #roster .. " players • 2,500 studs/s"
    inform(v54.flingAllProgress)
    task.spawn(function()
        local attempted, skipped = 0, 0
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
                if flingSelected(player, function() finished = true end) then
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
            and string.format("Fling All: %d attempted, %d skipped (server UNVERIFIED)", attempted, skipped)
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
local function findConfirmedMurderer()
    local ownRoot = rootOf(localPlayer)
    local candidate, bestDistance = nil, math.huge
    for _, player in ipairs(otherPlayers()) do
        local role, source, isDead = getRole(player)
        local part = rootOf(player)
        if role == "Murderer" and source == "game" and not isDead
            and part and alive(player) then
            local distance = ownRoot and (part.Position - ownRoot.Position).Magnitude or 0
            if distance < bestDistance then
                candidate, bestDistance = player, distance
            end
        end
    end
    return candidate
end

local function findAimPart()
    local camera = Workspace.CurrentCamera
    if not camera then return nil end
    if enabled.AimRequireSheriff then
        local myRole, source = getRole(localPlayer)
        if source ~= "game" or (myRole ~= "Sheriff" and myRole ~= "Hero") then
            return nil
        end
    end
    if enabled.AutoAimMurderer or (enabled.ControllerHoldAim and v54.gamepadAimHeld) then
        -- Explicit murderer lock requires game-reported role; no knife-hint guessing.
        local murderer = findConfirmedMurderer()
        local char = characterOf(murderer)
        local part = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
        if part and hasWallClearance(camera, part) then return part end
        return nil
    end
    local center = camera.ViewportSize / 2
    local best, chosen = numbers.AimRadius, nil
    for _, player in ipairs(otherPlayers()) do
        local role = getRole(player)
        if alive(player) and role == "Murderer" then
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
    local gun = char and char:FindFirstChild("Gun")
    if gun and gun:IsA("Tool") then return gun, true end
    gun = backpack and backpack:FindFirstChild("Gun")
    if gun and gun:IsA("Tool") then return gun, false end
    return nil, false
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

local function attemptMurdererShot(manual)
    if destroyed or shotInFlight then return end
    local now = os.clock()
    if now - lastShotAttempt < 2.5 then
        if manual then inform("Gun cooldown • wait before shooting again") end
        return
    end
    local myRole, mySource = getRole(localPlayer)
    -- Allow a Hero using a picked-up Gun, but do not shoot anyone based on guessed roles.
    if mySource ~= "game" or (myRole ~= "Sheriff" and myRole ~= "Hero") then
        shotNotice = "Waiting for confirmed Sheriff/Hero role"
        if manual then inform(shotNotice) end
        return
    end
    local murderer = findConfirmedMurderer()
    local targetPart = murderer and rootOf(murderer)
    if not targetPart then
        shotNotice = "Waiting for a living, game-confirmed Murderer"
        if manual then inform(shotNotice) end
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
        if manual then inform("Equipping Gun; try again in a moment") end
        return
    end
    local position = targetPart.Position + targetPart.AssemblyLinearVelocity * 0.10
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
    shotNotice = "Shot request #" .. shotAttemptCount .. " pending; hit not confirmed"
    task.spawn(function()
        local ok, err = pcall(function() remote:InvokeServer(1, position, shotTag) end)
        shotInFlight = false
        if destroyed then return end
        shotNotice = ok and ("Sent gun request #" .. shotAttemptCount .. "; hit unconfirmed")
            or ("Gun remote error: " .. tostring(err):sub(1, 65))
        if manual or not ok then inform(shotNotice) end
    end)
end
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
-- Roblox normally uses the two triggers for gameplay actions; we reserve
-- L1/LB for a hold-to-track camera assist and optionally R1/RB for a shot.
-- This NEVER simulates a mouse, fires a gun merely on aim, or consumes input.
v54.controllerStatusLabel = nil
v54.updateControllerStatus = function()
    if destroyed or not v54.controllerStatusLabel or not v54.controllerStatusLabel.Parent then return end
    local online = UserInputService.GamepadEnabled
    local held = enabled.ControllerHoldAim and v54.gamepadAimHeld
    v54.controllerStatusLabel.Text = (online and "GAMEPAD CONNECTED" or "NO GAMEPAD DETECTED")
        .. "  |  hold L1/LB: " .. (enabled.ControllerHoldAim and (held and "AIMING" or "ready") or "disabled")
        .. "\nD-pad ↑/↓: fly altitude  |  R1/RB: "
        .. (enabled.ControllerR1Shoot and "manual shoot" or "disabled")
        .. "\nY/Triangle menu  •  D-pad navigate  •  A select  •  B back"
        .. "\n" .. v54.lastGamepadInput
end
watch(UserInputService.InputBegan:Connect(function(input, processed)
    if destroyed or not v54.isGamepadInput(input) then return end
    if input.KeyCode == Enum.KeyCode.ButtonL1 and not processed then
        v54.gamepadAimHeld = true
        v54.lastGamepadInput = "L1/LB aim held"
    elseif not processed and enabled.Fly and (minimized or not v54.gamepadMenuMode)
        and input.KeyCode == Enum.KeyCode.DPadUp then
        v54.gamepadFlyUp = true
        v54.lastGamepadInput = "D-pad: ascend"
    elseif not processed and enabled.Fly and (minimized or not v54.gamepadMenuMode)
        and input.KeyCode == Enum.KeyCode.DPadDown then
        v54.gamepadFlyDown = true
        v54.lastGamepadInput = "D-pad: descend"
    elseif not processed and enabled.ControllerR1Shoot and input.KeyCode == Enum.KeyCode.ButtonR1 then
        v54.lastGamepadInput = "R1/RB shot requested (hit not confirmed)"
        attemptMurdererShot(true)
    end
    v54.updateControllerStatus()
    v54.updateFlyHUD()
end))
watch(UserInputService.InputEnded:Connect(function(input)
    if destroyed or not v54.isGamepadInput(input) then return end
    if input.KeyCode == Enum.KeyCode.ButtonL1 then
        v54.gamepadAimHeld = false
        v54.lastGamepadInput = "L1/LB released"
    elseif input.KeyCode == Enum.KeyCode.DPadUp then
        v54.gamepadFlyUp = false
    elseif input.KeyCode == Enum.KeyCode.DPadDown then
        v54.gamepadFlyDown = false
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
    v54.lastGamepadInput = "Controller detected; hold L1/LB to track"
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
local function updateAimRing()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local view = camera.ViewportSize
    aimRing.Position = UDim2.fromOffset(view.X / 2, view.Y / 2)
    aimRing.Size = UDim2.fromOffset(numbers.AimRadius * 2, numbers.AimRadius * 2)
    aimRing.Visible = enabled.AimFOVRing and not minimized
end
-- Role radar ----------------------------------------------------------
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
makeButton(visualsPage, "Decrease ESP range by 50 studs", function()
    numbers.ESPRange = math.max(50, numbers.ESPRange - 50)
    inform("ESP range: " .. numbers.ESPRange .. " studs")
end)
makeButton(visualsPage, "Increase ESP range by 50 studs", function()
    numbers.ESPRange = math.min(1500, numbers.ESPRange + 50)
    inform("ESP range: " .. numbers.ESPRange .. " studs")
end)
toggle(visualsPage, "Player ESP", "PlayerESP")
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
makeButton(movementPage, "Walkspeed -5", function()
    numbers.Speed = math.max(8, numbers.Speed - 5)
    applyCharacterSettings()
    inform("Custom walkspeed: " .. numbers.Speed)
end)
makeButton(movementPage, "Walkspeed +5", function()
    numbers.Speed = math.min(75, numbers.Speed + 5)
    applyCharacterSettings()
    inform("Custom walkspeed: " .. numbers.Speed)
end)
toggle(movementPage, "Custom jump power", "CustomJump", applyCharacterSettings)
makeButton(movementPage, "Jump power -10", function()
    numbers.Jump = math.max(30, numbers.Jump - 10)
    applyCharacterSettings()
    inform("Jump power: " .. numbers.Jump)
end)
makeButton(movementPage, "Jump power +10", function()
    numbers.Jump = math.min(150, numbers.Jump + 10)
    applyCharacterSettings()
    inform("Jump power: " .. numbers.Jump)
end)
toggle(movementPage, "Infinite jump", "InfiniteJump")
toggle(movementPage, "Anti-fling velocity cap", "AntiFling")
toggle(movementPage, "Noclip (local)", "Noclip", function(on)
    if not on then restoreNoclip() end
end)
toggle(movementPage, "Fly (touch HUD available outside menu)", "Fly", function(on)
    v54.setFlight(on)
end)
label(movementPage, "Use the floating flight controls on the right: Roblox joystick for direction, hold UP or DOWN for height. Keyboard E/Q or Space/Ctrl also work. The HUD stays visible after X minimizes the menu.", 108, Color3.fromRGB(188, 224, 250), 13)
local function holdButton(page, name, setter)
    local b = makeButton(page, name .. " (hold)", function() end)
    watch(b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            setter(true)
        end
    end))
    watch(b.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            setter(false)
        end
    end))
end
-- Flight altitude buttons are always accessible in the floating HUD.
makeButton(movementPage, "Fly speed +10", function()
    numbers.FlySpeed = math.min(120, numbers.FlySpeed + 10)
    inform("Fly speed: " .. numbers.FlySpeed)
end)
makeButton(movementPage, "Fly speed -10", function()
    numbers.FlySpeed = math.max(10, numbers.FlySpeed - 10)
    inform("Fly speed: " .. numbers.FlySpeed)
end)
makeButton(movementPage, "Camera FOV +10", function()
    numbers.FOV = math.min(110, numbers.FOV + 10)
    if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = numbers.FOV end
    inform("Field of view: " .. numbers.FOV)
end)
makeButton(movementPage, "Camera FOV -10", function()
    numbers.FOV = math.max(40, numbers.FOV - 10)
    if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = numbers.FOV end
    inform("Field of view: " .. numbers.FOV)
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
makeButton(farmPage, "Farm flight speed +5 studs/s", function()
    numbers.FarmFlySpeed = math.min(100, numbers.FarmFlySpeed + 5)
    inform("Farm flight speed: " .. numbers.FarmFlySpeed)
end)
makeButton(farmPage, "Farm flight speed -5 studs/s", function()
    numbers.FarmFlySpeed = math.max(10, numbers.FarmFlySpeed - 5)
    inform("Farm flight speed: " .. numbers.FarmFlySpeed)
end)
makeButton(farmPage, "Teleport interval +0.5 sec", function()
    numbers.FarmTeleportDelay = math.min(8, numbers.FarmTeleportDelay + 0.5)
    inform("Teleport cooldown: " .. numbers.FarmTeleportDelay .. " sec")
end)
makeButton(farmPage, "Teleport interval -0.5 sec", function()
    numbers.FarmTeleportDelay = math.max(1, numbers.FarmTeleportDelay - 0.5)
    inform("Teleport cooldown: " .. numbers.FarmTeleportDelay .. " sec")
end)
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
makeButton(farmPage, "Visit target +10", function()
    numbers.FarmVisitCap = math.min(100, numbers.FarmVisitCap + 10)
    inform("Farm stop after " .. numbers.FarmVisitCap .. " visits (not verified coins)")
end)
makeButton(farmPage, "Visit target -10", function()
    numbers.FarmVisitCap = math.max(10, numbers.FarmVisitCap - 10)
    inform("Farm stop after " .. numbers.FarmVisitCap .. " visits (not verified coins)")
end)
toggle(farmPage, "Show coin markers", "CoinESP", function() scanObjects() end)
makeButton(farmPage, "Collection radius +50 studs", function()
    numbers.FarmRadius = math.min(1800, numbers.FarmRadius + 100)
    inform("Farm radius: " .. numbers.FarmRadius)
end)
makeButton(farmPage, "Collection radius −50 studs", function()
    numbers.FarmRadius = math.max(100, numbers.FarmRadius - 100)
    inform("Farm radius: " .. numbers.FarmRadius)
end)
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
label(aimPage, "Manual aim uses a screen-radius. Auto aim locks only onto a game-confirmed Murderer. Auto shoot sends real gun requests but cannot guarantee server hits.",
    78, Color3.fromRGB(207, 218, 237), 13)
toggle(aimPage, "Aim camera at Murderer (FOV-limited)", "AimAssist", function(on)
    if on then enabled.CameraLock = false; enabled.AutoAimMurderer = false end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end)
toggle(aimPage, "AUTO AIM • confirmed Murderer (full view)", "AutoAimMurderer", function(on)
    if on then enabled.AimAssist = false; enabled.CameraLock = false end
    for _, refresh in ipairs(toggleUpdaters) do refresh() end
end)
toggle(aimPage, "AUTO SHOOT • confirmed Murderer (Gun only)", "AutoShootMurderer")
makeButton(aimPage, "SHOOT confirmed Murderer NOW (one attempt)", function()
    attemptMurdererShot(true)
end)
local shotInfoLabel = label(aimPage, "Gun status: waiting", 72, Color3.fromRGB(189, 221, 255), 13)

toggle(aimPage, "Require clear line of sight", "AimWallCheck")
toggle(aimPage, "Only aim when my role is Sheriff/Hero", "AimRequireSheriff")
toggle(aimPage, "Show aim area on screen", "AimFOVRing")
makeButton(aimPage, "Increase aim speed", function()
    numbers.AimSmooth = math.min(1, numbers.AimSmooth + 0.1)
    inform("Aim smooth step " .. math.floor(numbers.AimSmooth * 100) .. "%")
end)
makeButton(aimPage, "Decrease aim speed", function()
    numbers.AimSmooth = math.max(0.1, numbers.AimSmooth - 0.1)
    inform("Aim smooth step " .. math.floor(numbers.AimSmooth * 100) .. "%")
end)
makeButton(aimPage, "Increase aim radius", function()
    numbers.AimRadius = math.min(500, numbers.AimRadius + 40)
    inform("Aim radius " .. numbers.AimRadius .. " px")
end)
makeButton(aimPage, "Decrease aim radius", function()
    numbers.AimRadius = math.max(70, numbers.AimRadius - 40)
    inform("Aim radius " .. numbers.AimRadius .. " px")
end)
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
    "Connect a gamepad, then hold LB (Xbox) / L1 (PlayStation) to smoothly track a game-confirmed Murderer. This works with the menu minimized. No right-thumbstick/cursor input needed. R1/RB shooting is optional and OFF by default.",
    120, Color3.fromRGB(195, 222, 247), 13)
toggle(aimPage, "Controller HOLD L1/LB to aim at Murderer", "ControllerHoldAim", function(on)
    if not on then v54.gamepadAimHeld = false end
    v54.updateControllerStatus()
end)
toggle(aimPage, "Controller R1/RB manual shot (optional)", "ControllerR1Shoot", function()
    v54.updateControllerStatus()
end)
v54.controllerStatusLabel = label(aimPage, "Controller status: waiting", 90,
    Color3.fromRGB(157, 213, 255), 13)
v54.updateControllerStatus()
heading(funPage, "FUN MOVEMENT")
label(funPage, "Fling is experimental: physics constraints may create local contact but cannot force another player's server-owned movement. FUN shows overlap and locally observed displacement.",
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
label(funPage, "SINGLE FLING METHOD • 2,500 studs/s, short timed contact. Fling All uses this exact routine for each living player. Target motion here is LOCAL-ONLY evidence.",
    95, Color3.fromRGB(255, 207, 172), 12)
makeButton(funPage, "FLING SELECTED • 2,500 studs/s", function()
    flingSelected()
end)
makeButton(funPage, "FLING ALL • SAME 2,500 METHOD", function()
    v54.flingAll()
end)
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
makeButton(funPage, "Stop fling / spinning / ALL", function()
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
    inform("Physics effects stopped / Fling All cancelled")
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
    if key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.DPadRight
        or key == Enum.KeyCode.DPadUp or key == Enum.KeyCode.DPadDown then
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
    elseif key == Enum.KeyCode.DPadUp then
        focusMenuControl(-1)
    elseif key == Enum.KeyCode.DPadDown then
        focusMenuControl(1)
    end
    -- Let Roblox handle ButtonA GuiButton.Activated for the focused button.
end))
end
-- Settings page -------------------------------------------------------
heading(settingsPage, "Visual settings")
toggle(settingsPage, "Ghosted avatar (only on MY screen)", "LocalGhost", setLocalGhost)
toggle(settingsPage, "Fullbright", "Fullbright", setFullbright)
toggle(settingsPage, "Remove fog and atmosphere haze", "NoFog", setNoFog)
toggle(settingsPage, "Hide my overhead name (local)", "HideOwnName", setHideOwnName)
toggle(settingsPage, "Reduce sliding on ice (local)", "AntiSlip")
toggle(settingsPage, "Disable post-processing FX", "LowFX", setLowFX)
toggle(settingsPage, "Anti-void (experimental)", "AntiVoid")
makeButton(settingsPage, "Reset gravity", function()
    Workspace.Gravity = previousGravity
    inform("Gravity restored")
end)
makeButton(settingsPage, "Decrease local gravity by 20", function()
    Workspace.Gravity = math.max(30, Workspace.Gravity - 20)
    inform("Local gravity: " .. math.floor(Workspace.Gravity))
end)
makeButton(settingsPage, "Increase local gravity by 20", function()
    Workspace.Gravity = math.min(300, Workspace.Gravity + 20)
    inform("Local gravity: " .. math.floor(Workspace.Gravity))
end)
heading(settingsPage, "SAVED SETTINGS")
label(settingsPage, "Save preferences for next session. Uses executor readfile/writefile when supported; otherwise only this executor session is remembered. Active farming, shooting, fling and flight are NEVER auto-enabled on load.",
    112, Color3.fromRGB(191, 213, 245), 12)
v54.settingsFile = "SPECTRA_MM2_settings_v5_9.json"
v54.safeActive = {
    AutoCoinFarm = true, AutoGunPickup = true, AutoGunApproach = true,
    AutoShootMurderer = true, FlingActive = true, Fly = true, SpinMode = true,
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
        animationPack = v54.selectedAnimationPack}
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
    numbers.FarmRadius = math.clamp(numbers.FarmRadius, 100, 1800)
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
    enabled.AimAssist = false
    enabled.AutoAimMurderer = false
    enabled.AutoShootMurderer = false
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
label(diagnosticsPage, "Not implemented or verified: silent hit redirection, guaranteed hits, kill aura, kill-all, god mode, forced wins, auto trades/buys/crafting, bag resetting, Discord webhooks, multi-account sync, server hop or FPS unlocking. These require game-specific server integration, independent APIs, or special permissions.", 210, Color3.fromRGB(255, 206, 178), 13)
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
        task.wait(0.65)
        if enabled.AutoGunPickup and not v54.gunPickupBusy and not destroyed then
            v54.attemptGunPickup(true)
        end
    end
end)
-- Server calls can yield; keep them out of the RenderStep and heartbeat.
task.spawn(function()
    while not destroyed do
        task.wait(0.28)
        if enabled.AutoShootMurderer then attemptMurdererShot(false) end
    end
end)
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
    if enabled.Noclip then
        local char = characterOf(localPlayer)
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    if originalCollisions[part] == nil then
                        originalCollisions[part] = part.CanCollide
                    end
                    part.CanCollide = false
                end
            end
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
    if destroyed or not (enabled.AimAssist or enabled.AutoAimMurderer or (enabled.ControllerHoldAim and v54.gamepadAimHeld)) or enabled.CameraLock or spectateTarget then return end
    local camera = Workspace.CurrentCamera
    local target = findAimPart()
    if camera and target then
        local wanted = CFrame.lookAt(camera.CFrame.Position, target.Position)
        camera.CFrame = camera.CFrame:Lerp(wanted, numbers.AimSmooth)
    end
end)
local cameraStepName = "LearningHub_Camera_" .. tostring(localPlayer.UserId)

local function unload()
    if destroyed then return end
    destroyed = true
    for _, c in ipairs(connections) do c:Disconnect() end
    RunService:UnbindFromRenderStep(cameraStepName)
    RunService:UnbindFromRenderStep(aimStepName)
    enabled.AutoCoinFarm = false
    enabled.AutoGunApproach = false
    enabled.AutoGunPickup = false
    v54.farmTravelToken += 1
    v54.postActionToken += 1
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
    gui:Destroy()
    if environment.MM2LearningHubUnload == unload then
        environment.MM2LearningHubUnload = nil
    end
end
environment.MM2LearningHubUnload = unload
performFullUnload = unload

-- Load saved preferences quietly on each run; active automation stays off.
v54.loadSettings(true)
-- First pass only once when launched.
applyCharacterSettings()
refreshRoles()
refreshPlayerDropdown()
updateRoleRadar()
inform("SPECTRA v6.7 loaded • 2,500 fling + Moondiety telemetry")
print("SPECTRA MM2 Hub v6.7 loaded. X minimizes; STOP FLING in FUN.")
