if not ESP then ESP = {} end

ESP.CornerColor         = Color3.new(1,1,1)
ESP.CornerThickness     = 1
ESP.BaseCornerLength    = 16
ESP.OutlineColor        = Color3.new(0,0,0)
ESP.OutlineThickness    = 2
ESP.SkeletonMainColor   = Color3.fromRGB(255,255,255)
ESP.SkeletonOutlineColor= Color3.fromRGB(0,0,0)
ESP.SkeletonMainThickness= 1.6
ESP.SkeletonOutlineThickness= 3.2
ESP.ShowNames           = true
ESP.NameTextSize        = 15
ESP.ShowDistance        = true
ESP.DistanceTextSize    = 14
ESP.EnableHealthBar     = true
ESP.HealthBarSide       = "Left"
ESP.HealthBarGap        = 6
ESP.RescanInterval      = 0.25

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera

local Vector2_new = Vector2.new
local Color3_fromRGB = Color3.fromRGB
local time = time
local floor = math.floor
local clamp = math.clamp
local huge = math.huge

ESP.DefaultAdapter = {
    getRoot = function(character)
        return character:FindFirstChild("HumanoidRootPart")
    end,
    getHumanoid = function(character)
        return character:FindFirstChildOfClass("Humanoid")
    end,
    getHealth = function(humanoid)
        return humanoid and humanoid.Health or 0, humanoid and humanoid.MaxHealth or 0
    end,
    isAlive = function(humanoid)
        return humanoid and humanoid.Health > 0
    end,
    isR15 = function(humanoid)
        return humanoid and humanoid.RigType == Enum.HumanoidRigType.R15
    end
}

local Cache = {}
local BoxCache = {}
local SkeletonCache = {}
local NameCache = {}
local DistanceCache = {}
local HealthBarCache = {}

