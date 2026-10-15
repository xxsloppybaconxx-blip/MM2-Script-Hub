-- SPECTRA Extras 1.0 | Original, client-only Luau
-- Camera assist + coin/gun auto-walk + local spin. No remote attacks or forced wins.
-- Designed for testing in a LocalScript in your own Roblox Studio place.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")
local me = Players.LocalPlayer
if not me then return end
local pg = me:WaitForChild("PlayerGui")
local env = _G
if type(getgenv) == "function" then
    local ok, e = pcall(getgenv)
    if ok and type(e) == "table" then env = e end
end
if type(env.SpectraExtrasUnload) == "function" then
    pcall(env.SpectraExtrasUnload)
end
local on = { Aim = false, WallCheck = true, CoinWalk = false, GunWalk = false, Spin = false }
local roleMap, roleUpdated, requesting = {}, 0, false
local alive = true
local connections = {}
local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end
local function char(p) return p and p.Character end
local function root(p) local c=char(p); return c and c:FindFirstChild("HumanoidRootPart") end
local function humanoid(p) local c=char(p); return c and c:FindFirstChildOfClass("Humanoid") end
local function living(p) local h=humanoid(p); return h and h.Health > 0 end
local function knifeEquipped(p)
    local c = char(p)
    for _, tool in ipairs(c and c:GetChildren() or {}) do
        if tool:IsA("Tool") and tool.Name:lower():find("knife", 1, true) then return true end
    end
    return false
end
local function refreshRoles()
    if requesting or not alive then return end
    requesting = true
    task.spawn(function()
        local found = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
        if found and found:IsA("RemoteFunction") then
            local ok, data = pcall(function() return found:InvokeServer() end)
            if ok and type(data) == "table" then
                local fresh = {}
                for username, entry in pairs(data) do
                    if type(username) == "string" and type(entry) == "table"
                        and type(entry.Role) == "string" then
                        fresh[username] = entry.Role
                    end
                end
                roleMap = fresh
                roleUpdated = os.clock()
            end
        end
        requesting = false
    end)
end
local function isMurderer(p)
    if not p or p == me or not living(p) then return false end
    if os.clock() - roleUpdated < 15 and roleMap[p.Name] then
        return roleMap[p.Name] == "Murderer"
    end
    return knifeEquipped(p) -- Visible-tool fallback, not a confirmed role
end
local function visible(camera, targetPart, targetChar)
    if not on.WallCheck then return true end
    local origin = camera.CFrame.Position
    local vec = targetPart.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = char(me) and {char(me)} or {}
    local result = Workspace:Raycast(origin, vec, params)
    return not result or result.Instance:IsDescendantOf(targetChar)
end
local function aimTarget()
    local camera = Workspace.CurrentCamera
    if not camera then return nil end
    local center = camera.ViewportSize / 2
    local closest, best = nil, 220
    for _, p in ipairs(Players:GetPlayers()) do
        if isMurderer(p) then
            local c = char(p)
            local part = c and (c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart"))
            if part then
                local point, projected = camera:WorldToViewportPoint(part.Position)
                if projected and point.Z > 0 then
                    local d = (Vector2.new(point.X,point.Y) - center).Magnitude
                    if d < best and visible(camera,part,c) then
                        best, closest = d, part
                    end
                end
            end
        end
    end
    return closest
end
local function nearestNamed(kind)
    local mine = root(me)
    if not mine then return nil end
    local best, dist = nil, 180
    for _, item in ipairs(Workspace:GetDescendants()) do
        if item:IsA("BasePart") then
            local n = item.Name:lower()
            local matching = (kind == "coin" and (n == "coin" or n == "coinpart"))
                or (kind == "gun" and (n == "gundrop" or n == "droppedgun" or n == "dropped_gun"))
            if matching then
                local d = (item.Position - mine.Position).Magnitude
                if d < dist then best,dist=item,d end
            end
        end
    end
    return best
end

local gui=Instance.new("ScreenGui")
gui.Name="SpectraExtras"
gui.ResetOnSpawn=false
gui.Parent=pg
local panel=Instance.new("Frame")
panel.Size=UDim2.fromOffset(276,290)
panel.Position=UDim2.new(.5,-138,.36,0)
panel.BackgroundColor3=Color3.fromRGB(17,25,40)
panel.BorderSizePixel=0
panel.Parent=gui
local panelCorner=Instance.new("UICorner")
panelCorner.CornerRadius=UDim.new(0,12)
panelCorner.Parent=panel
local outline=Instance.new("UIStroke")
outline.Color=Color3.fromRGB(58,99,138)
outline.Parent=panel
local header=Instance.new("TextLabel")
header.BackgroundTransparency=1
header.Size=UDim2.new(1,-40,0,39)
header.Position=UDim2.fromOffset(12,0)
header.Font=Enum.Font.GothamBold
header.TextSize=17
header.TextColor3=Color3.fromRGB(231,246,255)
header.TextXAlignment=Enum.TextXAlignment.Left
header.Text="SPECTRA  /  EXTRAS"
header.Parent=panel
local close=Instance.new("TextButton")
close.Size=UDim2.fromOffset(28,28)
close.Position=UDim2.new(1,-35,0,5)
close.BackgroundColor3=Color3.fromRGB(105,42,62)
close.TextColor3=Color3.new(1,1,1)
close.Font=Enum.Font.GothamBold
close.Text="X"
close.Parent=panel
Instance.new("UICorner",close).CornerRadius=UDim.new(0,6)
local hint=Instance.new("TextLabel")
hint.Position=UDim2.fromOffset(12,39)
hint.Size=UDim2.new(1,-24,0,33)
hint.BackgroundTransparency=1
hint.Text="Aim = camera only. Coins/gun = auto-walk."
hint.TextWrapped=true
hint.TextSize=11
hint.Font=Enum.Font.Gotham
hint.TextColor3=Color3.fromRGB(173,194,214)
hint.Parent=panel
local status=Instance.new("TextLabel")
status.Position=UDim2.fromOffset(12,255)
status.Size=UDim2.new(1,-24,0,30)
status.BackgroundTransparency=1
status.Font=Enum.Font.Gotham
status.TextSize=11
status.TextWrapped=true
status.TextColor3=Color3.fromRGB(135,200,244)
status.Text="Ready • experimental features"
status.Parent=panel
local toggles={}
local function toggleButton(title,key,y)
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(1,-24,0,31)
    b.Position=UDim2.fromOffset(12,y)
    b.BackgroundColor3=Color3.fromRGB(33,49,72)
    b.TextColor3=Color3.fromRGB(226,236,247)
    b.Font=Enum.Font.GothamMedium
    b.TextSize=12
    b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,7)
    local function redraw() b.Text=(on[key] and "[ON]  " or "[OFF]  ") .. title end
    connect(b.MouseButton1Click,function()
        on[key]=not on[key]
        if key == "CoinWalk" and on[key] then on.GunWalk=false end
        if key == "GunWalk" and on[key] then on.CoinWalk=false end
        for _,update in ipairs(toggles) do update() end
        status.Text=title..(on[key] and " enabled" or " disabled")
        if key == "Spin" and not on[key] and root(me) then root(me).AssemblyAngularVelocity=Vector3.zero end
    end)
    table.insert(toggles,redraw)
    redraw()
