-- ============================================================================
-- BOREN STORE - AUTO HARVEST PRO (STANDALONE SCRIPT)
-- File: script/script code/auto_harvest.lua
-- Repo: https://github.com/rendhi69/sc_harvest_growlauncher.git
-- Fitur:
--   1. Multi-World Farm List (WORLD:DOOR:ITEM_ID) + Item ID Harvest (auto Block & Seed ID)
--   2. Multi-World Save Block/Seed Table (pilihan ALL / BLOCK / SEED) + Limit per World (10k/20k/Custom)
--      + Posisi drop rapi (skip White Door/Lock, otomatis pindah baris & tile)
--   3. Ignore Gems (blokir collect Gems ID 112 via onSendPacketRaw)
--   4. Mode 3-Zigzag Serpentine & 1-by-1
--   5. Auto Collect Block & Seed hasil harvest
--   6. Multi-World Save khusus Event / Mooncake dengan Limit Total Item
--   7. Custom List ID Item Event (Mooncake default 1058,1094,1096,1098,1828)
--   8. Unified Magni + Fuel Pack (1252 & 1746) + Gear Equip ID List (DCS 6840 / Harvester 1966/1830)
--   9. Opsional Take Floating (sapu sisa block/seed/event setelah pohon habis)
--  10. Dual UI: Dear ImGui Standalone Window + Native Growlauncher 5-Tab Menu
-- ============================================================================

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`e[BOREN HARVEST] `w" .. tostring(msg)) end
end

