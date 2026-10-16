-- Adopt Me Halloween 2026 experimental client helper
-- Ghost Gallery + Hauntlet 2 | No MM2 dependencies or remote-event guessing
-- IMPORTANT: ESP and auto actions require game objects visible to the client.
local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local Tags=game:GetService("CollectionService")
local Input=game:GetService("UserInputService")
local player=Players.LocalPlayer
local env=(getgenv and getgenv()) or _G
if env.AdoptMeHalloweenHub and env.AdoptMeHalloweenHub.Stop then
    pcall(env.AdoptMeHalloweenHub.Stop)
end
local live=true
local cfg={
    mode="Ghost Gallery", ghostESP=true, ghostTP=false, ghostAuto=false,
    doorESP=true, doorTP=false, doorAuto=false, safeOnly=false
}
local overlays,connections={},{}
local nextAction=0
local previousDoor,previousDoorAt=nil,0
local function contains(s,term)
    return string.find(string.lower(s),term,1,true)~=nil
end
local function hasTag(inst,tag)
    local ok,value=pcall(function()return Tags:HasTag(inst,tag)end)
    return ok and value
end
local function attr(inst,key)
    local ok,value=pcall(function()return inst:GetAttribute(key)end)
    if ok then return value end
end
local function mainPart(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart",true)
    end
end
local function root()
    local c=player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function inCharacter(inst)
    for _,plr in ipairs(Players:GetPlayers())do
        if plr.Character and inst:IsDescendantOf(plr.Character)then return true end
    end
    return false
end
local function ghostTarget(inst)
    if inCharacter(inst)then return false end
    local n=string.lower(inst.Name)
    if contains(n,"gallery") or contains(n,"lobby") or contains(n,"spawner")
       or contains(n,"manager") or contains(n,"trigger") or contains(n,"template")
       or contains(n,"camera") or contains(n,"effect") then return false end
    if contains(n,"ghost") or contains(n,"possess") or contains(n,"poltergeist")
       or contains(n,"specter") then return true end
    for _,tag in ipairs({"Ghost","Haunted","Possessed","GhostTarget"})do
        if hasTag(inst,tag)then return true end
    end
    for _,key in ipairs({"Haunted","IsHaunted","Possessed","GhostInside","HasGhost"})do
        if attr(inst,key)==true then return true end
    end
    local count=attr(inst,"GhostCount")
    return type(count)=="number" and count>0
end
local function getDoor(inst)
    if not contains(inst.Name,"door") or inCharacter(inst)then return nil end
    local obj=inst
    local p=inst.Parent
    for i=1,3 do
        if p and p:IsA("Model") and contains(p.Name,"door")then
            obj=p; p=p.Parent
        else break end
    end
    return obj
end
local function doorRisk(inst)
    local n=string.lower(inst.Name)
    local danger=false
    local safe=false
    for _,key in ipairs({"GhostInside","HasGhost","ContainsGhost","Unsafe",
        "IsDangerous","PhoneMarked","BoltPhoneTarget"})do
        if attr(inst,key)==true then danger=true end
    end
    for _,key in ipairs({"Safe","IsSafe","GhostFree"})do
        if attr(inst,key)==true then safe=true end
    end
    if attr(inst,"GhostInside")==false or attr(inst,"HasGhost")==false then safe=true end
    if hasTag(inst,"GhostDoor") or hasTag(inst,"DangerDoor")
       or hasTag(inst,"PhoneMarked")then danger=true end
    if hasTag(inst,"SafeDoor")then safe=true end
    if danger then return 100,"GHOST SIGNAL",Color3.fromRGB(255,90,95),false end
    if safe then return -10,"SAFE SIGNAL",Color3.fromRGB(80,235,130),true end
    if contains(n,"nightmare") or contains(n,"spike") or contains(n,"electric")then
        return 60,"HIGH RISK",Color3.fromRGB(255,140,70),false
    end
    if contains(n,"haunted") or contains(n,"mystery") or contains(n,"bounce")then
        return 35,"RISKY TYPE",Color3.fromRGB(255,165,75),false
    end
    if contains(n,"golden") or contains(n,"security") or contains(n,"spider")then
        return 15,"ITEM/KEY?",Color3.fromRGB(255,205,95),false
    end
    return 10,"UNKNOWN",Color3.fromRGB(255,205,95),false
end
local function scan(mode)
    local items,seen={},{}
    local r=root()
    if not r then return items end
    for _,inst in ipairs(Workspace:GetDescendants())do
        if inst:IsA("BasePart") or inst:IsA("Model")then
            local selected=nil
            if mode=="Ghost Gallery" then
                if ghostTarget(inst)then
                    selected=inst
                    if inst:IsA("BasePart") and inst.Parent:IsA("Model")
                        and ghostTarget(inst.Parent)then selected=inst.Parent end
                end
            else selected=getDoor(inst) end
            if selected and not seen[selected]then
                local p=mainPart(selected)
                if p then
                    local d=(r.Position-p.Position).Magnitude
                    if d<=(mode=="Ghost Gallery" and 250 or 150)then
                        seen[selected]=true
                        local score,name,color,safe=0,"GHOST TARGET",Color3.fromRGB(110,190,255),true
                        if mode=="Hauntlet 2"then
                            score,name,color,safe=doorRisk(selected)
                        end
                        table.insert(items,{obj=selected,part=p,pos=p.Position,
                            distance=d,score=score,name=name,color=color,safe=safe})
                    end
                end
            end
        end
    end
    table.sort(items,function(a,b)
        if mode=="Hauntlet 2" and a.score~=b.score then return a.score<b.score end
        return a.distance<b.distance
    end)
    return items
end
local gui=Instance.new("ScreenGui")
gui.Name="AdoptMeHalloweenHub2026"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.DisplayOrder=900
gui.Parent=player:WaitForChild("PlayerGui")
local panel=Instance.new("Frame")
panel.Name="Window"
panel.Size=UDim2.fromOffset(306,362)
panel.Position=UDim2.new(0,18,0.5,-181)
panel.BackgroundColor3=Color3.fromRGB(24,27,40)
panel.BorderSizePixel=0
panel.Parent=gui
Instance.new("UICorner",panel).CornerRadius=UDim.new(0,10)
local border=Instance.new("UIStroke",panel)
border.Color=Color3.fromRGB(89,97,138)
local function text(y,h,msg,size,color)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1
    l.Position=UDim2.fromOffset(12,y)
    l.Size=UDim2.new(1,-24,0,h)
    l.Font=Enum.Font.GothamMedium
    l.TextSize=size or 12
    l.TextColor3=color or Color3.new(1,1,1)
    l.TextXAlignment=Enum.TextXAlignment.Left
    l.TextWrapped=true
    l.Text=msg
    l.Parent=panel
    return l
end
text(10,25,"👻 Adopt Me Halloween 2026",16)
text(36,19,"Experimental: red = danger; yellow = unknown",10,Color3.fromRGB(190,198,219))
local function button(y,title,key)
    local b=Instance.new("TextButton")
    b.Position=UDim2.fromOffset(12,y)
    b.Size=UDim2.new(1,-24,0,33)
    b.TextColor3=Color3.new(1,1,1)
    b.TextSize=12
    b.Font=Enum.Font.GothamMedium
    b.BorderSizePixel=0
    b.Parent=panel
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6)
    local function repaint()
        local on=key and cfg[key]
        b.BackgroundColor3=on and Color3.fromRGB(34,123,102)
            or Color3.fromRGB(51,57,79)
        b.Text=title..(key and (on and "  [ON]" or "  [OFF]") or "")
    end
    if key then b.MouseButton1Click:Connect(function()cfg[key]=not cfg[key];repaint()end)end
    repaint()
    return b
