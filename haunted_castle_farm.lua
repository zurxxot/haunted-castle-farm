local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local lp = Players.LocalPlayer
local genv = getgenv()

if genv.HauntedGroup then
    pcall(genv.HauntedGroup.stop)
end

local cfg = genv.HauntedGroupConfig or {}

local DEFAULT_MOBS = {"Living Zombie", "Demonic Soul", "Posessed Mummy", "Reborn Skeleton"}
local XZ = Vector3.new(1, 0, 1)

local owns = isnetworkowner or function()
    return true
end

local mobs = nil
if cfg.Mobs ~= false then
    mobs = {}
    for _, name in ipairs(cfg.Mobs or DEFAULT_MOBS) do
        mobs[name] = true
    end
end

local S = {
    running = true,
    enabled = cfg.StartOn ~= false,
    groups = math.max(1, cfg.Groups or 3),
    perGroup = math.max(1, cfg.PerGroup or 12),
    range = cfg.Range or 1200,
    spread = cfg.Spread or 3,
    toggleKey = cfg.ToggleKey or Enum.KeyCode.J,
    reclusterKey = cfg.ReclusterKey or Enum.KeyCode.K,
    farm = cfg.Farm ~= false,
    height = cfg.Height or 14,
    retreatHp = cfg.RetreatHp or 5000,
    resumeHp = cfg.ResumeHp or 8000,
    safeHeight = cfg.SafeHeight or 120,
    speed = cfg.TweenSpeed or 300,
    m1Interval = (cfg.Interval == nil) and 0.05 or (cfg.Interval or nil),
    maxCombo = math.clamp(cfg.MaxCombo or 3, 1, 4),
    autoAwaken = cfg.AutoAwaken ~= false,
    combo = 1,
    lastHit = 0,
    lastAwaken = 0,
    firing = false,
    mode = "farm",
    anchors = nil,
    assigned = {},
    slots = {},
    saved = setmetatable({}, {__mode = "k"}),
    lastClaim = 0,
    lastRefresh = 0,
    conns = {},
}
genv.HauntedGroup = S

local function notify(text)
    pcall(StarterGui.SetCore, StarterGui, "SendNotification", {Title = "Haunted Castle farm", Text = text, Duration = 3})
end

local function release()
    table.clear(S.assigned)
    table.clear(S.slots)
    S.anchors = nil
    S.station = nil
    S.waitSince = nil
end

local function cluster(points, k)
    local centers = {points[1]}
    while #centers < k do
        local far, farDistance = nil, -1
        for _, p in ipairs(points) do
            local nearest = math.huge
            for _, c in ipairs(centers) do
                nearest = math.min(nearest, (p - c).Magnitude)
            end
            if nearest > farDistance then
                far, farDistance = p, nearest
            end
        end
        table.insert(centers, far)
    end
    local owner = {}
    for _ = 1, 12 do
        local sums, counts = {}, {}
        for i = 1, k do
            sums[i], counts[i] = Vector3.zero, 0
        end
        for index, p in ipairs(points) do
            local best, bestDistance = 1, math.huge
            for i, c in ipairs(centers) do
                local d = (p - c).Magnitude
                if d < bestDistance then
                    best, bestDistance = i, d
                end
            end
            owner[index] = best
            sums[best] += p
            counts[best] += 1
        end
        for i = 1, k do
            if counts[i] > 0 then
                centers[i] = sums[i] / counts[i]
            end
        end
    end
    return centers, owner
end

local function candidates(root, folder)
    local list = {}
    for _, npc in ipairs(folder:GetChildren()) do
        local hrp = npc:FindFirstChild("HumanoidRootPart")
        local hum = npc:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 and (not mobs or mobs[npc.Name]) and (hrp.Position - root.Position).Magnitude <= S.range then
            table.insert(list, {hrp = hrp, hum = hum})
        end
    end
    return list
end

