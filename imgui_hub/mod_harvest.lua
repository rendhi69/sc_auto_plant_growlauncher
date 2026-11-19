-- ============================================================================
-- BOREN HUB IMGUI - MODUL AUTO HARVEST PRO (ENGINE + UI)
-- File: imgui_hub/mod_harvest.lua
-- Repo Harvest: https://github.com/rendhi69/sc_harvest_growlauncher.git
-- Fitur:
--   1. Multi-World Farm List + Item ID Harvest (auto Block & Seed ID) + Paste/Copy
--   2. Multi-World Save Block/Seed (gabung atau pisah) + Limit Item per World (10k/20k)
--      + posisi drop rapi (skip White Door/Lock, otomatis pindah tile & baris)
--   3. Ignore Gems (blokir collect ID 112 via onSendPacketRaw)
--   4. Mode 3-Zigzag Serpentine & 1-by-1
--   5. Auto Collect Block, Seed & Item Event
--   6. Multi-World Save khusus Event / Mooncake
--   7. Custom List ID Item Event (selain block & seed)
--   8. Gear World (Magni / DCS / Harvester / Fuel Pack + proteksi anti-panen tanpa fuel)
--   9. Opsional Take Floating setelah tree habis + Auto Reconnect (HUB.conn)
-- ============================================================================

local HV = {
    id      = "harvest",
    label   = "Harvest",
    VERSION = "1.1.0",
    META    = {
        type    = "boren_gl_feature",
        id      = "harvest",
        label   = "Harvest",
        order   = 15,
        enabled = true,
    },
}

HV.CFG = {
    default_item_id    = 4584,      -- Block genap / Seed ganjil (auto pair)
    save_worlds_raw    = "",        -- Multi-world save Block (atau Block+Seed)
    seed_save_raw      = "",        -- Opsional: Multi-world save khusus Seed
    separate_seed_save = false,     -- false = gabung 1 list, true = pisah Block & Seed
    save_limit         = 20000,     -- Maks item per save world (0 = unlimited)
    limit_block_only   = false,     -- false = hitung Block+Seed, true = hitung Block saja
    drop_threshold     = 180,       -- Drop saat tas >= nilai ini
    ignore_gems        = true,      -- Blokir collect Gems (ID 112)
    harvest_mode       = "3zigzag", -- "3zigzag" | "1by1"
    harvest_delay      = 180,
    step_delay         = 110,
    warp_delay         = 4500,
    use_modfly         = true,
    loop_enabled       = false,
    auto_collect       = true,
    collect_range      = 4,
    event_worlds_raw   = "",        -- Multi-world save Event / Mooncake
    event_ids_raw      = "1058,1094,1096,1098,1828", -- Mooncakes default
    event_threshold    = 150,
    gear_world         = "",        -- 1 world khusus Magni / DCS / Harvester / Fuel Pack
    use_magni          = false,
    use_dcs            = false,
    use_harvester      = false,
    harvester_id       = 1966,      -- 1966 = Harvester of Sorrows, 1830 = Harvester
    use_fuel_pack      = false,
    fuel_target_amt    = 100,
    stop_if_no_fuel    = true,      -- Proteksi: stop aman jika Fuel Pack habis di tas & Gear World
    take_floating      = true,      -- Sapu sisa block/seed/event setelah tree habis
}