end
local modeButton=button(62,"Mode: Ghost Gallery")
local ghost={
    button(103,"Ghost ESP","ghostESP"),
    button(142,"Teleport to ghosts","ghostTP"),
    button(181,"Auto aim + Ghost Blaster","ghostAuto")
}
local doors={
    button(103,"Door ESP + risk","doorESP"),
    button(142,"Teleport near selected door","doorTP"),
    button(181,"Auto choose / enter door","doorAuto"),
    button(220,"Require confirmed-safe signal","safeOnly")
}
local function drawMode()
    modeButton.Text="Mode: "..cfg.mode.." (tap to switch)"
    for _,b in ipairs(ghost)do b.Visible=cfg.mode=="Ghost Gallery"end
    for _,b in ipairs(doors)do b.Visible=cfg.mode=="Hauntlet 2"end
end
modeButton.MouseButton1Click:Connect(function()
    cfg.mode=cfg.mode=="Ghost Gallery" and "Hauntlet 2" or "Ghost Gallery"
    drawMode()
end)
drawMode()
local status=text(265,44,"Status: ready. Join an event round.",11,Color3.fromRGB(200,215,237))
local unload=button(314,"Unload / Close")
local function setStatus(msg)
    if status.Parent then status.Text="Status: "..msg end
end
local function clearESP()
    for inst,pair in pairs(overlays)do
        pair.h:Destroy();pair.b:Destroy()
        overlays[inst]=nil
    end