end
toggleButton("Aim assist • Murderer only", "Aim",77)
toggleButton("Line of sight check", "WallCheck",112)
toggleButton("Auto-walk to nearby coins", "CoinWalk",147)
toggleButton("Auto-walk to dropped gun", "GunWalk",182)
toggleButton("Local spin effect", "Spin",217)
-- Mobile + mouse dragging by header.
local dragging,origin,startPos=false,nil,nil
connect(header.InputBegan,function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging=true; origin=input.Position; startPos=panel.Position
    end
end)
connect(UIS.InputChanged,function(input)
    if dragging and origin and (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=input.Position-origin
        panel.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
connect(UIS.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)

local lastScan,lastRolePoll=0,0
local aimStep="SPECTRA_Extras_Aim_" .. tostring(me.UserId)
RunService:BindToRenderStep(aimStep,Enum.RenderPriority.Camera.Value+2,function()
    if not alive or not on.Aim then return end
    local camera=Workspace.CurrentCamera
    local target=aimTarget()
    if camera and target then
        local desired=CFrame.lookAt(camera.CFrame.Position,target.Position)
        camera.CFrame=camera.CFrame:Lerp(desired,.18)
    end
end)
connect(RunService.Heartbeat,function()
    if not alive then return end
    local now=os.clock()
    local myRoot=root(me)
    if on.Spin and myRoot then
        myRoot.AssemblyAngularVelocity=Vector3.new(0,12,0)
    end
    if now-lastRolePoll >= 7 then
        lastRolePoll=now
        refreshRoles()
    end
    if now-lastScan >= 1.3 then
        lastScan=now
        if on.CoinWalk or on.GunWalk then
            local h=humanoid(me)
            local destination=nearestNamed(on.GunWalk and "gun" or "coin")
            if h and h.Health>0 and destination then
                h:MoveTo(destination.Position)
                status.Text=(on.GunWalk and "Walking to dropped gun" or "Walking to a coin")
            else
                status.Text="No matching nearby object found"
            end
        end
    end
end)
local function unload()
    if not alive then return end
    alive=false
    RunService:UnbindFromRenderStep(aimStep)
    for _,c in ipairs(connections) do c:Disconnect() end
    local r=root(me)
    if r then r.AssemblyAngularVelocity=Vector3.zero end
    local h=humanoid(me)
    if h and r then h:MoveTo(r.Position) end
    gui:Destroy()
    if env.SpectraExtrasUnload==unload then env.SpectraExtrasUnload=nil end
end
env.SpectraExtrasUnload=unload
connect(close.MouseButton1Click,unload)
refreshRoles()
print("SPECTRA Extras loaded: aim camera, coin walk, gun walk, spin.")
