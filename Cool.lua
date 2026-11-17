--[[
  Combined bot script: the original strippedbot + every add-on, in ONE file (no other script is loaded).
  Run it with the short loader:
      getgenv().CONFIG = { main = "pocitac222222", mains = {"im_notdeko"} }
      loadstring(game:HttpGet("<raw link to THIS file>", true))()
  Optional CONFIG keys:
      bots = { name = "group" }   -- extra/override bot accounts (the built-in list is below)
      afk = false                 -- start with the focus spoof off
      summonRadius = {4, 10}      -- .summon lands this many studs from the player
      enlightener = "CommanderOfTheNull"   -- the one bot that answers .enlighten
      boombox = "boombox"         -- tool name to look for in the bot's hand
]]

local CONFIG = getgenv().CONFIG
if not CONFIG or not CONFIG.main then
    warn("CONFIG not set! do getgenv().CONFIG = { main = 'yourname' } before loading!")
    return
end
if getgenv().BOT_STOP then pcall(getgenv().BOT_STOP) end -- re-running replaces the old copy

local Players  = game:GetService("Players")
local RS       = game:GetService("RunService")
local TCS      = game:GetService("TextChatService")
local SG       = game:GetService("StarterGui")
local UIS      = game:GetService("UserInputService")
local WS       = game:GetService("Workspace")
local RepStore = game:GetService("ReplicatedStorage")
local lp  = Players.LocalPlayer
local TAU = math.pi * 2