local function notifyMsg(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end
local HV = {
    id      = "harvest",
    label   = "Harvest",
    VERSION = "1.2.0",
    META    = {
        type    = "boren_gl_feature",
        id      = "harvest",
        label   = "Harvest",
        order   = 15,
        enabled = true,
    },
}

HV.CFG = {
    default_item_id    = 4584,          -- Block genap / Seed ganjil (auto pair)
    drop_threshold     = 200,           -- Default 200 block (permintaan user)
    default_save_limit = 20000,         -- Default limit save world
    default_ev_limit   = 10000,         -- Default limit event world
    ignore_gems        = true,          -- Blokir collect Gems (ID 112)
    harvest_mode       = "3zigzag",     -- "3zigzag" | "1by1"
    harvest_delay      = 180,
    step_delay         = 110,
    warp_delay         = 4500,
    use_modfly         = true,
    loop_enabled       = false,
    auto_collect       = true,
    collect_range      = 4,
    event_ids_raw      = "1058,1094,1096,1098,1828", -- Mooncakes default
    event_threshold    = 150,
    gear_world         = "",            -- 1 world khusus Magni / Fuel Pack / Gear
    auto_magni_fuel    = false,         -- Auto ambil Magni (1252) & Fuel Pack (1746)
    fuel_target_amt    = 100,
    stop_if_no_fuel    = true,          -- Proteksi: stop aman jika Fuel Pack habis di tas & Gear World
    gear_equip_ids     = "6840, 1966",  -- List ID alat/gear to equip (DCS, Harvester, dll.)
    take_floating      = true,          -- Sapu sisa block/seed/event setelah tree habis
}

HV.STATE = {
    enabled          = false,
    running          = false,
    status_text      = "Idle",
    rows             = {},              -- { { name="W", door="D", item_id=4584, status="Ready" }, ... }
    selected_idx     = 0,
    save_rows        = {},              -- { { name="W", door="D", save_type="ALL"|"BLOCK"|"SEED", limit=20000, count=0, status="Ready" }, ... }
    selected_save    = 0,
    event_rows       = {},              -- { { name="W", door="D", limit=10000, count=0, status="Ready" }, ... }
    selected_ev      = 0,
    anti_take        = false,
    pending_drop_id  = 0,
    pending_drop_amt = 0,
    drop_confirmed   = false,
    need_fuel        = false,
    total_harvested  = 0,
    total_dropped    = 0,
    logs             = {},
    inv_preview      = { block = 0, seed = 0, ev = 0, fuel = 0 },
}

local HUB_REF = nil
local activeSub = "farms"

-- UI Buffers
local addFarmWorldBuf = ""
local addFarmItemBuf  = "4584"

local addSaveWorldBuf = ""
local addSaveTypeBuf  = "ALL"           -- "ALL" | "BLOCK" | "SEED"
local addSaveLimitBuf = "20000"

local addEventWorldBuf = ""
local addEventLimitBuf = "10000"

local uiNotice    = ""
local CACHED_PATH = nil

-- ============================================================================
-- 1. ITEM IDs & SAFE HELPERS
-- ============================================================================
local ITEM = {
    PUNCH     = 18,
    GEMS      = 112,
    MAGNI     = 1252,
    DCS       = 6840,
    HARVESTER = 1830,
    SORROWS   = 1966,
    FUEL_PACK = 1746,
}

local LOCK_OR_DOOR_IDS = {
    [6] = true, [12] = true, [30] = true, [60] = true, [202] = true, [204] = true,
    [206] = true, [224] = true, [226] = true, [242] = true, [544] = true, [546] = true,
    [1796] = true, [2810] = true, [4428] = true, [4802] = true, [4994] = true, [7188] = true,
}

local function trimStr(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function cleanWorldName(s)
    return trimStr(s):gsub("[^%w_]", ""):upper()
end

local function normalizeHarvestPair(itemID)
    local id = tonumber(itemID) or 4584
    if id <= 0 then id = 4584 end
    if id % 2 == 1 then return id - 1, id end
    return id, id + 1
end

local function addLog(msg)
    local clean = tostring(msg or ""):gsub("`[0-9a-zA-Z!]", "")
    local ts = ""
    if os and os.date then
        local okD, d = pcall(os.date, "[%H:%M:%S] ")
        if okD and d then ts = d end
    end
    local entry = ts .. "[HARVEST] " .. clean
    table.insert(HV.STATE.logs, 1, entry)
    if #HV.STATE.logs > 60 then table.remove(HV.STATE.logs) end
    if HUB_REF and HUB_REF.addLog then HUB_REF.addLog(entry) end
end

local function safeSleep(ms)
    local d = tonumber(ms) or 100
    if Sleep then pcall(Sleep, d)
    elseif sleep then pcall(sleep, d) end
end

local function runAsync(fn)
    if runCoroutine then pcall(runCoroutine, fn)
    else coroutine.resume(coroutine.create(fn)) end
end

-- ============================================================================
-- 2. PERSISTENCE (SAVE / LOAD KONFIGURASI & WORLD LISTS)
-- ============================================================================
local function isSystemWindows()
    if package and package.config and package.config:sub(1, 1) == "\\" then return true end
    if os and type(os.getenv) == "function" then
        local ok, env = pcall(os.getenv, "OS")
        if ok and env and tostring(env):lower():find("windows", 1, true) then return true end
    end
    return false
end

local function getDataPath()
    if CACHED_PATH then return CACHED_PATH end
    if isSystemWindows() then CACHED_PATH = "boren_hub_harvest_data.txt"; return CACHED_PATH end
    local dirs = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
    }
    for _, d in ipairs(dirs) do
        local p = d .. "boren_hub_harvest_data.txt"
        local ok, f = pcall(io.open, p, "a")
        if ok and f then f:close(); CACHED_PATH = p; return p end
    end
    CACHED_PATH = "boren_hub_harvest_data.txt"
    return CACHED_PATH
end

local function parseWorldDoor(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local w, d = s:match("^([^:]+):(.*)$")
    if w then
        w = cleanWorldName(w); d = cleanWorldName(d)
        return (w ~= "") and { name = w, door = d } or nil
    end
    local wn = cleanWorldName(s)
    return (wn ~= "") and { name = wn, door = "" } or nil
end

local function parseWorldList(raw)
    local list = {}
    for tok in tostring(raw or ""):gmatch("[^,\r\n;]+") do
        local p = parseWorldDoor(tok)
        if p then table.insert(list, p) end
    end
    return list
end

local function parseFarmRow(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts = {}
    for tok in s:gmatch("[^:]+") do
        table.insert(parts, trimStr(tok))
    end
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    local iid = math.floor(tonumber(parts[3]) or tonumber(HV.CFG.default_item_id) or 4584)
    if iid <= 0 then iid = 4584 end
    return { name = w, door = door, item_id = iid, status = "Ready" }
end

local function parseSaveRow(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts = {}
    for tok in s:gmatch("[^:]+") do
        table.insert(parts, trimStr(tok))
    end
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    local stype = (parts[3] or "ALL"):upper()
    if stype ~= "BLOCK" and stype ~= "SEED" and stype ~= "ALL" then
        local n = tonumber(stype)
        if n then
            local lim = math.floor(n)
            return { name = w, door = door, save_type = "ALL", limit = lim, count = 0, status = "Ready" }
        end
        stype = "ALL"
    end
    local lim = tonumber(parts[4]) or tonumber(HV.CFG.default_save_limit) or 20000
    local cur = tonumber(parts[5]) or 0
    return { name = w, door = door, save_type = stype, limit = math.max(0, math.floor(lim)), count = cur, status = "Ready" }
end

local function parseEventRow(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts = {}
    for tok in s:gmatch("[^:]+") do
        table.insert(parts, trimStr(tok))
    end
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    local lim = tonumber(parts[3]) or tonumber(HV.CFG.default_ev_limit) or 10000
    local cur = tonumber(parts[4]) or 0
    return { name = w, door = door, limit = math.max(0, math.floor(lim)), count = cur, status = "Ready" }
end

local function parseEventIDs()
    local map, list = {}, {}
    for tok in tostring(HV.CFG.event_ids_raw or ""):gmatch("[^,%s;|]+") do
        local id = math.floor(tonumber(tok) or 0)
        if id > 0 and not map[id] then map[id] = true; table.insert(list, id) end
    end
    return list, map
end

local function parseEquipIDs(raw)
    local list = {}
    for tok in tostring(raw or ""):gmatch("[^,%s;|]+") do
        local id = math.floor(tonumber(tok) or 0)
        if id > 0 then table.insert(list, id) end
    end
    return list
end

function HV.saveData()
    local c = HV.CFG
    local lines = {
        "DEFID="    .. tostring(c.default_item_id),
        "DROPTH="   .. tostring(c.drop_threshold or 200),
        "SAVELIM="  .. tostring(c.default_save_limit or 20000),
        "EVLIM="    .. tostring(c.default_ev_limit or 10000),
        "IGEMS="    .. (c.ignore_gems and "1" or "0"),
        "MODE="     .. tostring(c.harvest_mode),
        "HDELAY="   .. tostring(c.harvest_delay),
        "SDELAY="   .. tostring(c.step_delay),
        "MODFLY="   .. (c.use_modfly and "1" or "0"),
        "LOOP="     .. (c.loop_enabled and "1" or "0"),
        "ACOL="     .. (c.auto_collect and "1" or "0"),
        "EVIDS="    .. tostring(c.event_ids_raw or ""),
        "EVTH="     .. tostring(c.event_threshold),
        "GEARW="    .. tostring(c.gear_world or ""),
        "AMAGFUEL=" .. (c.auto_magni_fuel and "1" or "0"),
        "GEAREQUIP=".. tostring(c.gear_equip_ids or ""),
        "FUELAMT="  .. tostring(c.fuel_target_amt),
        "STPFUEL="  .. (c.stop_if_no_fuel and "1" or "0"),
        "FLOAT="    .. (c.take_floating and "1" or "0"),
    }
    for _, r in ipairs(HV.STATE.rows) do
        table.insert(lines, string.format("ROW=%s:%s:%d|%s", r.name, r.door or "", r.item_id or c.default_item_id, r.status or "Ready"))
    end
    for _, r in ipairs(HV.STATE.save_rows) do
        table.insert(lines, string.format("SAVEROW=%s:%s:%s:%d:%d|%s", r.name, r.door or "", r.save_type or "ALL", r.limit or 20000, r.count or 0, r.status or "Ready"))
    end
    for _, r in ipairs(HV.STATE.event_rows) do
        table.insert(lines, string.format("EVROW=%s:%s:%d:%d|%s", r.name, r.door or "", r.limit or 10000, r.count or 0, r.status or "Ready"))
    end

    local ok, f = pcall(io.open, getDataPath(), "w")
    if ok and f then f:write(table.concat(lines, "\n")); f:close() end
end

function HV.loadData()
    local ok, f = pcall(io.open, getDataPath(), "r")
    if not ok or not f then return end
    local txt = f:read("*a"); f:close()
    if not txt or txt == "" then return end
    local c = HV.CFG
    HV.STATE.rows       = {}
    HV.STATE.save_rows  = {}
    HV.STATE.event_rows = {}

    local legacySaveStr, legacyEventStr = "", ""
    for line in txt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([A-Z]+)=(.*)$")
        if k == "DEFID" then c.default_item_id = tonumber(v) or 4584
        elseif k == "DROPTH" then c.drop_threshold = tonumber(v) or 200
        elseif k == "SAVELIM" then c.default_save_limit = tonumber(v) or 20000
        elseif k == "EVLIM" then c.default_ev_limit = tonumber(v) or 10000
        elseif k == "IGEMS" then c.ignore_gems = (v ~= "0")
        elseif k == "MODE" and (v == "3zigzag" or v == "1by1") then c.harvest_mode = v
        elseif k == "HDELAY" then c.harvest_delay = tonumber(v) or 180
        elseif k == "SDELAY" then c.step_delay = tonumber(v) or 110
        elseif k == "MODFLY" then c.use_modfly = (v ~= "0")
        elseif k == "LOOP" then c.loop_enabled = (v == "1")
        elseif k == "ACOL" then c.auto_collect = (v ~= "0")
        elseif k == "EVIDS" then c.event_ids_raw = trimStr(v)
        elseif k == "EVTH" then c.event_threshold = tonumber(v) or 150
        elseif k == "GEARW" then c.gear_world = trimStr(v)
        elseif k == "AMAGFUEL" then c.auto_magni_fuel = (v == "1")
        elseif k == "GEAREQUIP" then c.gear_equip_ids = trimStr(v)
        elseif k == "FUELAMT" then c.fuel_target_amt = tonumber(v) or 100
        elseif k == "STPFUEL" then c.stop_if_no_fuel = (v ~= "0")
        elseif k == "FLOAT" then c.take_floating = (v ~= "0")
        elseif k == "MAGNI" or k == "FUEL" then if v == "1" then c.auto_magni_fuel = true end
        elseif k == "SAVEW" then legacySaveStr = trimStr(v)
        elseif k == "EVW" then legacyEventStr = trimStr(v)
        elseif k == "ROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseFarmRow(wd or v)
            if p then p.status = (st and st ~= "") and st or "Ready"; table.insert(HV.STATE.rows, p) end
        elseif k == "SAVEROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseSaveRow(wd or v)
            if p then p.status = (st and st ~= "") and st or "Ready"; table.insert(HV.STATE.save_rows, p) end
        elseif k == "EVROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseEventRow(wd or v)
            if p then p.status = (st and st ~= "") and st or "Ready"; table.insert(HV.STATE.event_rows, p) end
        end
    end

    -- Migrasi format legacy ke list tables bila sebelumnya berupa string
    if #HV.STATE.save_rows == 0 and legacySaveStr ~= "" then
        for _, sw in ipairs(parseWorldList(legacySaveStr)) do
            table.insert(HV.STATE.save_rows, { name = sw.name, door = sw.door or "", save_type = "ALL", limit = c.default_save_limit, count = 0, status = "Ready" })
        end
    end
    if #HV.STATE.event_rows == 0 and legacyEventStr ~= "" then
        for _, ew in ipairs(parseWorldList(legacyEventStr)) do
            table.insert(HV.STATE.event_rows, { name = ew.name, door = ew.door or "", limit = c.default_ev_limit, count = 0, status = "Ready" })
        end
    end

    addFarmItemBuf  = tostring(c.default_item_id)
    addSaveLimitBuf = tostring(c.default_save_limit)
    addEventLimitBuf = tostring(c.default_ev_limit)
end

-- ============================================================================
-- 3. GAME API, CONN GUARD, MOVEMENT & OBJECT HELPERS
-- ============================================================================
local function getLocalSafe()
    if not getLocal then return nil end
    local ok, p = pcall(getLocal)
    return (ok and p) and p or nil
end

local function getPlayerPos()
    local p = getLocalSafe()
    if not p then return 0, 0 end
    local px = p.posX or (p.pos and p.pos.x) or 0
    local py = p.posY or (p.pos and p.pos.y) or 0
    return math.floor((px + 10) / 32), math.floor((py + 10) / 32)
end

local function getCurrentWorldSafe()
    local cw = nil
    if getRealWorldName then
        local ok, w = pcall(getRealWorldName)
        if ok and type(w) == "string" and w ~= "" then cw = w end
    end
    if not cw and GetWorld then
        local ok, w = pcall(GetWorld)
        if ok and w then
            local name = w.name or (w.getName and w:getName())
            if type(name) == "string" and name ~= "" then cw = name end
        end
    end
    if not cw and getLocalSafe() then
        local p = getLocalSafe()
        if p.world and type(p.world) == "string" and p.world ~= "" then cw = p.world end
    end
    return cleanWorldName(cw or "EXIT")
end

local function getInvCount(itemID)
    if not itemID or itemID <= 0 then return 0 end
    local total = 0
    if getInventory then
        local ok, inv = pcall(getInventory)
        if ok and type(inv) == "table" then
            for _, it in ipairs(inv) do
                local id = it.id or it.itemid or it.itemID
                local c  = it.count or it.amount or it.itemCount or 0
                if id and tonumber(id) == itemID then total = total + (tonumber(c) or 0) end
            end
            return total
        end
    end
    if findItem then
        local ok, c = pcall(findItem, itemID)
        if ok and tonumber(c) then return math.floor(tonumber(c)) end
    end
    return 0
end

local function setCollectCheats(enable)
    local v = enable == true
    if cheat and cheat.collect then pcall(cheat.collect, v) end
    if setCheat then pcall(setCheat, "collect", v) end
    if autoCollect then pcall(autoCollect, v) end
end

local function setConnWarping(isWarping)
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.STATE then
        HUB_REF.conn.STATE.warping = (isWarping == true)
        if isWarping and HUB_REF.conn.touchActivity then pcall(HUB_REF.conn.touchActivity) end
    end
end

local function getTileSafe(x, y)
    if not getTile and not getTiles then return nil end
    if getTile then
        local ok, t = pcall(getTile, x, y)
        if ok and t then return t end
    end
    if getTiles then
        local ok, tiles = pcall(getTiles)
        if ok and type(tiles) == "table" then
            local idx = (y * 100) + x + 1
            if tiles[idx] then return tiles[idx] end
        end
    end
    return nil
end

local function forEachWorldObject(callback)
    if not getObjects then return end
    local ok, objs = pcall(getObjects)
    if not ok or type(objs) ~= "table" then return end
    for _, o in pairs(objs) do
        local oid = o.id or o.itemid or o.itemID
        local uid = o.oid or o.uid or o.objID
        local amt = o.count or o.amount or 1
        local ox  = o.posX or (o.pos and o.pos.x) or 0
        local oy  = o.posY or (o.pos and o.pos.y) or 0
        if oid and uid then callback(tonumber(oid), tonumber(uid), tonumber(amt), ox, oy) end
    end
end

local function countDroppedObjectsInWorld(allowedSet)
    local total = 0
    forEachWorldObject(function(oid, _, amt)
        if (not allowedSet) or allowedSet[oid] then total = total + amt end
    end)
    return total
end

local function isTileBlocked(x, y)
    local t = getTileSafe(x, y)
    if not t then return true end
    local fg = tonumber(t.fg) or 0
    if fg > 0 and LOCK_OR_DOOR_IDS[fg] then return true end
    return false
end

local unreachableMap = {}
local function moveSafeTo(tx, ty)
    if unreachableMap[tx .. ":" .. ty] then return false end
    if tx < 0 or tx > 99 or ty < 0 or ty > 59 then return false end
    if FindPath then
        local ok, r = pcall(FindPath, tx, ty)
        if ok and r == false then
            unreachableMap[tx .. ":" .. ty] = true
            return false
        end
    end
    local px, py = getPlayerPos()
    if math.abs(px - tx) <= 1 and math.abs(py - ty) <= 1 then return true end
    safeSleep(tonumber(HV.CFG.step_delay) or 110)
    local npx, npy = getPlayerPos()
    local moved = (math.abs(npx - tx) < math.abs(px - tx)) or (math.abs(npy - ty) < math.abs(py - ty)) or (npx == tx and npy == ty)
    if not moved then unreachableMap[tx .. ":" .. ty] = true end
    return moved
end

local function warpToWorldInner(wName, doorID)
    doorID = doorID or ""
    if wName == "" then return false end
    unreachableMap = {}
    if getCurrentWorldSafe() == wName and doorID == "" then return true end
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.isPlayerOnline and (not HUB_REF.conn.isPlayerOnline()) and (not HUB_REF.conn.isReconnecting()) then
        local okOn = HUB_REF.conn.ensureOnline({ world = "", isRunning = function() return HV.STATE.running end })
        if not okOn then return false end
    end
    local joinStr = (doorID ~= "") and (wName .. "|" .. doorID) or wName
    for _ = 1, 3 do
        if not HV.STATE.running then return false end
        if sendPacket then pcall(sendPacket, 3, "action|join_request\nname|" .. joinStr .. "\ninvitedWorld|0\n")
        elseif growtopia and growtopia.warpTo then pcall(growtopia.warpTo, joinStr) end
        local w, lim = 0, math.max(4000, tonumber(HV.CFG.warp_delay) or 4500)
        while w < lim and HV.STATE.running do
            safeSleep(250); w = w + 250
            if getCurrentWorldSafe() == wName then safeSleep(600); return true end
        end
    end
    return getCurrentWorldSafe() == wName
end

local function warpToWorld(wName, doorID)
    setConnWarping(true)
    local ok = warpToWorldInner(wName, doorID)
    setConnWarping(false)
    return ok
end

local function ensureHVOnline(row, resumeCollect)
    local conn = HUB_REF and HUB_REF.conn
    if not conn or not conn.ensureOnline then return true end
    local tw = row and row.name or ""
    local td = row and row.door or ""
    if not conn.needsReconnect(tw) then return true end
    HV.STATE.status_text = "RECONNECTING..."
    if row then row.status = "Reconnecting..." end
    local okOn = conn.ensureOnline({
        world     = tw,
        door      = td,
        isRunning = function() return HV.STATE.running end,
        onResume  = function() setCollectCheats(resumeCollect == true) end,
        warpFn    = function(w, d) return warpToWorld(w, d) end,
    })
    return okOn == true
end

local function punchTile(tx, ty)
    if not sendPacketRaw then return false end
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.STATE and HUB_REF.conn.STATE.reconnecting then return false end
    local p = getLocalSafe()
    local px = (p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    return pcall(sendPacketRaw, false, {
        type = 3, value = ITEM.PUNCH, px = tx, py = ty, x = px, y = py,
        state = (px > tx * 32) and 48 or 32,
    })
end

local function collectNearbyAllowed(allowedSet, radiusTiles)
    if not HV.CFG.auto_collect or not sendPacketRaw then return end
    local px, py = getPlayerPos()
    local rad = radiusTiles or (tonumber(HV.CFG.collect_range) or 4)
    forEachWorldObject(function(oid, uid, _, ox, oy)
        if HV.CFG.ignore_gems and oid == ITEM.GEMS then return end
        if (not allowedSet) or allowedSet[oid] then
            local otx = math.floor((ox + 10) / 32)
            local oty = math.floor((oy + 10) / 32)
            if math.abs(otx - px) <= rad and math.abs(oty - py) <= rad then
                pcall(sendPacketRaw, false, { type = 11, value = uid, x = ox, y = oy })
            end
        end
    end)
end

-- ============================================================================
-- 4. DROP ENGINE (RAPI, SKIP LOCK/DOOR, PINDAH TILE & CEK LIMIT)
-- ============================================================================
local function parseDropDialogPacket(dlgText, fallbackID, dropAmt)
    local embedLines = {}
    local dName = dlgText:match("end_dialog|([^|\r\n]+)") or "drop_item"
    for k, v in dlgText:gmatch("embed_data|([^|\r\n]+)|([^\r\n|]*)") do
        table.insert(embedLines, k .. "|" .. v)
    end
    local countField = dlgText:match("add_text_input|([^|\r\n]+)|") or "count"
    local out = { "action|dialog_return", "dialog_name|" .. dName }
    for _, l in ipairs(embedLines) do table.insert(out, l) end
    if not dlgText:find("itemID|", 1, true) then
        table.insert(out, "itemID|" .. tostring(fallbackID) .. "|")
    end
    table.insert(out, countField .. "|" .. tostring(dropAmt))
    return table.concat(out, "\n") .. "\n"
end

local function onVariantHook(var)
    if not HV.STATE.running or HV.STATE.pending_drop_id <= 0 then return end
    if var and var[0] == "OnDialogRequest" and type(var[1]) == "string" then
        local text = var[1]
        if text:find("drop", 1, true) or text:find("Drop", 1, true) then
            local pkt = parseDropDialogPacket(text, HV.STATE.pending_drop_id, HV.STATE.pending_drop_amt)
            if sendPacket then
                pcall(sendPacket, 2, pkt)
                HV.STATE.drop_confirmed = true
            end
        end
    end
end

local function onSendPacketRawHook(raw)
    if not HV.STATE.running then return end
    if raw and raw.type == 10 and raw.value then
        if raw.value == ITEM.SORROWS or raw.value == ITEM.HARVESTER then
            if not HV.STATE.need_fuel then addLog("`2[Harvester] Berhasil equip Harvester!") end
        end
    end
    if HV.CFG.ignore_gems and raw and raw.type == 11 and raw.value then
        local targetUID = raw.value
        local isGems = false
        forEachWorldObject(function(oid, uid)
            if uid == targetUID and oid == ITEM.GEMS then isGems = true end
        end)
        if isGems then return true end
    end
end

local function waitInvDropTo(itemID, targetMax, timeoutMs)
    local elapsed = 0
    while elapsed < timeoutMs do
        safeSleep(60); elapsed = elapsed + 60
        if getInvCount(itemID) <= targetMax or HV.STATE.drop_confirmed then return true end
    end
    return getInvCount(itemID) <= targetMax
end

local function findCleanDropPositions()
    local spots = {}
    local px, py = getPlayerPos()
    local startX = math.max(2, math.min(94, px))
    local startY = math.max(2, math.min(54, py))
    for r = 0, 8 do
        for dy = -r, r do
            for dx = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    local sx, sy = startX + dx, startY + dy
                    if sx >= 2 and sx <= 97 and sy >= 2 and sy <= 55 then
                        if not isTileBlocked(sx, sy) and not isTileBlocked(sx, sy + 1) then
                            table.insert(spots, { x = sx, y = sy })
                            if #spots >= 16 then return spots end
                        end
                    end
                end
            end
        end
    end
    if #spots == 0 then table.insert(spots, { x = startX, y = startY }) end
    return spots
end

local function dropItemAllInCurrentWorld(itemID, label)
    local cur = getInvCount(itemID)
    if cur <= 0 then return true, 0 end

    local spots = findCleanDropPositions()
    local spotIdx = 1
    if spots[1] then moveSafeTo(spots[1].x, spots[1].y); safeSleep(150) end

    local droppedTotal = 0
    local failMove = 0
    while cur > 0 and HV.STATE.running and failMove < 15 do
        local batch = math.min(200, cur)
        HV.STATE.pending_drop_id  = itemID
        HV.STATE.pending_drop_amt = batch
        HV.STATE.drop_confirmed   = false
        HV.STATE.status_text = string.format("Drop %s (%d)...", tostring(label or itemID), batch)

        local ok = false
        if growtopia and growtopia.confirmDropItem then
            pcall(growtopia.confirmDropItem, itemID, batch)
            ok = waitInvDropTo(itemID, cur - 1, 700)
        end
        if not ok and sendPacket and HV.STATE.running then
            HV.STATE.drop_confirmed = false
            pcall(sendPacket, 2, "action|drop\n|itemID|" .. tostring(itemID))
            ok = waitInvDropTo(itemID, cur - 1, 950)
        end
        if not ok and sendPacket and HV.STATE.running then
            for _, dn in ipairs({ "drop", "drop_item" }) do
                pcall(sendPacket, 2, string.format("action|dialog_return\ndialog_name|%s\nitemID|%d|\ncount|%d\n", dn, itemID, batch))
                ok = waitInvDropTo(itemID, cur - 1, 650)
                if ok then break end
            end
        end

        HV.STATE.pending_drop_id  = 0
        HV.STATE.pending_drop_amt = 0

        local after = getInvCount(itemID)
        if after < cur then
            droppedTotal = droppedTotal + (cur - after)
            HV.STATE.total_dropped = HV.STATE.total_dropped + (cur - after)
            cur = after
            safeSleep(180)
        else
            failMove = failMove + 1
            spotIdx = spotIdx + 1
            if spots[spotIdx] then
                moveSafeTo(spots[spotIdx].x, spots[spotIdx].y)
            else
                local px, py = getPlayerPos()
                local nx = (px < 94) and (px + 2) or 2
                local ny = (px < 94) and py or math.max(2, py - 2)
                moveSafeTo(nx, ny)
            end
            safeSleep(220)
        end
    end
    return (getInvCount(itemID) == 0), droppedTotal
end

local function dropToSaveWorlds(blockID, seedID, returnFarm)
    local bCnt = getInvCount(blockID)
    local sCnt = getInvCount(seedID)
    if bCnt <= 0 and sCnt <= 0 then return true end

    local rows = HV.STATE.save_rows
    if #rows == 0 then
        addLog("`4[Save World] Daftar Save World kosong! Tambahkan di tab Save World.")
        return false
    end

    local itemsToDrop = {}
    if bCnt > 0 then table.insert(itemsToDrop, { id = blockID, name = "Block", isBlock = true }) end
    if sCnt > 0 then table.insert(itemsToDrop, { id = seedID, name = "Seed", isBlock = false }) end

    for _, itm in ipairs(itemsToDrop) do
        local curAmt = getInvCount(itm.id)
        while curAmt > 0 and HV.STATE.running do
            local targetRow = nil
            for _, r in ipairs(rows) do
                if r.status ~= "Full" and r.status ~= "Inaccessible" then
                    local t = (r.save_type or "ALL"):upper()
                    if itm.isBlock and (t == "ALL" or t == "BLOCK") then
                        targetRow = r; break
                    elseif (not itm.isBlock) and (t == "ALL" or t == "SEED") then
                        targetRow = r; break
                    end
                end
            end

            if not targetRow then
                addLog(string.format("`4[Save World] Semua world untuk %s sudah penuh / tidak tersedia!", itm.name))
                break
            end

            HV.STATE.status_text = "Drop " .. itm.name .. " -> " .. targetRow.name
            if warpToWorld(targetRow.name, targetRow.door) then
                setCollectCheats(false)
                safeSleep(350)

                local filterSet = {}
                local t = (targetRow.save_type or "ALL"):upper()
                if t == "BLOCK" then filterSet[blockID] = true
                elseif t == "SEED" then filterSet[seedID] = true
                else filterSet[blockID] = true; filterSet[seedID] = true end

                local lim = math.max(0, math.floor(tonumber(targetRow.limit) or 0))
                local curInWorld = countDroppedObjectsInWorld(filterSet)
                targetRow.count = curInWorld

                if lim > 0 and curInWorld >= lim then
                    addLog(string.format("`e[Save World] %s capai limit (%d/%d) -> lanjut next world!", targetRow.name, curInWorld, lim))
                    targetRow.status = "Full"
                    HV.saveData()
                else
                    local okD = dropItemAllInCurrentWorld(itm.id, itm.name)
                    local afterInWorld = countDroppedObjectsInWorld(filterSet)
                    targetRow.count = afterInWorld
                    if lim > 0 and afterInWorld >= lim then
                        targetRow.status = "Full"
                    end
                    HV.saveData()
                    if not okD then
                        targetRow.status = "Full"
                        HV.saveData()
                    end
                end
            else
                addLog("`4[Save World] Gagal warp ke " .. targetRow.name)
                targetRow.status = "Inaccessible"
                HV.saveData()
            end
            curAmt = getInvCount(itm.id)
        end
    end

    if returnFarm and HV.STATE.running then
        warpToWorld(returnFarm.name, returnFarm.door)
        setCollectCheats(true)
    end
    return (getInvCount(blockID) == 0 and getInvCount(seedID) == 0)
end

local function dropToEventWorlds(returnFarm)
    local evList, evMap = parseEventIDs()
    local toDrop = {}
    for _, id in ipairs(evList) do
        if getInvCount(id) > 0 then table.insert(toDrop, id) end
    end
    if #toDrop == 0 then return true end

    local rows = HV.STATE.event_rows
    if #rows == 0 then
        addLog("`4[Event World] Daftar Event Save World kosong! Isi di tab Event Save.")
        return false
    end

    for _, itmID in ipairs(toDrop) do
        local curAmt = getInvCount(itmID)
        while curAmt > 0 and HV.STATE.running do
            local targetRow = nil
            for _, r in ipairs(rows) do
                if r.status ~= "Full" and r.status ~= "Inaccessible" then
                    targetRow = r; break
                end
            end

            if not targetRow then
                addLog("`4[Event World] Semua World Event sudah penuh / tidak tersedia!")
                break
            end

            HV.STATE.status_text = "Drop Event -> " .. targetRow.name
            if warpToWorld(targetRow.name, targetRow.door) then
                setCollectCheats(false)
                safeSleep(350)

                local lim = math.max(0, math.floor(tonumber(targetRow.limit) or 0))
                local curInWorld = countDroppedObjectsInWorld(evMap)
                targetRow.count = curInWorld

                if lim > 0 and curInWorld >= lim then
                    addLog(string.format("`e[Event World] %s capai limit total (%d/%d) -> pindah world event!", targetRow.name, curInWorld, lim))
                    targetRow.status = "Full"
                    HV.saveData()
                else
                    local okD = dropItemAllInCurrentWorld(itmID, "Item " .. itmID)
                    local afterInWorld = countDroppedObjectsInWorld(evMap)
                    targetRow.count = afterInWorld
                    if lim > 0 and afterInWorld >= lim then
                        targetRow.status = "Full"
                    end
                    HV.saveData()
                    if not okD then
                        targetRow.status = "Full"
                        HV.saveData()
                    end
                end
            else
                addLog("`4[Event World] Gagal warp ke " .. targetRow.name)
                targetRow.status = "Inaccessible"
                HV.saveData()
            end
            curAmt = getInvCount(itmID)
        end
    end

    if returnFarm and HV.STATE.running then
        warpToWorld(returnFarm.name, returnFarm.door)
        setCollectCheats(true)
    end
    return true
end

-- ============================================================================
-- 5. GEAR WORLD (MAGNI + FUEL TERPADU & LIST ID EQUIP ALAT)
-- ============================================================================
local function equipItem(itemID)
    if not sendPacketRaw or getInvCount(itemID) <= 0 then return false end
    return pcall(sendPacketRaw, false, { type = 10, value = itemID })
end

local function ensureGearAndFuel(returnFarm)
    local c = HV.CFG
    local needed = {}

    -- 1. Magni & Fuel Pack dijadikan satu
    if c.auto_magni_fuel then
        if getInvCount(ITEM.MAGNI) <= 0 then
            table.insert(needed, { id = ITEM.MAGNI, amt = 1, equip = true, name = "Magnifying Glass" })
        end
        local fuelCount = getInvCount(ITEM.FUEL_PACK)
        if HV.STATE.need_fuel and fuelCount > 0 then
            equipItem(ITEM.FUEL_PACK)
            HV.STATE.need_fuel = false
            safeSleep(250)
            fuelCount = getInvCount(ITEM.FUEL_PACK)
        end
        local targetFuel = math.max(1, math.min(200, tonumber(c.fuel_target_amt) or 100))
        if fuelCount < targetFuel or HV.STATE.need_fuel then
            table.insert(needed, { id = ITEM.FUEL_PACK, amt = targetFuel, equip = false, name = "Fuel Pack" })
        end
    end

    -- 2. Daftar ID Alat untuk Di-equip (DCS, Harvester, dll.)
    local equipIDs = parseEquipIDs(c.gear_equip_ids)
    for _, eqID in ipairs(equipIDs) do
        if getInvCount(eqID) <= 0 then
            table.insert(needed, { id = eqID, amt = 1, equip = true, name = "Gear " .. tostring(eqID) })
        end
    end

    -- Jika semua perlengkapan sudah ada di tas
    if #needed == 0 then
        if c.auto_magni_fuel and getInvCount(ITEM.MAGNI) > 0 then equipItem(ITEM.MAGNI); safeSleep(100) end
        for _, eqID in ipairs(equipIDs) do if getInvCount(eqID) > 0 then equipItem(eqID); safeSleep(100) end end
        return true
    end

    local gw = parseWorldDoor(c.gear_world)
    if not gw then
        if c.auto_magni_fuel and c.stop_if_no_fuel and getInvCount(ITEM.FUEL_PACK) <= 0 then
            addLog("`4[Fuel Guard] Fuel Pack habis & Gear World belum diatur — bot berhenti aman!")
            HV.STATE.status_text = "No Fuel Pack"
            return false
        end
        addLog("`e[Gear] Gear World belum diatur — melewati restock gear.")
        return true
    end

    HV.STATE.status_text = "Gear World: " .. gw.name
    addLog("[Gear] Ambil perlengkapan / fuel di " .. gw.name)
    if not warpToWorld(gw.name, gw.door) then
        addLog("`4[Gear] Gagal warp ke Gear World " .. gw.name)
        return false
    end

    setCollectCheats(true)
    safeSleep(450)
    for _, req in ipairs(needed) do
        if not HV.STATE.running then return false end
        forEachWorldObject(function(oid, uid, _, ox, oy)
            if not HV.STATE.running then return end
            if oid == req.id and getInvCount(req.id) < req.amt then
                if moveSafeTo(math.floor((ox + 10) / 32), math.floor((oy + 10) / 32)) then
                    if sendPacketRaw then pcall(sendPacketRaw, false, { type = 11, value = uid, x = ox, y = oy }) end
                    safeSleep(220)
                end
            end
        end)
        if req.equip and getInvCount(req.id) > 0 then
            equipItem(req.id); safeSleep(180)
            addLog("`2[Gear] Equip " .. req.name)
        elseif req.id == ITEM.FUEL_PACK and getInvCount(ITEM.FUEL_PACK) > 0 then
            addLog("`2[Gear] Fuel Pack terambil: " .. getInvCount(ITEM.FUEL_PACK))
            if HV.STATE.need_fuel then equipItem(ITEM.FUEL_PACK); HV.STATE.need_fuel = false; safeSleep(200) end
        end
    end

    if c.auto_magni_fuel and c.stop_if_no_fuel and getInvCount(ITEM.FUEL_PACK) <= 0 then
        addLog("`4[Fuel Guard] Stok Fuel Pack habis di tas & Gear World — bot berhenti aman!")
        HV.STATE.status_text = "No Fuel Pack"
        return false
    end

    if returnFarm and HV.STATE.running then
        warpToWorld(returnFarm.name, returnFarm.door)
        setCollectCheats(true)
    end
    return true
end

-- ============================================================================
-- 6. HARVEST ENGINE (3-ZIGZAG / 1BY1 + TAKE FLOATING + AUTO DROP)
-- ============================================================================
local function isReadyTree(tx, ty, seedID)
    local t = getTileSafe(tx, ty)
    if not t or tonumber(t.fg) ~= seedID then return false end
    if t.readyharvest == true then return true end
    if tonumber(t.progress) and tonumber(t.progress) >= 1.0 then return true end
    return false
end

local function updateInvPreview(blockID, seedID, eventList)
    HV.STATE.inv_preview.block = getInvCount(blockID)
    HV.STATE.inv_preview.seed  = getInvCount(seedID)
    HV.STATE.inv_preview.fuel  = getInvCount(ITEM.FUEL_PACK)
    local evSum = 0
    for _, eid in ipairs(eventList or {}) do evSum = evSum + getInvCount(eid) end
    HV.STATE.inv_preview.ev = evSum
end

local function checkAndDropIfFull(row, blockID, seedID, eventList, forceDrop)
    updateInvPreview(blockID, seedID, eventList)
    local c = HV.CFG
    local th  = math.max(20, math.min(200, tonumber(c.drop_threshold) or 200))
    local eth = math.max(10, math.min(200, tonumber(c.event_threshold) or 150))

    -- 1. Cek Fuel Pack proaktif jika memakai harvester & fuel
    if (not forceDrop) and c.auto_magni_fuel and (HV.STATE.need_fuel or getInvCount(ITEM.FUEL_PACK) <= 0) then
        if not ensureGearAndFuel(row) then return false end
    end

    -- 2. Drop Item Event bila ada di tas
    local needEventDrop = false
    for _, eid in ipairs(eventList) do
        local cnt = getInvCount(eid)
        if (forceDrop and cnt > 0) or cnt >= eth then needEventDrop = true; break end
    end
    if needEventDrop and #HV.STATE.event_rows > 0 then
        if not dropToEventWorlds(forceDrop and nil or row) then return false end
    end

    -- 3. Drop Block & Seed
    local bCnt, sCnt = getInvCount(blockID), getInvCount(seedID)
    if (forceDrop and (bCnt > 0 or sCnt > 0)) or bCnt >= th or sCnt >= th then
        if not dropToSaveWorlds(blockID, seedID, forceDrop and nil or row) then return false end
    end

    updateInvPreview(blockID, seedID, eventList)
    return true
end

local function sweepFloatingObjects(row, blockID, seedID, allowedSet, eventList)
    if not HV.CFG.take_floating then return true end
    HV.STATE.status_text = row.name .. " Take Floating..."
    addLog("[Floating] Sapu sisa drop block/seed/event di " .. row.name)
    setCollectCheats(true)

    local pass = 0
    while pass < 6 and HV.STATE.running do
        pass = pass + 1
        if not ensureHVOnline(row, true) then return false end
        local targets = {}
        forEachWorldObject(function(oid, uid, _, ox, oy)
            if HV.CFG.ignore_gems and oid == ITEM.GEMS then return end
            if allowedSet[oid] then
                table.insert(targets, { oid = oid, uid = uid, ox = ox, oy = oy, tx = math.floor((ox + 10) / 32), ty = math.floor((oy + 10) / 32) })
            end
        end)
        if #targets == 0 then break end
        for _, obj in ipairs(targets) do
            if not HV.STATE.running then return false end
            if not ensureHVOnline(row, true) then return false end
            if not checkAndDropIfFull(row, blockID, seedID, eventList, false) then return false end
            if moveSafeTo(obj.tx, obj.ty) then
                if sendPacketRaw then pcall(sendPacketRaw, false, { type = 11, value = obj.uid, x = obj.ox, y = obj.oy }) end
                collectNearbyAllowed(allowedSet, 3)
                safeSleep(120)
            end
        end
    end
    return true
end

local function processFarmWorld(row)
    local blockID, seedID = normalizeHarvestPair(row.item_id or HV.CFG.default_item_id)
    if blockID <= 0 then row.status = "Invalid ID"; HV.saveData(); return false end

    local eventList, eventMap = parseEventIDs()
    local allowedSet = { [blockID] = true, [seedID] = true }
    for id in pairs(eventMap) do allowedSet[id] = true end

    if not ensureGearAndFuel(nil) then return false end

    row.status = "Warping..."
    HV.STATE.status_text = "Warp: " .. row.name
    if not warpToWorld(row.name, row.door) then
        row.status = "Inaccessible"; HV.saveData(); return false
    end
    setCollectCheats(true)
    safeSleep(500)

    local hDelay = math.max(90, tonumber(HV.CFG.harvest_delay) or 180)
    local isZigzag = (HV.CFG.harvest_mode == "3zigzag")
    local rowCount = 0

    for py = 52, 2, -2 do
        if not HV.STATE.running then return false end
        rowCount = rowCount + 1
        local l2r = (rowCount % 2 == 1)
        local startX = l2r and 2 or 97
        local endX   = l2r and 97 or 2
        local stepX  = l2r and 1 or -1

        local ty = py - 1
        local hasTreeInRow = false
        for x = 2, 97 do
            if isReadyTree(x, ty, seedID) then hasTreeInRow = true; break end
        end

        if hasTreeInRow then
            if not ensureHVOnline(row, true) then return false end
            if isZigzag then
                local x = startX
                while (l2r and x <= endX) or ((not l2r) and x >= endX) do
                    if not HV.STATE.running then return false end
                    if not ensureHVOnline(row, true) then return false end

                    local t1 = isReadyTree(x, ty, seedID)
                    local t2 = isReadyTree(x + stepX, ty, seedID)
                    local t3 = isReadyTree(x + (stepX * 2), ty, seedID)

                    if t1 or t2 or t3 then
                        if not checkAndDropIfFull(row, blockID, seedID, eventList, false) then return false end
                        moveSafeTo(x, py)
                        collectNearbyAllowed(allowedSet, 4)

                        if t1 then punchTile(x, ty); safeSleep(hDelay); HV.STATE.total_harvested = HV.STATE.total_harvested + 1 end
                        if t2 then punchTile(x + stepX, ty); safeSleep(hDelay); HV.STATE.total_harvested = HV.STATE.total_harvested + 1 end
                        if t3 then punchTile(x + (stepX * 2), ty); safeSleep(hDelay); HV.STATE.total_harvested = HV.STATE.total_harvested + 1 end
                        collectNearbyAllowed(allowedSet, 4)
                        x = x + (stepX * 3)
                    else
                        x = x + stepX
                    end
                end
            else
                for x = startX, endX, stepX do
                    if not HV.STATE.running then return false end
                    if not ensureHVOnline(row, true) then return false end
                    if isReadyTree(x, ty, seedID) then
                        if not checkAndDropIfFull(row, blockID, seedID, eventList, false) then return false end
                        moveSafeTo(x, py)
                        collectNearbyAllowed(allowedSet, 4)
                        punchTile(x, ty)
                        safeSleep(hDelay)
                        HV.STATE.total_harvested = HV.STATE.total_harvested + 1
                        collectNearbyAllowed(allowedSet, 4)
                    end
                end
            end
        end
    end

    -- Sapu sisa floating block / seed / event jika opsi take_floating aktif
    sweepFloatingObjects(row, blockID, seedID, allowedSet, eventList)

    -- Force drop semua hasil yang tersisa di tas sebelum pindah farm
    checkAndDropIfFull(row, blockID, seedID, eventList, true)

    row.status = "Done"
    HV.saveData()
    addLog(string.format("`2World %s SELESAI dipanen!", row.name))
    return true
end

local function harvestLoopRunner()
    HV.STATE.running = true
    HV.STATE.enabled = true
    addLog("`2Auto Harvest dimulai...")

    while HV.STATE.running do
        local allDone = true
        for i, row in ipairs(HV.STATE.rows) do
            if not HV.STATE.running then break end
            if row.status ~= "Done" and row.status ~= "Inaccessible" and row.status ~= "Invalid ID" then
                allDone = false
                HV.STATE.selected_idx = i
                local ok = processFarmWorld(row)
                if not ok and not HV.STATE.running then break end
                safeSleep(1000)
            end
        end

        if not HV.STATE.running then break end
        if allDone then
            if HV.CFG.loop_enabled and #HV.STATE.rows > 0 then
                addLog("`eSemua farm selesai, looping antrean diulang!")
                for _, r in ipairs(HV.STATE.rows) do
                    if r.status == "Done" then r.status = "Ready" end
                end
                HV.saveData()
                safeSleep(2000)
            else
                addLog("`2Semua antrean Farm Harvest telah selesai!")
                HV.STATE.status_text = "Done All"
                break
            end
        end
    end

    HV.STATE.running = false
    HV.STATE.enabled = false
    setCollectCheats(false)
    HV.STATE.status_text = "Idle"
    HV.saveData()
    addLog("`eAuto Harvest berhenti.")
end

function HV.start()
    if HV.STATE.running then return false end
    if #HV.STATE.rows == 0 then
        addLog("`4Daftar Farm kosong! Tambahkan world di tab Farm List.")
        return false
    end
    runAsync(harvestLoopRunner)
    return true
end

function HV.stop()
    if not HV.STATE.running then
        HV.STATE.enabled = false
        return false
    end
    HV.STATE.running = false
    HV.STATE.enabled = false
    setCollectCheats(false)
    HV.STATE.status_text = "Stopping..."
    addLog("Menghentikan bot...")
    return true
end

function HV.init(hub)
    HUB_REF = hub
    HV.loadData()
end

-- ============================================================================
-- 7. UI RENDERER (TERINTEGRASI DENGAN UI_KIT BOREN STORE HUB)
-- ============================================================================
local function uiKit()
    return HUB_REF and HUB_REF.ui_kit or nil
end

local function autoBtn(lbl)
    local ok, r = pcall(ImGui.Button, lbl)
    return ok and (r == true)
end

local function uiGap(px)
    local k = uiKit()
    if k and k.gap then k.gap(px); return end
    if ImGui and ImGui.Spacing then pcall(ImGui.Spacing) end
end

local function uiSection(title, skipTopSep)
    local k = uiKit()
    if k and k.section then k.section(title, skipTopSep); return end
    if not skipTopSep then ImGui.Separator() end
    if title and title ~= "" then ImGui.Text(title) end
end

local function uiSectionWithKetik(title, btnId, onKetikClick, skipTopSep)
    local k = uiKit()
    if k and k.sectionWithKetik and k.openInputDialog then
        k.sectionWithKetik(title, btnId, onKetikClick, skipTopSep)
        return
    end
    uiSection(title, skipTopSep)
end

local function uiOpenDialog(id, title, fields, submitLbl, onSubmit)
    local k = uiKit()
    if k and k.openInputDialog then
        k.openInputDialog(id, title, fields, submitLbl, onSubmit)
    end
end

local function uiEnableBtn(isOn, id)
    local k = uiKit()
    if k and k.enableBtn then return k.enableBtn(isOn, id) end
    return autoBtn((isOn and "ON##" or "OFF##") .. tostring(id))
end

local function uiToggleBtn(isOn, id, onLbl, offLbl)
    local k = uiKit()
    if k and k.toggleBtn then return k.toggleBtn(isOn, id, onLbl, offLbl) end
    return autoBtn(" " .. (isOn and (onLbl or "ON") or (offLbl or "OFF")) .. " ##" .. tostring(id))
end

local function uiTabBtn(label, isActive)
    local k = uiKit()
    if k and k.tabBtn then return k.tabBtn(label, isActive) end
    return autoBtn(isActive and ("[ " .. label .. " ]") or label)
end

local function uiNote(msg)
    if not msg or msg == "" then return end
    local k = uiKit()
    if k and k.coloredText and k.getPal then
        k.coloredText(k.getPal().textPurple, "Info: " .. tostring(msg))
    else
        ImGui.Text("Info: " .. tostring(msg))
    end
end

local function uiActionBar(id, w, buttons)
    local k = uiKit()
    if k and k.renderActionBar then return k.renderActionBar(id, w, buttons) end
    local hit = nil
    for i, b in ipairs(buttons) do
        if i > 1 then ImGui.SameLine() end
        if autoBtn(b.label) then hit = i end
    end
    return hit
end

local function safeInput(id, val, maxL)
    local k = uiKit()
    if k and k.safeInputText then return k.safeInputText(id, val, maxL) end
    local s = tostring(val or "")
    local ok, r1, r2 = pcall(ImGui.InputText, id, s, maxL or 256)
    if not ok then return false, s end
    if type(r1) == "boolean" and type(r2) == "string" then return (r1 or r2 ~= s), r2
    elseif type(r1) == "string" then return (r2 == true or r1 ~= s), r1
    elseif type(r2) == "string" and r2 ~= s then return true, r2 end
    return false, s
end

local function readClipLines()
    local k = uiKit()
    if k and k.readClipboardLines then return k.readClipboardLines() end
    local clip = ""
    if ImGui and ImGui.GetClipboardText then
        local ok, c = pcall(ImGui.GetClipboardText)
        if ok and type(c) == "string" then clip = c end
    end
    local out = {}
    for line in clip:gmatch("[^\r\n]+") do
        local s = trimStr(line); if s ~= "" then out[#out + 1] = s end
    end
    return out
end

local function availX()
    if ImGui and ImGui.GetContentRegionAvail then
        local ok, av = pcall(ImGui.GetContentRegionAvail)
        if ok and av then
            if type(av) == "number" and av > 40 then return av end
            local okX, x = pcall(function() return av.x end)
            if okX and type(x) == "number" and x > 40 then return x end
        end
    end
    return 480
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 1: FARM LIST
-- ----------------------------------------------------------------------------
local function renderFarmsSub()
    local c, st = HV.CFG, HV.STATE
    local w = availX()

    uiSection("Kontrol Auto Harvest", true)
    ImGui.Text("Status Bot  :"); ImGui.SameLine()
    if uiEnableBtn(st.enabled, "hv_en") then
        if st.enabled then HV.stop() else HV.start() end
    end
    ImGui.SameLine(); ImGui.Text("    Loop  :"); ImGui.SameLine()
    if uiToggleBtn(c.loop_enabled, "hv_lp") then
        c.loop_enabled = not c.loop_enabled; HV.saveData()
    end
    ImGui.SameLine()
    if autoBtn(" Reset ##hv_rst") then
        for _, r in ipairs(st.rows) do r.status = "Ready" end
        HV.saveData(); uiNotice = "Semua status farm di-reset ke Ready."
    end
    ImGui.SameLine()
    if autoBtn(" Clear ##hv_clr") then
        st.rows = {}; st.selected_idx = 0; HV.saveData(); uiNotice = "Daftar farm dikosongkan."
    end

    uiGap(4)
    ImGui.Text(string.format("Status: %s   |   Farm: %d   |   Tree: %d   |   Drop: %d",
        tostring(st.status_text), #st.rows, st.total_harvested, st.total_dropped))
    uiNote(uiNotice)

    uiSection("Daftar World Farm (" .. tostring(#st.rows) .. ")")

    if ImGui.BeginTable("BorenHarvestTable", 4) then
        ImGui.TableSetupColumn("World")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableSetupColumn("Block/Seed ID")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #st.rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(c.default_item_id))
            ImGui.TableSetColumnIndex(3); ImGui.Text("Tambah di bawah")
        else
            for i, r in ipairs(st.rows) do
                local bID, sID = normalizeHarvestPair(r.item_id)
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (st.selected_idx == i)
                if autoBtn((sel and "> " or "") .. tostring(r.name) .. "##hvr" .. tostring(i)) then
                    st.selected_idx = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text((r.door and r.door ~= "") and r.door or "-")
                ImGui.TableSetColumnIndex(2); ImGui.Text(string.format("%d / %d", bID, sID))
                ImGui.TableSetColumnIndex(3); ImGui.Text(tostring(r.status or "Ready"))
            end
        end
        ImGui.EndTable()
    end

    uiSectionWithKetik("Tambah World Farm Baru", "hv_ktk_w", function()
        local wPre, dPre = tostring(addFarmWorldBuf or ""):gsub("|", ":"):match("^([^:]+):(.*)$")
        if not wPre then wPre = tostring(addFarmWorldBuf or ""); dPre = "" end
        uiOpenDialog("boren_in_hv_w", "Tambah World Harvest", {
            { id = "f_world", label = "Nama World", default = wPre, maxLen = 32 },
            { id = "f_door",  label = "Door ID (opsional)", default = dPre, maxLen = 32 },
            { id = "f_item",  label = "Block / Seed ID", default = addFarmItemBuf, maxLen = 12 },
        }, "Tambah & Simpan", function(vals)
            local wn = trimStr(vals.f_world or ""):upper()
            local dn = trimStr(vals.f_door or ""):upper()
            local iid = math.floor(tonumber(vals.f_item) or tonumber(c.default_item_id) or 4584)
            if iid <= 0 then iid = 4584 end
            c.default_item_id = iid
            addFarmItemBuf = tostring(iid)
            if wn ~= "" then
                local p = { name = wn, door = dn, item_id = iid, status = "Ready" }
                table.insert(st.rows, p); addFarmWorldBuf = ""; HV.saveData()
                uiNotice = "Tersimpan: " .. wn .. " (ID " .. tostring(iid) .. ")"
            end
        end)
    end)

    if ImGui.BeginTable("BorenHarvestAddW", 2) then
        ImGui.TableSetupColumn("World:DoorID")
        ImGui.TableSetupColumn("Item ID (Block/Seed)")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(120, math.floor(w * 0.56)))
        local chW, nvW = safeInput("##hv_add_w", addFarmWorldBuf, 256)
        ImGui.PopItemWidth()
        if chW then addFarmWorldBuf = nvW end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(80, math.floor(w * 0.34)))
        local chI, nvI = safeInput("##hv_add_item", addFarmItemBuf, 64)
        ImGui.PopItemWidth()
        if chI then
            addFarmItemBuf = nvI:gsub("[^0-9]", "")
            local n = tonumber(addFarmItemBuf)
            if n and n > 0 then c.default_item_id = math.floor(n); HV.saveData() end
        end
        ImGui.EndTable()
    end
    uiGap(4)

    local act = uiActionBar("BorenHarvestActs", w, {
        { label = "+ Tambah##hv_add", style = "accent" },
        { label = "World Ini##hv_cur" },
        { label = "Paste List##hv_pst" },
        { label = "Copy List##hv_cpy" },
        { label = "Hapus##hv_del",    style = "muted" },
    })

    if act == 1 then
        local rawW = trimStr(addFarmWorldBuf)
        local p = nil
        if rawW ~= "" then
            local norm = rawW:gsub("|", ":")
            local colons = 0
            for _ in norm:gmatch(":") do colons = colons + 1 end
            if colons >= 2 then
                p = parseFarmRow(norm)
            else
                local wPart, dPart = norm:match("^([^:]+):(.*)$")
                local wName = trimStr(wPart or norm):upper()
                local dId   = trimStr(dPart or ""):upper()
                local iid   = math.floor(tonumber(addFarmItemBuf) or tonumber(c.default_item_id) or 4584)
                if iid <= 0 then iid = 4584 end
                if wName ~= "" then p = { name = wName, door = dId, item_id = iid, status = "Ready" } end
            end
        end
        if p then
            table.insert(st.rows, p); addFarmWorldBuf = ""; HV.saveData()
            uiNotice = "Tersimpan: " .. p.name .. " (ID " .. tostring(p.item_id) .. ")"
        else uiNotice = "Isi World:DoorID dulu!" end

    elseif act == 2 then
        runAsync(function()
            local curW = getCurrentWorldSafe()
            if curW ~= "" and curW ~= "EXIT" then
                local iid = math.floor(tonumber(addFarmItemBuf) or tonumber(c.default_item_id) or 4584)
                table.insert(st.rows, { name = curW, door = "", item_id = iid, status = "Ready" })
                HV.saveData(); uiNotice = "World aktif ditambah: " .. curW
            else uiNotice = "Masuk ke world dulu!" end
        end)

    elseif act == 3 then
        local added = 0
        for _, line in ipairs(readClipLines()) do
            local p = parseFarmRow(line)
            if p then table.insert(st.rows, p); added = added + 1 end
        end
        if added > 0 then HV.saveData() end
        uiNotice = "Paste berhasil: +" .. tostring(added) .. " world."

    elseif act == 4 then
        if ImGui and ImGui.SetClipboardText then
            local out = {}
            for _, r in ipairs(st.rows) do
                table.insert(out, string.format("%s:%s:%d", r.name, r.door or "", r.item_id or c.default_item_id))
            end
            pcall(ImGui.SetClipboardText, table.concat(out, "\n"))
            uiNotice = "Disalin " .. tostring(#out) .. " world ke clipboard."
        end

    elseif act == 5 then
        if st.selected_idx > 0 and st.rows[st.selected_idx] then
            table.remove(st.rows, st.selected_idx); st.selected_idx = 0; HV.saveData()
            uiNotice = "World terpilih dihapus."
        else
            uiNotice = "Pilih baris world di tabel dulu!"
        end
    end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 2: SAVE WORLD (LIST TABEL BLOCK & SEED + LIMIT CUSTOM)
-- ----------------------------------------------------------------------------
local function renderSaveSub()
    local c, st = HV.CFG, HV.STATE
    local w = availX()

    uiSection("Daftar Save World Block & Seed (" .. tostring(#st.save_rows) .. ")", true)
    uiNote(uiNotice)

    if ImGui.BeginTable("BorenHarvestSaveTbl", 5) then
        ImGui.TableSetupColumn("World")
        ImGui.TableSetupColumn("Door")
        ImGui.TableSetupColumn("Tipe")
        ImGui.TableSetupColumn("Limit (Isi)")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #st.save_rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text("ALL")
            ImGui.TableSetColumnIndex(3); ImGui.Text("20.000")
            ImGui.TableSetColumnIndex(4); ImGui.Text("Tambah di bawah")
        else
            for i, r in ipairs(st.save_rows) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (st.selected_save == i)
                if autoBtn((sel and "> " or "") .. tostring(r.name) .. "##hvsr" .. tostring(i)) then
                    st.selected_save = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text((r.door and r.door ~= "") and r.door or "-")
                ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(r.save_type or "ALL"))
                local limStr = (r.limit == 0) and "Unli" or string.format("%d (%d)", r.limit, r.count or 0)
                ImGui.TableSetColumnIndex(3); ImGui.Text(limStr)
                ImGui.TableSetColumnIndex(4); ImGui.Text(tostring(r.status or "Ready"))
            end
        end
        ImGui.EndTable()
    end

    uiSectionWithKetik("Tambah Save World Baru", "hv_ktk_sw", function()
        local wPre, dPre = tostring(addSaveWorldBuf or ""):gsub("|", ":"):match("^([^:]+):(.*)$")
        if not wPre then wPre = tostring(addSaveWorldBuf or ""); dPre = "" end
        uiOpenDialog("boren_in_hv_sw", "Tambah Save World", {
            { id = "f_world", label = "World Save", default = wPre, maxLen = 32 },
            { id = "f_door",  label = "Door ID (opsional)", default = dPre, maxLen = 32 },
            { id = "f_type",  label = "Tipe: ALL / BLOCK / SEED", default = addSaveTypeBuf, maxLen = 8 },
            { id = "f_lim",   label = "Limit Item (0 = Unlimited)", default = addSaveLimitBuf, maxLen = 16 },
        }, "Tambah & Simpan", function(vals)
            local wn = trimStr(vals.f_world or ""):upper()
            local dn = trimStr(vals.f_door or ""):upper()
            local stype = trimStr(vals.f_type or "ALL"):upper()
            if stype ~= "BLOCK" and stype ~= "SEED" then stype = "ALL" end
            local lim = math.floor(tonumber(vals.f_lim) or tonumber(c.default_save_limit) or 20000)
            if lim < 0 then lim = 0 end
            addSaveTypeBuf = stype
            addSaveLimitBuf = tostring(lim)
            if wn ~= "" then
                table.insert(st.save_rows, { name = wn, door = dn, save_type = stype, limit = lim, count = 0, status = "Ready" })
                addSaveWorldBuf = ""; HV.saveData()
                uiNotice = "Tersimpan Save: " .. wn .. " (" .. stype .. ")"
            end
        end)
    end)

    if ImGui.BeginTable("BorenHarvestAddSwTbl", 2) then
        ImGui.TableSetupColumn("World:DoorID")
        ImGui.TableSetupColumn("Pilihan Tipe Simpan")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(120, math.floor(w * 0.48)))
        local chW, nvW = safeInput("##hv_add_sw", addSaveWorldBuf, 256)
        ImGui.PopItemWidth()
        if chW then addSaveWorldBuf = nvW end

        ImGui.TableSetColumnIndex(1)
        if autoBtn((addSaveTypeBuf == "ALL" and "[ Gabung ]" or "Gabung") .. "##sw_t_all") then addSaveTypeBuf = "ALL" end
        ImGui.SameLine()
        if autoBtn((addSaveTypeBuf == "BLOCK" and "[ Block ]" or "Block") .. "##sw_t_blk") then addSaveTypeBuf = "BLOCK" end
        ImGui.SameLine()
        if autoBtn((addSaveTypeBuf == "SEED" and "[ Seed ]" or "Seed") .. "##sw_t_sd") then addSaveTypeBuf = "SEED" end
        ImGui.EndTable()
    end

    uiGap(2)
    ImGui.Text("Limit per World:")
    ImGui.SameLine()
    ImGui.PushItemWidth(math.max(70, math.floor(w * 0.22)))
    local chLim, nvLim = safeInput("##hv_sw_lim_in", addSaveLimitBuf, 16)
    ImGui.PopItemWidth()
    if chLim then addSaveLimitBuf = nvLim:gsub("[^0-9]", "") end
    ImGui.SameLine()
    if autoBtn("10k##sw_10") then addSaveLimitBuf = "10000" end
    ImGui.SameLine()
    if autoBtn("20k##sw_20") then addSaveLimitBuf = "20000" end
    ImGui.SameLine()
    if autoBtn("50k##sw_50") then addSaveLimitBuf = "50000" end
    ImGui.SameLine()
    if autoBtn("Unli##sw_unl") then addSaveLimitBuf = "0" end

    uiGap(4)
    local act = uiActionBar("BorenHarvestSaveActs", w, {
        { label = "+ Tambah##sw_add", style = "accent" },
        { label = "World Ini##sw_cur" },
        { label = "Paste List##sw_pst" },
        { label = "Reset Penuh##sw_rst_all" },
        { label = "Hapus##sw_del",    style = "muted" },
    })

    if act == 1 then
        local rawW = trimStr(addSaveWorldBuf)
        local p = nil
        if rawW ~= "" then
            local norm = rawW:gsub("|", ":")
            local colons = 0
            for _ in norm:gmatch(":") do colons = colons + 1 end
            if colons >= 2 then
                p = parseSaveRow(norm)
            else
                local wPart, dPart = norm:match("^([^:]+):(.*)$")
                local wName = trimStr(wPart or norm):upper()
                local dId   = trimStr(dPart or ""):upper()
                local lim   = math.floor(tonumber(addSaveLimitBuf) or 20000)
                if lim < 0 then lim = 0 end
                if wName ~= "" then p = { name = wName, door = dId, save_type = addSaveTypeBuf, limit = lim, count = 0, status = "Ready" } end
            end
        end
        if p then
            table.insert(st.save_rows, p); addSaveWorldBuf = ""; HV.saveData()
            uiNotice = "Tersimpan Save: " .. p.name .. " (" .. p.save_type .. " - " .. p.limit .. ")"
        else uiNotice = "Isi World:DoorID dulu!" end

    elseif act == 2 then
        runAsync(function()
            local curW = getCurrentWorldSafe()
            if curW ~= "" and curW ~= "EXIT" then
                local lim = math.floor(tonumber(addSaveLimitBuf) or 20000)
                table.insert(st.save_rows, { name = curW, door = "", save_type = addSaveTypeBuf, limit = lim, count = 0, status = "Ready" })
                HV.saveData(); uiNotice = "World aktif ditambah: " .. curW
            else uiNotice = "Masuk ke world dulu!" end
        end)

    elseif act == 3 then
        local added = 0
        local defLim = math.floor(tonumber(addSaveLimitBuf) or 20000)
        for _, line in ipairs(readClipLines()) do
            local p = parseSaveRow(line)
            if not p then
                local p2 = parseWorldDoor(line)
                if p2 then p = { name = p2.name, door = p2.door, save_type = addSaveTypeBuf, limit = defLim, count = 0, status = "Ready" } end
            end
            if p then table.insert(st.save_rows, p); added = added + 1 end
        end
        if added > 0 then HV.saveData() end
        uiNotice = "Paste berhasil: +" .. tostring(added) .. " save world."

    elseif act == 4 then
        for _, r in ipairs(st.save_rows) do r.status = "Ready" end
        HV.saveData(); uiNotice = "Status semua save world di-reset ke Ready."

    elseif act == 5 then
        if st.selected_save > 0 and st.save_rows[st.selected_save] then
            table.remove(st.save_rows, st.selected_save); st.selected_save = 0; HV.saveData()
            uiNotice = "Save world terpilih dihapus."
        else uiNotice = "Pilih baris save world di tabel dulu!" end
    end

    uiGap(4)
    uiSection("Pengaturan Drop Tas (Default: 200 Block)")
    ImGui.Text("Drop saat tas penuh    : >= " .. tostring(c.drop_threshold or 200) .. " block")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_dt1") then c.drop_threshold = math.max(20, (c.drop_threshold or 200) - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_dt2") then c.drop_threshold = math.min(200, (c.drop_threshold or 200) + 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" Default 200 ##hv_dt_def") then c.drop_threshold = 200; HV.saveData() end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 3: EVENT SAVE (LIST TABEL EVENT + LIMIT TOTAL)
-- ----------------------------------------------------------------------------
local function renderEventSub()
    local c, st = HV.CFG, HV.STATE
    local w = availX()

    uiSection("Daftar World Save Event & Mooncake (" .. tostring(#st.event_rows) .. ")", true)
    uiNote(uiNotice)

    if ImGui.BeginTable("BorenHarvestEventTbl", 4) then
        ImGui.TableSetupColumn("World")
        ImGui.TableSetupColumn("Door")
        ImGui.TableSetupColumn("Limit Total (Isi)")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #st.event_rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text("10.000")
            ImGui.TableSetColumnIndex(3); ImGui.Text("Tambah di bawah")
        else
            for i, r in ipairs(st.event_rows) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (st.selected_ev == i)
                if autoBtn((sel and "> " or "") .. tostring(r.name) .. "##hver" .. tostring(i)) then
                    st.selected_ev = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text((r.door and r.door ~= "") and r.door or "-")
                local limStr = (r.limit == 0) and "Unli" or string.format("%d (%d)", r.limit, r.count or 0)
                ImGui.TableSetColumnIndex(2); ImGui.Text(limStr)
                ImGui.TableSetColumnIndex(3); ImGui.Text(tostring(r.status or "Ready"))
            end
        end
        ImGui.EndTable()
    end

    uiSectionWithKetik("Tambah Event World Baru", "hv_ktk_ew", function()
        local wPre, dPre = tostring(addEventWorldBuf or ""):gsub("|", ":"):match("^([^:]+):(.*)$")
        if not wPre then wPre = tostring(addEventWorldBuf or ""); dPre = "" end
        uiOpenDialog("boren_in_hv_ew", "Tambah World Event", {
            { id = "f_world", label = "World Event", default = wPre, maxLen = 32 },
            { id = "f_door",  label = "Door ID (opsional)", default = dPre, maxLen = 32 },
            { id = "f_lim",   label = "Limit Total Item (0 = Unlimited)", default = addEventLimitBuf, maxLen = 16 },
        }, "Tambah & Simpan", function(vals)
            local wn = trimStr(vals.f_world or ""):upper()
            local dn = trimStr(vals.f_door or ""):upper()
            local lim = math.floor(tonumber(vals.f_lim) or tonumber(c.default_ev_limit) or 10000)
            if lim < 0 then lim = 0 end
            addEventLimitBuf = tostring(lim)
            if wn ~= "" then
                table.insert(st.event_rows, { name = wn, door = dn, limit = lim, count = 0, status = "Ready" })
                addEventWorldBuf = ""; HV.saveData()
                uiNotice = "Tersimpan Event: " .. wn
            end
        end)
    end)

    if ImGui.BeginTable("BorenHarvestAddEwTbl", 2) then
        ImGui.TableSetupColumn("World:DoorID")
        ImGui.TableSetupColumn("Limit Total Item")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(120, math.floor(w * 0.52)))
        local chW, nvW = safeInput("##hv_add_ew", addEventWorldBuf, 256)
        ImGui.PopItemWidth()
        if chW then addEventWorldBuf = nvW end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(70, math.floor(w * 0.24)))
        local chLim, nvLim = safeInput("##hv_ew_lim_in", addEventLimitBuf, 16)
        ImGui.PopItemWidth()
        if chLim then addEventLimitBuf = nvLim:gsub("[^0-9]", "") end
        ImGui.EndTable()
    end

    uiGap(2)
    ImGui.Text("Preset Limit Event:")
    ImGui.SameLine()
    if autoBtn("5k##ew_5") then addEventLimitBuf = "5000" end
    ImGui.SameLine()
    if autoBtn("10k##ew_10") then addEventLimitBuf = "10000" end
    ImGui.SameLine()
    if autoBtn("20k##ew_20") then addEventLimitBuf = "20000" end
    ImGui.SameLine()
    if autoBtn("Unli##ew_unl") then addEventLimitBuf = "0" end

    uiGap(4)
    local act = uiActionBar("BorenHarvestEventActs", w, {
        { label = "+ Tambah##ew_add", style = "accent" },
        { label = "World Ini##ew_cur" },
        { label = "Paste List##ew_pst" },
        { label = "Reset Penuh##ew_rst_all" },
        { label = "Hapus##ew_del",    style = "muted" },
    })

    if act == 1 then
        local rawW = trimStr(addEventWorldBuf)
        local p = nil
        if rawW ~= "" then
            local norm = rawW:gsub("|", ":")
            local colons = 0
            for _ in norm:gmatch(":") do colons = colons + 1 end
            if colons >= 2 then
                p = parseEventRow(norm)
            else
                local wPart, dPart = norm:match("^([^:]+):(.*)$")
                local wName = trimStr(wPart or norm):upper()
                local dId   = trimStr(dPart or ""):upper()
                local lim   = math.floor(tonumber(addEventLimitBuf) or 10000)
                if lim < 0 then lim = 0 end
                if wName ~= "" then p = { name = wName, door = dId, limit = lim, count = 0, status = "Ready" } end
            end
        end
        if p then
            table.insert(st.event_rows, p); addEventWorldBuf = ""; HV.saveData()
            uiNotice = "Tersimpan Event: " .. p.name .. " (Limit " .. p.limit .. ")"
        else uiNotice = "Isi World:DoorID dulu!" end

    elseif act == 2 then
        runAsync(function()
            local curW = getCurrentWorldSafe()
            if curW ~= "" and curW ~= "EXIT" then
                local lim = math.floor(tonumber(addEventLimitBuf) or 10000)
                table.insert(st.event_rows, { name = curW, door = "", limit = lim, count = 0, status = "Ready" })
                HV.saveData(); uiNotice = "Event world ditambah: " .. curW
            else uiNotice = "Masuk ke world dulu!" end
        end)

    elseif act == 3 then
        local added = 0
        local defLim = math.floor(tonumber(addEventLimitBuf) or 10000)
        for _, line in ipairs(readClipLines()) do
            local p = parseEventRow(line)
            if not p then
                local p2 = parseWorldDoor(line)
                if p2 then p = { name = p2.name, door = p2.door, limit = defLim, count = 0, status = "Ready" } end
            end
            if p then table.insert(st.event_rows, p); added = added + 1 end
        end
        if added > 0 then HV.saveData() end
        uiNotice = "Paste berhasil: +" .. tostring(added) .. " event world."

    elseif act == 4 then
        for _, r in ipairs(st.event_rows) do r.status = "Ready" end
        HV.saveData(); uiNotice = "Status semua world event di-reset ke Ready."

    elseif act == 5 then
        if st.selected_ev > 0 and st.event_rows[st.selected_ev] then
            table.remove(st.event_rows, st.selected_ev); st.selected_ev = 0; HV.saveData()
            uiNotice = "Event world terpilih dihapus."
        else uiNotice = "Pilih baris event world di tabel dulu!" end
    end

    uiGap(4)
    uiSection("Daftar ID Item Event (Disimpan ke World Event)")
    ImGui.PushItemWidth(math.max(160, math.floor(w * 0.96)))
    local chEI, vEI = safeInput("##hv_ei", c.event_ids_raw, 512)
    ImGui.PopItemWidth()
    if chEI then c.event_ids_raw = vEI; HV.saveData() end

    uiGap(2)
    ImGui.Text("Preset :")
    ImGui.SameLine()
    if autoBtn(" Mooncake (1058,1094,1096,1098,1828) ##hv_pmc") then
        c.event_ids_raw = "1058,1094,1096,1098,1828"
        HV.saveData(); uiNotice = "Preset Mooncake diterapkan."
    end
    ImGui.SameLine()
    if autoBtn(" Kosongkan ID ##hv_ceid") then
        c.event_ids_raw = ""; HV.saveData(); uiNotice = "List ID event dikosongkan."
    end

    uiGap(3)
    ImGui.Text("Drop Event saat tas    : >= " .. tostring(c.event_threshold) .. " item")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_et1") then c.event_threshold = math.max(10, c.event_threshold - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_et2") then c.event_threshold = math.min(200, c.event_threshold + 20); HV.saveData() end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 4: GEAR & FUEL (TERPADU + LIST ID EQUIP ALAT)
-- ----------------------------------------------------------------------------
local function renderGearSub()
    local c = HV.CFG
    local w = availX()

    uiSection("Gudang Alat & Fuel (Gear World)", true)
    uiNote(uiNotice)

    uiSectionWithKetik("World Penyimpanan Alat & Fuel (WORLD:DOOR)", "hv_ktk_gw", function()
        uiOpenDialog("boren_in_hv_gw", "Setting Gear World", {
            { id = "gw", label = "Gear World (WORLD:DOOR)", default = c.gear_world, maxLen = 64 },
            { id = "eq", label = "List ID Equip Alat (pisah koma)", default = c.gear_equip_ids, maxLen = 64 },
            { id = "fa", label = "Target Ambil Fuel Pack", default = tostring(c.fuel_target_amt), maxLen = 8 },
        }, "Simpan", function(v)
            c.gear_world = trimStr(v.gw or "")
            c.gear_equip_ids = trimStr(v.eq or "6840, 1966")
            local n = tonumber(v.fa); if n and n >= 1 then c.fuel_target_amt = math.min(200, math.floor(n)) end
            HV.saveData(); uiNotice = "Gear World berhasil disimpan."
        end)
    end)

    ImGui.PushItemWidth(math.max(160, math.floor(w * 0.72)))
    local chGW, vGW = safeInput("##hv_gw", c.gear_world, 128)
    ImGui.PopItemWidth()
    if chGW then c.gear_world = vGW; HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" World Ini ##hv_gwc") then
        runAsync(function()
            local cw = getCurrentWorldSafe()
            if cw ~= "" and cw ~= "EXIT" then
                c.gear_world = cw .. ":"; HV.saveData(); uiNotice = "Gear World diset ke: " .. cw
            else uiNotice = "Masuk ke world dulu!" end
        end)
    end

    uiGap(4)
    uiSection("Auto Restock Magni & Fuel Pack")

    ImGui.Text("Ambil Magni (1252) & Fuel Pack (1746) :"); ImGui.SameLine()
    if uiToggleBtn(c.auto_magni_fuel, "hv_amf") then
        c.auto_magni_fuel = not c.auto_magni_fuel; HV.saveData()
    end

    if c.auto_magni_fuel then
        uiGap(2)
        ImGui.Text("Target Stok Fuel Pack di Tas          : " .. tostring(c.fuel_target_amt) .. " pack")
        ImGui.SameLine()
        if autoBtn(" -25 ##hv_fa1") then c.fuel_target_amt = math.max(25, c.fuel_target_amt - 25); HV.saveData() end
        ImGui.SameLine()
        if autoBtn(" +25 ##hv_fa2") then c.fuel_target_amt = math.min(200, c.fuel_target_amt + 25); HV.saveData() end

        uiGap(2)
        ImGui.Text("Fuel Guard: Stop Bot jika Fuel Habis  :"); ImGui.SameLine()
        if uiToggleBtn(c.stop_if_no_fuel, "hv_stpf") then
            c.stop_if_no_fuel = not c.stop_if_no_fuel; HV.saveData()
        end
    end

    uiGap(4)
    uiSection("Daftar ID Alat untuk Di-equip (Hand / Back)")
    ImGui.Text("List ID Item Equip (DCS, Harvester, dll. pisah koma):")
    ImGui.PushItemWidth(math.max(160, math.floor(w * 0.96)))
    local chEq, vEq = safeInput("##hv_eq_ids", c.gear_equip_ids, 256)
    ImGui.PopItemWidth()
    if chEq then c.gear_equip_ids = vEq; HV.saveData() end

    uiGap(2)
    ImGui.Text("Preset Cepat :")
    ImGui.SameLine()
    if autoBtn(" DCS + Sorrows (6840, 1966) ##eq_p1") then
        c.gear_equip_ids = "6840, 1966"; HV.saveData(); uiNotice = "Preset DCS + Sorrows diterapkan."
    end
    ImGui.SameLine()
    if autoBtn(" DCS + Normal (6840, 1830) ##eq_p2") then
        c.gear_equip_ids = "6840, 1830"; HV.saveData(); uiNotice = "Preset DCS + Normal diterapkan."
    end
    ImGui.SameLine()
    if autoBtn(" Sorrows Saja (1966) ##eq_p3") then
        c.gear_equip_ids = "1966"; HV.saveData(); uiNotice = "Preset Sorrows saja diterapkan."
    end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 5: SETTINGS
-- ----------------------------------------------------------------------------
local function renderSettingsSub()
    local c = HV.CFG

    uiSection("Pengaturan Navigasi & Collect", true)

    ImGui.Text("Ignore Gems (ID 112)       :"); ImGui.SameLine()
    if uiToggleBtn(c.ignore_gems, "hv_ig") then c.ignore_gems = not c.ignore_gems; HV.saveData() end

    uiGap(2)
    ImGui.Text("Auto Collect Block/Seed    :"); ImGui.SameLine()
    if uiToggleBtn(c.auto_collect, "hv_ac") then c.auto_collect = not c.auto_collect; HV.saveData() end

    uiGap(2)
    ImGui.Text("Take Floating (Sapu Sisa)  :"); ImGui.SameLine()
    if uiToggleBtn(c.take_floating, "hv_tf") then c.take_floating = not c.take_floating; HV.saveData() end

    uiGap(2)
    ImGui.Text("Mode Traversal             :"); ImGui.SameLine()
    if uiToggleBtn(c.harvest_mode == "3zigzag", "hv_md", "3-ZIGZAG", "1-BY-1") then
        c.harvest_mode = (c.harvest_mode == "3zigzag") and "1by1" or "3zigzag"; HV.saveData()
    end

    uiGap(2)
    ImGui.Text("ModFly (Tembus Rintangan)  :"); ImGui.SameLine()
    if uiToggleBtn(c.use_modfly, "hv_mf") then c.use_modfly = not c.use_modfly; HV.saveData() end

    uiGap(4)
    uiSection("Pacing Delay Riil (Milidetik)")

    ImGui.Text("Delay Harvest              : " .. tostring(c.harvest_delay) .. " ms")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_hd1") then c.harvest_delay = math.max(90, c.harvest_delay - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_hd2") then c.harvest_delay = math.min(500, c.harvest_delay + 20); HV.saveData() end

    uiGap(2)
    ImGui.Text("Delay Langkah Bot          : " .. tostring(c.step_delay) .. " ms")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_sd1") then c.step_delay = math.max(50, c.step_delay - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_sd2") then c.step_delay = math.min(400, c.step_delay + 20); HV.saveData() end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 6: LOGS
-- ----------------------------------------------------------------------------
local function renderLogsSub()
    local st = HV.STATE
    local w = availX()

    uiSection("Live Preview Tas & Log Panen", true)
    ImGui.Text(string.format("Tas Saat Ini -> Block: %d | Seed: %d | Event: %d | Fuel: %d",
        st.inv_preview.block, st.inv_preview.seed, st.inv_preview.ev, st.inv_preview.fuel))

    uiGap(3)
    if autoBtn(" Bersihkan Log ##hv_clg") then st.logs = {} end
    ImGui.Separator()

    for i = 1, math.min(14, #st.logs) do
        if ImGui.TextWrapped then ImGui.TextWrapped(st.logs[i]) else ImGui.Text(st.logs[i]) end
    end
end


local function renderHarvestBody()
    local w = availX()
    local tabs = {
        { "farms", "Farm List" },
        { "save",  "Save World" },
        { "event", "Event Save" },
        { "gear",  "Gear & Fuel" },
        { "set",   "Settings" },
        { "logs",  "Logs" },
    }
    for i, tb in ipairs(tabs) do
        if i > 1 then ImGui.SameLine() end
        if uiTabBtn(tb[2], activeSub == tb[1]) then activeSub = tb[1] end
    end
    ImGui.Separator()
    if activeSub == "farms" then renderFarmsSub()
    elseif activeSub == "save" then renderSaveSub()
    elseif activeSub == "event" then renderEventSub()
    elseif activeSub == "gear" then renderGearSub()
    elseif activeSub == "set" then renderSettingsSub()
    else renderLogsSub() end
end

-- ============================================================================
-- 8. STANDALONE DEAR IMGUI WINDOW
-- ============================================================================
function onDrawImGui()
    if not HV.STATE.show_ui then return end
    if not ImGui or not ImGui.Begin then return end
    pcall(function()
        local winFlags = 2048 -- ImGuiWindowFlags_HorizontalScrollbar
        if ImGui.WindowFlags and ImGui.WindowFlags.HorizontalScrollbar then
            winFlags = tonumber(ImGui.WindowFlags.HorizontalScrollbar) or 2048
        end
        local MIN_CONTENT_W = 680
        if ImGui.SetNextWindowContentSize and ImVec2 then
            pcall(ImGui.SetNextWindowContentSize, ImVec2(MIN_CONTENT_W, 0))
        end
        local okCall, opened = pcall(ImGui.Begin, "BOREN STORE - AUTO HARVEST PRO v" .. HV.VERSION, true, winFlags)
        if not okCall or opened == nil then
            okCall, opened = pcall(ImGui.Begin, "BOREN STORE - AUTO HARVEST PRO v" .. HV.VERSION, winFlags)
        end
        if not okCall or opened == nil then
            okCall, opened = pcall(ImGui.Begin, "BOREN STORE - AUTO HARVEST PRO v" .. HV.VERSION)
        end
        if opened then
            if ImGui.Dummy and ImVec2 then pcall(ImGui.Dummy, ImVec2(MIN_CONTENT_W, 0.1)) end
            renderHarvestBody()
            ImGui.End()
        end
    end)
end
OnDrawImGui = onDrawImGui

-- ============================================================================
-- 9. NATIVE GROWLAUNCHER MULTI-TAB MENU & ONVALUE HANDLER
-- ============================================================================
local function createNativeUI(subName, icon)
    if UserInterface and UserInterface.new then
        local ok, ui = pcall(UserInterface.new, subName, icon or "PlayArrow")
        if ok and ui then return ui end
    end
    local dummy = { items = {} }
    function dummy:addLabelApp(t, ic) table.insert(self.items, string.format('{"type":"labelapp","text":"%s","icon":"%s"}', t, ic or "Storefront")) end
    function dummy:addButton(t, al) table.insert(self.items, string.format('{"type":"button","text":"%s","alias":"%s"}', t, al)) end
    function dummy:addToggleButton(t, d, al) table.insert(self.items, string.format('{"type":"toggle_button","text":"%s","default":%s,"alias":"%s"}', t, d and "true" or "false", al)) end
    function dummy:addToggle(t, d, al, ov) table.insert(self.items, string.format('{"type":"toggle","text":"%s","default":%s,"alias":"%s"}', t, d and "true" or "false", al)) end
    function dummy:addDivider() table.insert(self.items, '{"type":"divider"}') end
    function dummy:addLabel(t) table.insert(self.items, string.format('{"type":"label","text":"%s"}', t)) end
    function dummy:addInputString(t, v, l, h, ic, al) table.insert(self.items, string.format('{"type":"input_string","text":"%s","value":"%s","label":"%s","hint":"%s","icon":"%s","alias":"%s"}', t, v or "", l or "", h or "", ic or "Public", al)) end
    function dummy:addInputInt(t, v, l, h, ic, al) table.insert(self.items, string.format('{"type":"input_int","text":"%s","value":"%s","label":"%s","hint":"%s","icon":"%s","alias":"%s"}', t, tostring(v or "0"), l or "", h or "", ic or "FormatListNumbered", al)) end
    function dummy:addSlider(t, mn, mx, v, stp, f, al) table.insert(self.items, string.format('{"type":"slider","text":"%s","min":%d,"max":%d,"value":%d,"step":%d,"alias":"%s"}', t, mn, mx, v, stp or 1, al)) end
    function dummy:addDisplayList(t, s, al) table.insert(self.items, string.format('{"type":"display_list","text":"%s","style":"%s","alias":"%s"}', t, s or "Default", al)) end
    function dummy:generateJSON() return string.format('{"sub_name":"%s","icon":"%s","menu":[%s]}', subName, icon or "PlayArrow", table.concat(self.items, ",")) end
    return dummy
end

local function registerNativeHarvestUI()
    if not addCategory or not addIntoModule then return end

    -- TAB 1: START & FARM
    local uiFarm = createNativeUI("1. Start & Farm", "PlayArrow")
    uiFarm:addLabelApp("Boren Store - Auto Harvest v" .. HV.VERSION, "Storefront")
    uiFarm:addButton("▶ START HARVEST BOT", "hv_btn_start")
    uiFarm:addButton("■ STOP HARVEST BOT", "hv_btn_stop")
    uiFarm:addToggleButton("▶ START / ■ STOP TOGGLE", HV.STATE.running, "hv_run_power")
    uiFarm:addToggle("Tampilkan Panel ImGui", HV.STATE.show_ui, "hv_show_ui", false)
    uiFarm:addDivider()
    uiFarm:addLabel("Tambah Antrean World Farm:")
    uiFarm:addInputString("Nama World Farm", HV.STATE.input_add_world, "World", "FARMWORLD", "Public", "hv_manual_world_input")
    uiFarm:addInputString("Door ID (Opsional)", HV.STATE.input_add_door, "Door ID", "Kosong = White Door", "DoorFront", "hv_manual_door_input")
    uiFarm:addInputInt("Block / Seed ID", tostring(HV.STATE.input_add_id or HV.CFG.default_item_id), "Item ID", "4584", "Category", "hv_manual_item_input")
    uiFarm:addButton("➕ Tambah Farm ke Antrean", "hv_btn_add_farm")
    uiFarm:addButton("📍 Tambah World Sekarang", "hv_btn_add_cur_farm")
    uiFarm:addButton("🔄 Reset Status Antrean (Ready)", "hv_btn_reset_status")
    uiFarm:addButton("🗑️ Kosongkan Antrean Farm", "hv_btn_clear_farms")

    -- TAB 2: SAVE & LIMIT
    local uiSave = createNativeUI("2. Save & Limit", "Archive")
    uiSave:addLabelApp("Multi-World Save Table & Limit Drop", "Archive")
    uiSave:addLabel("Tambah World Save Baru:")
    uiSave:addInputString("Nama World Save", HV.STATE.input_save_w, "World", "SAVEBLOCK1", "CloudUpload", "hv_input_save_w")
    uiSave:addInputString("Door ID (Opsional)", HV.STATE.input_save_d, "Door ID", "Kosong = Door Utama", "DoorFront", "hv_input_save_d")
    uiSave:addInputInt("Limit Item World Ini (0 = Unlimited)", tostring(HV.STATE.input_save_lim or HV.CFG.default_save_limit), "Limit", "20000", "FormatListNumbered", "hv_input_save_lim")
    uiSave:addLabel("Tipe Simpan: " .. tostring(HV.STATE.input_save_type or "ALL"))
    uiSave:addButton("Tipe: ALL (Block + Seed)", "hv_btn_stype_all")
    uiSave:addButton("Tipe: BLOCK Saja", "hv_btn_stype_block")
    uiSave:addButton("Tipe: SEED Saja", "hv_btn_stype_seed")
    uiSave:addButton("➕ Tambah World Save ke List", "hv_btn_add_save")
    uiSave:addButton("📍 Tambah World Sekarang (Save)", "hv_btn_add_cur_save")
    uiSave:addButton("🔄 Reset Penanda Penuh (Ready)", "hv_btn_reset_save_status")
    uiSave:addButton("🗑️ Kosongkan List Save World", "hv_btn_clear_save")
    uiSave:addDivider()
    uiSave:addLabel("Pengaturan Drop Tas (Default 200 Block):")
    uiSave:addSlider("Threshold Drop Tas", 50, 200, HV.CFG.drop_threshold or 200, 10, false, "hv_slider_drop_threshold")

    -- TAB 3: EVENT & MOONCAKE
    local uiEvent = createNativeUI("3. Event & Mooncake", "Celebration")
    uiEvent:addLabelApp("Save Khusus Event & Mooncake", "Celebration")
    uiEvent:addLabel("Tambah World Save Event:")
    uiEvent:addInputString("Nama World Event", HV.STATE.input_ev_w, "World", "WORLDEVENT1", "Event", "hv_input_ev_w")
    uiEvent:addInputString("Door ID (Opsional)", HV.STATE.input_ev_d, "Door ID", "Kosong = Door Utama", "DoorFront", "hv_input_ev_d")
    uiEvent:addInputInt("Limit Total Item Event (0 = Unli)", tostring(HV.STATE.input_ev_lim or HV.CFG.default_ev_limit), "Limit", "10000", "FormatListNumbered", "hv_input_ev_lim")
    uiEvent:addButton("➕ Tambah World Event ke List", "hv_btn_add_ev")
    uiEvent:addButton("📍 Tambah World Sekarang (Event)", "hv_btn_add_cur_ev")
    uiEvent:addButton("🔄 Reset Penanda Event Penuh", "hv_btn_reset_ev_status")
    uiEvent:addButton("🗑️ Kosongkan List Event World", "hv_btn_clear_ev")
    uiEvent:addDivider()
    uiEvent:addLabel("List ID Item Event (Selain Block & Seed):")
    uiEvent:addInputString("ID Item Event (Koma)", HV.CFG.event_ids_raw or "", "Event IDs", "1058,1094,1096,1098,1828", "Stars", "hv_input_event_ids")
    uiEvent:addButton("🌕 Preset Mooncake (5 Jenis)", "hv_btn_preset_mooncake")
    uiEvent:addSlider("Threshold Drop Event", 20, 200, HV.CFG.event_threshold or 150, 10, false, "hv_slider_event_threshold")

    -- TAB 4: GEAR & FUEL
    local uiGear = createNativeUI("4. Gear & Fuel", "Build")
    uiGear:addLabelApp("Gear World, Restock & Equip", "Build")
    uiGear:addLabel("World Ambil Alat & Fuel Pack:")
    uiGear:addInputString("Gear World (WORLD:DOOR)", HV.CFG.gear_world or "", "Gear World", "GEARWORLD:DOOR", "Home", "hv_input_gear_world")
    uiGear:addButton("📍 Pakai World Sekarang (Gear)", "hv_btn_add_cur_gear")
    uiGear:addDivider()
    uiGear:addLabel("Auto Restock Magni (1252) + Fuel Pack (1746):")
    uiGear:addToggle("Ambil Magni & Fuel Pack Otomatis", HV.CFG.auto_magni_fuel == true, "hv_toggle_magni_fuel", false)
    uiGear:addToggle("Stop Bot Jika Fuel Habis (Proteksi)", HV.CFG.stop_if_no_fuel ~= false, "hv_toggle_stop_no_fuel", false)
    uiGear:addSlider("Target Stok Fuel Pack di Tas", 25, 200, HV.CFG.fuel_target_amt or 100, 25, false, "hv_slider_fuel_target")
    uiGear:addDivider()
    uiGear:addLabel("List ID Gear yang Dipakai (Auto-Equip):")
    uiGear:addInputString("ID Gear (Koma)", HV.CFG.gear_equip_ids or "6840, 1966", "Gear IDs", "6840, 1966", "Settings", "hv_input_gear_equip_ids")
    uiGear:addButton("⚙️ Preset: DCS (6840) + Harvester (1966)", "hv_btn_gear_preset_both")
    uiGear:addButton("🚜 Preset: Harvester Saja (1966)", "hv_btn_gear_preset_harv")
    uiGear:addButton("⚡ Preset: DCS Saja (6840)", "hv_btn_gear_preset_dcs")

    -- TAB 5: PENGATURAN & DELAY
    local uiSet = createNativeUI("5. Pengaturan & Delay", "Tune")
    uiSet:addLabelApp("Pengaturan Navigasi & Kecepatan", "Tune")
    uiSet:addToggle("Abaikan Gems (Anti Penuh Tas)", HV.CFG.ignore_gems ~= false, "hv_toggle_ignore_gems", false)
    uiSet:addToggle("Auto Collect Block & Seed", HV.CFG.auto_collect ~= false, "hv_toggle_auto_collect", false)
    uiSet:addToggle("Ambil Floating Item Sisa", HV.CFG.take_floating ~= false, "hv_toggle_take_floating", false)
    uiSet:addToggle("Mode 3-Zigzag (OFF = 1-by-1)", HV.CFG.harvest_mode == "3zigzag", "hv_toggle_mode_zigzag", false)
    uiSet:addToggle("Gunakan ModFly saat Bergerak", HV.CFG.use_modfly ~= false, "hv_toggle_modfly", false)
    uiSet:addToggle("Looping Ulang Semua Farm", HV.CFG.loop_enabled == true, "hv_toggle_loop", false)
    uiSet:addDivider()
    uiSet:addSlider("Delay Harvest (ms)", 90, 500, HV.CFG.harvest_delay or 180, 10, false, "hv_slider_harvest_delay")
    uiSet:addSlider("Delay Langkah Bot (ms)", 50, 400, HV.CFG.step_delay or 110, 10, false, "hv_slider_step_delay")
    uiSet:addSlider("Delay Warp Antar World (ms)", 1000, 10000, HV.CFG.warp_delay or 4500, 500, false, "hv_slider_warp_delay")

    pcall(addCategory, "Boren Harvest Pro", "Agriculture")
    pcall(addIntoModule, "Boren Harvest Pro", uiFarm:generateJSON())
    pcall(addIntoModule, "Boren Harvest Pro", uiSave:generateJSON())
    pcall(addIntoModule, "Boren Harvest Pro", uiEvent:generateJSON())
    pcall(addIntoModule, "Boren Harvest Pro", uiGear:generateJSON())
    pcall(addIntoModule, "Boren Harvest Pro", uiSet:generateJSON())
end

function OnValue(a1, a2, a3)
    local name, val = a1, a2
    if type(a1) == "table" then
        name = a1.name or a1.alias or a1.id
        val  = a1.value or a1.val
    elseif a3 ~= nil then
        name = a2
        val  = a3
    end
    if not name then return end

    local c = HV.CFG
    local st = HV.STATE

    if name == "hv_btn_start" then
        HV.start()
    elseif name == "hv_btn_stop" then
        HV.stop()
    elseif name == "hv_run_power" then
        if val == true or val == "true" or val == 1 then HV.start() else HV.stop() end
    elseif name == "hv_show_ui" then
        st.show_ui = (val == true)
    -- FARM TAB
    elseif name == "hv_manual_world_input" then
        st.input_add_world = trimStr(val or "")
    elseif name == "hv_manual_door_input" then
        st.input_add_door = trimStr(val or "")
    elseif name == "hv_manual_item_input" then
        local n = tonumber(val)
        if n and n > 0 then st.input_add_id = tostring(math.floor(n)) end
    elseif name == "hv_btn_add_farm" then
        local w = cleanWorldName(st.input_add_world)
        if w ~= "" then
            local iid = tonumber(st.input_add_id) or c.default_item_id or 4584
            table.insert(st.rows, { name = w, door = cleanWorldName(st.input_add_door), item_id = iid, status = "Ready" })
            st.input_add_world = ""
            st.input_add_door  = ""
            HV.saveData()
            addLog("Farm ditambah: " .. w)
        end
    elseif name == "hv_btn_add_cur_farm" then
        local cw = getCurrentWorld()
        if cw ~= "" and cw ~= "EXIT" then
            local iid = tonumber(st.input_add_id) or c.default_item_id or 4584
            table.insert(st.rows, { name = cw, door = "", item_id = iid, status = "Ready" })
            HV.saveData()
            addLog("Farm saat ini ditambah: " .. cw)
        end
    elseif name == "hv_btn_reset_status" then
        for _, r in ipairs(st.rows) do r.status = "Ready" end
        HV.saveData()
        addLog("Status semua farm di-reset ke Ready.")
    elseif name == "hv_btn_clear_farms" then
        st.rows = {}
        HV.saveData()
        addLog("Daftar farm dikosongkan.")

    -- SAVE TAB
    elseif name == "hv_input_save_w" then
        st.input_save_w = trimStr(val or "")
    elseif name == "hv_input_save_d" then
        st.input_save_d = trimStr(val or "")
    elseif name == "hv_input_save_lim" then
        local n = tonumber(val)
        if n and n >= 0 then st.input_save_lim = tostring(math.floor(n)) end
    elseif name == "hv_btn_stype_all" then
        st.input_save_type = "ALL"
    elseif name == "hv_btn_stype_block" then
        st.input_save_type = "BLOCK"
    elseif name == "hv_btn_stype_seed" then
        st.input_save_type = "SEED"
    elseif name == "hv_btn_add_save" then
        local w = cleanWorldName(st.input_save_w)
        if w ~= "" then
            local lim = tonumber(st.input_save_lim) or c.default_save_limit or 20000
            table.insert(st.save_rows, { name = w, door = cleanWorldName(st.input_save_d), save_type = st.input_save_type or "ALL", limit = lim, count = 0, status = "Ready" })
            st.input_save_w = ""
            st.input_save_d = ""
            HV.saveData()
            addLog("Save World ditambah: " .. w .. " (" .. (st.input_save_type or "ALL") .. ")")
        end
    elseif name == "hv_btn_add_cur_save" then
        local cw = getCurrentWorld()
        if cw ~= "" and cw ~= "EXIT" then
            local lim = tonumber(st.input_save_lim) or c.default_save_limit or 20000
            table.insert(st.save_rows, { name = cw, door = "", save_type = st.input_save_type or "ALL", limit = lim, count = 0, status = "Ready" })
            HV.saveData()
            addLog("Save World aktif ditambah: " .. cw)
        end
    elseif name == "hv_btn_reset_save_status" then
        for _, r in ipairs(st.save_rows) do r.status = "Ready" end
        HV.saveData()
        addLog("Status semua save world di-reset.")
    elseif name == "hv_btn_clear_save" then
        st.save_rows = {}
        HV.saveData()
        addLog("Daftar save world dikosongkan.")
    elseif name == "hv_slider_drop_threshold" then
        local n = tonumber(val)
        if n and n >= 20 then c.drop_threshold = math.floor(n); HV.saveData() end

    -- EVENT TAB
    elseif name == "hv_input_ev_w" then
        st.input_ev_w = trimStr(val or "")
    elseif name == "hv_input_ev_d" then
        st.input_ev_d = trimStr(val or "")
    elseif name == "hv_input_ev_lim" then
        local n = tonumber(val)
        if n and n >= 0 then st.input_ev_lim = tostring(math.floor(n)) end
    elseif name == "hv_btn_add_ev" then
        local w = cleanWorldName(st.input_ev_w)
        if w ~= "" then
            local lim = tonumber(st.input_ev_lim) or c.default_ev_limit or 10000
            table.insert(st.event_rows, { name = w, door = cleanWorldName(st.input_ev_d), limit = lim, count = 0, status = "Ready" })
            st.input_ev_w = ""
            st.input_ev_d = ""
            HV.saveData()
            addLog("Event World ditambah: " .. w)
        end
    elseif name == "hv_btn_add_cur_ev" then
        local cw = getCurrentWorld()
        if cw ~= "" and cw ~= "EXIT" then
            local lim = tonumber(st.input_ev_lim) or c.default_ev_limit or 10000
            table.insert(st.event_rows, { name = cw, door = "", limit = lim, count = 0, status = "Ready" })
            HV.saveData()
            addLog("Event World aktif ditambah: " .. cw)
        end
    elseif name == "hv_btn_reset_ev_status" then
        for _, r in ipairs(st.event_rows) do r.status = "Ready" end
        HV.saveData()
        addLog("Status semua event world di-reset.")
    elseif name == "hv_btn_clear_ev" then
        st.event_rows = {}
        HV.saveData()
        addLog("Daftar event world dikosongkan.")
    elseif name == "hv_input_event_ids" then
        c.event_ids_raw = trimStr(val or "")
        HV.saveData()
    elseif name == "hv_btn_preset_mooncake" then
        c.event_ids_raw = "1058,1094,1096,1098,1828"
        HV.saveData()
        addLog("Preset Mooncake 5 jenis diterapkan.")
    elseif name == "hv_slider_event_threshold" then
        local n = tonumber(val)
        if n and n >= 10 then c.event_threshold = math.floor(n); HV.saveData() end

    -- GEAR TAB
    elseif name == "hv_input_gear_world" then
        c.gear_world = trimStr(val or "")
        HV.saveData()
    elseif name == "hv_btn_add_cur_gear" then
        local cw = getCurrentWorld()
        if cw ~= "" and cw ~= "EXIT" then
            c.gear_world = cw .. ":"
            HV.saveData()
            addLog("Gear World diset ke: " .. cw)
        end
    elseif name == "hv_toggle_magni_fuel" then
        c.auto_magni_fuel = (val == true)
        HV.saveData()
    elseif name == "hv_toggle_stop_no_fuel" then
        c.stop_if_no_fuel = (val == true)
        HV.saveData()
    elseif name == "hv_slider_fuel_target" then
        local n = tonumber(val)
        if n and n >= 10 then c.fuel_target_amt = math.floor(n); HV.saveData() end
    elseif name == "hv_input_gear_equip_ids" then
        c.gear_equip_ids = trimStr(val or "")
        HV.saveData()
    elseif name == "hv_btn_gear_preset_both" then
        c.gear_equip_ids = "6840, 1966"
        HV.saveData()
        addLog("Preset Gear: DCS + Harvester.")
    elseif name == "hv_btn_gear_preset_harv" then
        c.gear_equip_ids = "1966"
        HV.saveData()
        addLog("Preset Gear: Harvester Sorrows saja.")
    elseif name == "hv_btn_gear_preset_dcs" then
        c.gear_equip_ids = "6840"
        HV.saveData()
        addLog("Preset Gear: DCS saja.")

    -- SETTINGS TAB
    elseif name == "hv_toggle_ignore_gems" then
        c.ignore_gems = (val == true)
        HV.saveData()
    elseif name == "hv_toggle_auto_collect" then
        c.auto_collect = (val == true)
        HV.saveData()
    elseif name == "hv_toggle_take_floating" then
        c.take_floating = (val == true)
        HV.saveData()
    elseif name == "hv_toggle_mode_zigzag" then
        c.harvest_mode = (val == true) and "3zigzag" or "1by1"
        HV.saveData()
    elseif name == "hv_toggle_modfly" then
        c.use_modfly = (val == true)
        HV.saveData()
    elseif name == "hv_toggle_loop" then
        c.loop_enabled = (val == true)
        HV.saveData()
    elseif name == "hv_slider_harvest_delay" then
        local n = tonumber(val)
        if n and n >= 80 then c.harvest_delay = math.floor(n); HV.saveData() end
    elseif name == "hv_slider_step_delay" then
        local n = tonumber(val)
        if n and n >= 50 then c.step_delay = math.floor(n); HV.saveData() end
    elseif name == "hv_slider_warp_delay" then
        local n = tonumber(val)
        if n and n >= 1000 then c.warp_delay = math.floor(n); HV.saveData() end
    end
end
onValue = OnValue

-- Global hook setup
if setOnValue then
    local aliases = {
        "hv_btn_start", "hv_btn_stop", "hv_run_power", "hv_show_ui",
        "hv_manual_world_input", "hv_manual_door_input", "hv_manual_item_input",
        "hv_btn_add_farm", "hv_btn_add_cur_farm", "hv_btn_reset_status", "hv_btn_clear_farms",
        "hv_input_save_w", "hv_input_save_d", "hv_input_save_lim",
        "hv_btn_stype_all", "hv_btn_stype_block", "hv_btn_stype_seed",
        "hv_btn_add_save", "hv_btn_add_cur_save", "hv_btn_reset_save_status", "hv_btn_clear_save",
        "hv_slider_drop_threshold",
        "hv_input_ev_w", "hv_input_ev_d", "hv_input_ev_lim",
        "hv_btn_add_ev", "hv_btn_add_cur_ev", "hv_btn_reset_ev_status", "hv_btn_clear_ev",
        "hv_input_event_ids", "hv_btn_preset_mooncake", "hv_slider_event_threshold",
        "hv_input_gear_world", "hv_btn_add_cur_gear", "hv_toggle_magni_fuel", "hv_toggle_stop_no_fuel",
        "hv_slider_fuel_target", "hv_input_gear_equip_ids", "hv_btn_gear_preset_both", "hv_btn_gear_preset_harv", "hv_btn_gear_preset_dcs",
        "hv_toggle_ignore_gems", "hv_toggle_auto_collect", "hv_toggle_take_floating",
        "hv_toggle_mode_zigzag", "hv_toggle_modfly", "hv_toggle_loop",
        "hv_slider_harvest_delay", "hv_slider_step_delay", "hv_slider_warp_delay",
    }
    for _, al in ipairs(aliases) do
        pcall(setOnValue, al, function(a1, a2, a3)
            OnValue(al, a1 or a2 or a3)
        end)
    end
end

-- Packet Hooks (Ignore Gems 112)
local function onSendPacketRawHook(pkt)
    if HV.CFG.ignore_gems and pkt and type(pkt) == "table" and pkt.type == 11 then
        if pkt.value == ITEM.GEMS then return true end
    end
    return false
end
onSendPacketRaw = onSendPacketRawHook
OnSendPacketRaw = onSendPacketRawHook
if addHook then
    pcall(addHook, onSendPacketRawHook, "onsendpacketraw")
end

-- Load persisted configuration & register Native Menu
HV.loadData()
registerNativeHarvestUI()

logMsg("`2BOREN HARVEST PRO v" .. HV.VERSION .. " SIAP! (/harvest)")
notifyMsg("BOREN HARVEST PRO Siap!")

return HV