local function createOutlinedTextArray(offsets, mainColor, outlineColor, size, fontMain, fontOutline)
    local arr = {}
    for i = 1, #offsets do
        local t = Drawing.new("Text")
        t.Color = outlineColor
        t.Transparency = 1
        t.Size = size
        t.Center = true
        t.Outline = false
        t.Font = fontOutline
        t.Visible = false
        arr[i] = t
    end
    local main = Drawing.new("Text")
    main.Color = mainColor
    main.Transparency = 1
    main.Size = size
    main.Center = true
    main.Outline = false
    main.Font = fontMain
    main.Visible = false
    arr[#offsets + 1] = main
    return arr
end

local function updateOutlinedText(arr, offsets, basePos, text, size)
    if not arr then return end
    for i = 1, #offsets do
        local t = arr[i]
        t.Text = text
        t.Size = size
        t.Position = basePos + offsets[i]
        t.Visible = true
    end
    local main = arr[#offsets + 1]
    main.Text = text
    main.Size = size
    main.Position = basePos
    main.Visible = true
end

local function hideOutlinedText(arr)
    if not arr then return end
    for i = 1, #arr do
        arr[i].Visible = false
    end
end

local function getBox(id)
    local arr = BoxCache[id]
    if arr then return arr end
    arr = {}
    for i = 1,8 do
        local line = Drawing.new("Line")
        line.Visible = false
        line.Thickness = ESP.OutlineThickness
        line.Color = ESP.OutlineColor
        line.Transparency = 1
        arr[i] = line
    end
    for i = 9,16 do
        local corner = Drawing.new("Line")
        corner.Visible = false
        corner.Thickness = ESP.CornerThickness
        corner.Color = ESP.CornerColor
        corner.Transparency = 1
        arr[i] = corner
    end
    BoxCache[id] = arr
    return arr
end

local NAME_OUTLINE_OFFSETS = {
    Vector2_new(-1,0), Vector2_new(1,0), Vector2_new(0,-1), Vector2_new(0,1),
    Vector2_new(-1,-1), Vector2_new(-1,1), Vector2_new(1,-1), Vector2_new(1,1)
}
local DISTANCE_OUTLINE_OFFSETS = NAME_OUTLINE_OFFSETS

local function getNameArray(id)
    if not ESP.ShowNames then return nil end
    local arr = NameCache[id]
    if arr then return arr end
    arr = createOutlinedTextArray(NAME_OUTLINE_OFFSETS, ESP.CornerColor, ESP.OutlineColor, ESP.NameTextSize, 1, 1)
    NameCache[id] = arr
    return arr
end

local function getDistanceArray(id)
    if not ESP.ShowDistance then return nil end
    local arr = DistanceCache[id]
    if arr then return arr end
    arr = createOutlinedTextArray(DISTANCE_OUTLINE_OFFSETS, ESP.CornerColor, ESP.OutlineColor, ESP.DistanceTextSize, 1, 1)
    DistanceCache[id] = arr
    return arr
end

local function getHealthBar(id)
    if not ESP.EnableHealthBar then return nil end
    local hb = HealthBarCache[id]
    if hb then return hb end
    hb = {}
    hb.outline = Drawing.new("Line")
    hb.outline.Color = ESP.OutlineColor
    hb.outline.Thickness = 4
    hb.outline.Transparency = 1
    hb.outline.Visible = false

    hb.background = Drawing.new("Line")
    hb.background.Color = Color3_fromRGB(0,0,0)
    hb.background.Thickness = 4
    hb.background.Transparency = 1
    hb.background.Visible = false

    hb.fill = Drawing.new("Line")
    hb.fill.Color = Color3_fromRGB(0,255,0)
    hb.fill.Thickness = 2
    hb.fill.Transparency = 1
    hb.fill.Visible = false

    HealthBarCache[id] = hb
    return hb
end

local function hideHealthBar(hb)
    if not hb then return end
    hb.outline.Visible = false
    hb.background.Visible = false
    hb.fill.Visible = false
end

local KNOWN_MOTORS = {
    "Waist","Neck","LeftShoulder","LeftElbow","LeftWrist",
    "RightShoulder","RightElbow","RightWrist",
    "LeftHip","LeftKnee","LeftAnkle",
    "RightHip","RightKnee","RightAnkle"
}
local KNOWN_SET = {}; for _,k in ipairs(KNOWN_MOTORS) do KNOWN_SET[k]=true end

local JOINT_CHAINS = {
    {"LeftShoulder","LeftElbow","LeftWrist"},
    {"RightShoulder","RightElbow","RightWrist"},
    {"LeftHip","LeftKnee","LeftAnkle"},
    {"RightHip","RightKnee","RightAnkle"},
    {"Waist","Neck"}
}
local CROSS_EDGES = {
    {"Neck","LeftShoulder"},
    {"Neck","RightShoulder"},
    {"Waist","LeftHip"},
    {"Waist","RightHip"}
}
local EDGES = {}
do
    for _,chain in ipairs(JOINT_CHAINS) do
        for i=1,#chain-1 do
            table.insert(EDGES,{chain[i],chain[i+1]})
        end
    end
    for _,edge in ipairs(CROSS_EDGES) do
        table.insert(EDGES,edge)
    end
end
local TOTAL_LINES = #EDGES

local function getSkeleton(id)
    local arr = SkeletonCache[id]
    if arr then return arr end
    arr = {}
    for i = 1,TOTAL_LINES do
        local outline = Drawing.new("Line")
        outline.Color = ESP.SkeletonOutlineColor
        outline.Thickness = ESP.SkeletonOutlineThickness
        outline.Transparency = 1
        outline.Visible = false
        outline.ZIndex = 1

        local main = Drawing.new("Line")
        main.Color = ESP.SkeletonMainColor
        main.Thickness = ESP.SkeletonMainThickness
        main.Transparency = 1
        main.Visible = false
        main.ZIndex = 2

        arr[i] = {outline,main}
    end
    SkeletonCache[id] = arr
    return arr
end

local function hideSkeleton(arr)
    if not arr then return end
    for i = 1,TOTAL_LINES do
        local pair = arr[i]
        if pair then
            pair[1].Visible = false
            pair[2].Visible = false
        end
    end
end

local function setSkeletonLine(pair, a2, b2)
    pair[1].From, pair[1].To, pair[1].Visible = a2, b2, true
    pair[2].From, pair[2].To, pair[2].Visible = a2, b2, true
end

local function healthColor(pct)
    if pct > 0.5 then return Color3_fromRGB(0,255,0)
    elseif pct > 0.25 then return Color3_fromRGB(255,170,0)
    else return Color3_fromRGB(255,0,0) end
end

function ESP:AddCharacter(character, opts)
    assert(character, "Character required")
    opts = opts or {}
    local adapter = opts.Adapter or ESP.DefaultAdapter
    local id = opts.Name or (character.Name .. tostring(character:GetDebugId() or ""))
    Cache[id] = {
        character = character,
        adapter = adapter,
        color = opts.Color or ESP.CornerColor
    }
end

function ESP:RemoveCharacter(characterOrId)
    local id = typeof(characterOrId)=="string" and characterOrId or (characterOrId.Name .. tostring(characterOrId:GetDebugId() or ""))
    BoxCache[id] = nil
    NameCache[id] = nil
    DistanceCache[id] = nil
    HealthBarCache[id] = nil
    SkeletonCache[id] = nil
    Cache[id] = nil
end

RunService.RenderStepped:Connect(function()
    local localPlayer = Players.LocalPlayer
    local localChar = localPlayer and localPlayer.Character
    local localRoot = localChar and ESP.DefaultAdapter.getRoot(localChar)
    for id,info in pairs(Cache) do
        local char = info.character
        local adapter = info.adapter
        local root = adapter.getRoot(char)
        local humanoid = adapter.getHumanoid(char)
        local alive = humanoid and adapter.isAlive(humanoid) and root
        local boxLines = getBox(id)
        local nameArr = getNameArray(id)
        local distArr = getDistanceArray(id)
        local hb = getHealthBar(id)
        local skel = getSkeleton(id)
        hideSkeleton(skel)
        if not alive then
            for _,l in ipairs(boxLines) do l.Visible = false end
            hideOutlinedText(nameArr)
            hideOutlinedText(distArr)
            hideHealthBar(hb)
        else
            local size = root.Size
            local boxSize = Vector3.new(size.X*1.5, size.Y*2.5, size.Z*1.5)
            local cf = CFrame.new(root.Position, Camera.CFrame.Position)
            local minX,minY,maxX,maxY = huge,huge,-huge,-huge
            local onscreen = false
            for x=-1,1,2 do
                for y=-1,1,2 do
                    for z=-1,1,2 do
                        local world = cf:PointToWorldSpace(Vector3.new(boxSize.X*x*0.5, boxSize.Y*y*0.5, boxSize.Z*z*0.5))
                        local pos,vis = Camera:WorldToViewportPoint(world)
                        if vis then
                            local px,py = pos.X,pos.Y
                            minX = math.min(minX,px)
                            minY = math.min(minY,py)
                            maxX = math.max(maxX,px)
                            maxY = math.max(maxY,py)
                            onscreen = true
                        end
                    end
                end
            end
            if not onscreen then
                for _,l in ipairs(boxLines) do l.Visible = false end
                hideOutlinedText(nameArr)
                hideOutlinedText(distArr)
                hideHealthBar(hb)
            else
                local TL = Vector2_new(minX,minY)
                local TR = Vector2_new(maxX,minY)
                local BL = Vector2_new(minX,maxY)
                local BR = Vector2_new(maxX,maxY)
                local boxW = maxX-minX
                local boxH = maxY-minY
                local cl = math.max(2, math.min(ESP.BaseCornerLength, boxW*0.25, boxH*0.25))
                local froms = {TL,TL,TR,TR,BL,BL,BR,BR}
                local tos = {
                    TL+Vector2_new(cl,0), TL+Vector2_new(0,cl),
                    TR+Vector2_new(-cl,0), TR+Vector2_new(0,cl),
                    BL+Vector2_new(cl,0), BL+Vector2_new(0,-cl),
                    BR+Vector2_new(-cl,0), BR+Vector2_new(0,-cl)
                }
                for i=1,8 do
                    boxLines[i].From = froms[i]
                    boxLines[i].To = tos[i]
                    boxLines[i].Visible = true
                    boxLines[i+8].From = froms[i]
                    boxLines[i+8].To = tos[i]
                    boxLines[i+8].Visible = true
                end
                if ESP.ShowNames and nameArr then
                    local namePos = Vector2_new((minX+maxX)*0.5, minY-15)
                    updateOutlinedText(nameArr, NAME_OUTLINE_OFFSETS, namePos, char.Name, ESP.NameTextSize)
                elseif nameArr then hideOutlinedText(nameArr) end
                if ESP.ShowDistance and distArr and localRoot then
                    local distance = (root.Position-localRoot.Position).Magnitude
                    local distText = tostring(floor(distance+0.5)).."s"
                    local distPos = Vector2_new((minX+maxX)*0.5, maxY+4)
                    updateOutlinedText(distArr, DISTANCE_OUTLINE_OFFSETS, distPos, distText, ESP.DistanceTextSize)
                elseif distArr then hideOutlinedText(distArr) end
                if ESP.EnableHealthBar and hb and humanoid then
                    local hp, mhp = adapter.getHealth(humanoid)
                    if mhp > 0 then
                        local pct = clamp(hp/mhp,0,1)
                        local barX = (ESP.HealthBarSide=="Left") and (minX-ESP.HealthBarGap) or (maxX+ESP.HealthBarGap)
                        local barBottom = Vector2_new(barX, maxY)
                        local barTopFull = Vector2_new(barX, minY)
                        local fillTop = Vector2_new(barX, maxY-(boxH*pct))
                        hb.outline.From = barBottom; hb.outline.To = barTopFull; hb.outline.Visible = true
                        hb.background.From = barBottom; hb.background.To = barTopFull; hb.background.Visible = true
                        hb.fill.Color = healthColor(pct)
                        hb.fill.From = barBottom; hb.fill.To = fillTop; hb.fill.Visible = true
                    else hideHealthBar(hb) end
                else hideHealthBar(hb) end
                if adapter.isR15(humanoid) then
                    local motors = {}
                    for _,d in ipairs(char:GetDescendants()) do
                        if d:IsA("Motor6D") and KNOWN_SET[d.Name] then
                            motors[d.Name] = d
                        end
                    end
                    local jointPosCache = {}
                    local function jointWorldPos(name)
                        if jointPosCache[name] ~= nil then return jointPosCache[name] end
                        local m = motors[name]
                        if not (m and m.Part0) then jointPosCache[name]=false return false end
                        local pos = (m.Part0.CFrame * m.C0).Position
                        jointPosCache[name]=pos
                        return pos
                    end
                    local idx = 1
                    for e=1,TOTAL_LINES do
                        local aName,bName = EDGES[e][1],EDGES[e][2]
                        local aPos = jointWorldPos(aName)
                        if aPos then
                            local bPos = jointWorldPos(bName)
                            if bPos then
                                local a2, av = Camera:WorldToViewportPoint(aPos)
                                local b2, bv = Camera:WorldToViewportPoint(bPos)
                                if av and bv then
                                    local pair = skel[idx]
                                    if pair then setSkeletonLine(pair, Vector2_new(a2.X,a2.Y), Vector2_new(b2.X,b2.Y)) end
                                    idx = idx + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)