local conns, threads = {}, {}
local function on(sig, fn) conns[#conns + 1] = sig:Connect(fn) end
local function bg(fn) local t = task.spawn(fn); threads[#threads + 1] = t; return t end

local function notify(t, x)
    pcall(function() SG:SetCore("SendNotification", { Title = t, Text = tostring(x), Duration = 5 }) end)
end

local function say(msg)
    pcall(function()
        local chans = TCS:FindFirstChild("TextChannels")
        local chan = chans and chans:FindFirstChild("RBXGeneral")
        if chan then chan:SendAsync(msg) return end
        local ev = RepStore:FindFirstChild("DefaultChatSystemChatEvents")
        if ev then ev.SayMessageRequest:FireServer(msg, "All") end
    end)
end

-- ===== WHO IS WHO =====
-- Bot names are compared with look-alike characters merged (i/l/1/| and 0/o), so a name read off a
-- screenshot still matches. Mains and trusted players are ALWAYS compared exactly.
local function K(n) return (tostring(n):lower():gsub("[il1|]", "l"):gsub("0", "o")) end

local PREFIX = { ["."] = true, ["?"] = true, ["!"] = true, [";"] = true }

local BOTS, NAMES = {}, {} -- BOTS[K(username)] = set of lowercase groups
local function addBot(name, g)
    local s = {}
    if type(g) == "string" then
        s[g:lower()] = true
    elseif type(g) == "table" then
        for _, x in ipairs(g) do s[tostring(x):lower()] = true end
    end
    BOTS[K(name)] = s
    NAMES[K(name)] = name
end
for n, g in pairs({ -- USERNAMES (the @name, not the display name)
    AWwLSRXcjsRWej = "A", BQFJeGaEkVvP = "A", BYZDPMVZcmJJzF = "A", Gpei4biCTrfW9o = "A",
    o4pEbQgaZQc9l7 = "A", CommanderOfTheNull = "A", qbUMZl95eys5Gk = "A", wc7W4QEVJa23Vr = "A",
}) do addBot(n, g) end
for n, g in pairs(CONFIG.bots or {}) do
    if type(n) == "number" then addBot(g) else addBot(n, g) end
end

local meK = K(lp.Name)
if CONFIG.group then addBot(lp.Name, CONFIG.group) end
if not BOTS[meK] then
    addBot(lp.Name)
    notify("Bots list", lp.Name .. " is not in the bots list! Formations will be off for this account.")
end

local MAINS = { [tostring(CONFIG.main):lower()] = true }
for _, n in ipairs(CONFIG.mains or {}) do MAINS[tostring(n):lower()] = true end
local TRUSTED = getgenv().TRUSTED or {}
getgenv().TRUSTED = TRUSTED

local function mainName()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == tostring(CONFIG.main):lower() then return p.Name end
    end
    return CONFIG.main
end

-- g:A or g:A,B or g:all anywhere in a command picks groups; no g: = every bot
local function split(msg)
    local words, tg = {}, nil
    for w in msg:gmatch("%S+") do
        local g = w:match("^[gG]:(.+)$")
        if g then
            tg = tg or {}
            for part in g:gmatch("[^,]+") do tg[part:lower()] = true end
        else
            words[#words + 1] = w
        end
    end
    return words, tg
end
local function pass(tg, set)
    if not tg or tg.all then return true end
    for g in pairs(set) do if tg[g] then return true end end
    return false
end
local function match(name, disp, arg)
    if not arg or arg == "" then return true end
    arg = arg:lower()
    return name:lower():find(arg, 1, true) ~= nil or (disp or ""):lower():find(arg, 1, true) ~= nil
end
local function isMe(arg) return match(lp.Name, lp.DisplayName, arg) end
local function others(tg, arg) -- the OTHER roster bots in the server this command covers
    local s = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local k = K(p.Name)
        if p ~= lp and BOTS[k] and pass(tg, BOTS[k]) and match(p.Name, p.DisplayName, arg) then s[k] = true end
    end
    return s
end

local function findPlayer(q)
    if not q or q == "" then return nil end
    q = q:lower()
    for _, p in ipairs(Players:GetPlayers()) do if p.Name:lower() == q then return p end end
    for _, p in ipairs(Players:GetPlayers()) do if (p.DisplayName or ""):lower() == q then return p end end
    for _, p in ipairs(Players:GetPlayers()) do if p.Name:lower():find(q, 1, true) then return p end end
    for _, p in ipairs(Players:GetPlayers()) do if (p.DisplayName or ""):lower():find(q, 1, true) then return p end end
    return nil
end

-- ===== ORIGINAL: donate / hide / summon / fling =====
local function getTime()
    local ls = lp:FindFirstChild("leaderstats")
    if ls then
        local t = ls:FindFirstChild("Time")
        if t and (t:IsA("IntValue") or t:IsA("NumberValue")) then return math.max(0, math.floor(t.Value)) end
    end
    return 0
end

local function dn(n) return (tostring(n):gsub("_", ".")) end -- the game doesn't allow "_" in names

local function donate(amount, to)
    if amount <= 0 then return notify("Donate Fail", "0 time") end
    say(';donate "' .. dn(to) .. '" "' .. amount .. '"')
    notify("Donated", amount .. " to " .. to)
end

local autoOn, autoThread = false, nil
local function toggleAuto(enable, interval, to, silent)
    if autoThread then pcall(task.cancel, autoThread); autoThread = nil end
    autoOn = enable
    if enable then
        local iv = interval or 60
        autoThread = bg(function()
            while autoOn do donate(getTime(), to) task.wait(iv) end
        end)
        notify("Auto Donate", "ON every " .. iv .. "s")
    elseif not silent then
        notify("Auto Donate", "OFF")
    end
end

local hideConn
local function toggleHide(enable, silent)
    if hideConn then hideConn:Disconnect(); hideConn = nil end
    if enable then
        hideConn = RS.Stepped:Connect(function()
            local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = CFrame.new(9999, 9999, 9999) end
        end)
    end
    if not silent then notify("Hide", enable and "ON" or "OFF") end
end

local flingConn
local function toggleFling(enable, targetName, silent)
    if flingConn then flingConn:Disconnect(); flingConn = nil end
    if not enable then
        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.AssemblyLinearVelocity = Vector3.zero; hrp.AssemblyAngularVelocity = Vector3.zero end
        if not silent then notify("Fling", "Stopped") end
        return
    end
    local target = findPlayer(targetName)
    if not target then notify("Fling Error", "No player: " .. tostring(targetName)) return end
    flingConn = RS.Heartbeat:Connect(function()
        local tHrp  = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        local myHrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        local hum   = lp.Character and lp.Character:FindFirstChild("Humanoid")
        if not (myHrp and tHrp) then return end
        myHrp.CFrame = tHrp.CFrame * CFrame.new(math.random(-2, 2), math.random(0, 1), math.random(-2, 2))
        myHrp.AssemblyAngularVelocity = Vector3.new(math.random(-900, 900), math.random(-1800, 1800), math.random(-900, 900))
        local dir = tHrp.Position - myHrp.Position
        local flat = Vector3.new(dir.X, 0, dir.Z)
        local pushDir = (flat.Magnitude > 0.01) and flat.Unit or Vector3.new(1, 0, 0)
        tHrp.AssemblyLinearVelocity = pushDir * 2800 + Vector3.new(math.random(-200, 200), math.random(600, 1000), math.random(-200, 200))
        if hum and hum:GetState() ~= Enum.HumanoidStateType.Jumping then hum.Jump = true end
    end)
    notify("Fling", "Flinging " .. target.Name)
end

local function stopHF() -- drop out of hide/fling (used when a movement command takes over)
    if hideConn then toggleHide(false, true) end
    if flingConn then toggleFling(false, nil, true) end
end

local SR = type(CONFIG.summonRadius) == "table" and CONFIG.summonRadius or { 4, 10 }
local function summonCF(th) -- random spot around the player, facing them
    local a, r = math.random() * TAU, SR[1] + math.random() * (SR[2] - SR[1])
    local c = th.Position
    local p = Vector3.new(c.X + math.cos(a) * r, c.Y, c.Z + math.sin(a) * r)
    return CFrame.lookAt(p, Vector3.new(c.X, p.Y, c.Z))
end

-- ===== ANTI-AFK =====
local VU = game:GetService("VirtualUser")
local function nudge()
    pcall(function() VU:CaptureController() end)
    pcall(function() VU:ClickButton2(Vector2.new(math.random(1, 8), math.random(1, 8))) end)
end
on(lp.Idled, nudge)
bg(function() while true do nudge() task.wait(45) end end)

-- "always tabbed in" spoof: kills the game's focus-lost handlers, fires its focus handlers,
-- and makes IsWindowFocused() return true. Needs getconnections / hookmetamethod in the executor.
local afk, afkOff = false, {}
local function conList(sig)
    if typeof(getconnections) ~= "function" then return {} end
    local ok, r = pcall(getconnections, sig)
    return ok and r or {}
end
pcall(function()
    if hookmetamethod and newcclosure and getnamecallmethod and checkcaller then
        local old
        old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if afk and self == UIS and not checkcaller() and getnamecallmethod() == "IsWindowFocused" then
                return true
            end
            return old(self, ...)
        end))
    end
end)
local afkThread
local function setAfk(enable, silent)
    if afkThread then pcall(task.cancel, afkThread); afkThread = nil end
    afk = enable
    if not enable then
        for c in pairs(afkOff) do pcall(function() c:Enable() end) end
        afkOff = {}
        if not silent then notify("AFK Spoof", "OFF") end
        return
    end
    if not silent then
        notify("AFK Spoof", typeof(getconnections) == "function" and "ON" or "ON (limited: no getconnections)")
    end
    afkThread = bg(function()
        while afk do
            for _, c in ipairs(conList(UIS.WindowFocusReleased)) do
                if not afkOff[c] and pcall(function() c:Disable() end) then afkOff[c] = true end
            end
            for _, c in ipairs(conList(UIS.WindowFocused)) do pcall(function() c:Fire() end) end
            task.wait(10)
        end
    end)
end

-- ===== FORMATION SHAPES (pure maths, no Roblox objects) =====
-- <SHAPES>
-- A shape = strokes in unit coordinates (u right, v up, about -1..1). N points get spread over them.
local function d2(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end
local function lerp2(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t } end
local function poly(n, r, rot, inner)
    local pts, cnt = {}, inner and n * 2 or n
    for i = 0, cnt - 1 do
        local rad = (inner and i % 2 == 1) and inner or r
        local a = math.rad((rot or 90) + i * 360 / cnt)
        pts[#pts + 1] = { math.cos(a) * rad, math.sin(a) * rad }
    end
    return pts
end
local function loop(pts) return { { closed = true, pts = pts } } end
local function arms(dirs)
    local s = { { pts = { { 0, 0 } }, min = 1 } }
    for _, d in ipairs(dirs) do s[#s + 1] = { pts = { { d[1] * .22, d[2] * .22 }, d }, min = 1 } end
    return s
end

local SH = {
    circle   = function() return loop(poly(48, 1)) end,
    square   = function() return loop({ { -1, 1 }, { 1, 1 }, { 1, -1 }, { -1, -1 } }) end,
    triangle = function() return loop(poly(3, 1)) end,
    diamond  = function() return loop(poly(4, 1)) end,
    star     = function() return loop(poly(5, 1, 90, .382)) end,
    plus     = function() return arms({ { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }) end,
    x        = function() return arms({ { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }) end,
    line     = function() return { { pts = { { -1, 0 }, { 1, 0 } } } } end,
    v        = function() return { { corner = true, pts = { { -1, 1 }, { 0, -1 }, { 1, 1 } } } } end,
    wedge    = function() return { { corner = true, pts = { { -1, -1 }, { 0, 1 }, { 1, -1 } } } } end,
    heart = function()
        local pts = {}
        for i = 0, 71 do
            local t = i / 72 * TAU
            local x = 16 * math.sin(t) ^ 3
            local y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
            pts[#pts + 1] = { x / 17, (y + 2.5) / 17 }
        end
        return loop(pts)
    end,
    spiral = function()
        local pts = {}
        for i = 0, 90 do
            local t = i / 90
            pts[#pts + 1] = { math.cos(t * TAU * 3) * (.12 + .88 * t), math.sin(t * TAU * 3) * (.12 + .88 * t) }
        end
        return { { pts = pts } }
    end,
}

-- your picture: four corner brackets + a small square in the middle.
-- Always symmetric: every bracket gets the same number of bots, leftovers go to the middle piece.
SH.frame = function(N)
    local W, H, AX, AY, S = 1, .75, .6, .45, .16
    local function br(sx, sy)
        return { corner = true, pts = { { sx * (W - AX), sy * H }, { sx * W, sy * H }, { sx * W, sy * (H - AY) } } }
    end
    local c = N % 4
    if N >= 16 and c < 4 then c = c + 4 end
    local per = math.floor((N - c) / 4)
    local mid = (c == 1) and { pts = { { 0, 0 } } } or loop({ { -S, S }, { S, S }, { S, -S }, { -S, -S } })[1]
    return { br(-1, 1), br(1, 1), br(-1, -1), br(1, -1), mid }, { per, per, per, per, c }
end

local ALIAS = {
    frame = "frame", viewfinder = "frame", focus = "frame", brackets = "frame",
    circle = "circle", ring = "circle", round = "circle", square = "square", box = "square",
    triangle = "triangle", tri = "triangle", diamond = "diamond", star = "star", heart = "heart",
    plus = "plus", cross = "plus", x = "x", line = "line", row = "line",
    v = "v", wedge = "wedge", arrow = "wedge", spiral = "spiral", grid = "grid",
}
local FORM_LIST = "frame circle square triangle diamond star heart plus x line v wedge spiral grid"

local function slen(s)
    local n = #s.pts
    if n < 2 then return 0 end
    if s.corner then return d2(s.pts[1], s.pts[2]) + d2(s.pts[2], s.pts[3]) end
    local t = 0
    for i = 1, s.closed and n or n - 1 do t = t + d2(s.pts[i], s.pts[i % n + 1]) end
    return t
end

local function alloc(st, N, total) -- bots per stroke, proportional to length (largest remainder)
    local minSum = 0
    for _, s in ipairs(st) do minSum = minSum + (s.min or 0) end
    local useMin = N >= minSum
    local counts, pool = {}, N
    for i, s in ipairs(st) do
        counts[i] = useMin and (s.min or 0) or 0
        pool = pool - counts[i]
    end
    local fr, used = {}, 0
    for i, s in ipairs(st) do
        local share = pool * s.len / total
        local fl = math.floor(share)
        counts[i] = counts[i] + fl
        used = used + fl
        fr[#fr + 1] = { i = i, r = share - fl }
    end
    table.sort(fr, function(a, b)
        if a.r ~= b.r then return a.r > b.r end
        return a.i < b.i
    end)
    for k = 1, pool - used do
        if fr[k] then counts[fr[k].i] = counts[fr[k].i] + 1 end
    end
    return counts
end

local function place(s, k, out)
    if k <= 0 then return end
    local pts, n = s.pts, #s.pts
    if n == 1 then
        for _ = 1, k do out[#out + 1] = pts[1] end
        return
    end
    if s.corner then -- L / V: the corner always gets a bot, the rest go out along the two arms
        local p1, c, p3 = pts[1], pts[2], pts[3]
        local l1, l2 = d2(p1, c), d2(c, p3)
        out[#out + 1] = c
        local rest = k - 1
        if rest <= 0 then return end
        local a = (rest == 1) and 1 or math.clamp(math.floor(rest * l1 / (l1 + l2) + .5), 1, rest - 1)
        for j = 1, a do out[#out + 1] = lerp2(c, p1, j / a) end
        for j = 1, rest - a do out[#out + 1] = lerp2(c, p3, j / (rest - a)) end
        return
    end
    local seg, total, last = {}, 0, s.closed and n or n - 1
    for i = 1, last do
        seg[i] = d2(pts[i], pts[i % n + 1])
        total = total + seg[i]
    end
    for j = 1, k do
        local t
        if s.closed then t = (j - 1) / k elseif k == 1 then t = .5 else t = (j - 1) / (k - 1) end
        local target, acc = t * total, 0
        for i = 1, last do
            if target <= acc + seg[i] or i == last then
                out[#out + 1] = lerp2(pts[i], pts[i % n + 1], seg[i] > 0 and math.clamp((target - acc) / seg[i], 0, 1) or 0)
                break
            end
            acc = acc + seg[i]
        end
    end
end

-- returns: one point per bot, default size in studs, lowest v
local function build(name, N)
    local pts, nat
    if name == "grid" then
        local cols = math.ceil(math.sqrt(N))
        local rows = math.ceil(N / cols)
        local sp = 2 / math.max(cols - 1, 1)
        pts = {}
        for i = 1, N do
            local r, c = math.floor((i - 1) / cols), (i - 1) % cols
            local inRow = (r == rows - 1) and (N - cols * (rows - 1)) or cols
            pts[i] = { (c - (inRow - 1) / 2) * sp, ((rows - 1) / 2 - r) * sp }
        end
        nat = 3.5 / sp
    else
        local st, counts = SH[name](N)
        local total = 0
        for _, s in ipairs(st) do
            s.len = slen(s)
            total = total + s.len
        end
        counts = counts or alloc(st, N, math.max(total, .001))
        pts = {}
        for i, s in ipairs(st) do place(s, counts[i], pts) end
        nat = N * 3.5 / math.max(total, .001) -- about 3.5 studs between bots
    end
    while #pts < N do pts[#pts + 1] = { 0, 0 } end
    local vmin = math.huge
    for _, p in ipairs(pts) do vmin = math.min(vmin, p[2]) end
    return pts, math.clamp(nat, 4, 60), vmin
end
-- </SHAPES>

-- ===== MOVEMENT: orbit / formation / line / stare =====
-- Every bot sees every command, so each keeps the same picture of who is doing what:
--   ASSIGN[K(bot)] = movement key,  PARAMS[key] = settings shared by everyone on that key.
-- Each bot works out its own slot from that (sorted by name), so no bot-to-bot talking is needed.
local ASSIGN, PARAMS, TRAIL = {}, {}, {}
local slotIdx, slotCount, lastKey, lastT, moving = 1, 1, nil, 0, false
local stare = nil -- username being stared at
local fc = {}

on(Players.PlayerRemoving, function(p) ASSIGN[K(p.Name)] = nil end)

local function slotOf(key, skipK)
    local present = {}
    for _, p in ipairs(Players:GetPlayers()) do present[K(p.Name)] = true end
    local list, me = {}, false
    for k, v in pairs(ASSIGN) do
        if v == key and present[k] and k ~= skipK then
            list[#list + 1] = k
            if k == meK then me = true end
        end
    end
    if not me then list[#list + 1] = meK end
    table.sort(list)
    for i, k in ipairs(list) do if k == meK then return i, #list end end
    return 1, #list
end

local function flat(v)
    local f = Vector3.new(v.X, 0, v.Z)
    return f.Magnitude > .01 and f.Unit or nil
end

local function orbitCF(P, th)
    local r = math.max(P.radius, slotCount * 3 / TAU) -- widen if crowded
    -- server time is shared by every client, so all bots stay in step
    local a = WS:GetServerTimeNow() * P.speed + (slotIdx - 1) / slotCount * TAU
    local c = th.Position
    return CFrame.lookAt(c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), c) -- facing the middle
end

local function formCF(P, key, th)
    local tag = key .. "#" .. slotCount
    if fc.tag ~= tag then
        fc.tag = tag
        fc.pts, fc.nat, fc.vmin = build(P.shape, slotCount)
    end
    local pt = fc.pts[slotIdx]
    if not pt then return nil end
    local f = (not P.lock and flat(th.CFrame.LookVector)) or P.fwd
    local r = Vector3.new(-f.Z, 0, f.X)
    local size = P.size or fc.nat
    local c = th.Position
    local u, v = pt[1] * size, pt[2] * size
    local pos, face
    if P.plane == "wall" then -- upright, in front of the player, lowest bots level with them
        pos = Vector3.new(c.X, c.Y - fc.vmin * size, c.Z) + f * (size + 6) + r * u + Vector3.new(0, v, 0)
        face = -f
    elseif P.plane == "flat" then -- lying on the ground in front of the player
        pos = c + f * (6 + (pt[2] - fc.vmin) * size) + r * u
        face = c - pos
    else -- "around": flat, centred on the player
        pos = c + f * v + r * u
        face = c - pos
    end
    face = flat(face) or -f
    return CFrame.lookAt(pos, pos + face)
end

-- line: bots follow the player's real path, one behind the other
local function lineCF(P, th)
    local head = th.Position
    local name = P.target:lower()
    local t = TRAIL[name]
    if not t then t = {}; TRAIL[name] = t end
    local last = t[#t]
    if last and (head - last).Magnitude > 40 then -- teleported: fresh trail
        t = {}
        TRAIL[name] = t
        last = nil
    end
    if not last or (head - last).Magnitude > .75 then
        t[#t + 1] = head
        if #t > 900 then t = table.move(t, #t - 599, #t, 1, {}); TRAIL[name] = t end
    end
    local look = flat(th.CFrame.LookVector) or Vector3.new(0, 0, -1)
    local function at(dist)
        local prev, rem = head, dist
        for i = #t, 1, -1 do
            local seg = (prev - t[i]).Magnitude
            if seg > 0 and seg >= rem then return prev:Lerp(t[i], rem / seg) end
            rem = rem - seg
            prev = t[i]
        end
        return prev - look * rem
    end
    local d = slotIdx * P.gap
    local pos, ahead = at(d), at(math.max(d - P.gap * .5, 0))
    local face = flat(ahead - pos) or look
    return CFrame.lookAt(pos, pos + face)
end

on(RS.Heartbeat, function()
    local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local key = ASSIGN[meK]
    local P = key and PARAMS[key]
    if P then
        local anchor = Players:FindFirstChild(P.target)
        if not anchor then
            ASSIGN[meK] = nil
            notify("Movement", P.target .. " left, stopped")
        else
            local now = os.clock()
            if key ~= lastKey or now - lastT > .5 then
                lastKey, lastT = key, now
                slotIdx, slotCount = slotOf(key, K(P.target))
            end
            local th = anchor.Character and anchor.Character:FindFirstChild("HumanoidRootPart")
            if th then
                local cf
                if P.kind == "orbit" then cf = orbitCF(P, th)
                elseif P.kind == "line" then cf = lineCF(P, th)
                else cf = formCF(P, key, th) end
                if cf then
                    hrp.CFrame = cf
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                    moving = true
                end
            end
        end
    elseif moving then
        moving = false
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
    if stare then -- keep turning to face them (works on top of any movement)
        local t = Players:FindFirstChild(stare)
        local th = t and t.Character and t.Character:FindFirstChild("HumanoidRootPart")
        if th then
            local p = hrp.Position
            local d = flat(th.Position - p)
            if d then hrp.CFrame = CFrame.lookAt(p, p + d) end
        end
    end
end)

local function assign(set, meIn, key)
    for k in pairs(set) do ASSIGN[k] = key end
    if meIn then ASSIGN[meK] = key; stopHF() end
end
local function release(set, meIn, prefix) -- prefix nil = free them from anything
    local function ok(k) return k ~= nil and (not prefix or k:sub(1, #prefix) == prefix) end
    for k in pairs(set) do if ok(ASSIGN[k]) then ASSIGN[k] = nil end end
    if meIn and ok(ASSIGN[meK]) then ASSIGN[meK] = nil return true end
    return false
end
local function countOn(key, target) local _, n = slotOf(key, K(target)); return n end

-- ===== BOOMBOX =====
local BOOM = tostring(CONFIG.boombox or "boombox"):lower()
local function boomTool()
    local ch = lp.Character
    for _, t in ipairs(ch and ch:GetChildren() or {}) do
        if t:IsA("Tool") and t.Name:lower():find(BOOM, 1, true) then return t end
    end
end
local function boombox(arg)
    local tool = boomTool()
    if not tool then return notify("Boombox", "no boombox in hand") end
    local id = tonumber(arg)
    local stop = (arg or ""):lower() == "stop"
    if not id and not stop then return notify("Boombox", "usage: .play <id> | .play stop") end
    local n = 0
    for _, d in ipairs(tool:GetDescendants()) do
        local ev, fn = d:IsA("RemoteEvent"), d:IsA("RemoteFunction")
        if ev or fn then
            local nm, args = d.Name:lower(), nil
            if nm == "remote" then
                args = stop and { "StopSong" } or { "PlaySong", id } -- the classic Roblox boombox
            elseif nm:find("play") or nm:find("song") or nm:find("music") or nm:find("sound") or nm:find("track") or nm:find("audio") then
                args = stop and {} or { id }
            end
            if args then
                n = n + 1
                task.spawn(function()
                    pcall(function()
                        if ev then d:FireServer(unpack(args)) else d:InvokeServer(unpack(args)) end
                    end)
                end)
            end
        end
    end
    notify("Boombox", n > 0 and ((stop and "stop" or ("play " .. id)) .. " sent to " .. n .. " remote(s)")
        or "no matching remote, try .boominfo")
end
local function boominfo()
    local tool = boomTool()
    if not tool then return notify("Boombox", "no boombox in hand") end
    local names = {}
    for _, d in ipairs(tool:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
            names[#names + 1] = d.ClassName .. " " .. d:GetFullName()
        end
    end
    print("[Boombox] " .. tool.Name .. ":\n" .. table.concat(names, "\n"))
    notify("Boombox", tool.Name .. ": " .. #names .. " remote(s), see console (F9)")
end

-- ===== COMMANDS =====
local seen = {}
local function handle(msg, plr)
    local sp = plr.Name
    local isMain = MAINS[sp:lower()] == true
    if not (isMain or TRUSTED[sp:lower()]) then return end -- exact username only, never display name
    if not PREFIX[msg:sub(1, 1)] then return end

    local now = os.clock()
    if now - (seen.__t or 0) > 60 then seen = { __t = now } end
    local dk = sp .. "|" .. msg
    if seen[dk] and now - seen[dk] < .5 then return end
    seen[dk] = now

    local w, tg = split(msg)
    if #w == 0 then return end
    local cmd = w[1]:sub(2):lower()
    local passed = pass(tg, BOTS[meK])
    local function cover(arg) return others(tg, arg), passed and isMe(arg) end
    local to = isMain and sp or mainName() -- who donations go to

    -- original commands
    if cmd == "dall" or cmd == "donateall" then
        local _, meIn = cover(w[2])
        if meIn then donate(getTime(), to) end

    elseif cmd == "adall" then
        local _, meIn = cover(w[3])
        if meIn then
            local n = tonumber(w[2])
            if n and n > 0 then toggleAuto(true, n, to) else toggleAuto(false) end
        end

    elseif cmd == "stopauto" then
        local _, meIn = cover(w[2])
        if meIn then toggleAuto(false) end

    elseif cmd == "hide" then
        local set, meIn = cover(w[2])
        release(set, meIn)
        if meIn then stopHF(); toggleHide(true) end

    elseif cmd == "unhide" or cmd == "show" then
        local _, meIn = cover(w[2])
        if meIn then toggleHide(false) end

    elseif cmd == "summon" then
        local set, meIn = cover(w[2])
        release(set, meIn)
        if meIn then
            local th = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            if th and hrp and plr ~= lp then
                stopHF()
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.CFrame = summonCF(th)
                notify("Summon", "Teleported to " .. sp)
            else
                notify("Summon", "Main not found")
            end
        end

    elseif cmd == "f" then
        local set, meIn = cover(w[3])
        if not w[2] then
            if meIn then notify("Fling", "Usage: .f [player]") end
            return
        end
        release(set, meIn)
        if meIn then toggleFling(true, w[2]) end

    elseif cmd == "stopfling" or cmd == "unfling" then
        local _, meIn = cover(w[2])
        if meIn then toggleFling(false) end

    -- add-ons
    elseif cmd == "say" then
        local text = table.concat(w, " ", 2)
        if passed and text ~= "" then task.delay(math.random() * 1.2, say, text) end

    elseif cmd == "enlighten" then
        -- only the enlightener bot answers, whatever group filter was used
        if K(lp.Name) == K(CONFIG.enlightener or "CommanderOfTheNull") then
            task.delay(.3, say, ";enlighten " .. dn(sp))
        end

    elseif cmd == "play" or cmd == "boombox" then
        if passed and isMe(w[3]) then boombox(w[2]) end
    elseif cmd == "boominfo" then
        if passed and isMe(w[2]) then boominfo() end

    elseif cmd == "follow" or cmd == "stare" then
        if not passed then return end
        local t = w[2] and findPlayer(w[2]) or plr
        if not t then return notify("Follow", "Player not found") end
        if t == lp then return notify("Follow", "Can't watch myself") end
        stare = t.Name
        notify("Follow", "Watching " .. t.Name)
    elseif cmd == "unfollow" or cmd == "unstare" then
        if passed then stare = nil; notify("Follow", "Stopped") end

    elseif cmd == "orbit" then -- .orbit [radius] [speed] [player|me] [bot]
        local nums, names = {}, {}
        for i = 2, #w do
            local n = tonumber(w[i])
            if n and #nums < 2 then nums[#nums + 1] = n else names[#names + 1] = w[i] end
        end
        local set, meIn = cover(names[2])
        local t = (not names[1] or names[1]:lower() == "me") and plr or findPlayer(names[1])
        if not t then
            if meIn then notify("Orbit", "Player not found") end
            return
        end
        if t == lp then meIn = false end
        local key = "orbit|" .. t.Name:lower()
        local P = PARAMS[key] or { kind = "orbit", target = t.Name, radius = 6, speed = 3 }
        P.radius = math.clamp(nums[1] or P.radius, 2, 50)
        P.speed = math.clamp(nums[2] or P.speed, 0, 20) -- 0 holds the circle still
        PARAMS[key] = P
        assign(set, meIn, key)
        if meIn then notify("Orbit", "Orbiting " .. t.Name .. " (" .. countOn(key, t.Name) .. " bots)") end

    elseif cmd == "unorbit" then
        local set, meIn = cover(w[2])
        if release(set, meIn, "orbit|") then notify("Orbit", "Stopped") end

    elseif cmd == "line" or cmd == "train" then -- .line [gap] [bot] | .line off
        local a2 = (w[2] or ""):lower()
        if a2 == "off" or a2 == "stop" then
            local set, meIn = cover(w[3])
            if release(set, meIn, "line|") then notify("Line", "Stopped") end
            return
        end
        local gap, botArg
        for i = 2, #w do
            local n = tonumber(w[i])
            if n and not gap then gap = n else botArg = w[i] end
        end
        local set, meIn = cover(botArg)
        if plr == lp then meIn = false end
        local key = "line|" .. sp:lower()
        local P = PARAMS[key] or { kind = "line", target = sp, gap = 4 }
        P.gap = math.clamp(gap or P.gap, 2, 20)
        PARAMS[key] = P
        assign(set, meIn, key)
        if meIn then notify("Line", "Following " .. sp) end

    elseif cmd == "unline" then
        local set, meIn = cover(w[2])
        if release(set, meIn, "line|") then notify("Line", "Stopped") end

    elseif cmd == "formation" or cmd == "form" then -- .formation <type> [size] [wall|flat|around] [lock] [bot]
        local a2 = (w[2] or ""):lower()
        if a2 == "" or a2 == "list" then
            if passed then notify("Formations", FORM_LIST) end
            return
        end
        if a2 == "off" or a2 == "stop" or a2 == "none" then
            local set, meIn = cover(w[3])
            if release(set, meIn, "form|") then notify("Formation", "Stopped") end
            return
        end
        local shape = ALIAS[a2]
        if not shape then
            if passed then notify("Formation", "Unknown: " .. a2 .. " (try .formation list)") end
            return
        end
        local size, plane, lock, botArg
        for i = 3, #w do
            local x, n = w[i]:lower(), tonumber(w[i])
            if n and not size then size = n
            elseif x == "wall" or x == "flat" or x == "around" then plane = x
            elseif x == "lock" then lock = true
            else botArg = w[i] end
        end
        local set, meIn = cover(botArg)
        if plr == lp then meIn = false end
        local key = "form|" .. shape .. "|" .. (plane or "wall") .. "|" .. sp:lower()
        local P = PARAMS[key] or { kind = "form", shape = shape, plane = plane or "wall", target = sp }
        P.size = size and math.clamp(size, 3, 80) or nil -- nil = automatic
        P.lock = lock
        local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        P.fwd = (hrp and flat(hrp.CFrame.LookVector)) or P.fwd or Vector3.new(0, 0, -1)
        PARAMS[key] = P
        assign(set, meIn, key)
        if meIn then notify("Formation", shape .. " / " .. P.plane .. " / " .. countOn(key, sp) .. " bots") end

    elseif cmd == "unform" or cmd == "unformation" or cmd == "stopform" then
        local set, meIn = cover(w[2])
        if release(set, meIn, "form|") then notify("Formation", "Stopped") end

    elseif cmd == "afk" or cmd == "antiafk" then
        if not passed then return end
        local a2 = (w[2] or ""):lower()
        local state, botArg
        if a2 == "on" or a2 == "off" then state, botArg = (a2 == "on"), w[3] else botArg = w[2] end
        if not isMe(botArg) then return end
        if state == nil then state = not afk end
        setAfk(state)

    elseif cmd == "r" then
        local set, meIn = cover(w[2])
        release(set, meIn)
        if meIn then
            ASSIGN[meK] = nil
            stare = nil
            toggleAuto(false, nil, nil, true)
            stopHF()
            local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.Health = 0 elseif lp.Character then lp.Character:BreakJoints() end
            notify("Reset", "Stopped everything + reset")
        end

    elseif cmd == "clear" or cmd == "perish" then
        local set, meIn = cover(w[2])
        release(set, meIn)
        if meIn then
            ASSIGN[meK] = nil
            toggleAuto(false, nil, nil, true)
            stopHF()
            setAfk(false, true)
            notify("Perish", "Closing Roblox...")
            task.wait(.3)
            pcall(function() game:Shutdown() end)
            task.wait(1)
            pcall(function() lp:Kick("Closed") end)
            task.wait(1)
            pcall(function() game:Shutdown() end)
        end

    elseif cmd == "setgroup" then -- .setgroup NAME [bot] | .setgroup none   (+ g:OLD)
        if not isMain then return end
        local name = w[2]
        if not name then
            if passed then notify("Group", "Usage: .setgroup NAME") end
            return
        end
        local function setTo(k) BOTS[k] = (name:lower() == "none") and {} or { [name:lower()] = true } end
        for k in pairs(others(tg, w[3])) do setTo(k) end
        if passed and isMe(w[3]) then
            setTo(meK)
            notify("Group", name:lower() == "none" and "Cleared" or ("Now in group " .. name))
        end

    elseif cmd == "trust" or cmd == "untrust" then -- all bots, whatever g: says
        if not isMain then return end
        local t = findPlayer(w[2])
        if not t then return notify("Trust", "Player not found: " .. tostring(w[2])) end
        if MAINS[t.Name:lower()] then return end
        TRUSTED[t.Name:lower()] = (cmd == "trust") or nil
        notify("Trust", (cmd == "trust" and "Trusted " or "Untrusted ") .. t.Name)

    elseif cmd == "bots" then -- how many roster bots can this account see?
        local here, missing = 1, {}
        local present = {}
        for _, p in ipairs(Players:GetPlayers()) do present[K(p.Name)] = true end
        local total = 0
        for k in pairs(BOTS) do
            total = total + 1
            if k ~= meK and present[k] then here = here + 1
            elseif k ~= meK then missing[#missing + 1] = NAMES[k] or k end
        end
        notify("Bots", here .. "/" .. total .. " here" .. (#missing > 0 and (", missing: " .. table.concat(missing, ", ", 1, math.min(#missing, 4))) or ""))

    elseif cmd == "cmds" or cmd == "help" then
        if passed then notify("Commands", "dall adall hide unhide summon f stopfling say enlighten play follow unfollow orbit unorbit line formation afk r clear trust bots") end
    end
end

-- ===== LISTENERS =====
local function safe(m, p)
    local ok, e = pcall(handle, m, p)
    if not ok then warn("[bot] " .. tostring(e)) end
end
local function hook(p) on(p.Chatted, function(m) safe(m, p) end) end
for _, p in ipairs(Players:GetPlayers()) do hook(p) end
on(Players.PlayerAdded, hook)
pcall(function()
    on(TCS.MessageReceived, function(m)
        local src = m.TextSource
        local p = src and Players:GetPlayerByUserId(src.UserId)
        if p then
            local t = m.Text:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&amp;", "&")
            safe(t, p)
        end
    end)
end)

getgenv().BOT_STOP = function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, t in ipairs(threads) do pcall(task.cancel, t) end
    afk = false
    autoOn = false
    pcall(toggleHide, false, true)
    pcall(toggleFling, false, nil, true)
end

if CONFIG.afk ~= false then setAfk(true, true) end
notify("Script Loaded", "Prefixes: . ? ! ;  |  .cmds for the list  |  Anti-AFK: ON")