HV.STATE = {
    enabled          = false,
    running          = false,
    status_text      = "Idle",
    rows             = {},          -- { { name="W", door="D", item_id=4584, status="Ready" }, ... }
    selected_idx     = 0,
    save_world_idx   = 1,
    seed_world_idx   = 1,
    event_world_idx  = 1,
    full_save_map    = {},
    full_seed_map    = {},
    full_event_map   = {},
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
local addFarmWorldBuf = ""
local addFarmItemBuf  = "4584"
local saveLimitBuf    = "20000"
local uiNotice        = ""
local CACHED_PATH     = nil

-- ============================================================================
-- 1. ITEM IDs & SAFE HELPERS
-- ============================================================================
local function resolveItemID(name, fallback)
    if findItemID then
        local ok, id = pcall(findItemID, name)
        if ok and tonumber(id) and tonumber(id) > 0 then return math.floor(tonumber(id)) end
    end
    if growtopia and growtopia.getItemID then
        local ok, id = pcall(growtopia.getItemID, name)
        if ok and tonumber(id) and tonumber(id) > 0 then return math.floor(tonumber(id)) end
    end
    return fallback
end

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
    return tostring(s or ""):gsub("%z", ""):gsub("`.", ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
end

local function normalizeHarvestPair(id)
    id = math.floor(tonumber(id) or 0)
    if id <= 0 then return 0, 0 end
    if id % 2 == 1 then return id - 1, id end
    return id, id + 1
end

local function addLogUI(msg)
    local clean = tostring(msg or ""):gsub("`.", "")
    local ts = ""
    if os and os.date then
        local ok, d = pcall(os.date, "%H:%M:%S")
        if ok and d then ts = "[" .. d .. "] " end
    end
    local entry = ts .. "[HARVEST] " .. clean
    table.insert(HV.STATE.logs, 1, entry)
    if #HV.STATE.logs > 60 then table.remove(HV.STATE.logs) end
    if HUB_REF and HUB_REF.addLog then HUB_REF.addLog(entry) end
end

local function addLog(msg)
    addLogUI(msg)
    if LogToConsole then pcall(LogToConsole, "`e[Boren Harvest] `w" .. tostring(msg or "")) end
end

local function safeSleep(ms)
    ms = math.max(10, tonumber(ms) or 50)
    local fn = sleep or CSleep
    if fn then pcall(fn, ms) end
end

local function runAsync(fn)
    if runCoroutine then pcall(runCoroutine, fn)
    else coroutine.resume(coroutine.create(fn)) end
end

-- ============================================================================
-- 2. PERSISTENCE (SAVE / LOAD KONFIGURASI & WORLD LIST)
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

local function joinWorldList(list)
    local out = {}
    for _, it in ipairs(list or {}) do
        if it and it.name and it.name ~= "" then
            table.insert(out, (it.door and it.door ~= "") and (it.name .. ":" .. it.door) or it.name)
        end
    end
    return table.concat(out, ",")
end

local function parseFarmRow(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts, st = {}, 1
    while true do
        local idx = s:find(":", st, true)
        if not idx then table.insert(parts, trimStr(s:sub(st))); break
        else table.insert(parts, trimStr(s:sub(st, idx - 1))); st = idx + 1 end
    end
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    local iid = math.floor(tonumber(parts[3]) or tonumber(HV.CFG.default_item_id) or 4584)
    if iid <= 0 then iid = 4584 end
    return { name = w, door = door, item_id = iid, status = "Ready" }
end

local function parseEventIDSet()
    local map, list = {}, {}
    for tok in tostring(HV.CFG.event_ids_raw or ""):gmatch("[^,%s;|]+") do
        local id = math.floor(tonumber(tok) or 0)
        if id > 0 and not map[id] then map[id] = true; table.insert(list, id) end
    end
    return map, list
end

function HV.saveData()
    local c = HV.CFG
    local lines = {
        "DEFID="   .. tostring(c.default_item_id),
        "SAVEW="   .. tostring(c.save_worlds_raw or ""),
        "SEEDW="   .. tostring(c.seed_save_raw or ""),
        "SEPSEED=" .. (c.separate_seed_save and "1" or "0"),
        "SAVELIM=" .. tostring(c.save_limit),
        "LIMBLK="  .. (c.limit_block_only and "1" or "0"),
        "DROPTH="  .. tostring(c.drop_threshold),
        "IGEMS="   .. (c.ignore_gems and "1" or "0"),
        "MODE="    .. tostring(c.harvest_mode),
        "HDELAY="  .. tostring(c.harvest_delay),
        "SDELAY="  .. tostring(c.step_delay),
        "MODFLY="  .. (c.use_modfly and "1" or "0"),
        "LOOP="    .. (c.loop_enabled and "1" or "0"),
        "ACOL="    .. (c.auto_collect and "1" or "0"),
        "EVW="     .. tostring(c.event_worlds_raw or ""),
        "EVIDS="   .. tostring(c.event_ids_raw or ""),
        "EVTH="    .. tostring(c.event_threshold),
        "GEARW="   .. tostring(c.gear_world or ""),
        "MAGNI="   .. (c.use_magni and "1" or "0"),
        "DCS="     .. (c.use_dcs and "1" or "0"),
        "HARV="    .. (c.use_harvester and "1" or "0"),
        "HARVID="  .. tostring(c.harvester_id),
        "FUEL="    .. (c.use_fuel_pack and "1" or "0"),
        "FUELAMT=" .. tostring(c.fuel_target_amt),
        "STPFUEL=" .. (c.stop_if_no_fuel and "1" or "0"),
        "FLOAT="   .. (c.take_floating and "1" or "0"),
    }
    for _, r in ipairs(HV.STATE.rows) do
        table.insert(lines, string.format("ROW=%s:%s:%d|%s", r.name, r.door or "", r.item_id or c.default_item_id, r.status or "Ready"))
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
    HV.STATE.rows = {}
    for line in txt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([A-Z]+)=(.*)$")
        if k == "DEFID" then c.default_item_id = tonumber(v) or 4584
        elseif k == "SAVEW" then c.save_worlds_raw = trimStr(v)
        elseif k == "SEEDW" then c.seed_save_raw = trimStr(v)
        elseif k == "SEPSEED" then c.separate_seed_save = (v == "1")
        elseif k == "SAVELIM" then c.save_limit = tonumber(v) or 20000
        elseif k == "LIMBLK" then c.limit_block_only = (v == "1")
        elseif k == "DROPTH" then c.drop_threshold = tonumber(v) or 180
        elseif k == "IGEMS" then c.ignore_gems = (v ~= "0")
        elseif k == "MODE" and (v == "3zigzag" or v == "1by1") then c.harvest_mode = v
        elseif k == "HDELAY" then c.harvest_delay = tonumber(v) or 180
        elseif k == "SDELAY" then c.step_delay = tonumber(v) or 110
        elseif k == "MODFLY" then c.use_modfly = (v ~= "0")
        elseif k == "LOOP" then c.loop_enabled = (v == "1")
        elseif k == "ACOL" then c.auto_collect = (v ~= "0")
        elseif k == "EVW" then c.event_worlds_raw = trimStr(v)
        elseif k == "EVIDS" then c.event_ids_raw = trimStr(v)
        elseif k == "EVTH" then c.event_threshold = tonumber(v) or 150
        elseif k == "GEARW" then c.gear_world = trimStr(v)
        elseif k == "MAGNI" then c.use_magni = (v == "1")
        elseif k == "DCS" then c.use_dcs = (v == "1")
        elseif k == "HARV" then c.use_harvester = (v == "1")
        elseif k == "HARVID" then c.harvester_id = tonumber(v) or ITEM.SORROWS
        elseif k == "FUEL" then c.use_fuel_pack = (v == "1")
        elseif k == "FUELAMT" then c.fuel_target_amt = tonumber(v) or 100
        elseif k == "STPFUEL" then c.stop_if_no_fuel = (v ~= "0")
        elseif k == "FLOAT" then c.take_floating = (v ~= "0")
        elseif k == "ROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseFarmRow(wd or v)
            if p then p.status = (st and st ~= "") and st or "Ready"; table.insert(HV.STATE.rows, p) end
        end
    end
    addFarmItemBuf = tostring(c.default_item_id)
    saveLimitBuf   = tostring(c.save_limit)
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
    for _, fn in ipairs({ getCurrentWorldName, GetWorldName, getWorld, getCurrentWorld }) do
        if type(fn) == "function" then
            local ok, res = pcall(fn)
            if ok and res ~= nil then
                if type(res) == "string" then
                    local nm = cleanWorldName(res)
                    if nm ~= "" then return nm end
                elseif type(res) == "table" or type(res) == "userdata" then
                    local okN, nm = pcall(function() return res.name or res.worldName end)
                    if okN and type(nm) == "string" and cleanWorldName(nm) ~= "" then return cleanWorldName(nm) end
                end
            end
        end
    end
    return ""
end

local function getTileSafe(tx, ty)
    if not getTile or tx < 0 or tx > 99 or ty < 0 or ty > 53 then return nil end
    local ok, t = pcall(getTile, tx, ty)
    return (ok and t) and t or nil
end

local function getInvCount(id)
    id = math.floor(tonumber(id) or 0)
    if id <= 0 then return 0 end
    if growtopia and growtopia.checkInventoryCount then
        local ok, cnt = pcall(growtopia.checkInventoryCount, id)
        if ok and tonumber(cnt) then return math.floor(tonumber(cnt)) end
    end
    if getInventory then
        local ok, inv = pcall(getInventory)
        if ok and inv then
            local total = 0
            pcall(function()
                for _, it in pairs(inv) do
                    local iid = tonumber(it.id or it.itemid or it.itemID)
                    local amt = tonumber(it.amount or it.count) or 0
                    if iid == id then total = total + amt end
                end
            end)
            return total
        end
    end
    return 0
end

local function forEachWorldObject(fn)
    local getFn = getObjectList or getObjects or getWorldObjects
    if not getFn then return 0 end
    local ok, objs = pcall(getFn)
    if not ok or not objs then return 0 end
    local seen = 0
    pcall(function()
        for _, o in pairs(objs) do
            if o then
                local oid = tonumber(o.itemid or o.itemId or o.item_id)
                local uid = tonumber(o.id or o.oid or o.netid)
                local amt = tonumber(o.amount or o.count) or 1
                local px = (o.pos and tonumber(o.pos.x or o.pos[1])) or tonumber(o.x or o.posX)
                local py = (o.pos and tonumber(o.pos.y or o.pos[2])) or tonumber(o.y or o.posY)
                if oid and oid > 0 and uid and px and py then
                    seen = seen + 1
                    fn(oid, uid, amt, px, py)
                end
            end
        end
    end)
    return seen
end

local function setCollectCheats(enableCollect)
    HV.STATE.anti_take = not enableCollect
    if not editToggle then return end
    if HV.CFG.use_modfly then pcall(editToggle, "ModFly", true) end
    pcall(editToggle, "Anti Lava", true)
    pcall(editToggle, "Anti Collect", not enableCollect)
    pcall(editToggle, "Anti-Collect", not enableCollect)
    local apkAuto = enableCollect and HV.CFG.auto_collect and (not HV.CFG.ignore_gems)
    pcall(editToggle, "Auto Collect", apkAuto)
end

local function setConnWarping(flag)
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.setWarping then
        pcall(HUB_REF.conn.setWarping, flag == true)
    end
end

local unreachableMap = {}
local function moveSafeTo(tx, ty)
    if not HV.STATE.running then return false end
    tx = math.max(0, math.min(99, math.floor(tx or 0)))
    ty = math.max(0, math.min(53, math.floor(ty or 0)))
    local key = tx .. "," .. ty
    if unreachableMap[key] then return false end
    local cx, cy = getPlayerPos()
    if cx == tx and cy == ty then return true end
    local pFn = FindPath or findPath
    if not pFn then return false end
    if HV.CFG.use_modfly and editToggle then pcall(editToggle, "ModFly", true) end

    local dist = math.max(math.abs(cx - tx), math.abs(cy - ty))
    local okCall = pcall(pFn, tx, ty)
    if not okCall then unreachableMap[key] = true; return false end

    local maxW = (dist <= 3) and math.max(160, (tonumber(HV.CFG.step_delay) or 110) * 3) or math.max(1200, math.min(7000, dist * 160))
    local waited, lastX, lastY, stuck = 0, cx, cy, 0
    while waited < maxW and HV.STATE.running do
        local sl = (dist <= 3) and 25 or 50
        safeSleep(sl); waited = waited + sl
        local nx, ny = getPlayerPos()
        if nx == tx and ny == ty then safeSleep(HV.CFG.step_delay or 80); return true end
        if nx == lastX and ny == lastY then
            stuck = stuck + 1
            if stuck >= 6 then unreachableMap[key] = true; break end
        else
            stuck = 0; lastX, lastY = nx, ny
        end
    end
    local fx, fy = getPlayerPos()
    local arrived = (math.abs(fx - tx) <= 1 and math.abs(fy - ty) <= 1)
    if not arrived then unreachableMap[key] = true end
    return arrived
end

local function warpToWorldInner(wName, doorID)
    wName = cleanWorldName(wName); doorID = cleanWorldName(doorID)
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
    local rPx = (radiusTiles or HV.CFG.collect_range or 4) * 32
    local p = getLocalSafe()
    local ppx = (p and (p.posX or (p.pos and p.pos.x))) or (px * 32)
    local ppy = (p and (p.posY or (p.pos and p.pos.y))) or (py * 32)
    forEachWorldObject(function(oid, uid, _, ox, oy)
        if not HV.STATE.running then return end
        if HV.CFG.ignore_gems and oid == ITEM.GEMS then return end
        if allowedSet[oid] and math.abs(ox - ppx) <= rPx and math.abs(oy - ppy) <= rPx then
            pcall(sendPacketRaw, false, { type = 11, value = uid, x = ox, y = oy })
        end
    end)
end

-- ============================================================================
-- 4. DROP ENGINE MULTI-WORLD RAPI (SKIP DOOR/LOCK + PINDAH TILE/BARIS + LIMIT)
-- ============================================================================
local function buildDropDialogReturn(dlgText, fallbackID, dropAmt)
    local dName = dlgText:match("end_dialog|([^|\r\n]+)") or "drop_item"
    local embedLines, hasEmbed = {}, false
    for k, v in dlgText:gmatch("embed_data|([^|\r\n]+)|([^\r\n|]*)") do
        table.insert(embedLines, k .. "|" .. v)
        if k:lower():find("item", 1, true) then hasEmbed = true end
    end
    local countField = dlgText:match("add_text_input|([^|\r\n]+)|") or "count"
    local out = { "action|dialog_return", "dialog_name|" .. dName }
    if hasEmbed then
        for _, l in ipairs(embedLines) do table.insert(out, l) end
    else
        table.insert(out, "itemID|" .. tostring(fallbackID) .. "|")
    end
    table.insert(out, countField .. "|" .. tostring(dropAmt))
    return table.concat(out, "\n") .. "\n"
end

local function countDroppedObjectsInWorld(filterSet)
    local total = 0
    forEachWorldObject(function(oid, _, amt)
        if (not filterSet) or filterSet[oid] then
            total = total + (tonumber(amt) or 1)
        end
    end)
    return total
end

local function isSafeDropSpot(tx, ty)
    if tx < 1 or tx > 97 or ty < 1 or ty > 53 then return false end
    local t = getTileSafe(tx, ty)
    local tR = getTileSafe(tx + 1, ty) -- Drop jatuh ke kanan (state 32)
    if not t or not tR then return false end
    local fg, fgR = tonumber(t.fg) or 0, tonumber(tR.fg) or 0
    if t.collidable or tR.collidable then return false end
    if LOCK_OR_DOOR_IDS[fg] or LOCK_OR_DOOR_IDS[fgR] then return false end
    -- Cek 1 tile sekeliling target drop bebas White Door (6)
    for dy = -1, 1 do
        for dx = -1, 1 do
            local nt = getTileSafe(tx + 1 + dx, ty + dy)
            if nt and tonumber(nt.fg) == 6 then return false end
        end
    end
    return true
end

-- Cari daftar koordinat drop rapi (hindari White Door/Lock, multi-baris, urutan paling sedikit tumpukan)
local function findCleanDropPositions()
    local tileStack = {}
    forEachWorldObject(function(_, _, _, ox, oy)
        local tx, ty = math.floor((ox + 10) / 32), math.floor((oy + 10) / 32)
        local k = tx .. "," .. ty
        tileStack[k] = (tileStack[k] or 0) + 1
    end)
    local px, py = getPlayerPos()
    local cands = {}
    -- Mulai dari baris spawn (py), lalu baris atas/bawahnya agar rapi & mudah dijangkau
    local rowsToTry = { py }
    for d = 2, 20, 2 do
        if py - d >= 2 then table.insert(rowsToTry, py - d) end
        if py + d <= 52 then table.insert(rowsToTry, py + d) end
    end
    for _, y in ipairs(rowsToTry) do
        for x = 2, 95, 2 do
            if isSafeDropSpot(x, y) then
                local st = tileStack[(x + 1) .. "," .. y] or 0
                if st < 18 then -- Growtopia maks ~20 stack per tile
                    table.insert(cands, { x = x, y = y, stacks = st })
                end
            end
        end
    end
    table.sort(cands, function(a, b)
        if a.stacks ~= b.stacks then return a.stacks < b.stacks end
        return math.abs(a.y - py) + math.abs(a.x - px) < math.abs(b.y - py) + math.abs(b.x - px)
    end)
    return cands
end

local function waitInvDropTo(itemID, targetMax, timeoutMs)
    local w = 0
    while w < (timeoutMs or 900) and HV.STATE.running do
        if getInvCount(itemID) <= targetMax then return true end
        safeSleep(60); w = w + 60
    end
    return getInvCount(itemID) <= targetMax
end

local function dropItemAllInCurrentWorld(itemID, label)
    local cur = getInvCount(itemID)
    if cur <= 0 then return true, 0 end
    setCollectCheats(false)
    safeSleep(150)

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

local function dropItemsToWorldList(itemIDs, worldsRaw, limitPerWorld, countFilterSet, fullMap, idxKey, tag, returnFarm)
    local toDrop = {}
    for _, id in ipairs(itemIDs) do
        if getInvCount(id) > 0 then table.insert(toDrop, id) end
    end
    if #toDrop == 0 then return true end

    local worlds = parseWorldList(worldsRaw)
    if #worlds == 0 then
        addLog("`4List " .. tag .. " kosong!")
        return false
    end

    local lim = math.max(0, math.floor(tonumber(limitPerWorld) or 0))
    local startIdx = tonumber(HV.STATE[idxKey]) or 1
    if startIdx < 1 or startIdx > #worlds then startIdx = 1 end

    for offset = 0, #worlds - 1 do
        if not HV.STATE.running then return false end
        local idx = ((startIdx - 1 + offset) % #worlds) + 1
        local sw = worlds[idx]
        if not fullMap[sw.name] then
            HV.STATE.status_text = tag .. ": " .. sw.name
            if warpToWorld(sw.name, sw.door) then
                setCollectCheats(false)
                safeSleep(350)

                local curInWorld = countDroppedObjectsInWorld(countFilterSet)
                if lim > 0 and curInWorld >= lim then
                    addLog(string.format("`e[%s] %s capai limit (%d/%d) -> pindah next world!", tag, sw.name, curInWorld, lim))
                    fullMap[sw.name] = true
                else
                    local allCleared = true
                    for _, id in ipairs(toDrop) do
                        if not HV.STATE.running then return false end
                        if getInvCount(id) > 0 then
                            if lim > 0 and countDroppedObjectsInWorld(countFilterSet) >= lim then
                                addLog(string.format("`e[%s] %s capai limit %d -> lanjut next world!", tag, sw.name, lim))
                                fullMap[sw.name] = true
                                allCleared = false
                                break
                            end
                            local okD = dropItemAllInCurrentWorld(id, id)
                            if not okD then
                                fullMap[sw.name] = true
                                allCleared = false
                                break
                            end
                        end
                    end

                    HV.STATE[idxKey] = idx
                    if allCleared then
                        if returnFarm then
                            warpToWorld(returnFarm.name, returnFarm.door)
                            setCollectCheats(true)
                        end
                        return true
                    end
                end
            end
        end
    end

    addLog("`4Semua " .. tag .. " penuh / mencapai limit!")
    return false
end

-- ============================================================================
-- 5. GEAR WORLD (MAGNI / DCS / HARVESTER / FUEL PACK + PROTEKSI ANTI-RUGI FUEL)
-- ============================================================================
local function equipItem(itemID)
    if not sendPacketRaw or getInvCount(itemID) <= 0 then return false end
    return pcall(sendPacketRaw, false, { type = 10, value = itemID })
end

local function ensureGearAndFuel(returnFarm)
    local c = HV.CFG
    local needed = {}
    if c.use_magni and getInvCount(ITEM.MAGNI) <= 0 then table.insert(needed, { id = ITEM.MAGNI, amt = 1, equip = true, name = "Magni" }) end
    if c.use_dcs and getInvCount(ITEM.DCS) <= 0 then table.insert(needed, { id = ITEM.DCS, amt = 1, equip = true, name = "DCS" }) end
    if c.use_harvester then
        local hid = (tonumber(c.harvester_id) == ITEM.HARVESTER) and ITEM.HARVESTER or ITEM.SORROWS
        if getInvCount(hid) <= 0 then table.insert(needed, { id = hid, amt = 1, equip = true, name = "Harvester" }) end
    end

    local fuelBefore = getInvCount(ITEM.FUEL_PACK)
    if HV.STATE.need_fuel and c.use_fuel_pack and fuelBefore > 0 then
        equipItem(ITEM.FUEL_PACK)
        HV.STATE.need_fuel = false
        safeSleep(250)
        fuelBefore = getInvCount(ITEM.FUEL_PACK)
    end

    local needFuelRestock = c.use_fuel_pack and (fuelBefore <= 0 or HV.STATE.need_fuel)
    if needFuelRestock then
        local want = math.max(1, math.min(200, tonumber(c.fuel_target_amt) or 100))
        table.insert(needed, { id = ITEM.FUEL_PACK, amt = want, equip = false, name = "Fuel Pack" })
    end

    if #needed == 0 then
        if c.use_magni then equipItem(ITEM.MAGNI); safeSleep(120) end
        if c.use_dcs then equipItem(ITEM.DCS); safeSleep(120) end
        if c.use_harvester then equipItem((tonumber(c.harvester_id) == ITEM.HARVESTER) and ITEM.HARVESTER or ITEM.SORROWS); safeSleep(120) end
        return true
    end

    local gw = parseWorldDoor(c.gear_world)
    if not gw then
        if needFuelRestock and c.stop_if_no_fuel then
            addLog("`4[Fuel Guard] Fuel Pack habis & Gear World kosong — bot stop aman agar tidak rugi drop!")
            HV.STATE.status_text = "No Fuel Pack"
            return false
        end
        addLog("`e[Gear] Gear World kosong — melewati ambil gear.")
        return true
    end

    HV.STATE.status_text = "Gear World: " .. gw.name
    addLog("[Gear] Ambil perlengkapan/fuel di " .. gw.name)
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
            equipItem(req.id); safeSleep(200)
            addLog("`2[Gear] Equip " .. req.name)
        elseif req.id == ITEM.FUEL_PACK and getInvCount(ITEM.FUEL_PACK) > 0 then
            addLog("`2[Gear] Fuel Pack terambil: " .. getInvCount(ITEM.FUEL_PACK))
            if HV.STATE.need_fuel then equipItem(ITEM.FUEL_PACK); HV.STATE.need_fuel = false; safeSleep(200) end
        end
    end

    -- Proteksi: jika Fuel Pack tetap 0 setelah cek Gear World -> STOP AMAN
    if needFuelRestock and c.stop_if_no_fuel and getInvCount(ITEM.FUEL_PACK) <= 0 then
        addLog("`4[Fuel Guard] Stok Fuel Pack habis di tas & Gear World — bot berhenti aman!")
        HV.STATE.status_text = "No Fuel Pack"
        return false
    end

    if returnFarm then
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
    for _, eid in ipairs(eventList) do evSum = evSum + getInvCount(eid) end
    HV.STATE.inv_preview.ev = evSum
end

local function checkAndDropIfFull(row, blockID, seedID, eventList, forceDrop)
    updateInvPreview(blockID, seedID, eventList)
    local c = HV.CFG
    local th  = math.max(20, math.min(200, tonumber(c.drop_threshold) or 180))
    local eth = math.max(10, math.min(200, tonumber(c.event_threshold) or 150))

    -- 1. Cek Fuel Pack proaktif sebelum lanjut panen
    if (not forceDrop) and c.use_harvester and c.use_fuel_pack and (HV.STATE.need_fuel or getInvCount(ITEM.FUEL_PACK) <= 0) then
        if not ensureGearAndFuel(row) then return false end
    end

    -- 2. Item Event (Mooncake & Custom IDs) -> Event Save World
    local needEventDrop = false
    for _, eid in ipairs(eventList) do
        local cnt = getInvCount(eid)
        if (forceDrop and cnt > 0) or cnt >= eth then needEventDrop = true; break end
    end
    if needEventDrop and trimStr(c.event_worlds_raw) ~= "" then
        if not dropItemsToWorldList(eventList, c.event_worlds_raw, 0, nil, HV.STATE.full_event_map, "event_world_idx", "Event Save", forceDrop and nil or row) then
            return false
        end
    end

    -- 3. Block & Seed -> Save World (gabung atau pisah) + Limit
    local bCnt, sCnt = getInvCount(blockID), getInvCount(seedID)
    local limitFilter = c.limit_block_only and { [blockID] = true } or { [blockID] = true, [seedID] = true }

    if c.separate_seed_save and trimStr(c.seed_save_raw) ~= "" then
        if (forceDrop and bCnt > 0) or bCnt >= th then
            if not dropItemsToWorldList({ blockID }, c.save_worlds_raw, c.save_limit, { [blockID] = true }, HV.STATE.full_save_map, "save_world_idx", "Save Block", forceDrop and nil or row) then
                return false
            end
        end
        if (forceDrop and sCnt > 0) or sCnt >= th then
            if not dropItemsToWorldList({ seedID }, c.seed_save_raw, c.save_limit, { [seedID] = true }, HV.STATE.full_seed_map, "seed_world_idx", "Save Seed", forceDrop and nil or row) then
                return false
            end
        end
    else
        if (forceDrop and (bCnt > 0 or sCnt > 0)) or bCnt >= th or sCnt >= th then
            if not dropItemsToWorldList({ blockID, seedID }, c.save_worlds_raw, c.save_limit, limitFilter, HV.STATE.full_save_map, "save_world_idx", "Save World", forceDrop and nil or row) then
                return false
            end
        end
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

    local eventMap, eventList = parseEventIDSet()
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
    local goingRight = true

    for y = 0, 53 do
        if not HV.STATE.running then return false end
        if not ensureHVOnline(row, true) then return false end
        local hasReady = false
        for x = 0, 99 do
            if isReadyTree(x, y, seedID) then hasReady = true; break end
        end

        if hasReady then
            row.status = "Harvest Y=" .. tostring(y)
            HV.STATE.status_text = row.name .. " Y=" .. tostring(y)
            if HV.CFG.harvest_mode == "3zigzag" then
                local standX = goingRight and 1 or 98
                local step = goingRight and 3 or -3
                while (goingRight and standX <= 99) or ((not goingRight) and standX >= 0) do
                    if not HV.STATE.running then return false end
                    if not ensureHVOnline(row, true) then return false end
                    local xs = goingRight and { standX - 1, standX, standX + 1 } or { standX + 1, standX, standX - 1 }
                    local spots = {}
                    for _, bx in ipairs(xs) do
                        if bx >= 0 and bx <= 99 and isReadyTree(bx, y, seedID) then table.insert(spots, bx) end
                    end
                    if #spots > 0 then
                        if not checkAndDropIfFull(row, blockID, seedID, eventList, false) then return false end
                        local moveX = (standX >= 0 and standX <= 99) and standX or spots[1]
                        if moveSafeTo(moveX, y) then
                            for _, bx in ipairs(spots) do
                                if not HV.STATE.running then return false end
                                if not ensureHVOnline(row, true) then return false end
                                if isReadyTree(bx, y, seedID) then
                                    punchTile(bx, y)
                                    HV.STATE.total_harvested = HV.STATE.total_harvested + 1
                                    safeSleep(hDelay)
                                end
                            end
                            collectNearbyAllowed(allowedSet, HV.CFG.collect_range)
                        end
                    end
                    standX = standX + step
                end
            else
                local x1, x2, st = goingRight and 0 or 99, goingRight and 99 or 0, goingRight and 1 or -1
                for bx = x1, x2, st do
                    if not HV.STATE.running then return false end
                    if not ensureHVOnline(row, true) then return false end
                    if isReadyTree(bx, y, seedID) then
                        if not checkAndDropIfFull(row, blockID, seedID, eventList, false) then return false end
                        if moveSafeTo(bx, y) then
                            punchTile(bx, y)
                            HV.STATE.total_harvested = HV.STATE.total_harvested + 1
                            safeSleep(hDelay)
                            collectNearbyAllowed(allowedSet, HV.CFG.collect_range)
                        end
                    end
                end
            end
            goingRight = not goingRight
        end
    end

    if HV.CFG.take_floating then
        if not sweepFloatingObjects(row, blockID, seedID, allowedSet, eventList) then return false end
    end

    if not checkAndDropIfFull(row, blockID, seedID, eventList, true) then return false end

    -- Anti False Done jika disconnect di akhir
    if not HV.STATE.running then return false end
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.isPlayerOnline and not HUB_REF.conn.isPlayerOnline() then return false end

    row.status = "Done"
    HV.saveData()
    addLog("`2[Selesai] Harvest " .. row.name .. " tuntas!")
    return true
end

local function mainLoop()
    HV.STATE.running = true
    HV.STATE.full_save_map  = {}
    HV.STATE.full_seed_map  = {}
    HV.STATE.full_event_map = {}
    addLog("Auto Harvest dimulai.")

    while HV.STATE.running do
        for _, row in ipairs(HV.STATE.rows) do
            if not HV.STATE.running then break end
            if row.status ~= "Done" and row.status ~= "Inaccessible" then
                if not processFarmWorld(row) then break end
                safeSleep(400)
            end
        end
        if not HV.STATE.running then break end
        if HV.CFG.loop_enabled and #HV.STATE.rows > 0 then
            for _, r in ipairs(HV.STATE.rows) do
                if r.status ~= "Inaccessible" then r.status = "Ready" end
            end
            HV.saveData()
            safeSleep(2500)
        else
            break
        end
    end

    HV.STATE.running = false; HV.STATE.enabled = false
    setCollectCheats(true)
    if HV.STATE.status_text == "Idle" or HV.STATE.status_text:find("Warp", 1, true) or HV.STATE.status_text:find("Y=", 1, true) then
        HV.STATE.status_text = "Idle"
    end
    addLog("Auto Harvest berhenti.")
end

function HV.start()
    if HV.STATE.running then return end
    if #HV.STATE.rows == 0 then
        addLogUI("Daftar Farm Harvest kosong!")
        HV.STATE.status_text = "List Kosong"
        HV.STATE.enabled = false
        return
    end
    HV.STATE.enabled = true
    runAsync(function()
        local ok, err = xpcall(mainLoop, function(e)
            return tostring(e) .. "\n" .. (debug and debug.traceback and debug.traceback() or "")
        end)
        if not ok then
            addLog("`4[Harvest Crash] " .. tostring(err))
            HV.STATE.running = false; HV.STATE.enabled = false; HV.STATE.status_text = "Error"
        end
    end)
end

function HV.stop()
    HV.STATE.running = false; HV.STATE.enabled = false
    HV.STATE.pending_drop_id = 0
    HV.STATE.status_text = "Stopped"
end

-- Hooks terintegrasi dengan Boren Store Hub (tab_plant.lua)
function HV.handleSendPacketRaw(pkt)
    if not pkt or tonumber(pkt.type) ~= 11 then return false end
    if HV.STATE.anti_take then return true end
    if HV.STATE.running and HV.CFG.ignore_gems then
        local uid = tonumber(pkt.value) or 0
        if uid > 0 then
            local isGem = false
            forEachWorldObject(function(oid, id)
                if id == uid and oid == ITEM.GEMS then isGem = true end
            end)
            if isGem then return true end
        end
    end
    return false
end

function HV.handleVariant(var)
    if not var then return false end
    local fn, v2 = tostring(var.v1 or ""), tostring(var.v2 or "")
    if fn == "OnDialogRequest" and (HV.STATE.pending_drop_id or 0) > 0 then
        if v2:lower():find("drop", 1, true) then
            if not HV.STATE.drop_confirmed then
                HV.STATE.drop_confirmed = true
                if sendPacket then
                    pcall(sendPacket, 2, buildDropDialogReturn(v2, HV.STATE.pending_drop_id, HV.STATE.pending_drop_amt))
                end
            end
            return true
        end
    end
    if fn == "OnConsoleMessage" or fn == "OnTextOverlay" then
        local low = v2:lower()
        if low:find("out of fuel", 1, true) or low:find("need fuel", 1, true) or low:find("no fuel", 1, true) then
            HV.STATE.need_fuel = true
        end
    end
    return false
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
        HV.saveData(); uiNotice = "Semua status di-reset ke Ready."
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

local function renderSaveSub()
    local c, st = HV.CFG, HV.STATE
    local w = availX()

    uiSection("Multi-World Save Block / Seed", true)
    uiNote(uiNotice)

    uiSectionWithKetik("Daftar Save World Block (Koma / Baris)", "hv_ktk_sw", function()
        uiOpenDialog("boren_in_hv_sw", "Save Worlds Block / Seed", {
            { id = "sw", label = "List Save World (WORLD:DOOR, ...)", default = c.save_worlds_raw, maxLen = 512 },
            { id = "lim", label = "Limit Item/World (0 = tanpa limit)", default = tostring(c.save_limit), maxLen = 16 },
        }, "Simpan", function(v)
            c.save_worlds_raw = trimStr(v.sw or "")
            local n = tonumber(v.lim)
            if n and n >= 0 then c.save_limit = math.floor(n); saveLimitBuf = tostring(c.save_limit) end
            HV.saveData(); uiNotice = "Save World berhasil disimpan."
        end)
    end)

    ImGui.PushItemWidth(math.max(160, math.floor(w * 0.96)))
    local chSW, vSW = safeInput("##hv_sw", c.save_worlds_raw, 512)
    ImGui.PopItemWidth()
    if chSW then c.save_worlds_raw = vSW; HV.saveData() end

    uiGap(3)
    local actSw = uiActionBar("BorenHarvestSwActs", w, {
        { label = "Paste Save##hv_swp", style = "accent" },
        { label = "+ World Ini##hv_swc" },
        { label = "Reset Status Penuh##hv_rfull" },
    })
    if actSw == 1 then
        local list = parseWorldList(c.save_worlds_raw)
        for _, ln in ipairs(readClipLines()) do
            local p = parseWorldDoor(ln); if p then table.insert(list, p) end
        end
        c.save_worlds_raw = joinWorldList(list); HV.saveData(); uiNotice = "Paste Save World OK (" .. tostring(#list) .. " world)."
    elseif actSw == 2 then
        runAsync(function()
            local cw = getCurrentWorldSafe()
            if cw ~= "" and cw ~= "EXIT" then
                local list = parseWorldList(c.save_worlds_raw)
                table.insert(list, { name = cw, door = "" })
                c.save_worlds_raw = joinWorldList(list); HV.saveData(); uiNotice = "Save World ditambah: " .. cw
            else uiNotice = "Masuk ke world dulu!" end
        end)
    elseif actSw == 3 then
        st.full_save_map = {}; st.full_seed_map = {}; st.save_world_idx = 1; st.seed_world_idx = 1
        uiNotice = "Penanda save world penuh di-reset."
    end

    uiGap(4)
    uiSection("Opsi Pemisahan Seed & Limit Drop")

    ImGui.Text("Pisah Save World Seed  :"); ImGui.SameLine()
    if uiToggleBtn(c.separate_seed_save, "hv_seps", "PISAH (SEPARATE)", "GABUNG (1 WORLD)") then
        c.separate_seed_save = not c.separate_seed_save; HV.saveData()
    end

    if c.separate_seed_save then
        uiGap(2)
        ImGui.Text("Save World Khusus Seed (WORLD:DOOR, ...):")
        ImGui.PushItemWidth(math.max(160, math.floor(w * 0.96)))
        local chSS, vSS = safeInput("##hv_ssw", c.seed_save_raw, 512)
        ImGui.PopItemWidth()
        if chSS then c.seed_save_raw = vSS; HV.saveData() end
    end

    uiGap(3)
    ImGui.Text("Hitung Limit Drop      :"); ImGui.SameLine()
    if uiToggleBtn(c.limit_block_only, "hv_lblk", "BLOCK SAJA", "BLOCK + SEED") then
        c.limit_block_only = not c.limit_block_only; HV.saveData()
    end

    uiGap(3)
    ImGui.Text("Limit Item per World   : " .. (c.save_limit == 0 and "Unlimited" or (tostring(c.save_limit) .. " item")))
    ImGui.SameLine()
    if autoBtn(" 10.000 ##hv_l10k") then c.save_limit = 10000; saveLimitBuf = "10000"; HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" 20.000 ##hv_l20k") then c.save_limit = 20000; saveLimitBuf = "20000"; HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" Unlimited ##hv_lunl") then c.save_limit = 0; saveLimitBuf = "0"; HV.saveData() end

    uiGap(3)
    ImGui.Text("Drop saat tas penuh    : >= " .. tostring(c.drop_threshold) .. " item")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_dt1") then c.drop_threshold = math.max(20, c.drop_threshold - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_dt2") then c.drop_threshold = math.min(200, c.drop_threshold + 20); HV.saveData() end
end

local function renderEventSub()
    local c, st = HV.CFG, HV.STATE
    local w = availX()

    uiSection("Save Khusus Event & Mooncake", true)
    uiNote(uiNotice)

    uiSectionWithKetik("Daftar Save World Event (Koma / Baris)", "hv_ktk_ev", function()
        uiOpenDialog("boren_in_hv_ev", "Event Save & Custom Item ID", {
            { id = "ew", label = "Event Save Worlds (WORLD:DOOR, ...)", default = c.event_worlds_raw, maxLen = 512 },
            { id = "ids", label = "List ID Item Event (pisah koma)", default = c.event_ids_raw, maxLen = 512 },
        }, "Simpan", function(v)
            c.event_worlds_raw = trimStr(v.ew or "")
            c.event_ids_raw    = trimStr(v.ids or "")
            HV.saveData(); uiNotice = "Konfigurasi Event berhasil disimpan."
        end)
    end)

    ImGui.PushItemWidth(math.max(160, math.floor(w * 0.96)))
    local chEW, vEW = safeInput("##hv_ew", c.event_worlds_raw, 512)
    ImGui.PopItemWidth()
    if chEW then c.event_worlds_raw = vEW; HV.saveData() end

    uiGap(3)
    local actEv = uiActionBar("BorenHarvestEvActs", w, {
        { label = "Paste Event##hv_evp", style = "accent" },
        { label = "+ World Ini##hv_evc" },
        { label = "Reset Penuh Event##hv_rev" },
    })
    if actEv == 1 then
        local list = parseWorldList(c.event_worlds_raw)
        for _, ln in ipairs(readClipLines()) do
            local p = parseWorldDoor(ln); if p then table.insert(list, p) end
        end
        c.event_worlds_raw = joinWorldList(list); HV.saveData(); uiNotice = "Paste Event World OK (" .. tostring(#list) .. ")."
    elseif actEv == 2 then
        runAsync(function()
            local cw = getCurrentWorldSafe()
            if cw ~= "" and cw ~= "EXIT" then
                local list = parseWorldList(c.event_worlds_raw)
                table.insert(list, { name = cw, door = "" })
                c.event_worlds_raw = joinWorldList(list); HV.saveData(); uiNotice = "Event World ditambah: " .. cw
            else uiNotice = "Masuk ke world dulu!" end
        end)
    elseif actEv == 3 then
        st.full_event_map = {}; st.event_world_idx = 1; uiNotice = "Status penuh save event di-reset."
    end

    uiGap(4)
    uiSection("Daftar ID Item Event (Disimpan ke World Event)")
    ImGui.PushItemWidth(math.max(160, math.floor(w * 0.96)))
    local chEI, vEI = safeInput("##hv_ei", c.event_ids_raw, 512)
    ImGui.PopItemWidth()
    if chEI then c.event_ids_raw = vEI; HV.saveData() end

    uiGap(3)
    ImGui.Text("Preset Cepat :")
    ImGui.SameLine()
    if autoBtn(" Preset Mooncake ##hv_pmc") then
        c.event_ids_raw = "1058,1094,1096,1098,1828"
        HV.saveData(); uiNotice = "Preset Mooncake (1058, 1094, 1096, 1098, 1828) diterapkan."
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

local function renderGearSub()
    local c = HV.CFG
    local w = availX()

    uiSection("Gear World (Magni / DCS / Harvester / Fuel)", true)
    uiNote(uiNotice)

    uiSectionWithKetik("World Ambil Alat & Fuel (WORLD:DOOR)", "hv_ktk_gw", function()
        uiOpenDialog("boren_in_hv_gw", "Setting Gear World", {
            { id = "gw", label = "Gear World (WORLD:DOOR)", default = c.gear_world, maxLen = 64 },
            { id = "fa", label = "Target Ambil Fuel Pack", default = tostring(c.fuel_target_amt), maxLen = 8 },
        }, "Simpan", function(v)
            c.gear_world = trimStr(v.gw or "")
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
    uiSection("Opsi Alat (Auto Equip)")

    ImGui.Text("Magnifying Glass (1252)    :"); ImGui.SameLine()
    if uiToggleBtn(c.use_magni, "hv_mag") then c.use_magni = not c.use_magni; HV.saveData() end

    uiGap(2)
    ImGui.Text("Dreamcatcher Staff (6840)  :"); ImGui.SameLine()
    if uiToggleBtn(c.use_dcs, "hv_dcs") then c.use_dcs = not c.use_dcs; HV.saveData() end

    uiGap(2)
    ImGui.Text("Harvester Tractor          :"); ImGui.SameLine()
    if uiToggleBtn(c.use_harvester, "hv_harv") then c.use_harvester = not c.use_harvester; HV.saveData() end
    if c.use_harvester then
        ImGui.SameLine()
        local isSor = (tonumber(c.harvester_id) == ITEM.SORROWS)
        if autoBtn(isSor and " Tipe: Sorrows (1966) ##hv_ht" or " Tipe: Normal (1830) ##hv_ht") then
            c.harvester_id = isSor and ITEM.HARVESTER or ITEM.SORROWS; HV.saveData()
        end
    end

    uiGap(4)
    uiSection("Auto Fuel Pack (1746) & Fuel Guard")

    ImGui.Text("Auto Ambil Fuel Pack       :"); ImGui.SameLine()
    if uiToggleBtn(c.use_fuel_pack, "hv_fuel") then c.use_fuel_pack = not c.use_fuel_pack; HV.saveData() end

    uiGap(2)
    ImGui.Text("Proteksi Fuel Guard        :"); ImGui.SameLine()
    if uiToggleBtn(c.stop_if_no_fuel, "hv_stpf", "STOP AMAN", "TERUSKAN") then
        c.stop_if_no_fuel = not c.stop_if_no_fuel; HV.saveData()
    end

    uiGap(2)
    ImGui.Text("Target Ambil Fuel          : " .. tostring(c.fuel_target_amt) .. " pack")
    ImGui.SameLine()
    if autoBtn(" -25 ##hv_fa1") then c.fuel_target_amt = math.max(25, c.fuel_target_amt - 25); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +25 ##hv_fa2") then c.fuel_target_amt = math.min(200, c.fuel_target_amt + 25); HV.saveData() end
end

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
    ImGui.Text("ModFly                     :"); ImGui.SameLine()
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

function HV.render(hub)
    HUB_REF = hub or HUB_REF
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

return HV