end
local function display(items,enabled)
    if not enabled then clearESP();return end
    local keep={}
    for i=1,math.min(#items,35)do
        local item=items[i]
        local obj=item.obj
        keep[obj]=true
        if not overlays[obj]then
            local h=Instance.new("Highlight")
            h.Name="AdoptMeGhostDoorESP"
            h.Adornee=obj
            h.FillTransparency=0.78
            h.OutlineTransparency=0
            h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent=gui
            local b=Instance.new("BillboardGui")
            b.Name="AdoptMeTargetLabel"
            b.Adornee=item.part
            b.Size=UDim2.fromOffset(180,30)
            b.StudsOffset=Vector3.new(0,3,0)
            b.AlwaysOnTop=true
            b.Parent=gui
            local l=Instance.new("TextLabel")
            l.Name="Label"
            l.Size=UDim2.fromScale(1,1)
            l.BackgroundColor3=Color3.fromRGB(15,18,27)
            l.BackgroundTransparency=0.2
            l.Font=Enum.Font.GothamBold
            l.TextSize=11
            l.TextColor3=Color3.new(1,1,1)
            l.Parent=b
            overlays[obj]={h=h,b=b}
        end
        local pair=overlays[obj]
        pair.h.FillColor=item.color
        pair.h.OutlineColor=item.color
        pair.b.Adornee=item.part
        pair.b.Label.Text=item.name.." | "..math.floor(item.distance).." studs"
    end
    for obj,pair in pairs(overlays)do
        if not keep[obj]then
            pair.h:Destroy();pair.b:Destroy();overlays[obj]=nil
        end
    end
end
local function tpNear(position,range)
    local r=root()
    if not r then return false end
    if (r.Position-position).Magnitude<=range then return true end
    local away=r.Position-position
    if away.Magnitude<0.2 then away=Vector3.new(0,0,1) end
    local dest=position+away.Unit*range+Vector3.new(0,2,0)
    return pcall(function()r.CFrame=CFrame.lookAt(dest,position)end)
end
local function shoot(position)
    local c=player.Character
    if not c then return false end
    local tool
    for _,parent in ipairs({c,player:FindFirstChildOfClass("Backpack")})do
        if parent then
            for _,t in ipairs(parent:GetChildren())do
                if t:IsA("Tool") and (contains(t.Name,"blaster") or contains(t.Name,"vacuum"))then
                    tool=t;break
                end
            end
        end
        if tool then break end
    end
    if not tool then return false end
    if tool.Parent~=c then
        local hum=c:FindFirstChildWhichIsA("Humanoid")
        if hum then pcall(function()hum:EquipTool(tool)end)end
    end
    if tool.Parent~=c then return false end
    local camera=Workspace.CurrentCamera
    if camera then pcall(function()camera.CFrame=CFrame.lookAt(camera.CFrame.Position,position)end)end
    return pcall(function()tool:Activate()end)
end
local function enterDoor(door)
    local p=door:FindFirstChildWhichIsA("ProximityPrompt",true)
    if p and p.Enabled then
        local r=root()
        local point=p.Parent:IsA("BasePart") and p.Parent.Position or
            (mainPart(door) and mainPart(door).Position)
        if not r or (point and (r.Position-point).Magnitude>p.MaxActivationDistance)then
            return false,"Move closer or enable door teleport"
        end
        local ok=pcall(function()
            p:InputHoldBegin()
            task.wait(math.max(p.HoldDuration+0.08,0.1))
            p:InputHoldEnd()
        end)
        return ok,ok and "Prompt attempted" or "Prompt unavailable"
    end
    local click=door:FindFirstChildWhichIsA("ClickDetector",true)
    if click and type(fireclickdetector)=="function"then
        local ok=pcall(function()fireclickdetector(click)end)
        return ok,ok and "Click attempted" or "Click failed"
    end
    return false,"No client interaction exposed"
end
local function step()
    local items=scan(cfg.mode)
    if cfg.mode=="Ghost Gallery"then
        display(items,cfg.ghostESP)
        if not cfg.ghostAuto then setStatus(#items.." ghost targets; auto off");return end
        if #items==0 then setStatus("No visible ghost targets in current area");return end
        if os.clock()<nextAction then return end
        if cfg.ghostTP then tpNear(items[1].pos,10)end
        local ok=shoot(items[1].pos)
        setStatus(ok and ("Blaster action sent toward "..items[1].obj.Name)
            or "No Ghost Blaster tool found/usable")
        nextAction=os.clock()+0.4
    else
        display(items,cfg.doorESP)
        if not cfg.doorAuto then setStatus(#items.." doors; auto off");return end
        if os.clock()<nextAction then return end
        local chosen
        for _,v in ipairs(items)do
            if v.score<100 and (not cfg.safeOnly or v.safe)
               and (v.obj~=previousDoor or os.clock()-previousDoorAt>15)then
                chosen=v;break
            end
        end
        if not chosen then
            setStatus(cfg.safeOnly and "No confirmed-safe door signal"
                or "No new non-danger door detected")
            return
        end
        if cfg.doorTP then tpNear(chosen.pos,4)end
        local ok,reason=enterDoor(chosen.obj)
        previousDoor,previousDoorAt=chosen.obj,os.clock()
        nextAction=os.clock()+2.5
        setStatus((ok and "Door attempted: " or "Door blocked: ")
            ..chosen.name.." / "..reason)
    end
end
local function stop()
    if not live then return end
    live=false
    for _,c in ipairs(connections)do pcall(function()c:Disconnect()end)end
    clearESP()
    gui:Destroy()
    if env.AdoptMeHalloweenHub and env.AdoptMeHalloweenHub.Stop==stop then
        env.AdoptMeHalloweenHub=nil
    end
end
unload.MouseButton1Click:Connect(stop)
-- Drag the panel using mouse or touch; F6 toggles visibility on desktop.
local dragging,startPoint,startPos=false,nil,nil
panel.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1
       or i.UserInputType==Enum.UserInputType.Touch then
        dragging=true;startPoint=i.Position;startPos=panel.Position
    end
end)
panel.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1
       or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)
table.insert(connections,Input.InputChanged:Connect(function(i)
    if dragging and startPoint and (i.UserInputType==Enum.UserInputType.Touch
       or i.UserInputType==Enum.UserInputType.MouseMovement)then
        local delta=i.Position-startPoint
        panel.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,
            startPos.Y.Scale,startPos.Y.Offset+delta.Y)
    end
end))
table.insert(connections,Input.InputBegan:Connect(function(i,processed)
    if not processed and i.KeyCode==Enum.KeyCode.F6 then
        panel.Visible=not panel.Visible
    end
end))
env.AdoptMeHalloweenHub={Stop=stop,Settings=cfg}
task.spawn(function()
    while live and gui.Parent do
        local ok,err=pcall(step)
        if not ok then setStatus("Error: "..tostring(err):sub(1,70))end
        task.wait(0.85)
    end
end)
print("[Adopt Me Halloween Hub] Experimental helper loaded. F6 to show/hide.")