local function buildAnchors(list, char, folder)
    local points = {}
    for _, c in ipairs(list) do
        table.insert(points, c.hrp.Position)
    end
    local k = math.min(S.groups, #points)
    if k == 0 then
        return nil
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {char, folder}
    local characters = workspace:FindFirstChild("Characters")
    if characters then
        table.insert(ignore, characters)
    end
    params.FilterDescendantsInstances = ignore
    local centers, owner = cluster(points, k)
    local anchors = {}
    for i = 1, k do
        local members = {}
        for index, o in ipairs(owner) do
            if o == i then
                table.insert(members, points[index])
            end
        end
        table.sort(members, function(a, b)
            return (a - centers[i]).Magnitude < (b - centers[i]).Magnitude
        end)
        local chosen
        for _, p in ipairs(members) do
            local hit = workspace:Raycast(p + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
            if hit then
                chosen = Vector3.new(p.X, hit.Position.Y, p.Z)
                break
            end
        end
        if not chosen then
            local p = members[1] or centers[i]
            chosen = Vector3.new(p.X, p.Y - 3, p.Z)
        end
        anchors[i] = chosen
        S.slots[i] = {}
    end
    return anchors
end

local function freeSlot(g)
    for i = 1, S.perGroup do
        if not S.slots[g][i] then
            return i
        end
    end
    return nil
end

local function refresh(char, root)
    local folder = workspace:FindFirstChild("Enemies")
    if not folder then
        return
    end
    for hrp, info in pairs(S.assigned) do
        if not hrp.Parent or info.hum.Health <= 0 then
            S.slots[info.group][info.slot] = nil
            S.assigned[hrp] = nil
        end
    end
    local list = candidates(root, folder)
    if not S.anchors then
        if #list < S.groups * 4 then
            S.waitSince = S.waitSince or os.clock()
            if #list < S.groups or os.clock() - S.waitSince < 20 then
                return
            end
        end
        S.anchors = buildAnchors(list, char, folder)
        S.waitSince = nil
        if not S.anchors then
            return
        end
        notify(#S.anchors .. " groups")
    end
    for _, c in ipairs(list) do
        if not S.assigned[c.hrp] and owns(c.hrp) then
            local order = {}
            for g = 1, #S.anchors do
                table.insert(order, g)
            end
            table.sort(order, function(a, b)
                return (c.hrp.Position - S.anchors[a]).Magnitude < (c.hrp.Position - S.anchors[b]).Magnitude
            end)
            for _, g in ipairs(order) do
                local slot = freeSlot(g)
                if slot then
                    S.slots[g][slot] = c.hrp
                    S.assigned[c.hrp] = {group = g, slot = slot, hum = c.hum}
                    break
                end
            end
        end
    end
end

local function place()
    for hrp, info in pairs(S.assigned) do
        if hrp.Parent and owns(hrp) then
            local anchor = S.anchors[info.group]
            local offset = Vector3.zero
            if S.perGroup > 1 then
                local angle = (info.slot - 1) / S.perGroup * math.pi * 2
                offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * S.spread
            end
            local y = anchor.Y + info.hum.HipHeight + hrp.Size.Y / 2
            hrp.CFrame = CFrame.new(anchor.X + offset.X, y, anchor.Z + offset.Z) * (hrp.CFrame - hrp.Position)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end
end

local function fruitTool(char)
    local data = lp:FindFirstChild("Data")
    local fruit = data and data:FindFirstChild("DevilFruit")
    if not fruit or fruit.Value == "" then
        return nil
    end
    return char:FindFirstChild(fruit.Value) or lp.Backpack:FindFirstChild(fruit.Value)
end

local function flag(parent, name)
    local v = parent and parent:FindFirstChild(name)
    return v ~= nil and v.Value == true
end

local function nearestEnemy(root)
    local folder = workspace:FindFirstChild("Enemies")
    if not folder then
        return nil
    end
    local best, bestDistance = nil, 80
    for _, enemy in ipairs(folder:GetChildren()) do
        local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
        local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
        if enemyRoot and enemyHumanoid and enemyHumanoid.Health > 0 then
            local distance = (enemyRoot.Position - root.Position).Magnitude
            if distance < bestDistance then
                best, bestDistance = enemyRoot, distance
            end
        end
    end
    return best
end

local function aimDirection(root)
    local target = nearestEnemy(root)
    local delta
    if target then
        delta = (target.Position - root.Position) * XZ
    else
        delta = workspace.CurrentCamera.CFrame.LookVector * XZ
    end
    if delta.Magnitude < 1e-3 then
        delta = root.CFrame.LookVector * XZ
    end
    if delta.Magnitude < 1e-3 then
        delta = Vector3.new(0, 0, 1)
    end
    return delta.Unit
end

local function onGround(char, root, humanoid)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    local reach = humanoid.HipHeight + root.Size.Y * 0.5 + 4
    return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), params) ~= nil
end

local function m1Step()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        return 0.5
    end
    local tool = fruitTool(char)
    local remote = tool and tool:FindFirstChild("LeftClickRemote")
    if not remote then
        return 1
    end
    local stun = char:FindFirstChild("Stun")
    if humanoid.Sit or flag(tool, "Holding") or flag(char, "Busy") or (stun and stun.Value > 0) then
        return 0.1
    end
    if os.clock() - S.lastHit > 1 then
        S.combo = 1
    end
    local delay = S.m1Interval
    if not delay then
        local reduction = char:GetAttribute("FruitTAPCooldown") or 0
        delay = ((S.combo < 4) and 0.3 or 1) * math.clamp(1 - reduction, 0.05, 1)
    end
    remote:FireServer(aimDirection(root), S.combo, onGround(char, root, humanoid))
    S.lastHit = os.clock()
    S.combo = (S.combo < S.maxCombo) and (S.combo + 1) or 1
    return delay
end

local function awaken(char)
    local now = os.clock()
    if now - S.lastAwaken < 1 then
        return
    end
    S.lastAwaken = now
    if flag(char, "RaceTransformed") then
        return
    end
    local tool = char:FindFirstChild("Awakening") or lp.Backpack:FindFirstChild("Awakening")
    local remote = tool and tool:FindFirstChild("RemoteFunction")
    if remote then
        task.spawn(pcall, remote.InvokeServer, remote, true)
    end
end

local function setM1(on)
    local spam = genv.FruitM1Spam
    if spam then
        if S.m1Initial == nil then
            S.m1Initial = spam.enabled
        end
        spam.enabled = false
    end
    S.firing = on
end

local function setNoclip(on)
    S.noclip = on
    if not on then
        for part, value in pairs(S.saved) do
            if part.Parent then
                part.CanCollide = value
            end
        end
        table.clear(S.saved)
    end
end

local function standDown()
    S.hold = nil
    S.mode = "farm"
    S.safe = nil
    S.firing = false
    setNoclip(false)
    if S.m1Initial ~= nil then
        local spam = genv.FruitM1Spam
        if spam then
            spam.enabled = S.m1Initial
        end
        S.m1Initial = nil
    end
end

local function travel(root, humanoid, target, abort)
    S.hold = nil
    local grip = Instance.new("BodyVelocity")
    grip.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    grip.Velocity = Vector3.zero
    grip.Parent = root
    local distance = (root.Position - target).Magnitude
    local tween = TweenService:Create(root, TweenInfo.new(math.max(distance / S.speed, 0.05), Enum.EasingStyle.Linear), {CFrame = CFrame.new(target)})
    tween:Play()
    local arrived = true
    while tween.PlaybackState == Enum.PlaybackState.Playing do
        if not S.running or not S.enabled or humanoid.Health <= 0 or (abort and abort()) then
            arrived = false
            break
        end
        task.wait()
    end
    tween:Cancel()
    grip:Destroy()
    return arrived
end

local function pickStation()
    local counts = {}
    for hrp, info in pairs(S.assigned) do
        if hrp.Parent and info.hum.Health > 0 then
            local anchor = S.anchors[info.group]
            if ((hrp.Position - anchor) * XZ).Magnitude < 8 then
                counts[info.group] = (counts[info.group] or 0) + 1
            end
        end
    end
    if S.station and (counts[S.station] or 0) > 0 then
        return S.station
    end
    local best, bestCount
    for g, n in pairs(counts) do
        if not bestCount or n > bestCount then
            best, bestCount = g, n
        end
    end
    S.station = best
    return best
end

local function stationHp(g)
    local total = 0
    for hrp, info in pairs(S.assigned) do
        if info.group == g and hrp.Parent and info.hum.Health > 0 then
            total += info.hum.Health
        end
    end
    return total
end

local function farmStep()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        S.hold = nil
        S.mode = "farm"
        return
    end
    if not S.anchors then
        return
    end
    local resume = math.min(S.resumeHp, humanoid.MaxHealth - 1)
    local hp = humanoid.Health
    setNoclip(true)
    if S.mode == "heal" then
        if hp < resume then
            setM1(false)
            if (root.Position - S.safe).Magnitude > 6 then
                if not travel(root, humanoid, S.safe) then
                    return
                end
            end
            S.hold = S.safe
            return
        end
        S.mode = "farm"
        S.safe = nil
        notify("healed, back to farming")
    elseif hp < S.retreatHp then
        S.mode = "heal"
        S.safe = root.Position + Vector3.new(0, S.safeHeight, 0)
        setM1(false)
        notify("low health, retreating")
        return
    end
    local g = pickStation()
    if not g then
        setM1(false)
        S.hold = S.hold or root.Position
        return
    end
    if S.liveStation ~= g then
        S.liveStation, S.live, S.lastTotal, S.lastChange = g, S.height, nil, os.clock()
    end
    local anchor = S.anchors[g]
    local target = Vector3.new(anchor.X, anchor.Y + 3 + S.live, anchor.Z)
    if (root.Position - target).Magnitude > 6 then
        setM1(false)
        local arrived = travel(root, humanoid, target, function()
            return humanoid.Health < S.retreatHp
        end)
        S.lastTotal, S.lastChange = nil, os.clock()
        if not arrived then
            return
        end
    end
    S.hold = target
    setM1(true)
    if S.autoAwaken then
        awaken(char)
    end
    local total = stationHp(g)
    local now = os.clock()
    if S.lastTotal == nil or math.abs(total - S.lastTotal) > 1 then
        S.lastTotal, S.lastChange = total, now
    elseif now - S.lastChange > 6 and S.live > 8 then
        S.live -= 1
        S.lastChange = now
    end
end

table.insert(S.conns, RunService.Heartbeat:Connect(function()
    if not S.enabled then
        return
    end
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end
    local now = os.clock()
    if now - S.lastClaim > 1 then
        S.lastClaim = now
        pcall(sethiddenproperty, lp, "SimulationRadius", math.huge)
    end
    if now - S.lastRefresh > 0.25 then
        S.lastRefresh = now
        refresh(char, root)
    end
    if S.anchors then
        place()
    end
    local hold = S.hold
    if hold then
        root.CFrame = CFrame.new(hold) * (root.CFrame - root.Position)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end))

table.insert(S.conns, RunService.Stepped:Connect(function()
    if not S.noclip then
        return
    end
    local char = lp.Character
    if not char then
        return
    end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if S.saved[part] == nil then
                S.saved[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end
end))

table.insert(S.conns, UserInputService.InputBegan:Connect(function(input, processed)
    if processed then
        return
    end
    if input.KeyCode == S.toggleKey then
        S.enabled = not S.enabled
        release()
        notify(S.enabled and "on" or "off")
    elseif input.KeyCode == S.reclusterKey and S.enabled then
        release()
        notify("regrouping")
    end
end))

task.spawn(function()
    while S.running do
        local delay = 0.1
        if S.enabled and S.firing then
            local ok, result = pcall(m1Step)
            delay = ok and result or 0.5
        end
        task.wait(delay)
    end
end)

task.spawn(function()
    while S.running do
        if S.enabled and S.farm then
            local ok, err = pcall(farmStep)
            if not ok then
                warn("[HauntedGroup] " .. tostring(err))
            end
            task.wait(0.2)
        else
            standDown()
            task.wait(0.3)
        end
    end
end)

S.stop = function()
    S.running = false
    S.enabled = false
    for _, c in ipairs(S.conns) do
        c:Disconnect()
    end
    standDown()
    release()
    if genv.HauntedGroup == S then
        genv.HauntedGroup = nil
    end
end
